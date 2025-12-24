"""
False Breakout Module

Detects false breakouts (failed breakouts) at key levels with 3-stage scoring system.
High reliability signal by detecting when price fails to hold above/below key levels.

Weight: 20% (highest among 7 modules)
"""

import numpy as np
from typing import Optional, Tuple
from enum import Enum
from dataclasses import dataclass
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from signal_engine.signal_aggregator import ModuleScore, SignalType


class FalseBreakoutType(Enum):
    """False breakout type"""
    FALSE_BREAKOUT_UP = "false_breakout_up"      # Failed upward breakout → Sell signal
    FALSE_BREAKOUT_DOWN = "false_breakout_down"  # Failed downward breakout → Buy signal


class FalseBreakoutStrength(Enum):
    """False breakout strength"""
    WEAK = 0.3      # Wick only (hint)
    MEDIUM = 0.7    # Close-based immediate reversal
    STRONG = 1.0    # Engulfing or strong body


@dataclass
class FalseBreakout:
    """False breakout information"""
    breakout_type: FalseBreakoutType
    strength: FalseBreakoutStrength
    confidence: float
    
    key_level: float
    level_type: str
    breakout_index: int
    reversal_index: int
    reversal_strength: float
    is_engulfing: bool
    atr_ratio: float
    time_to_reversal: int


class FalseBreakoutModule:
    """
    False Breakout Detection Module (20% weight)
    
    3-Stage Scoring System:
    - Score 0.3 (WEAK): Wick-only breakout, price immediately rejects
    - Score 0.7 (MEDIUM): Close above/below level, but immediate reversal
    - Score 1.0 (STRONG): Engulfing pattern or strong body reversal
    
    Detects failed breakouts at:
    - Range highs/lows
    - Previous high/low
    - Round numbers
    """
    
    def __init__(self,
                 atr_period: int = 14,
                 strong_body_threshold: float = 0.7,
                 immediate_reversal_bars: int = 3,
                 lookback_bars: int = 20):
        """
        Initialize false breakout detector
        
        Args:
            atr_period: ATR calculation period
            strong_body_threshold: Minimum body/ATR ratio for "strong body"
            immediate_reversal_bars: Max bars for "immediate" reversal
            lookback_bars: Lookback period for range detection
        """
        self.atr_period = atr_period
        self.strong_body_threshold = strong_body_threshold
        self.immediate_reversal_bars = immediate_reversal_bars
        self.lookback_bars = lookback_bars
    
    def analyze(self,
                opens: np.ndarray,
                highs: np.ndarray,
                lows: np.ndarray,
                closes: np.ndarray) -> ModuleScore:
        """
        Analyze for false breakouts
        
        Args:
            opens, highs, lows, closes: Price arrays (most recent last)
            
        Returns:
            ModuleScore with signal and confidence
        """
        if len(closes) < self.lookback_bars:
            return ModuleScore(
                signal=SignalType.NEUTRAL,
                confidence=0.0,
                reason="Insufficient data for false breakout detection"
            )
        
        # Detect key levels
        range_high = np.max(highs[-self.lookback_bars:])
        range_low = np.min(lows[-self.lookback_bars:])
        prev_high = highs[-2] if len(highs) > 1 else range_high
        prev_low = lows[-2] if len(lows) > 1 else range_low
        
        # Check for false breakout up (sell signal)
        fb_up = self._detect_false_breakout_up(
            highs, lows, opens, closes, range_high, "range_high"
        )
        
        if fb_up is None:
            fb_up = self._detect_false_breakout_up(
                highs, lows, opens, closes, prev_high, "prev_high"
            )
        
        # Check for false breakout down (buy signal)
        fb_down = self._detect_false_breakout_down(
            highs, lows, opens, closes, range_low, "range_low"
        )
        
        if fb_down is None:
            fb_down = self._detect_false_breakout_down(
                highs, lows, opens, closes, prev_low, "prev_low"
            )
        
        # Determine strongest signal
        if fb_up and fb_down:
            # Both detected, use stronger one
            if fb_up.confidence > fb_down.confidence:
                return self._create_score(fb_up, SignalType.SELL)
            else:
                return self._create_score(fb_down, SignalType.BUY)
        elif fb_up:
            return self._create_score(fb_up, SignalType.SELL)
        elif fb_down:
            return self._create_score(fb_down, SignalType.BUY)
        else:
            return ModuleScore(
                signal=SignalType.NEUTRAL,
                confidence=0.0,
                reason="No false breakout detected"
            )
    
    def _detect_false_breakout_up(self,
                                  highs: np.ndarray,
                                  lows: np.ndarray,
                                  opens: np.ndarray,
                                  closes: np.ndarray,
                                  key_level: float,
                                  level_type: str) -> Optional[FalseBreakout]:
        """Detect failed upward breakout (bearish)"""
        
        atr = self._calculate_atr(highs, lows, closes)
        
        # Check last few bars
        for i in range(len(closes) - 1, max(0, len(closes) - 10), -1):
            if highs[i] > key_level:
                breakout_index = i
                
                # Score 0.3: Wick-only breakout
                if closes[i] < key_level:
                    return FalseBreakout(
                        breakout_type=FalseBreakoutType.FALSE_BREAKOUT_UP,
                        strength=FalseBreakoutStrength.WEAK,
                        confidence=0.3,
                        key_level=key_level,
                        level_type=level_type,
                        breakout_index=breakout_index,
                        reversal_index=i,
                        reversal_strength=0.0,
                        is_engulfing=False,
                        atr_ratio=0.0,
                        time_to_reversal=0
                    )
                
                # Check next bar
                if i + 1 < len(closes):
                    next_close = closes[i + 1]
                    next_open = opens[i + 1]
                    next_body = abs(next_close - next_open)
                    
                    # Score 0.7/1.0: Close-based reversal
                    if next_close < key_level and closes[i] >= key_level:
                        reversal_strength = next_body / atr if atr > 0 else 0
                        
                        # Check for engulfing
                        is_engulfing = (
                            next_close < opens[i] and 
                            next_open > closes[i] and
                            next_close < closes[i]
                        )
                        
                        # Score 1.0: Strong reversal
                        if is_engulfing or reversal_strength >= self.strong_body_threshold:
                            return FalseBreakout(
                                breakout_type=FalseBreakoutType.FALSE_BREAKOUT_UP,
                                strength=FalseBreakoutStrength.STRONG,
                                confidence=1.0,
                                key_level=key_level,
                                level_type=level_type,
                                breakout_index=breakout_index,
                                reversal_index=i + 1,
                                reversal_strength=reversal_strength,
                                is_engulfing=is_engulfing,
                                atr_ratio=reversal_strength,
                                time_to_reversal=1
                            )
                        # Score 0.7: Medium reversal
                        else:
                            return FalseBreakout(
                                breakout_type=FalseBreakoutType.FALSE_BREAKOUT_UP,
                                strength=FalseBreakoutStrength.MEDIUM,
                                confidence=0.7,
                                key_level=key_level,
                                level_type=level_type,
                                breakout_index=breakout_index,
                                reversal_index=i + 1,
                                reversal_strength=reversal_strength,
                                is_engulfing=False,
                                atr_ratio=reversal_strength,
                                time_to_reversal=1
                            )
        
        return None
    
    def _detect_false_breakout_down(self,
                                    highs: np.ndarray,
                                    lows: np.ndarray,
                                    opens: np.ndarray,
                                    closes: np.ndarray,
                                    key_level: float,
                                    level_type: str) -> Optional[FalseBreakout]:
        """Detect failed downward breakout (bullish)"""
        
        atr = self._calculate_atr(highs, lows, closes)
        
        # Check last few bars
        for i in range(len(closes) - 1, max(0, len(closes) - 10), -1):
            if lows[i] < key_level:
                breakout_index = i
                
                # Score 0.3: Wick-only breakout
                if closes[i] > key_level:
                    return FalseBreakout(
                        breakout_type=FalseBreakoutType.FALSE_BREAKOUT_DOWN,
                        strength=FalseBreakoutStrength.WEAK,
                        confidence=0.3,
                        key_level=key_level,
                        level_type=level_type,
                        breakout_index=breakout_index,
                        reversal_index=i,
                        reversal_strength=0.0,
                        is_engulfing=False,
                        atr_ratio=0.0,
                        time_to_reversal=0
                    )
                
                # Check next bar
                if i + 1 < len(closes):
                    next_close = closes[i + 1]
                    next_open = opens[i + 1]
                    next_body = abs(next_close - next_open)
                    
                    # Score 0.7/1.0: Close-based reversal
                    if next_close > key_level and closes[i] <= key_level:
                        reversal_strength = next_body / atr if atr > 0 else 0
                        
                        # Check for engulfing
                        is_engulfing = (
                            next_close > opens[i] and 
                            next_open < closes[i] and
                            next_close > closes[i]
                        )
                        
                        # Score 1.0: Strong reversal
                        if is_engulfing or reversal_strength >= self.strong_body_threshold:
                            return FalseBreakout(
                                breakout_type=FalseBreakoutType.FALSE_BREAKOUT_DOWN,
                                strength=FalseBreakoutStrength.STRONG,
                                confidence=1.0,
                                key_level=key_level,
                                level_type=level_type,
                                breakout_index=breakout_index,
                                reversal_index=i + 1,
                                reversal_strength=reversal_strength,
                                is_engulfing=is_engulfing,
                                atr_ratio=reversal_strength,
                                time_to_reversal=1
                            )
                        # Score 0.7: Medium reversal
                        else:
                            return FalseBreakout(
                                breakout_type=FalseBreakoutType.FALSE_BREAKOUT_DOWN,
                                strength=FalseBreakoutStrength.MEDIUM,
                                confidence=0.7,
                                key_level=key_level,
                                level_type=level_type,
                                breakout_index=breakout_index,
                                reversal_index=i + 1,
                                reversal_strength=reversal_strength,
                                is_engulfing=False,
                                atr_ratio=reversal_strength,
                                time_to_reversal=1
                            )
        
        return None
    
    def _calculate_atr(self,
                      highs: np.ndarray,
                      lows: np.ndarray,
                      closes: np.ndarray) -> float:
        """Calculate Average True Range"""
        if len(closes) < self.atr_period + 1:
            return 0.0
        
        # True Range calculation
        high_low = highs[1:] - lows[1:]
        high_close = np.abs(highs[1:] - closes[:-1])
        low_close = np.abs(lows[1:] - closes[:-1])
        
        true_ranges = np.maximum(high_low, np.maximum(high_close, low_close))
        
        # ATR = simple moving average of TR
        if len(true_ranges) >= self.atr_period:
            atr = np.mean(true_ranges[-self.atr_period:])
            return float(atr)
        
        return 0.0
    
    def _create_score(self,
                     fb: FalseBreakout,
                     signal: SignalType) -> ModuleScore:
        """Create ModuleScore from FalseBreakout"""
        
        signal_name = "Bullish" if signal == SignalType.BUY else "Bearish"
        strength_name = fb.strength.name
        
        reason = (
            f"{signal_name} False Breakout ({strength_name}): "
            f"Failed {fb.level_type} breakout at {fb.key_level:.5f}, "
            f"confidence {fb.confidence:.2f}"
        )
        
        if fb.is_engulfing:
            reason += " (Engulfing)"
        
        return ModuleScore(
            signal=signal,
            confidence=fb.confidence,
            reason=reason
        )
