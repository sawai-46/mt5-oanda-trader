"""
Double Top and Double Bottom Pattern Detection

Implements detection for:
- Double Top (bearish reversal)
- Double Bottom (bullish reversal)
"""

import numpy as np
from typing import Optional
from .base_chart_pattern import (
    BaseChartPattern, ChartPatternResult, PatternType, PatternStrength
)


class DoubleTopBottomDetector(BaseChartPattern):
    """
    Detector for Double Top and Double Bottom patterns
    
    Pattern characteristics:
    1. Two peaks/troughs at similar price levels
    2. Trough/peak between them (neckline level)
    3. Breakout through neckline confirms pattern
    4. Price target = pattern height projected from neckline
    """
    
    def __init__(self,
                 min_pattern_bars: int = 20,
                 max_pattern_bars: int = 80,
                 peak_similarity_tolerance: float = 0.03,
                 min_peak_separation: int = 5):
        """
        Initialize Double Top/Bottom detector
        
        Args:
            min_pattern_bars: Minimum bars for pattern
            max_pattern_bars: Maximum bars to look back
            peak_similarity_tolerance: Max price difference between peaks (3%)
            min_peak_separation: Minimum bars between two peaks
        """
        super().__init__(min_pattern_bars, max_pattern_bars)
        self.peak_similarity_tolerance = peak_similarity_tolerance
        self.min_peak_separation = min_peak_separation
    
    def detect(self,
               high: np.ndarray,
               low: np.ndarray,
               close: np.ndarray,
               volume: Optional[np.ndarray] = None) -> ChartPatternResult:
        """
        Detect Double Top or Double Bottom pattern
        
        Returns ChartPatternResult with highest confidence pattern found
        """
        # Try bearish Double Top
        double_top = self._detect_double_pattern(
            high, low, close, volume, inverted=False
        )
        
        # Try bullish Double Bottom
        double_bottom = self._detect_double_pattern(
            high, low, close, volume, inverted=True
        )
        
        # Return pattern with higher confidence
        if double_top.confidence > double_bottom.confidence:
            return double_top
        else:
            return double_bottom
    
    def _detect_double_pattern(self,
                               high: np.ndarray,
                               low: np.ndarray,
                               close: np.ndarray,
                               volume: Optional[np.ndarray],
                               inverted: bool) -> ChartPatternResult:
        """
        Detect Double Top or Double Bottom pattern
        
        Args:
            high, low, close: Price data
            volume: Volume data
            inverted: If True, detect Double Bottom (bullish)
        
        Returns:
            ChartPatternResult
        """
        pattern_type = PatternType.DOUBLE_BOTTOM if inverted else PatternType.DOUBLE_TOP
        signal = 1 if inverted else -1
        
        # For Double Bottom, work with lows; for Double Top, work with highs
        primary_data = low if inverted else high
        secondary_data = high if inverted else low
        
        # Find peaks/troughs
        if inverted:
            extremes = self._find_troughs(primary_data, order=3, threshold=0.01)
        else:
            extremes = self._find_peaks(primary_data, order=3, threshold=0.01)
        
        if len(extremes) < 2:
            return self._create_no_pattern_result(pattern_type)
        
        # Find best double pattern
        best_pattern = None
        best_confidence = 0.0
        
        for i in range(len(extremes) - 1):
            for j in range(i + 1, len(extremes)):
                first_idx = extremes[i]
                second_idx = extremes[j]
                
                # Check minimum separation
                if second_idx - first_idx < self.min_peak_separation:
                    continue
                
                # Check if too far apart
                if second_idx - first_idx > self.max_pattern_bars:
                    break
                
                # Validate pattern
                pattern_info = self._validate_double_pattern(
                    primary_data, secondary_data,
                    first_idx, second_idx, inverted
                )
                
                if pattern_info and pattern_info['confidence'] > best_confidence:
                    best_confidence = pattern_info['confidence']
                    best_pattern = pattern_info
        
        if best_pattern is None:
            return self._create_no_pattern_result(pattern_type)
        
        # Check for breakout
        breakout_idx = self._check_neckline_breakout(
            close, best_pattern['neckline'],
            best_pattern['second_peak_idx'],
            inverted
        )
        
        # Volume confirmation
        volume_conf = False
        if breakout_idx is not None and volume is not None:
            volume_conf = self._check_volume_confirmation(volume, breakout_idx)
        
        # Calculate confidence
        confidence_factors = {
            'peak_similarity': best_pattern['similarity_score'],
            'neckline_strength': best_pattern['neckline_strength'],
            'pattern_proportion': best_pattern['proportion_score'],
            'breakout_confirmed': breakout_idx is not None,
            'volume_confirmation': volume_conf
        }
        
        confidence = self._calculate_confidence(confidence_factors, weights={
            'peak_similarity': 1.5,
            'neckline_strength': 1.0,
            'pattern_proportion': 0.8,
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
            # Bullish Double Bottom
            stop_loss = neckline - pattern_height * 0.5
            take_profit = neckline + pattern_height
        else:
            # Bearish Double Top
            stop_loss = neckline + pattern_height * 0.5
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
            formation_start=best_pattern['first_peak_idx'],
            formation_end=best_pattern['second_peak_idx'],
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
    
    def _validate_double_pattern(self,
                                 primary_data: np.ndarray,
                                 secondary_data: np.ndarray,
                                 first_idx: int,
                                 second_idx: int,
                                 inverted: bool) -> Optional[dict]:
        """
        Validate if two extremes form a valid Double Top/Bottom
        
        Returns:
            Dictionary with pattern info if valid, None otherwise
        """
        first_price = primary_data[first_idx]
        second_price = primary_data[second_idx]
        
        # 1. Peaks must be similar (within tolerance)
        price_diff = abs(first_price - second_price) / max(first_price, second_price)
        if price_diff > self.peak_similarity_tolerance:
            return None
        
        similarity_score = 1.0 - (price_diff / self.peak_similarity_tolerance)
        
        # 2. Find neckline (trough between peaks for Double Top, peak for Double Bottom)
        if inverted:
            # Double Bottom: find peak between troughs
            neckline_idx = np.argmax(secondary_data[first_idx:second_idx]) + first_idx
            neckline = secondary_data[neckline_idx]
        else:
            # Double Top: find trough between peaks
            neckline_idx = np.argmin(secondary_data[first_idx:second_idx]) + first_idx
            neckline = secondary_data[neckline_idx]
        
        # 3. Neckline should be significantly different from peaks
        pattern_height = abs((first_price + second_price) / 2 - neckline)
        avg_peak = (first_price + second_price) / 2
        
        if pattern_height / avg_peak < 0.02:  # At least 2% pattern height
            return None
        
        # 4. Neckline strength: should be a clear support/resistance
        # Check if neckline is tested multiple times
        neckline_tests = 0
        tolerance = pattern_height * 0.1
        
        for i in range(first_idx, second_idx):
            if abs(secondary_data[i] - neckline) < tolerance:
                neckline_tests += 1
        
        neckline_strength = min(neckline_tests / 3, 1.0)  # Normalize to 0-1
        
        # 5. Pattern proportion: balanced between peaks
        mid_point = (first_idx + second_idx) // 2
        time_balance = 1.0 - abs(neckline_idx - mid_point) / (second_idx - first_idx)
        proportion_score = time_balance
        
        reasons = [
            f"{'Double Bottom' if inverted else 'Double Top'} pattern detected",
            f"First peak at {first_idx}, Second peak at {second_idx}",
            f"Peak similarity: {similarity_score*100:.1f}%",
            f"Pattern height: {pattern_height:.2f}",
            f"Neckline at {neckline:.2f}"
        ]
        
        return {
            'first_peak_idx': first_idx,
            'second_peak_idx': second_idx,
            'neckline_idx': neckline_idx,
            'neckline': neckline,
            'pattern_height': pattern_height,
            'similarity_score': similarity_score,
            'neckline_strength': neckline_strength,
            'proportion_score': proportion_score,
            'confidence': (similarity_score + neckline_strength + proportion_score) / 3,
            'reasons': reasons
        }
    
    def _check_neckline_breakout(self,
                                 close: np.ndarray,
                                 neckline: float,
                                 second_peak_idx: int,
                                 inverted: bool) -> Optional[int]:
        """
        Check if price has broken through neckline after second peak
        
        Returns:
            Index of breakout bar, or None if no breakout
        """
        # Check bars after second peak
        for i in range(second_peak_idx + 1, len(close)):
            if inverted:
                # Double Bottom: breakout above neckline
                if close[i] > neckline * 1.01:  # 1% above for confirmation
                    return i
            else:
                # Double Top: breakout below neckline
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
