"""
Base Chart Pattern Detection Module

This module provides the foundation for detecting classic chart patterns
such as Head & Shoulders, Double Top/Bottom, Triangles, etc.
"""

from dataclasses import dataclass
from typing import List, Optional, Tuple
from abc import ABC, abstractmethod
from enum import Enum
import numpy as np


class PatternType(Enum):
    """Chart pattern types"""
    HEAD_SHOULDERS = "head_shoulders"
    INVERSE_HEAD_SHOULDERS = "inverse_head_shoulders"
    DOUBLE_TOP = "double_top"
    DOUBLE_BOTTOM = "double_bottom"
    ASCENDING_TRIANGLE = "ascending_triangle"
    DESCENDING_TRIANGLE = "descending_triangle"
    SYMMETRICAL_TRIANGLE = "symmetrical_triangle"


class PatternStrength(Enum):
    """Pattern strength classification"""
    WEAK = 1
    MODERATE = 2
    STRONG = 3
    VERY_STRONG = 4


@dataclass
class ChartPatternResult:
    """
    Result of chart pattern detection
    
    Attributes:
        pattern_type: Type of pattern detected
        detected: Whether pattern was found
        confidence: Confidence level (0.0-1.0)
        strength: Pattern strength classification
        signal: Trading signal (1=bullish, -1=bearish, 0=neutral)
        
        # Pattern key points
        formation_start: Index where pattern formation begins
        formation_end: Index where pattern formation ends
        breakout_point: Index of breakout (if confirmed)
        
        # Price levels
        entry_price: Suggested entry price
        stop_loss: Suggested stop loss
        take_profit: Suggested take profit (price target)
        
        # Additional info
        neckline: Neckline price (for H&S, Double patterns)
        pattern_height: Height of pattern (for target calculation)
        volume_confirmation: Volume confirms breakout
        
        reasons: List of detection reasons
        metadata: Additional pattern-specific data
    """
    pattern_type: PatternType
    detected: bool
    confidence: float
    strength: PatternStrength
    signal: int
    
    formation_start: int
    formation_end: int
    breakout_point: Optional[int] = None
    
    entry_price: float = 0.0
    stop_loss: float = 0.0
    take_profit: float = 0.0
    
    neckline: Optional[float] = None
    pattern_height: Optional[float] = None
    volume_confirmation: bool = False
    
    reasons: List[str] = None
    metadata: dict = None
    
    def __post_init__(self):
        if self.reasons is None:
            self.reasons = []
        if self.metadata is None:
            self.metadata = {}


class BaseChartPattern(ABC):
    """
    Abstract base class for chart pattern detection
    
    All chart pattern detectors should inherit from this class
    and implement the detect() method.
    """
    
    def __init__(self, min_pattern_bars: int = 20, max_pattern_bars: int = 100):
        """
        Initialize chart pattern detector
        
        Args:
            min_pattern_bars: Minimum bars required for pattern
            max_pattern_bars: Maximum bars to look back for pattern
        """
        self.min_pattern_bars = min_pattern_bars
        self.max_pattern_bars = max_pattern_bars
    
    @abstractmethod
    def detect(self, 
               high: np.ndarray, 
               low: np.ndarray, 
               close: np.ndarray,
               volume: Optional[np.ndarray] = None) -> ChartPatternResult:
        """
        Detect chart pattern in price data
        
        Args:
            high: High prices
            low: Low prices
            close: Close prices
            volume: Volume data (optional)
        
        Returns:
            ChartPatternResult with detection details
        """
        pass
    
    def _find_peaks(self, 
                    data: np.ndarray, 
                    order: int = 5,
                    threshold: float = 0.0) -> List[int]:
        """
        Find peaks (local maxima) in data
        
        Args:
            data: Price data array
            order: How many points on each side to use for comparison
            threshold: Minimum threshold for peak (percentage)
        
        Returns:
            List of peak indices
        """
        peaks = []
        n = len(data)
        
        for i in range(order, n - order):
            # Check if current point is higher than neighbors
            is_peak = True
            for j in range(1, order + 1):
                if data[i] <= data[i - j] or data[i] <= data[i + j]:
                    is_peak = False
                    break
            
            if is_peak:
                # Check threshold
                if threshold > 0:
                    pct_diff = (data[i] - min(data[i - order:i + order + 1])) / data[i]
                    if pct_diff < threshold:
                        is_peak = False
                
                if is_peak:
                    peaks.append(i)
        
        return peaks
    
    def _find_troughs(self, 
                      data: np.ndarray, 
                      order: int = 5,
                      threshold: float = 0.0) -> List[int]:
        """
        Find troughs (local minima) in data
        
        Args:
            data: Price data array
            order: How many points on each side to use for comparison
            threshold: Minimum threshold for trough (percentage)
        
        Returns:
            List of trough indices
        """
        troughs = []
        n = len(data)
        
        for i in range(order, n - order):
            # Check if current point is lower than neighbors
            is_trough = True
            for j in range(1, order + 1):
                if data[i] >= data[i - j] or data[i] >= data[i + j]:
                    is_trough = False
                    break
            
            if is_trough:
                # Check threshold
                if threshold > 0:
                    pct_diff = (max(data[i - order:i + order + 1]) - data[i]) / data[i]
                    if pct_diff < threshold:
                        is_trough = False
                
                if is_trough:
                    troughs.append(i)
        
        return troughs
    
    def _calculate_line(self, 
                       x1: int, y1: float, 
                       x2: int, y2: float) -> Tuple[float, float]:
        """
        Calculate line parameters (slope, intercept) from two points
        
        Args:
            x1, y1: First point coordinates
            x2, y2: Second point coordinates
        
        Returns:
            Tuple of (slope, intercept)
        """
        if x2 == x1:
            return 0.0, y1
        
        slope = (y2 - y1) / (x2 - x1)
        intercept = y1 - slope * x1
        
        return slope, intercept
    
    def _line_price_at(self, index: int, slope: float, intercept: float) -> float:
        """
        Calculate price at given index using line equation
        
        Args:
            index: X coordinate
            slope: Line slope
            intercept: Line intercept
        
        Returns:
            Y coordinate (price)
        """
        return slope * index + intercept
    
    def _is_price_near_line(self, 
                           price: float, 
                           line_price: float, 
                           tolerance: float = 0.02) -> bool:
        """
        Check if price is near a line within tolerance
        
        Args:
            price: Actual price
            line_price: Expected price on line
            tolerance: Tolerance as percentage (default 2%)
        
        Returns:
            True if price is within tolerance
        """
        diff_pct = abs(price - line_price) / line_price
        return diff_pct <= tolerance
    
    def _calculate_pattern_height(self, high_price: float, low_price: float) -> float:
        """
        Calculate pattern height
        
        Args:
            high_price: Highest price in pattern
            low_price: Lowest price in pattern
        
        Returns:
            Pattern height
        """
        return abs(high_price - low_price)
    
    def _check_volume_confirmation(self, 
                                   volume: np.ndarray, 
                                   breakout_idx: int,
                                   lookback: int = 20) -> bool:
        """
        Check if breakout is confirmed by volume increase
        
        Args:
            volume: Volume data
            breakout_idx: Index of breakout
            lookback: Bars to look back for average volume
        
        Returns:
            True if volume confirms breakout
        """
        if volume is None or len(volume) < breakout_idx + 1:
            return False
        
        start_idx = max(0, breakout_idx - lookback)
        avg_volume = np.mean(volume[start_idx:breakout_idx])
        
        if avg_volume == 0:
            return False
        
        # Breakout volume should be at least 1.5x average
        breakout_volume = volume[breakout_idx]
        return breakout_volume >= (avg_volume * 1.5)
    
    def _calculate_confidence(self, 
                             factors: dict,
                             weights: dict = None) -> float:
        """
        Calculate confidence score from multiple factors
        
        Args:
            factors: Dictionary of factor name -> boolean or 0-1 value
            weights: Optional weights for each factor
        
        Returns:
            Confidence score (0.0-1.0)
        """
        if weights is None:
            weights = {k: 1.0 for k in factors.keys()}
        
        total_score = 0.0
        total_weight = 0.0
        
        for factor, value in factors.items():
            weight = weights.get(factor, 1.0)
            score = float(value) if isinstance(value, (int, float)) else (1.0 if value else 0.0)
            total_score += score * weight
            total_weight += weight
        
        return total_score / total_weight if total_weight > 0 else 0.0
    
    def _classify_strength(self, confidence: float) -> PatternStrength:
        """
        Classify pattern strength based on confidence
        
        Args:
            confidence: Confidence score (0.0-1.0)
        
        Returns:
            PatternStrength classification
        """
        if confidence >= 0.8:
            return PatternStrength.VERY_STRONG
        elif confidence >= 0.7:
            return PatternStrength.STRONG
        elif confidence >= 0.6:
            return PatternStrength.MODERATE
        else:
            return PatternStrength.WEAK
