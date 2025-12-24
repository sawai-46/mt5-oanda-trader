"""
Triangle Pattern Detection

Implements detection for:
- Ascending Triangle (bullish continuation)
- Descending Triangle (bearish continuation)
- Symmetrical Triangle (continuation in trend direction)
"""

import numpy as np
from typing import Optional, Tuple
from .base_chart_pattern import (
    BaseChartPattern, ChartPatternResult, PatternType, PatternStrength
)


class TriangleDetector(BaseChartPattern):
    """
    Detector for Triangle patterns
    
    Pattern characteristics:
    - Ascending Triangle: Flat top resistance, rising support
    - Descending Triangle: Flat bottom support, falling resistance
    - Symmetrical Triangle: Converging trendlines
    
    All triangles resolve with a breakout in one direction
    """
    
    def __init__(self,
                 min_pattern_bars: int = 15,
                 max_pattern_bars: int = 60,
                 min_touches: int = 4,
                 line_flatness_tolerance: float = 0.01,
                 convergence_angle_min: float = 5.0,
                 convergence_angle_max: float = 45.0):
        """
        Initialize Triangle detector
        
        Args:
            min_pattern_bars: Minimum bars for pattern
            max_pattern_bars: Maximum bars to look back
            min_touches: Minimum touches on trendlines
            line_flatness_tolerance: Tolerance for flat line (1%)
            convergence_angle_min: Min convergence angle in degrees
            convergence_angle_max: Max convergence angle in degrees
        """
        super().__init__(min_pattern_bars, max_pattern_bars)
        self.min_touches = min_touches
        self.line_flatness_tolerance = line_flatness_tolerance
        self.convergence_angle_min = convergence_angle_min
        self.convergence_angle_max = convergence_angle_max
    
    def detect(self,
               high: np.ndarray,
               low: np.ndarray,
               close: np.ndarray,
               volume: Optional[np.ndarray] = None) -> ChartPatternResult:
        """
        Detect Triangle pattern
        
        Returns ChartPatternResult with highest confidence pattern found
        """
        # Try all three types
        ascending = self._detect_ascending_triangle(high, low, close, volume)
        descending = self._detect_descending_triangle(high, low, close, volume)
        symmetrical = self._detect_symmetrical_triangle(high, low, close, volume)
        
        # Return pattern with highest confidence
        results = [ascending, descending, symmetrical]
        return max(results, key=lambda x: x.confidence)
    
    def _detect_ascending_triangle(self,
                                   high: np.ndarray,
                                   low: np.ndarray,
                                   close: np.ndarray,
                                   volume: Optional[np.ndarray]) -> ChartPatternResult:
        """
        Detect Ascending Triangle (flat top, rising bottom)
        
        Bullish pattern: typically breaks upward
        """
        pattern_type = PatternType.ASCENDING_TRIANGLE
        
        # Find peaks for resistance line
        peaks = self._find_peaks(high, order=3)
        if len(peaks) < 2:
            return self._create_no_pattern_result(pattern_type)
        
        # Check if peaks form flat resistance
        resistance_info = self._check_flat_line(high, peaks)
        if resistance_info is None:
            return self._create_no_pattern_result(pattern_type)
        
        # Find troughs for support line
        troughs = self._find_troughs(low, order=3)
        if len(troughs) < 2:
            return self._create_no_pattern_result(pattern_type)
        
        # Filter troughs within pattern range
        pattern_start = peaks[0]
        pattern_end = peaks[-1]
        troughs_in_range = [t for t in troughs if pattern_start <= t <= pattern_end]
        
        if len(troughs_in_range) < 2:
            return self._create_no_pattern_result(pattern_type)
        
        # Fit rising support line
        support_slope, support_intercept = self._calculate_line(
            troughs_in_range[0], low[troughs_in_range[0]],
            troughs_in_range[-1], low[troughs_in_range[-1]]
        )
        
        # Support must be rising
        if support_slope <= 0:
            return self._create_no_pattern_result(pattern_type)
        
        # Count touches on both lines
        resistance_touches = self._count_line_touches(
            high, resistance_info['slope'], resistance_info['intercept'],
            pattern_start, pattern_end
        )
        support_touches = self._count_line_touches(
            low, support_slope, support_intercept,
            pattern_start, pattern_end
        )
        
        if resistance_touches + support_touches < self.min_touches:
            return self._create_no_pattern_result(pattern_type)
        
        # Check convergence
        convergence_valid = self._check_convergence(
            resistance_info['slope'], support_slope,
            pattern_end - pattern_start
        )
        
        if not convergence_valid:
            return self._create_no_pattern_result(pattern_type)
        
        # Check for breakout
        resistance_level = resistance_info['price']
        breakout_idx = self._check_breakout_above(close, resistance_level, pattern_end)
        
        # Volume confirmation
        volume_conf = False
        if breakout_idx is not None and volume is not None:
            volume_conf = self._check_volume_confirmation(volume, breakout_idx)
        
        # Calculate confidence
        pattern_height = resistance_level - self._line_price_at(support_slope, support_intercept, pattern_end)
        
        confidence_factors = {
            'resistance_flatness': resistance_info['flatness'],
            'line_touches': min((resistance_touches + support_touches) / 6, 1.0),
            'convergence_quality': convergence_valid,
            'breakout_confirmed': breakout_idx is not None,
            'volume_confirmation': volume_conf
        }
        
        confidence = self._calculate_confidence(confidence_factors, weights={
            'resistance_flatness': 1.5,
            'line_touches': 1.2,
            'convergence_quality': 1.0,
            'breakout_confirmed': 2.0,
            'volume_confirmation': 1.0
        })
        
        strength = self._classify_strength(confidence)
        
        # Calculate targets
        entry_price = close[breakout_idx] if breakout_idx else resistance_level
        stop_loss = self._line_price_at(support_slope, support_intercept, pattern_end) - pattern_height * 0.2
        take_profit = resistance_level + pattern_height
        
        reasons = [
            "Ascending Triangle detected",
            f"Flat resistance at {resistance_level:.2f}",
            f"Rising support line",
            f"{resistance_touches} resistance touches, {support_touches} support touches"
        ]
        
        if breakout_idx:
            reasons.append(f"Breakout confirmed at index {breakout_idx}")
        if volume_conf:
            reasons.append("Volume confirms breakout")
        
        return ChartPatternResult(
            pattern_type=pattern_type,
            detected=True,
            confidence=confidence,
            strength=strength,
            signal=1,  # Bullish
            formation_start=pattern_start,
            formation_end=pattern_end,
            breakout_point=breakout_idx,
            entry_price=entry_price,
            stop_loss=stop_loss,
            take_profit=take_profit,
            neckline=resistance_level,
            pattern_height=pattern_height,
            volume_confirmation=volume_conf,
            reasons=reasons,
            metadata={
                'resistance': resistance_level,
                'support_slope': support_slope,
                'resistance_touches': resistance_touches,
                'support_touches': support_touches
            }
        )
    
    def _detect_descending_triangle(self,
                                    high: np.ndarray,
                                    low: np.ndarray,
                                    close: np.ndarray,
                                    volume: Optional[np.ndarray]) -> ChartPatternResult:
        """
        Detect Descending Triangle (falling top, flat bottom)
        
        Bearish pattern: typically breaks downward
        """
        pattern_type = PatternType.DESCENDING_TRIANGLE
        
        # Find troughs for support line
        troughs = self._find_troughs(low, order=3)
        if len(troughs) < 2:
            return self._create_no_pattern_result(pattern_type)
        
        # Check if troughs form flat support
        support_info = self._check_flat_line(low, troughs)
        if support_info is None:
            return self._create_no_pattern_result(pattern_type)
        
        # Find peaks for resistance line
        peaks = self._find_peaks(high, order=3)
        if len(peaks) < 2:
            return self._create_no_pattern_result(pattern_type)
        
        # Filter peaks within pattern range
        pattern_start = troughs[0]
        pattern_end = troughs[-1]
        peaks_in_range = [p for p in peaks if pattern_start <= p <= pattern_end]
        
        if len(peaks_in_range) < 2:
            return self._create_no_pattern_result(pattern_type)
        
        # Fit falling resistance line
        resistance_slope, resistance_intercept = self._calculate_line(
            peaks_in_range[0], high[peaks_in_range[0]],
            peaks_in_range[-1], high[peaks_in_range[-1]]
        )
        
        # Resistance must be falling
        if resistance_slope >= 0:
            return self._create_no_pattern_result(pattern_type)
        
        # Count touches
        support_touches = self._count_line_touches(
            low, support_info['slope'], support_info['intercept'],
            pattern_start, pattern_end
        )
        resistance_touches = self._count_line_touches(
            high, resistance_slope, resistance_intercept,
            pattern_start, pattern_end
        )
        
        if support_touches + resistance_touches < self.min_touches:
            return self._create_no_pattern_result(pattern_type)
        
        # Check convergence
        convergence_valid = self._check_convergence(
            resistance_slope, support_info['slope'],
            pattern_end - pattern_start
        )
        
        if not convergence_valid:
            return self._create_no_pattern_result(pattern_type)
        
        # Check for breakout
        support_level = support_info['price']
        breakout_idx = self._check_breakout_below(close, support_level, pattern_end)
        
        # Volume confirmation
        volume_conf = False
        if breakout_idx is not None and volume is not None:
            volume_conf = self._check_volume_confirmation(volume, breakout_idx)
        
        # Calculate confidence
        pattern_height = self._line_price_at(resistance_slope, resistance_intercept, pattern_end) - support_level
        
        confidence_factors = {
            'support_flatness': support_info['flatness'],
            'line_touches': min((support_touches + resistance_touches) / 6, 1.0),
            'convergence_quality': convergence_valid,
            'breakout_confirmed': breakout_idx is not None,
            'volume_confirmation': volume_conf
        }
        
        confidence = self._calculate_confidence(confidence_factors, weights={
            'support_flatness': 1.5,
            'line_touches': 1.2,
            'convergence_quality': 1.0,
            'breakout_confirmed': 2.0,
            'volume_confirmation': 1.0
        })
        
        strength = self._classify_strength(confidence)
        
        # Calculate targets
        entry_price = close[breakout_idx] if breakout_idx else support_level
        stop_loss = self._line_price_at(resistance_slope, resistance_intercept, pattern_end) + pattern_height * 0.2
        take_profit = support_level - pattern_height
        
        reasons = [
            "Descending Triangle detected",
            f"Flat support at {support_level:.2f}",
            f"Falling resistance line",
            f"{support_touches} support touches, {resistance_touches} resistance touches"
        ]
        
        if breakout_idx:
            reasons.append(f"Breakout confirmed at index {breakout_idx}")
        if volume_conf:
            reasons.append("Volume confirms breakout")
        
        return ChartPatternResult(
            pattern_type=pattern_type,
            detected=True,
            confidence=confidence,
            strength=strength,
            signal=-1,  # Bearish
            formation_start=pattern_start,
            formation_end=pattern_end,
            breakout_point=breakout_idx,
            entry_price=entry_price,
            stop_loss=stop_loss,
            take_profit=take_profit,
            neckline=support_level,
            pattern_height=pattern_height,
            volume_confirmation=volume_conf,
            reasons=reasons,
            metadata={
                'support': support_level,
                'resistance_slope': resistance_slope,
                'support_touches': support_touches,
                'resistance_touches': resistance_touches
            }
        )
    
    def _detect_symmetrical_triangle(self,
                                     high: np.ndarray,
                                     low: np.ndarray,
                                     close: np.ndarray,
                                     volume: Optional[np.ndarray]) -> ChartPatternResult:
        """
        Detect Symmetrical Triangle (converging trendlines)
        
        Continuation pattern: breaks in trend direction
        """
        pattern_type = PatternType.SYMMETRICAL_TRIANGLE
        
        # Find peaks and troughs
        peaks = self._find_peaks(high, order=3)
        troughs = self._find_troughs(low, order=3)
        
        if len(peaks) < 2 or len(troughs) < 2:
            return self._create_no_pattern_result(pattern_type)
        
        # Fit resistance line (falling)
        resistance_slope, resistance_intercept = self._calculate_line(
            peaks[0], high[peaks[0]], peaks[-1], high[peaks[-1]]
        )
        
        # Fit support line (rising)
        support_slope, support_intercept = self._calculate_line(
            troughs[0], low[troughs[0]], troughs[-1], low[troughs[-1]]
        )
        
        # Lines must converge
        if resistance_slope >= support_slope:
            return self._create_no_pattern_result(pattern_type)
        
        pattern_start = min(peaks[0], troughs[0])
        pattern_end = max(peaks[-1], troughs[-1])
        
        # Check convergence angle
        convergence_valid = self._check_convergence(
            resistance_slope, support_slope,
            pattern_end - pattern_start
        )
        
        if not convergence_valid:
            return self._create_no_pattern_result(pattern_type)
        
        # Count touches
        resistance_touches = self._count_line_touches(
            high, resistance_slope, resistance_intercept,
            pattern_start, pattern_end
        )
        support_touches = self._count_line_touches(
            low, support_slope, support_intercept,
            pattern_start, pattern_end
        )
        
        if resistance_touches + support_touches < self.min_touches:
            return self._create_no_pattern_result(pattern_type)
        
        # Check for breakout (either direction)
        resistance_at_end = self._line_price_at(resistance_slope, resistance_intercept, pattern_end)
        support_at_end = self._line_price_at(support_slope, support_intercept, pattern_end)
        
        breakout_up = self._check_breakout_above(close, resistance_at_end, pattern_end)
        breakout_down = self._check_breakout_below(close, support_at_end, pattern_end)
        
        if breakout_up:
            signal = 1
            breakout_idx = breakout_up
            breakout_level = resistance_at_end
        elif breakout_down:
            signal = -1
            breakout_idx = breakout_down
            breakout_level = support_at_end
        else:
            signal = 0
            breakout_idx = None
            breakout_level = (resistance_at_end + support_at_end) / 2
        
        # Volume confirmation
        volume_conf = False
        if breakout_idx is not None and volume is not None:
            volume_conf = self._check_volume_confirmation(volume, breakout_idx)
        
        # Calculate confidence
        pattern_height = resistance_at_end - support_at_end
        
        confidence_factors = {
            'line_touches': min((resistance_touches + support_touches) / 6, 1.0),
            'symmetry': 1.0 - min(abs(abs(resistance_slope) - support_slope) / support_slope, 1.0),
            'convergence_quality': convergence_valid,
            'breakout_confirmed': breakout_idx is not None,
            'volume_confirmation': volume_conf
        }
        
        confidence = self._calculate_confidence(confidence_factors, weights={
            'line_touches': 1.2,
            'symmetry': 1.0,
            'convergence_quality': 1.0,
            'breakout_confirmed': 2.0,
            'volume_confirmation': 1.0
        })
        
        strength = self._classify_strength(confidence)
        
        # Calculate targets
        entry_price = close[breakout_idx] if breakout_idx else breakout_level
        
        if signal == 1:
            stop_loss = support_at_end - pattern_height * 0.2
            take_profit = resistance_at_end + pattern_height
        elif signal == -1:
            stop_loss = resistance_at_end + pattern_height * 0.2
            take_profit = support_at_end - pattern_height
        else:
            stop_loss = 0.0
            take_profit = 0.0
        
        reasons = [
            "Symmetrical Triangle detected",
            f"Converging trendlines",
            f"{resistance_touches} resistance touches, {support_touches} support touches"
        ]
        
        if breakout_idx:
            reasons.append(f"Breakout {'upward' if signal == 1 else 'downward'} at index {breakout_idx}")
        if volume_conf:
            reasons.append("Volume confirms breakout")
        
        return ChartPatternResult(
            pattern_type=pattern_type,
            detected=True,
            confidence=confidence,
            strength=strength,
            signal=signal,
            formation_start=pattern_start,
            formation_end=pattern_end,
            breakout_point=breakout_idx,
            entry_price=entry_price,
            stop_loss=stop_loss,
            take_profit=take_profit,
            neckline=breakout_level,
            pattern_height=pattern_height,
            volume_confirmation=volume_conf,
            reasons=reasons,
            metadata={
                'resistance_slope': resistance_slope,
                'support_slope': support_slope,
                'resistance_touches': resistance_touches,
                'support_touches': support_touches
            }
        )
    
    # === Helper Methods ===
    
    def _check_flat_line(self, data: np.ndarray, indices: list) -> Optional[dict]:
        """Check if points form a flat line within tolerance"""
        if len(indices) < 2:
            return None
        
        prices = [data[i] for i in indices]
        avg_price = np.mean(prices)
        max_deviation = max(abs(p - avg_price) for p in prices)
        
        if max_deviation / avg_price > self.line_flatness_tolerance:
            return None
        
        flatness = 1.0 - (max_deviation / avg_price / self.line_flatness_tolerance)
        
        return {
            'price': avg_price,
            'slope': 0.0,
            'intercept': avg_price,
            'flatness': flatness
        }
    
    def _count_line_touches(self,
                           data: np.ndarray,
                           slope: float,
                           intercept: float,
                           start: int,
                           end: int,
                           tolerance: float = 0.015) -> int:
        """Count how many times price touches a line"""
        touches = 0
        for i in range(start, min(end + 1, len(data))):
            line_price = self._line_price_at(slope, intercept, i)
            if self._is_price_near_line(data[i], line_price, tolerance):
                touches += 1
        return touches
    
    def _check_convergence(self, slope1: float, slope2: float, bars: int) -> bool:
        """Check if two lines converge at reasonable angle"""
        # Calculate convergence angle
        price_change1 = abs(slope1 * bars)
        price_change2 = abs(slope2 * bars)
        convergence = abs(price_change1 - price_change2)
        
        # Convert to approximate angle
        angle = np.degrees(np.arctan(convergence / bars))
        
        return self.convergence_angle_min <= angle <= self.convergence_angle_max
    
    def _check_breakout_above(self,
                             close: np.ndarray,
                             level: float,
                             start: int) -> Optional[int]:
        """Check for breakout above level"""
        for i in range(start + 1, len(close)):
            if close[i] > level * 1.01:  # 1% above
                return i
        return None
    
    def _check_breakout_below(self,
                             close: np.ndarray,
                             level: float,
                             start: int) -> Optional[int]:
        """Check for breakout below level"""
        for i in range(start + 1, len(close)):
            if close[i] < level * 0.99:  # 1% below
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
