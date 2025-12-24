"""
Base Candle Pattern Detector
Provides common interface for all pattern detectors
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple
import numpy as np


@dataclass
class CandleData:
    """Single candle/bar data structure"""
    timestamp: str
    open: float
    high: float
    low: float
    close: float
    volume: float = 0.0
    
    @property
    def body(self) -> float:
        """Candle body size"""
        return abs(self.close - self.open)
    
    @property
    def upper_shadow(self) -> float:
        """Upper wick/shadow length"""
        return self.high - max(self.open, self.close)
    
    @property
    def lower_shadow(self) -> float:
        """Lower wick/shadow length"""
        return min(self.open, self.close) - self.low
    
    @property
    def total_range(self) -> float:
        """Total candle range (high - low)"""
        return self.high - self.low
    
    @property
    def is_bullish(self) -> bool:
        """Check if candle is bullish (close > open)"""
        return self.close > self.open
    
    @property
    def is_bearish(self) -> bool:
        """Check if candle is bearish (close < open)"""
        return self.close < self.open


@dataclass
class PatternResult:
    """Pattern detection result"""
    pattern_name: str
    detected: bool
    signal: int  # 1=BUY, -1=SELL, 0=NEUTRAL
    confidence: float  # 0.0 to 1.0
    reasons: List[str]  # Why this pattern was detected
    metadata: Dict  # Additional information
    
    def __repr__(self):
        return (f"PatternResult(pattern='{self.pattern_name}', "
                f"signal={'BUY' if self.signal == 1 else 'SELL' if self.signal == -1 else 'NEUTRAL'}, "
                f"confidence={self.confidence:.2f})")


class BaseCandleDetector(ABC):
    """
    Abstract base class for all candle pattern detectors
    
    All detectors must implement:
    - detect(): Main detection logic
    - _calculate_confidence(): Confidence score calculation
    """
    
    def __init__(self, min_confidence: float = 0.5):
        """
        Args:
            min_confidence: Minimum confidence threshold (0.0-1.0)
        """
        self.min_confidence = min_confidence
        self.pattern_name = self.__class__.__name__.replace('Detector', '')
    
    @abstractmethod
    def detect(self, candles: List[CandleData]) -> PatternResult:
        """
        Detect pattern in given candle data
        
        Args:
            candles: List of CandleData, latest candle at end (candles[-1])
        
        Returns:
            PatternResult with detection information
        """
        pass
    
    @abstractmethod
    def _calculate_confidence(self, candles: List[CandleData]) -> float:
        """
        Calculate confidence score for pattern
        
        Args:
            candles: Candle data
            
        Returns:
            Confidence score (0.0-1.0)
        """
        pass
    
    def _validate_input(self, candles: List[CandleData], min_bars: int) -> bool:
        """
        Validate input candle data
        
        Args:
            candles: Candle data to validate
            min_bars: Minimum required bars
            
        Returns:
            True if valid, False otherwise
        """
        if not candles or len(candles) < min_bars:
            return False
        
        # Check for valid data
        for candle in candles[-min_bars:]:
            if candle.high < candle.low:
                return False
            if candle.high < max(candle.open, candle.close):
                return False
            if candle.low > min(candle.open, candle.close):
                return False
        
        return True
    
    def _get_average_range(self, candles: List[CandleData], periods: int = 14) -> float:
        """
        Calculate average true range (ATR-like)
        
        Args:
            candles: Candle data
            periods: Number of periods for average
            
        Returns:
            Average range value
        """
        if len(candles) < periods:
            periods = len(candles)
        
        ranges = [c.total_range for c in candles[-periods:]]
        return np.mean(ranges)
    
    def _get_average_body(self, candles: List[CandleData], periods: int = 20) -> float:
        """
        Calculate average body size
        
        Args:
            candles: List of candles
            periods: Number of periods to calculate average
        
        Returns:
            Average body size
        """
        if not candles:
            return 0.0
        
        bodies = [abs(c.body) for c in candles[-periods:]]
        return np.mean(bodies) if bodies else 0.0
    
    def _calculate_atr(self, candles: List[CandleData], period: int = 14) -> float:
        """
        Calculate Average True Range (ATR)
        
        ATR measures volatility by decomposing the entire range of price movement.
        True Range is the maximum of:
        - Current High - Current Low
        - abs(Current High - Previous Close)
        - abs(Current Low - Previous Close)
        
        Args:
            candles: List of candle data
            period: ATR period (default: 14)
        
        Returns:
            ATR value
        """
        if len(candles) < 2:
            # Not enough data, return current range
            return candles[-1].total_range if candles else 0.0
        
        true_ranges = []
        
        for i in range(1, len(candles)):
            prev_candle = candles[i-1]
            curr_candle = candles[i]
            
            # Three components of True Range
            high_low = curr_candle.high - curr_candle.low
            high_prev_close = abs(curr_candle.high - prev_candle.close)
            low_prev_close = abs(curr_candle.low - prev_candle.close)
            
            # True Range = max of the three
            true_range = max(high_low, high_prev_close, low_prev_close)
            true_ranges.append(true_range)
        
        # Calculate ATR (average of true ranges)
        lookback = min(period, len(true_ranges))
        atr = np.mean(true_ranges[-lookback:]) if true_ranges else 0.0
        
        return atr
    
    def create_result(self, detected: bool, signal: int, confidence: float, 
                     reasons: List[str], metadata: Optional[Dict] = None) -> PatternResult:
        """
        Create PatternResult object
        
        Args:
            detected: Whether pattern was detected
            signal: Signal direction (1=BUY, -1=SELL, 0=NEUTRAL)
            confidence: Confidence score
            reasons: List of reasons
            metadata: Additional metadata
            
        Returns:
            PatternResult object
        """
        if metadata is None:
            metadata = {}
        
        # Add detector info to metadata
        metadata['detector'] = self.pattern_name
        metadata['min_confidence'] = self.min_confidence
        
        return PatternResult(
            pattern_name=self.pattern_name,
            detected=detected and confidence >= self.min_confidence,
            signal=signal if confidence >= self.min_confidence else 0,
            confidence=confidence,
            reasons=reasons,
            metadata=metadata
        )
