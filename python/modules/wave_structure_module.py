"""
Wave Structure Module (10% weight)
Two-Leg Pattern Detection based on Al Brooks methodology
"""
from dataclasses import dataclass
from typing import Optional, List, Tuple
import numpy as np
from signal_engine.signal_aggregator import ModuleScore, SignalType


@dataclass
class LegInfo:
    """Wave leg information"""
    start_index: int
    end_index: int
    start_price: float
    end_price: float
    direction: int  # 1: up, -1: down
    strength: float


@dataclass
class TwoLegStructure:
    """Two-Leg pattern structure"""
    first_leg: LegInfo
    pullback: LegInfo
    second_leg: LegInfo
    
    pattern_type: str        # 'two_leg_up' or 'two_leg_down'
    confidence: float        # 0-1
    pullback_ratio: float    # Fibonacci retracement depth
    second_leg_strength: float
    breakout_confirmed: bool # 2nd leg breaks 1st leg high/low


class TwoLegDetector:
    """Two-Leg structure detection engine (Al Brooks methodology)"""
    
    def __init__(self, 
                 min_leg_bars: int = 3,
                 pullback_min_ratio: float = 0.382,
                 pullback_max_ratio: float = 0.618,
                 pip_threshold: float = 10.0,
                 swing_period: int = 5):
        """
        Initialize Two-Leg detector
        
        Args:
            min_leg_bars: Minimum bars for valid leg
            pullback_min_ratio: Minimum pullback (Fibonacci 38.2%)
            pullback_max_ratio: Maximum pullback (Fibonacci 61.8%)
            pip_threshold: Minimum leg size in pips
            swing_period: Period for swing high/low detection
        """
        self.min_leg_bars = min_leg_bars
        self.pullback_min_ratio = pullback_min_ratio
        self.pullback_max_ratio = pullback_max_ratio
        self.pip_threshold = pip_threshold
        self.swing_period = swing_period
    
    def detect_two_leg_up(self, 
                         highs: np.ndarray,
                         lows: np.ndarray,
                         closes: np.ndarray,
                         lookback: int = 50) -> Optional[TwoLegStructure]:
        """
        Detect bullish N-wave (Two-Leg Up)
        
        Steps:
        1. Detect swing points (highs/lows)
        2. 1st leg: swing low → swing high
        3. Pullback: 1st leg high → next swing low
        4. Check pullback depth (38.2% - 61.8%)
        5. 2nd leg: pullback low → current price
        6. Confirm breakout (2nd leg > 1st leg high)
        7. Calculate confidence
        
        Args:
            highs: High prices array
            lows: Low prices array
            closes: Close prices array
            lookback: Bars to look back
            
        Returns:
            TwoLegStructure if detected, None otherwise
        """
        if len(highs) < lookback or len(lows) < lookback:
            return None
        
        # Get recent data
        recent_highs = highs[-lookback:]
        recent_lows = lows[-lookback:]
        recent_closes = closes[-lookback:]
        
        # Find swing points
        swing_lows = self._find_swing_lows(recent_lows)
        swing_highs = self._find_swing_highs(recent_highs)
        
        if len(swing_lows) < 2 or len(swing_highs) < 2:
            return None
        
        # Try to identify pattern from most recent swing points
        for i in range(len(swing_lows) - 1):
            sl1_idx = swing_lows[i]
            sl1_price = recent_lows[sl1_idx]
            
            # Find swing high after sl1
            sh1_candidates = [sh for sh in swing_highs if sh > sl1_idx]
            if not sh1_candidates:
                continue
            sh1_idx = sh1_candidates[0]
            sh1_price = recent_highs[sh1_idx]
            
            # Find swing low after sh1 (pullback)
            sl2_candidates = [sl for sl in swing_lows if sl > sh1_idx]
            if not sl2_candidates:
                continue
            sl2_idx = sl2_candidates[0]
            sl2_price = recent_lows[sl2_idx]
            
            # Check 1st leg validity
            first_leg_pips = (sh1_price - sl1_price) * 10000
            if first_leg_pips < self.pip_threshold:
                continue
            
            # Check pullback ratio
            pullback_pips = (sh1_price - sl2_price) * 10000
            if first_leg_pips == 0:
                continue
            pullback_ratio = pullback_pips / first_leg_pips
            
            if pullback_ratio < self.pullback_min_ratio or pullback_ratio > self.pullback_max_ratio:
                continue
            
            # 2nd leg: from pullback low to current close
            current_price = recent_closes[-1]
            second_leg_pips = (current_price - sl2_price) * 10000
            
            if second_leg_pips < 0:
                continue
            
            # Breakout confirmation
            breakout_confirmed = current_price > sh1_price
            
            # Calculate confidence
            confidence = self._calculate_confidence(
                first_leg_pips, pullback_ratio, second_leg_pips, breakout_confirmed
            )
            
            if confidence < 0.3:
                continue
            
            # Build structure
            first_leg = LegInfo(
                start_index=sl1_idx,
                end_index=sh1_idx,
                start_price=sl1_price,
                end_price=sh1_price,
                direction=1,
                strength=first_leg_pips
            )
            
            pullback = LegInfo(
                start_index=sh1_idx,
                end_index=sl2_idx,
                start_price=sh1_price,
                end_price=sl2_price,
                direction=-1,
                strength=pullback_pips
            )
            
            second_leg = LegInfo(
                start_index=sl2_idx,
                end_index=len(recent_closes) - 1,
                start_price=sl2_price,
                end_price=current_price,
                direction=1,
                strength=second_leg_pips
            )
            
            return TwoLegStructure(
                first_leg=first_leg,
                pullback=pullback,
                second_leg=second_leg,
                pattern_type='two_leg_up',
                confidence=confidence,
                pullback_ratio=pullback_ratio,
                second_leg_strength=second_leg_pips,
                breakout_confirmed=breakout_confirmed
            )
        
        return None
    
    def detect_two_leg_down(self, 
                           highs: np.ndarray,
                           lows: np.ndarray,
                           closes: np.ndarray,
                           lookback: int = 50) -> Optional[TwoLegStructure]:
        """
        Detect bearish inverted N-wave (Two-Leg Down)
        
        Steps:
        1. Detect swing points (highs/lows)
        2. 1st leg: swing high → swing low
        3. Pullback: 1st leg low → next swing high
        4. Check pullback depth (38.2% - 61.8%)
        5. 2nd leg: pullback high → current price
        6. Confirm breakout (2nd leg < 1st leg low)
        7. Calculate confidence
        
        Args:
            highs: High prices array
            lows: Low prices array
            closes: Close prices array
            lookback: Bars to look back
            
        Returns:
            TwoLegStructure if detected, None otherwise
        """
        if len(highs) < lookback or len(lows) < lookback:
            return None
        
        # Get recent data
        recent_highs = highs[-lookback:]
        recent_lows = lows[-lookback:]
        recent_closes = closes[-lookback:]
        
        # Find swing points
        swing_lows = self._find_swing_lows(recent_lows)
        swing_highs = self._find_swing_highs(recent_highs)
        
        if len(swing_lows) < 2 or len(swing_highs) < 2:
            return None
        
        # Try to identify pattern from most recent swing points
        for i in range(len(swing_highs) - 1):
            sh1_idx = swing_highs[i]
            sh1_price = recent_highs[sh1_idx]
            
            # Find swing low after sh1
            sl1_candidates = [sl for sl in swing_lows if sl > sh1_idx]
            if not sl1_candidates:
                continue
            sl1_idx = sl1_candidates[0]
            sl1_price = recent_lows[sl1_idx]
            
            # Find swing high after sl1 (pullback)
            sh2_candidates = [sh for sh in swing_highs if sh > sl1_idx]
            if not sh2_candidates:
                continue
            sh2_idx = sh2_candidates[0]
            sh2_price = recent_highs[sh2_idx]
            
            # Check 1st leg validity
            first_leg_pips = (sh1_price - sl1_price) * 10000
            if first_leg_pips < self.pip_threshold:
                continue
            
            # Check pullback ratio
            pullback_pips = (sh2_price - sl1_price) * 10000
            if first_leg_pips == 0:
                continue
            pullback_ratio = pullback_pips / first_leg_pips
            
            if pullback_ratio < self.pullback_min_ratio or pullback_ratio > self.pullback_max_ratio:
                continue
            
            # 2nd leg: from pullback high to current close
            current_price = recent_closes[-1]
            second_leg_pips = (sh2_price - current_price) * 10000
            
            if second_leg_pips < 0:
                continue
            
            # Breakout confirmation
            breakout_confirmed = current_price < sl1_price
            
            # Calculate confidence
            confidence = self._calculate_confidence(
                first_leg_pips, pullback_ratio, second_leg_pips, breakout_confirmed
            )
            
            if confidence < 0.3:
                continue
            
            # Build structure
            first_leg = LegInfo(
                start_index=sh1_idx,
                end_index=sl1_idx,
                start_price=sh1_price,
                end_price=sl1_price,
                direction=-1,
                strength=first_leg_pips
            )
            
            pullback = LegInfo(
                start_index=sl1_idx,
                end_index=sh2_idx,
                start_price=sl1_price,
                end_price=sh2_price,
                direction=1,
                strength=pullback_pips
            )
            
            second_leg = LegInfo(
                start_index=sh2_idx,
                end_index=len(recent_closes) - 1,
                start_price=sh2_price,
                end_price=current_price,
                direction=-1,
                strength=second_leg_pips
            )
            
            return TwoLegStructure(
                first_leg=first_leg,
                pullback=pullback,
                second_leg=second_leg,
                pattern_type='two_leg_down',
                confidence=confidence,
                pullback_ratio=pullback_ratio,
                second_leg_strength=second_leg_pips,
                breakout_confirmed=breakout_confirmed
            )
        
        return None
    
    def _calculate_confidence(self,
                            first_leg_pips: float,
                            pullback_ratio: float,
                            second_leg_pips: float,
                            breakout_confirmed: bool) -> float:
        """
        Calculate confidence score
        
        Components:
        1. 1st leg strength (max 30%)
        2. Pullback validity (max 30%) - closer to 50% = higher score
        3. 2nd leg strength (max 20%)
        4. Breakout confirmation (20%)
        
        Args:
            first_leg_pips: 1st leg size in pips
            pullback_ratio: Pullback depth ratio
            second_leg_pips: 2nd leg size in pips
            breakout_confirmed: Whether breakout is confirmed
            
        Returns:
            Confidence score 0-1
        """
        confidence = 0.0
        
        # 1. 1st leg strength
        confidence += min(first_leg_pips / 50, 1.0) * 0.3
        
        # 2. Pullback validity (50% is ideal)
        ideal_ratio = 0.5
        ratio_deviation = abs(pullback_ratio - ideal_ratio)
        confidence += (1 - ratio_deviation / 0.5) * 0.3
        
        # 3. 2nd leg strength
        confidence += min(second_leg_pips / 50, 1.0) * 0.2
        
        # 4. Breakout confirmation
        if breakout_confirmed:
            confidence += 0.2
        
        return min(confidence, 1.0)
    
    def _find_swing_lows(self, lows: np.ndarray) -> List[int]:
        """
        Find swing low points
        
        A swing low is a local minimum where the price is lower than
        swing_period bars before and after.
        
        Args:
            lows: Low prices array
            
        Returns:
            List of swing low indices
        """
        swing_lows = []
        period = self.swing_period
        
        for i in range(period, len(lows) - period):
            is_swing_low = True
            current_low = lows[i]
            
            # Check left side
            for j in range(i - period, i):
                if lows[j] <= current_low:
                    is_swing_low = False
                    break
            
            if not is_swing_low:
                continue
            
            # Check right side
            for j in range(i + 1, i + period + 1):
                if lows[j] <= current_low:
                    is_swing_low = False
                    break
            
            if is_swing_low:
                swing_lows.append(i)
        
        return swing_lows
    
    def _find_swing_highs(self, highs: np.ndarray) -> List[int]:
        """
        Find swing high points
        
        A swing high is a local maximum where the price is higher than
        swing_period bars before and after.
        
        Args:
            highs: High prices array
            
        Returns:
            List of swing high indices
        """
        swing_highs = []
        period = self.swing_period
        
        for i in range(period, len(highs) - period):
            is_swing_high = True
            current_high = highs[i]
            
            # Check left side
            for j in range(i - period, i):
                if highs[j] >= current_high:
                    is_swing_high = False
                    break
            
            if not is_swing_high:
                continue
            
            # Check right side
            for j in range(i + 1, i + period + 1):
                if highs[j] >= current_high:
                    is_swing_high = False
                    break
            
            if is_swing_high:
                swing_highs.append(i)
        
        return swing_highs


class WaveStructureModule:
    """Wave Structure Module - Two-Leg Pattern Detection (10% weight)"""
    
    def __init__(self,
                 min_leg_bars: int = 3,
                 pullback_min_ratio: float = 0.382,
                 pullback_max_ratio: float = 0.618,
                 pip_threshold: float = 10.0,
                 swing_period: int = 5):
        """
        Initialize Wave Structure Module
        
        Args:
            min_leg_bars: Minimum bars for valid leg
            pullback_min_ratio: Minimum pullback (Fibonacci 38.2%)
            pullback_max_ratio: Maximum pullback (Fibonacci 61.8%)
            pip_threshold: Minimum leg size in pips
            swing_period: Period for swing high/low detection
        """
        self.detector = TwoLegDetector(
            min_leg_bars=min_leg_bars,
            pullback_min_ratio=pullback_min_ratio,
            pullback_max_ratio=pullback_max_ratio,
            pip_threshold=pip_threshold,
            swing_period=swing_period
        )
    
    def analyze(self,
                open_prices: np.ndarray,
                high_prices: np.ndarray,
                low_prices: np.ndarray,
                close_prices: np.ndarray,
                lookback: int = 50) -> ModuleScore:
        """
        Analyze price data for Two-Leg patterns
        
        Args:
            open_prices: Open prices array
            high_prices: High prices array
            low_prices: Low prices array
            close_prices: Close prices array
            lookback: Bars to analyze
            
        Returns:
            ModuleScore with signal and confidence
        """
        # Try to detect bullish Two-Leg Up
        two_leg_up = self.detector.detect_two_leg_up(
            high_prices, low_prices, close_prices, lookback
        )
        
        if two_leg_up:
            reason = (
                f"Two-Leg Up detected: "
                f"1st leg={two_leg_up.first_leg.strength:.1f}pips, "
                f"pullback={two_leg_up.pullback_ratio*100:.1f}%, "
                f"2nd leg={two_leg_up.second_leg_strength:.1f}pips, "
                f"breakout={'YES' if two_leg_up.breakout_confirmed else 'NO'}"
            )
            return ModuleScore(
                signal=SignalType.BUY,
                confidence=two_leg_up.confidence,
                reason=reason
            )
        
        # Try to detect bearish Two-Leg Down
        two_leg_down = self.detector.detect_two_leg_down(
            high_prices, low_prices, close_prices, lookback
        )
        
        if two_leg_down:
            reason = (
                f"Two-Leg Down detected: "
                f"1st leg={two_leg_down.first_leg.strength:.1f}pips, "
                f"pullback={two_leg_down.pullback_ratio*100:.1f}%, "
                f"2nd leg={two_leg_down.second_leg_strength:.1f}pips, "
                f"breakout={'YES' if two_leg_down.breakout_confirmed else 'NO'}"
            )
            return ModuleScore(
                signal=SignalType.SELL,
                confidence=two_leg_down.confidence,
                reason=reason
            )
        
        # No pattern detected
        return ModuleScore(
            signal=SignalType.NEUTRAL,
            confidence=0.0,
            reason="No Two-Leg pattern detected"
        )
