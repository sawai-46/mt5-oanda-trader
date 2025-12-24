"""
Engulfing Pattern Detector

Engulfing Pattern:
- Strong reversal signal
- Current candle completely engulfs previous candle's body
- Bullish Engulfing: After downtrend, large bullish candle engulfs bearish candle
- Bearish Engulfing: After uptrend, large bearish candle engulfs bullish candle
"""

from typing import List
from .base_detector import BaseCandleDetector, CandleData, PatternResult


class EngulfingDetector(BaseCandleDetector):
    """
    Engulfing Pattern Detector
    
    Detects bullish and bearish engulfing candlestick patterns.
    An engulfing pattern occurs when the current candle's body completely 
    engulfs the previous candle's body.
    
    Bullish Engulfing:
    - Previous candle is bearish (red)
    - Current candle is bullish (green) and engulfs previous body
    - Indicates potential reversal from downtrend
    
    Bearish Engulfing:
    - Previous candle is bullish (green)
    - Current candle is bearish (red) and engulfs previous body
    - Indicates potential reversal from uptrend
    
    Size Filter:
    - Both candles must meet minimum ATR ratio to avoid noise
    """
    
    def __init__(self, 
                 min_confidence: float = 0.5,
                 min_engulf_ratio: float = 1.0,
                 min_body_atr_ratio: float = 0.3,
                 min_range_atr_ratio: float = 0.5):
        """
        Args:
            min_confidence: Minimum confidence threshold
            min_engulf_ratio: Minimum ratio of current body to previous body
            min_body_atr_ratio: Minimum body size as ratio of ATR (default: 0.3)
            min_range_atr_ratio: Minimum range size as ratio of ATR (default: 0.5)
        """
        super().__init__(min_confidence)
        self.pattern_name = "Engulfing"
        self.min_engulf_ratio = min_engulf_ratio
        self.min_body_atr_ratio = min_body_atr_ratio
        self.min_range_atr_ratio = min_range_atr_ratio
    
    def detect(self, candles: List[CandleData]) -> PatternResult:
        """
        Detect engulfing pattern
        
        Args:
            candles: List of candle data (most recent last)
        
        Returns:
            PatternResult with detection outcome
        """
        if len(candles) < 2:
            return self.create_result(
                detected=False,
                signal=0,
                confidence=0.0,
                reasons=["Need at least 2 candles for engulfing pattern"],
                metadata={}
            )
        
        prev_candle = candles[-2]
        curr_candle = candles[-1]
        
        # ATR size filter to avoid noise
        atr = self._calculate_atr(candles, period=14)
        
        if atr > 0:
            # Check current candle size
            curr_body_size = abs(curr_candle.body)
            curr_range_size = curr_candle.total_range
            curr_body_atr_ratio = curr_body_size / atr
            curr_range_atr_ratio = curr_range_size / atr
            
            if curr_body_atr_ratio < self.min_body_atr_ratio:
                return self.create_result(
                    detected=False,
                    signal=0,
                    confidence=0.0,
                    reasons=[f"Current body too small: {curr_body_atr_ratio:.2f}x ATR < {self.min_body_atr_ratio}x"],
                    metadata={'atr': atr, 'curr_body_atr_ratio': curr_body_atr_ratio}
                )
            
            if curr_range_atr_ratio < self.min_range_atr_ratio:
                return self.create_result(
                    detected=False,
                    signal=0,
                    confidence=0.0,
                    reasons=[f"Current range too small: {curr_range_atr_ratio:.2f}x ATR < {self.min_range_atr_ratio}x"],
                    metadata={'atr': atr, 'curr_range_atr_ratio': curr_range_atr_ratio}
                )
        
        # Check for meaningful candles
        if curr_candle.body < 0.0001 or prev_candle.body < 0.0001:
            return self.create_result(
                detected=False,
                signal=0,
                confidence=0.0,
                reasons=["Candle bodies too small for Engulfing pattern"],
                metadata={}
            )
        
        # Analyze engulfing pattern
        is_bullish, is_bearish, confidence, reasons = self._analyze_engulfing(
            prev_candle, curr_candle, candles
        )
        
        # Determine signal
        if is_bullish and not is_bearish:
            signal = 1  # BUY
        elif is_bearish and not is_bullish:
            signal = -1  # SELL
        else:
            signal = 0  # NEUTRAL
        
        detected = (is_bullish or is_bearish) and confidence >= self.min_confidence
        
        metadata = {
            'prev_body': prev_candle.body,
            'prev_bullish': prev_candle.is_bullish,
            'current_body': curr_candle.body,
            'current_bullish': curr_candle.is_bullish,
            'engulf_ratio': curr_candle.body / prev_candle.body if prev_candle.body > 0 else 0,
            'prev_close': prev_candle.close,
            'prev_open': prev_candle.open,
            'current_close': curr_candle.close,
            'current_open': curr_candle.open,
            'atr': atr,
            'curr_body_atr_ratio': curr_body_atr_ratio if atr > 0 else 0.0,
            'curr_range_atr_ratio': curr_range_atr_ratio if atr > 0 else 0.0
        }
        
        return self.create_result(
            detected=detected,
            signal=signal,
            confidence=confidence,
            reasons=reasons,
            metadata=metadata
        )
    
    def _analyze_engulfing(self, previous: CandleData, current: CandleData, 
                          candles: List[CandleData]) -> tuple:
        """
        Analyze if pattern is Engulfing
        
        Returns:
            (is_bullish_engulfing, is_bearish_engulfing, confidence, reasons)
        """
        reasons = []
        is_bullish = False
        is_bearish = False
        
        # Get body boundaries
        prev_body_top = max(previous.open, previous.close)
        prev_body_bottom = min(previous.open, previous.close)
        curr_body_top = max(current.open, current.close)
        curr_body_bottom = min(current.open, current.close)
        
        # Check if current candle engulfs previous candle's body
        body_engulfed = (curr_body_bottom <= prev_body_bottom and 
                        curr_body_top >= prev_body_top)
        
        if not body_engulfed:
            reasons.append("Current candle does not engulf previous candle body")
            return False, False, 0.0, reasons
        
        # Check for opposite colors
        if previous.is_bullish == current.is_bullish:
            reasons.append("Candles must have opposite colors for Engulfing pattern")
            return False, False, 0.0, reasons
        
        # Calculate engulfing ratio
        engulf_ratio = current.body / previous.body
        
        if engulf_ratio < self.min_engulf_ratio:
            reasons.append(f"Engulf ratio {engulf_ratio:.2f} below minimum {self.min_engulf_ratio}")
            return False, False, 0.0, reasons
        
        # Bullish Engulfing: Previous bearish, Current bullish
        if previous.is_bearish and current.is_bullish:
            is_bullish = True
            reasons.append(f"Bullish Engulfing detected: Current bullish body ({current.body:.5f}) " +
                          f"engulfs previous bearish body ({previous.body:.5f})")
            reasons.append(f"Engulf ratio: {engulf_ratio:.2f}x")
            
            # Check for downtrend context (increases confidence)
            if self._is_in_downtrend(candles[:-1]):
                reasons.append("Pattern follows downtrend (stronger signal)")
        
        # Bearish Engulfing: Previous bullish, Current bearish
        elif previous.is_bullish and current.is_bearish:
            is_bearish = True
            reasons.append(f"Bearish Engulfing detected: Current bearish body ({current.body:.5f}) " +
                          f"engulfs previous bullish body ({previous.body:.5f})")
            reasons.append(f"Engulf ratio: {engulf_ratio:.2f}x")
            
            # Check for uptrend context (increases confidence)
            if self._is_in_uptrend(candles[:-1]):
                reasons.append("Pattern follows uptrend (stronger signal)")
        
        # Calculate confidence
        confidence = self._calculate_confidence(candles)
        
        return is_bullish, is_bearish, confidence, reasons
    
    def _calculate_confidence(self, candles: List[CandleData]) -> float:
        """
        Calculate confidence score for Engulfing pattern
        
        Factors:
        1. Engulfing ratio (larger = better)
        2. Size relative to recent average
        3. Trend context (following trend = better)
        4. Volume (if available, higher = better)
        """
        current = candles[-1]
        previous = candles[-2]
        
        # Engulfing ratio score (how much larger is current vs previous)
        engulf_ratio = current.body / previous.body if previous.body > 0 else 1.0
        engulf_score = min(engulf_ratio / 3.0, 1.0)  # Max score at 3x engulfing
        
        # Size score (compared to recent average)
        avg_body = self._get_average_body(candles[:-1], periods=10)
        if avg_body < 0.0001:
            size_score = 0.5
        else:
            size_ratio = current.body / avg_body
            size_score = min(size_ratio / 2.0, 1.0)  # Max score at 2x average
        
        # Trend context score
        if current.is_bullish:
            # Bullish engulfing after downtrend
            trend_score = 1.0 if self._is_in_downtrend(candles[:-1]) else 0.6
        else:
            # Bearish engulfing after uptrend
            trend_score = 1.0 if self._is_in_uptrend(candles[:-1]) else 0.6
        
        # Previous candle size (smaller previous = more significant reversal)
        prev_size_score = 1.0 - min(previous.body / avg_body, 1.0) * 0.3
        
        # Weighted average
        confidence = (
            engulf_score * 0.35 +
            size_score * 0.25 +
            trend_score * 0.30 +
            prev_size_score * 0.10
        )
        
        return min(confidence, 1.0)
    
    def _is_in_uptrend(self, candles: List[CandleData], periods: int = 5) -> bool:
        """
        Check if candles show uptrend
        Simple check: more bullish candles and rising closes
        """
        if len(candles) < periods:
            periods = len(candles)
        
        if periods < 2:
            return False
        
        recent = candles[-periods:]
        
        # Count bullish candles
        bullish_count = sum(1 for c in recent if c.is_bullish)
        
        # Check if closes are generally rising
        closes = [c.close for c in recent]
        rising = sum(1 for i in range(1, len(closes)) if closes[i] > closes[i-1])
        
        # Uptrend if majority bullish and mostly rising
        return bullish_count > periods * 0.6 and rising > len(closes) * 0.5
    
    def _is_in_downtrend(self, candles: List[CandleData], periods: int = 5) -> bool:
        """
        Check if candles show downtrend
        Simple check: more bearish candles and falling closes
        """
        if len(candles) < periods:
            periods = len(candles)
        
        if periods < 2:
            return False
        
        recent = candles[-periods:]
        
        # Count bearish candles
        bearish_count = sum(1 for c in recent if c.is_bearish)
        
        # Check if closes are generally falling
        closes = [c.close for c in recent]
        falling = sum(1 for i in range(1, len(closes)) if closes[i] < closes[i-1])
        
        # Downtrend if majority bearish and mostly falling
        return bearish_count > periods * 0.6 and falling > len(closes) * 0.5
