"""
Pin Bar Pattern Detector

Pin Bar (Pinocchio Bar):
- Long wick (nose) in one direction
- Small body
- Strong reversal signal
- Bullish Pin Bar: Long lower wick, suggests buying pressure
- Bearish Pin Bar: Long upper wick, suggests selling pressure
"""

from typing import List
from .base_detector import BaseCandleDetector, CandleData, PatternResult


class PinBarDetector(BaseCandleDetector):
    """
    Pin Bar Pattern Detector
    
    Detects pin bar (or "pinocchio bar") candlestick patterns.
    A pin bar has a long wick and small body, indicating rejection and potential reversal.
    
    Characteristics:
    - Long wick in one direction (upper or lower)
    - Small body
    - Body positioned at opposite end from wick
    - Indicates strong rejection of price level
    - Minimum size filter using ATR to avoid noise
    """
    
    def __init__(self, 
                 min_confidence: float = 0.5,
                 wick_to_body_ratio: float = 2.0,
                 body_position_threshold: float = 0.33,
                 min_body_atr_ratio: float = 0.3,
                 min_range_atr_ratio: float = 0.5):
        """
        Args:
            min_confidence: Minimum confidence threshold (0.0-1.0)
            wick_to_body_ratio: Minimum ratio of wick to body size (default: 2.0)
            body_position_threshold: Max distance of body from range end (0.0-1.0)
            min_body_atr_ratio: Minimum body size as ratio of ATR (default: 0.3)
            min_range_atr_ratio: Minimum range size as ratio of ATR (default: 0.5)
        """
        super().__init__(min_confidence)
        self.pattern_name = "PinBar"
        self.wick_to_body_ratio = wick_to_body_ratio
        self.body_position_threshold = body_position_threshold
        self.min_body_atr_ratio = min_body_atr_ratio
        self.min_range_atr_ratio = min_range_atr_ratio
    
    def detect(self, candles: List[CandleData]) -> PatternResult:
        """
        Detect pin bar pattern in candle data
        
        Args:
            candles: List of candle data (most recent last)
        
        Returns:
            PatternResult with detection outcome
        """
        if not self._validate_input(candles, min_bars=1):
            return self.create_result(
                detected=False,
                signal=0,
                confidence=0.0,
                reasons=["Insufficient or invalid candle data"],
                metadata={}
            )
        
        current_candle = candles[-1]
        
        # ATR size filter to avoid noise
        atr = self._calculate_atr(candles, period=14)
        body_size = abs(current_candle.body)
        range_size = current_candle.total_range
        
        if atr > 0:
            body_atr_ratio = body_size / atr
            range_atr_ratio = range_size / atr
            
            if body_atr_ratio < self.min_body_atr_ratio:
                return self.create_result(
                    detected=False,
                    signal=0,
                    confidence=0.0,
                    reasons=[f"Body too small: {body_atr_ratio:.2f}x ATR < {self.min_body_atr_ratio}x threshold"],
                    metadata={'atr': atr, 'body_atr_ratio': body_atr_ratio}
                )
            
            if range_atr_ratio < self.min_range_atr_ratio:
                return self.create_result(
                    detected=False,
                    signal=0,
                    confidence=0.0,
                    reasons=[f"Range too small: {range_atr_ratio:.2f}x ATR < {self.min_range_atr_ratio}x threshold"],
                    metadata={'atr': atr, 'range_atr_ratio': range_atr_ratio}
                )
        
        # Check if candle has meaningful range
        if current_candle.total_range < 0.0001:  # Avoid division by zero
            return self.create_result(
                detected=False,
                signal=0,
                confidence=0.0,
                reasons=["Candle range too small"],
                metadata={}
            )
        
        # Analyze Pin Bar characteristics
        is_bullish_pin, is_bearish_pin, confidence, reasons = self._analyze_pin_bar(current_candle, candles)
        
        # Determine signal
        if is_bullish_pin and not is_bearish_pin:
            signal = 1  # BUY
        elif is_bearish_pin and not is_bullish_pin:
            signal = -1  # SELL
        else:
            signal = 0  # NEUTRAL (ambiguous or no pattern)
        
        detected = (is_bullish_pin or is_bearish_pin) and confidence >= self.min_confidence
        
        metadata = {
            'body_size': current_candle.body,
            'upper_shadow': current_candle.upper_shadow,
            'lower_shadow': current_candle.lower_shadow,
            'total_range': current_candle.total_range,
            'wick_to_body_ratio_actual': self._get_dominant_wick_ratio(current_candle),
            'body_position': self._get_body_position(current_candle),
            'atr': atr,
            'body_atr_ratio': body_atr_ratio if atr > 0 else 0.0,
            'range_atr_ratio': range_atr_ratio if atr > 0 else 0.0
        }
        
        return self.create_result(
            detected=detected,
            signal=signal,
            confidence=confidence,
            reasons=reasons,
            metadata=metadata
        )
    
    def _analyze_pin_bar(self, current: CandleData, candles: List[CandleData]) -> tuple:
        """
        Analyze if candle is a Pin Bar
        
        Returns:
            (is_bullish_pin, is_bearish_pin, confidence, reasons)
        """
        reasons = []
        is_bullish_pin = False
        is_bearish_pin = False
        
        body_size = current.body
        upper_shadow = current.upper_shadow
        lower_shadow = current.lower_shadow
        total_range = current.total_range
        
        # Avoid tiny candles
        avg_range = self._get_average_range(candles, periods=14)
        if total_range < avg_range * 0.3:
            reasons.append(f"Candle too small (range={total_range:.5f} < {avg_range*0.3:.5f})")
            return False, False, 0.0, reasons
        
        # Check for Bullish Pin Bar (long lower wick)
        if lower_shadow > body_size * self.wick_to_body_ratio:
            body_pos = self._get_body_position(current)
            if body_pos >= (1.0 - self.body_position_threshold):  # Body in top third
                is_bullish_pin = True
                reasons.append(f"Bullish Pin Bar: Lower wick {lower_shadow:.5f} > body {body_size:.5f} * {self.wick_to_body_ratio}")
                reasons.append(f"Body position in top third ({body_pos:.2f})")
        
        # Check for Bearish Pin Bar (long upper wick)
        if upper_shadow > body_size * self.wick_to_body_ratio:
            body_pos = self._get_body_position(current)
            if body_pos <= self.body_position_threshold:  # Body in bottom third
                is_bearish_pin = True
                reasons.append(f"Bearish Pin Bar: Upper wick {upper_shadow:.5f} > body {body_size:.5f} * {self.wick_to_body_ratio}")
                reasons.append(f"Body position in bottom third ({body_pos:.2f})")
        
        # Calculate confidence
        confidence = self._calculate_confidence(candles)
        
        if not is_bullish_pin and not is_bearish_pin:
            reasons.append("No Pin Bar pattern detected")
        
        return is_bullish_pin, is_bearish_pin, confidence, reasons
    
    def _calculate_confidence(self, candles: List[CandleData]) -> float:
        """
        Calculate confidence score for Pin Bar
        
        Factors:
        1. Wick to body ratio (higher = better)
        2. Opposite wick size (smaller = better)
        3. Body position in range
        4. Candle size relative to recent average
        """
        current = candles[-1]
        
        # Base confidence from wick/body ratio
        dominant_wick = max(current.upper_shadow, current.lower_shadow)
        if current.body < 0.0001:  # Avoid division by zero
            wick_ratio_score = 1.0
        else:
            wick_ratio = dominant_wick / current.body
            wick_ratio_score = min(wick_ratio / (self.wick_to_body_ratio * 2), 1.0)
        
        # Penalty for large opposite wick
        opposite_wick = min(current.upper_shadow, current.lower_shadow)
        opposite_wick_score = 1.0 - min(opposite_wick / current.total_range, 0.5)
        
        # Body position score
        body_pos = self._get_body_position(current)
        if body_pos >= (1.0 - self.body_position_threshold):  # Top third (bullish)
            body_pos_score = body_pos
        elif body_pos <= self.body_position_threshold:  # Bottom third (bearish)
            body_pos_score = 1.0 - body_pos
        else:
            body_pos_score = 0.5  # Middle = less confident
        
        # Size score (relative to recent candles)
        avg_range = self._get_average_range(candles, periods=14)
        if avg_range < 0.0001:
            size_score = 0.5
        else:
            size_ratio = current.total_range / avg_range
            size_score = min(size_ratio / 1.5, 1.0)  # Larger than 1.5x average = max score
        
        # Weighted average
        confidence = (
            wick_ratio_score * 0.40 +
            opposite_wick_score * 0.25 +
            body_pos_score * 0.25 +
            size_score * 0.10
        )
        
        return min(confidence, 1.0)
    
    def _get_body_position(self, candle: CandleData) -> float:
        """
        Get body position in total range (0.0 = bottom, 1.0 = top)
        """
        if candle.total_range < 0.0001:
            return 0.5
        
        body_bottom = min(candle.open, candle.close)
        position = (body_bottom - candle.low) / candle.total_range
        return position
    
    def _get_dominant_wick_ratio(self, candle: CandleData) -> float:
        """
        Get the ratio of dominant wick to body
        """
        if candle.body < 0.0001:
            return 999.0  # Effectively infinite
        
        dominant_wick = max(candle.upper_shadow, candle.lower_shadow)
        return dominant_wick / candle.body
