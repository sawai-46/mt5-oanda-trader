"""
Doji Pattern Detector

Doji:
- Open ≈ Close (very small body)
- Represents indecision in the market
- Can signal trend reversal or continuation
- Types: Standard Doji, Dragonfly Doji, Gravestone Doji
"""

from typing import List
from .base_detector import BaseCandleDetector, CandleData, PatternResult


class DojiDetector(BaseCandleDetector):
    """
    Doji Pattern Detector
    
    Detects doji candlestick patterns which indicate market indecision.
    A doji occurs when open and close prices are nearly equal.
    
    Types of Doji:
    - Standard Doji: Open ≈ Close, balanced shadows
    - Dragonfly Doji: Long lower shadow, minimal upper (bullish reversal)
    - Gravestone Doji: Long upper shadow, minimal lower (bearish reversal)
    - Four Price Doji: Open = High = Low = Close (rare, extreme indecision)
    
    Size Filter:
    - Doji must meet minimum ATR ratio to be meaningful (avoid noise)
    """
    
    def __init__(self,
                 min_confidence: float = 0.5,
                 max_body_to_range_ratio: float = 0.1,
                 min_range_atr_ratio: float = 0.5):
        """
        Args:
            min_confidence: Minimum confidence threshold
            max_body_to_range_ratio: Maximum body/range ratio for doji (default: 0.1 = 10%)
            min_range_atr_ratio: Minimum range size as ratio of ATR (default: 0.5)
        """
        super().__init__(min_confidence)
        self.pattern_name = "Doji"
        self.max_body_to_range_ratio = max_body_to_range_ratio
        self.min_range_atr_ratio = min_range_atr_ratio
    
    def detect(self, candles: List[CandleData]) -> PatternResult:
        """
        Detect Doji pattern
        
        Args:
            candles: List of candles (need at least 1)
        
        Returns:
            PatternResult with detection info
        """
        if not self._validate_input(candles, min_bars=1):
            return self.create_result(
                detected=False,
                signal=0,
                confidence=0.0,
                reasons=["Insufficient data for Doji detection"],
                metadata={}
            )
        
        current = candles[-1]
        
        # ATR size filter to avoid noise
        atr = self._calculate_atr(candles, period=14)
        range_size = current.total_range
        
        if atr > 0:
            range_atr_ratio = range_size / atr
            
            if range_atr_ratio < self.min_range_atr_ratio:
                return self.create_result(
                    detected=False,
                    signal=0,
                    confidence=0.0,
                    reasons=[f"Range too small: {range_atr_ratio:.2f}x ATR < {self.min_range_atr_ratio}x threshold"],
                    metadata={'atr': atr, 'range_atr_ratio': range_atr_ratio}
                )
        
        # Check if candle has meaningful range
        if current.total_range < 0.0001:
            return self.create_result(
                detected=False,
                signal=0,
                confidence=0.0,
                reasons=["Candle range too small"],
                metadata={}
            )
        
        # Analyze Doji pattern
        is_doji, doji_type, confidence, reasons = self._analyze_doji(current, candles)
        
        # Determine signal based on doji type and context
        signal = self._determine_signal(current, candles, doji_type)
        
        detected = is_doji and confidence >= self.min_confidence
        
        metadata = {
            'body_size': current.body,
            'total_range': current.total_range,
            'body_to_range_ratio': current.body / current.total_range,
            'upper_shadow': current.upper_shadow,
            'lower_shadow': current.lower_shadow,
            'doji_type': doji_type,
            'atr': atr,
            'range_atr_ratio': range_atr_ratio if atr > 0 else 0.0
        }
        
        return self.create_result(
            detected=detected,
            signal=signal,
            confidence=confidence,
            reasons=reasons,
            metadata=metadata
        )
    
    def _analyze_doji(self, current: CandleData, candles: List[CandleData]) -> tuple:
        """
        Analyze if candle is a Doji
        
        Returns:
            (is_doji, doji_type, confidence, reasons)
        """
        reasons = []
        
        # Calculate body to range ratio
        body_to_range = current.body / current.total_range
        
        # Check if body is small enough for Doji
        if body_to_range > self.max_body_to_range_ratio:
            reasons.append(f"Body/Range ratio {body_to_range:.3f} exceeds threshold " +
                          f"{self.max_body_to_range_ratio}")
            return False, "none", 0.0, reasons
        
        # Determine Doji type
        doji_type = self._classify_doji_type(current)
        
        # Check minimum size (avoid tiny meaningless candles)
        avg_range = self._get_average_range(candles, periods=14)
        if current.total_range < avg_range * 0.3:
            reasons.append(f"Candle too small (range={current.total_range:.5f} < {avg_range*0.3:.5f})")
            return False, doji_type, 0.0, reasons
        
        # Doji detected
        is_doji = True
        reasons.append(f"Doji detected: Body/Range = {body_to_range:.3f} (threshold: {self.max_body_to_range_ratio})")
        reasons.append(f"Doji type: {doji_type}")
        
        # Add type-specific description
        if doji_type == "dragonfly":
            reasons.append("Dragonfly Doji: Long lower wick suggests buying pressure")
        elif doji_type == "gravestone":
            reasons.append("Gravestone Doji: Long upper wick suggests selling pressure")
        elif doji_type == "standard":
            reasons.append("Standard Doji: Wicks on both sides indicate indecision")
        
        # Calculate confidence
        confidence = self._calculate_confidence(candles)
        
        return is_doji, doji_type, confidence, reasons
    
    def _classify_doji_type(self, candle: CandleData) -> str:
        """
        Classify Doji type based on wick configuration
        
        Returns:
            "dragonfly", "gravestone", "standard", or "four-price" (open=high=low=close)
        """
        # Four-price Doji (very rare)
        if candle.body < 0.0001 and candle.total_range < 0.0001:
            return "four-price"
        
        upper = candle.upper_shadow
        lower = candle.lower_shadow
        
        # Dragonfly: Long lower wick, minimal upper wick
        if lower > candle.total_range * 0.6 and upper < candle.total_range * 0.1:
            return "dragonfly"
        
        # Gravestone: Long upper wick, minimal lower wick
        if upper > candle.total_range * 0.6 and lower < candle.total_range * 0.1:
            return "gravestone"
        
        # Standard Doji: Wicks on both sides
        return "standard"
    
    def _determine_signal(self, current: CandleData, candles: List[CandleData], 
                         doji_type: str) -> int:
        """
        Determine trading signal based on Doji type and context
        
        Doji is indecision, but can suggest reversal:
        - Dragonfly after downtrend → BUY
        - Gravestone after uptrend → SELL
        - Standard Doji → NEUTRAL (wait for confirmation)
        """
        if doji_type == "dragonfly":
            # Dragonfly is bullish, especially after downtrend
            if len(candles) >= 3 and self._is_in_downtrend(candles[:-1], periods=3):
                return 1  # BUY
            return 0  # NEUTRAL (no clear trend context)
        
        elif doji_type == "gravestone":
            # Gravestone is bearish, especially after uptrend
            if len(candles) >= 3 and self._is_in_uptrend(candles[:-1], periods=3):
                return -1  # SELL
            return 0  # NEUTRAL (no clear trend context)
        
        else:
            # Standard Doji or four-price → NEUTRAL (indecision)
            return 0
    
    def _calculate_confidence(self, candles: List[CandleData]) -> float:
        """
        Calculate confidence score for Doji pattern
        
        Factors:
        1. How small is the body (smaller = better)
        2. Size relative to recent candles
        3. Wick configuration
        4. Trend context (reversal potential)
        """
        current = candles[-1]
        
        # Body size score (smaller body = higher confidence)
        body_to_range = current.body / current.total_range
        body_score = 1.0 - (body_to_range / self.max_body_to_range_ratio)
        body_score = max(min(body_score, 1.0), 0.0)
        
        # Size score (relative to average)
        avg_range = self._get_average_range(candles, periods=14)
        if avg_range < 0.0001:
            size_score = 0.5
        else:
            size_ratio = current.total_range / avg_range
            # Prefer medium-to-large Doji (too small is insignificant)
            if size_ratio < 0.5:
                size_score = size_ratio / 0.5  # Penalty for very small
            elif size_ratio > 1.5:
                size_score = 1.0  # Max score for large Doji
            else:
                size_score = 0.5 + (size_ratio - 0.5)  # Linear 0.5 to 1.5
        
        # Wick score (balanced wicks or specific type)
        doji_type = self._classify_doji_type(current)
        if doji_type in ["dragonfly", "gravestone"]:
            wick_score = 1.0  # Clear directional signal
        elif doji_type == "standard":
            # Check if wicks are relatively balanced
            if current.upper_shadow > 0 and current.lower_shadow > 0:
                ratio = min(current.upper_shadow, current.lower_shadow) / max(current.upper_shadow, current.lower_shadow)
                wick_score = 0.5 + ratio * 0.5  # 0.5 to 1.0
            else:
                wick_score = 0.5
        else:
            wick_score = 0.3  # Four-price Doji (rare, less reliable)
        
        # Context score (potential reversal)
        if len(candles) >= 3:
            if doji_type == "dragonfly" and self._is_in_downtrend(candles[:-1], periods=3):
                context_score = 1.0  # Strong reversal signal
            elif doji_type == "gravestone" and self._is_in_uptrend(candles[:-1], periods=3):
                context_score = 1.0  # Strong reversal signal
            else:
                context_score = 0.6  # No clear trend context
        else:
            context_score = 0.5
        
        # Weighted average
        confidence = (
            body_score * 0.35 +
            size_score * 0.20 +
            wick_score * 0.25 +
            context_score * 0.20
        )
        
        return min(confidence, 1.0)
    
    def _is_in_uptrend(self, candles: List[CandleData], periods: int = 3) -> bool:
        """Check if candles show uptrend"""
        if len(candles) < periods or periods < 2:
            return False
        
        recent = candles[-periods:]
        bullish_count = sum(1 for c in recent if c.is_bullish)
        closes = [c.close for c in recent]
        rising = sum(1 for i in range(1, len(closes)) if closes[i] > closes[i-1])
        
        return bullish_count > periods * 0.6 and rising > len(closes) * 0.5
    
    def _is_in_downtrend(self, candles: List[CandleData], periods: int = 3) -> bool:
        """Check if candles show downtrend"""
        if len(candles) < periods or periods < 2:
            return False
        
        recent = candles[-periods:]
        bearish_count = sum(1 for c in recent if c.is_bearish)
        closes = [c.close for c in recent]
        falling = sum(1 for i in range(1, len(closes)) if closes[i] < closes[i-1])
        
        return bearish_count > periods * 0.6 and falling > len(closes) * 0.5
