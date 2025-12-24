"""
Head and Shoulders Pattern Detection

Implements detection for:
- Head and Shoulders (bearish reversal)
- Inverse Head and Shoulders (bullish reversal)
"""

import numpy as np
from typing import Optional, List, Tuple
from .base_chart_pattern import (
    BaseChartPattern, ChartPatternResult, PatternType, PatternStrength
)


class HeadShouldersDetector(BaseChartPattern):
    """
    Detector for Head and Shoulders patterns
    
    Pattern characteristics:
    1. Left Shoulder: Peak with decline
    2. Head: Higher peak with decline
    3. Right Shoulder: Peak similar to left shoulder
    4. Neckline: Support line connecting two troughs
    5. Breakout: Price breaks below neckline (bearish)
    
    For Inverse H&S, all conditions are inverted.
    """
    
    def __init__(self, 
                 min_pattern_bars: int = 30,
                 max_pattern_bars: int = 100,
                 shoulder_symmetry_tolerance: float = 0.15,
                 neckline_tolerance: float = 0.02):
        """
        Initialize Head and Shoulders detector
        
        Args:
            min_pattern_bars: Minimum bars for pattern
            max_pattern_bars: Maximum bars to look back
            shoulder_symmetry_tolerance: Max difference between shoulders (15%)
            neckline_tolerance: Tolerance for neckline price (2%)
        """
        super().__init__(min_pattern_bars, max_pattern_bars)
        self.shoulder_symmetry_tolerance = shoulder_symmetry_tolerance
        self.neckline_tolerance = neckline_tolerance
    
    def detect(self, 
               high: np.ndarray, 
               low: np.ndarray, 
               close: np.ndarray,
               volume: Optional[np.ndarray] = None) -> ChartPatternResult:
        """
        Detect Head and Shoulders pattern
        
        Returns ChartPatternResult with highest confidence pattern found
        """
        # Try bearish H&S
        bearish_result = self._detect_head_shoulders(
            high, low, close, volume, inverted=False
        )
        
        # Try bullish inverse H&S
        bullish_result = self._detect_head_shoulders(
            high, low, close, volume, inverted=True
        )
        
        # Return pattern with higher confidence
        if bearish_result.confidence > bullish_result.confidence:
            return bearish_result
        else:
            return bullish_result
    
    def _detect_head_shoulders(self,
                               high: np.ndarray,
                               low: np.ndarray,
                               close: np.ndarray,
                               volume: Optional[np.ndarray],
                               inverted: bool) -> ChartPatternResult:
        """
        Detect Head and Shoulders or Inverse Head and Shoulders
        
        Args:
            high, low, close: Price data
            volume: Volume data
            inverted: If True, detect Inverse H&S (bullish)
        
        Returns:
            ChartPatternResult
        """
        pattern_type = PatternType.INVERSE_HEAD_SHOULDERS if inverted else PatternType.HEAD_SHOULDERS
        signal = 1 if inverted else -1
        
        # For inverse, work with lows instead of highs
        primary_data = low if inverted else high
        secondary_data = high if inverted else low
        
        # Find peaks/troughs
        if inverted:
            extremes = self._find_troughs(primary_data, order=5, threshold=0.01)
        else:
            extremes = self._find_peaks(primary_data, order=5, threshold=0.01)
        
        if len(extremes) < 3:
            return self._create_no_pattern_result(pattern_type)
        
        # Try to find H&S pattern in recent extremes
        best_pattern = None
        best_confidence = 0.0
        
        for i in range(len(extremes) - 2):
            left_shoulder_idx = extremes[i]
            head_idx = extremes[i + 1]
            right_shoulder_idx = extremes[i + 2]
            
            # Check if this forms a valid H&S
            pattern_info = self._validate_head_shoulders_pattern(
                primary_data, secondary_data,
                left_shoulder_idx, head_idx, right_shoulder_idx,
                inverted
            )
            
            if pattern_info and pattern_info['confidence'] > best_confidence:
                best_confidence = pattern_info['confidence']
                best_pattern = pattern_info
        
        if best_pattern is None:
            return self._create_no_pattern_result(pattern_type)
        
        # Check for breakout
        breakout_idx = self._check_neckline_breakout(
            close, best_pattern['neckline'], 
            best_pattern['right_shoulder_idx'],
            inverted
        )
        
        # Volume confirmation
        volume_conf = False
        if breakout_idx is not None and volume is not None:
            volume_conf = self._check_volume_confirmation(volume, breakout_idx)
        
        # Calculate confidence
        confidence_factors = {
            'pattern_symmetry': best_pattern['symmetry_score'],
            'head_prominence': best_pattern['head_prominence'],
            'neckline_alignment': best_pattern['neckline_score'],
            'breakout_confirmed': breakout_idx is not None,
            'volume_confirmation': volume_conf
        }
        
        confidence = self._calculate_confidence(confidence_factors, weights={
            'pattern_symmetry': 1.5,
            'head_prominence': 1.2,
            'neckline_alignment': 1.0,
            'breakout_confirmed': 2.0,
            'volume_confirmation': 1.0
        })
        
        strength = self._classify_strength(confidence)
        
        # Calculate entry, SL, TP
        neckline = best_pattern['neckline']
        pattern_height = best_pattern['pattern_height']
        
        if breakout_idx is not None:
            entry_price = close[breakout_idx]
        else:
            entry_price = neckline
        
        if inverted:
            # Bullish: entry at neckline break up
            stop_loss = min(primary_data[best_pattern['head_idx']] - pattern_height * 0.1,
                           neckline - pattern_height * 0.5)
            take_profit = neckline + pattern_height
        else:
            # Bearish: entry at neckline break down
            stop_loss = max(primary_data[best_pattern['head_idx']] + pattern_height * 0.1,
                           neckline + pattern_height * 0.5)
            take_profit = neckline - pattern_height
        
        reasons = best_pattern['reasons']
        if breakout_idx is not None:
            reasons.append(f"Neckline breakout at index {breakout_idx}")
        if volume_conf:
            reasons.append("Volume confirms breakout")
        
        return ChartPatternResult(
            pattern_type=pattern_type,
            detected=True,
            confidence=confidence,
            strength=strength,
            signal=signal,
            formation_start=best_pattern['left_shoulder_idx'],
            formation_end=best_pattern['right_shoulder_idx'],
            breakout_point=breakout_idx,
            entry_price=entry_price,
            stop_loss=stop_loss,
            take_profit=take_profit,
            neckline=neckline,
            pattern_height=pattern_height,
            volume_confirmation=volume_conf,
            reasons=reasons,
            metadata=best_pattern
        )
    
    def _validate_head_shoulders_pattern(self,
                                         primary_data: np.ndarray,
                                         secondary_data: np.ndarray,
                                         ls_idx: int,
                                         h_idx: int,
                                         rs_idx: int,
                                         inverted: bool) -> Optional[dict]:
        """
        Validate if three extremes form a valid H&S pattern
        
        Returns:
            Dictionary with pattern info if valid, None otherwise
        """
        ls_price = primary_data[ls_idx]
        h_price = primary_data[h_idx]
        rs_price = primary_data[rs_idx]
        
        # 1. Head must be more extreme than shoulders
        if inverted:
            # Inverse H&S: head must be lowest
            if h_price >= ls_price or h_price >= rs_price:
                return None
        else:
            # H&S: head must be highest
            if h_price <= ls_price or h_price <= rs_price:
                return None
        
        # 2. Shoulders should be similar height (within tolerance)
        shoulder_diff = abs(ls_price - rs_price) / max(ls_price, rs_price)
        if shoulder_diff > self.shoulder_symmetry_tolerance:
            return None
        
        # 3. Find troughs between shoulders and head for neckline
        if inverted:
            # For inverse H&S, find peaks between troughs
            trough1 = np.argmax(secondary_data[ls_idx:h_idx]) + ls_idx
            trough2 = np.argmax(secondary_data[h_idx:rs_idx]) + h_idx
            trough1_price = secondary_data[trough1]
            trough2_price = secondary_data[trough2]
        else:
            # For H&S, find troughs between peaks
            trough1 = np.argmin(secondary_data[ls_idx:h_idx]) + ls_idx
            trough2 = np.argmin(secondary_data[h_idx:rs_idx]) + h_idx
            trough1_price = secondary_data[trough1]
            trough2_price = secondary_data[trough2]
        
        # 4. Neckline should be relatively flat (tolerance check)
        neckline_diff = abs(trough1_price - trough2_price) / max(trough1_price, trough2_price)
        neckline_score = 1.0 - min(neckline_diff / self.neckline_tolerance, 1.0)
        
        # Calculate neckline as average
        neckline = (trough1_price + trough2_price) / 2
        
        # 5. Calculate pattern metrics
        pattern_height = abs(h_price - neckline)
        
        # Head prominence: how much head extends beyond neckline
        head_prominence = abs(h_price - neckline) / neckline
        
        # Symmetry score
        symmetry_score = 1.0 - (shoulder_diff / self.shoulder_symmetry_tolerance)
        
        reasons = [
            f"{'Inverse ' if inverted else ''}H&S pattern detected",
            f"Left shoulder at {ls_idx}, Head at {h_idx}, Right shoulder at {rs_idx}",
            f"Shoulder symmetry: {(1-shoulder_diff)*100:.1f}%",
            f"Head prominence: {head_prominence*100:.1f}%",
            f"Neckline: {neckline:.2f}"
        ]
        
        return {
            'left_shoulder_idx': ls_idx,
            'head_idx': h_idx,
            'right_shoulder_idx': rs_idx,
            'neckline': neckline,
            'pattern_height': pattern_height,
            'symmetry_score': symmetry_score,
            'head_prominence': min(head_prominence * 10, 1.0),  # Scale to 0-1
            'neckline_score': neckline_score,
            'confidence': (symmetry_score + neckline_score) / 2,
            'reasons': reasons
        }
    
    def _check_neckline_breakout(self,
                                 close: np.ndarray,
                                 neckline: float,
                                 right_shoulder_idx: int,
                                 inverted: bool) -> Optional[int]:
        """
        Check if price has broken through neckline after right shoulder
        
        Returns:
            Index of breakout bar, or None if no breakout
        """
        # Check bars after right shoulder
        for i in range(right_shoulder_idx + 1, len(close)):
            if inverted:
                # Inverse H&S: breakout above neckline
                if close[i] > neckline * 1.01:  # 1% above for confirmation
                    return i
            else:
                # H&S: breakout below neckline
                if close[i] < neckline * 0.99:  # 1% below for confirmation
                    return i
        
        return None
    
    def _create_no_pattern_result(self, pattern_type: PatternType) -> ChartPatternResult:
        """Create result for when no pattern is detected"""
        return ChartPatternResult(
            pattern_type=pattern_type,
            detected=False,
            confidence=0.0,
            strength=PatternStrength.WEAK,
            signal=0,
            formation_start=0,
            formation_end=0,
            reasons=["No valid pattern detected"]
        )
