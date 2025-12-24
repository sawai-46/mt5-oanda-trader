"""
Structural Module (5% weight)
Pivot Points and Support/Resistance Detection
"""
from dataclasses import dataclass
from typing import Optional, Dict
import numpy as np
from signal_engine.signal_aggregator import ModuleScore, SignalType


@dataclass
class PivotLevels:
    """Daily Pivot Levels"""
    pivot: float
    r1: float
    r2: float
    s1: float
    s2: float


@dataclass
class ProximityCheck:
    """Price proximity to key level"""
    near_level: bool
    level_type: str = ""
    level_value: float = 0.0
    distance: float = 0.0


class PivotCalculator:
    """Daily Pivot Point Calculator"""
    
    @staticmethod
    def calculate(prev_high: float, prev_low: float, prev_close: float) -> PivotLevels:
        """
        Calculate Daily Pivot Points
        
        Formula:
        Pivot = (High + Low + Close) / 3
        R1 = 2 * Pivot - Low
        R2 = Pivot + (High - Low)
        S1 = 2 * Pivot - High
        S2 = Pivot - (High - Low)
        
        Args:
            prev_high: Previous day's high
            prev_low: Previous day's low
            prev_close: Previous day's close
            
        Returns:
            PivotLevels with pivot and support/resistance levels
        """
        pivot = (prev_high + prev_low + prev_close) / 3
        
        return PivotLevels(
            pivot=pivot,
            r1=2 * pivot - prev_low,
            r2=pivot + (prev_high - prev_low),
            s1=2 * pivot - prev_high,
            s2=pivot - (prev_high - prev_low)
        )
    
    @staticmethod
    def check_proximity(price: float, 
                       pivot_levels: PivotLevels, 
                       threshold: float = 0.001) -> ProximityCheck:
        """
        Check if price is near pivot level (±0.1% default)
        
        Args:
            price: Current price
            pivot_levels: PivotLevels to check
            threshold: Distance threshold (0.001 = 0.1%)
            
        Returns:
            ProximityCheck with proximity details
        """
        levels_dict = {
            'R2': pivot_levels.r2,
            'R1': pivot_levels.r1,
            'Pivot': pivot_levels.pivot,
            'S1': pivot_levels.s1,
            'S2': pivot_levels.s2
        }
        
        for level_name, level_value in levels_dict.items():
            if level_value == 0:
                continue
            distance = abs(price - level_value) / level_value
            if distance < threshold:
                return ProximityCheck(
                    near_level=True,
                    level_type=level_name,
                    level_value=level_value,
                    distance=distance
                )
        
        return ProximityCheck(near_level=False)


class SwingPointDetector:
    """Swing High/Low Support/Resistance Detector"""
    
    def __init__(self, swing_period: int = 10):
        """
        Initialize swing point detector
        
        Args:
            swing_period: Period for swing detection
        """
        self.swing_period = swing_period
    
    def find_recent_swing_high(self, highs: np.ndarray) -> Optional[float]:
        """
        Find most recent swing high
        
        Args:
            highs: High prices array
            
        Returns:
            Swing high price or None
        """
        if len(highs) < self.swing_period * 2 + 1:
            return None
        
        period = self.swing_period
        
        # Search from most recent bars
        for i in range(len(highs) - period - 1, period, -1):
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
            for j in range(i + 1, min(i + period + 1, len(highs))):
                if highs[j] >= current_high:
                    is_swing_high = False
                    break
            
            if is_swing_high:
                return current_high
        
        return None
    
    def find_recent_swing_low(self, lows: np.ndarray) -> Optional[float]:
        """
        Find most recent swing low
        
        Args:
            lows: Low prices array
            
        Returns:
            Swing low price or None
        """
        if len(lows) < self.swing_period * 2 + 1:
            return None
        
        period = self.swing_period
        
        # Search from most recent bars
        for i in range(len(lows) - period - 1, period, -1):
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
            for j in range(i + 1, min(i + period + 1, len(lows))):
                if lows[j] <= current_low:
                    is_swing_low = False
                    break
            
            if is_swing_low:
                return current_low
        
        return None


class StructuralModule:
    """Structural Module - Pivot Points & Support/Resistance (5% weight)"""
    
    def __init__(self,
                 pivot_threshold: float = 0.001,
                 swing_period: int = 10,
                 zone_threshold: float = 0.002):
        """
        Initialize Structural Module
        
        Args:
            pivot_threshold: Distance threshold for pivot proximity (0.1%)
            swing_period: Period for swing high/low detection
            zone_threshold: Distance threshold for swing zone (0.2%)
        """
        self.pivot_calculator = PivotCalculator()
        self.swing_detector = SwingPointDetector(swing_period=swing_period)
        self.pivot_threshold = pivot_threshold
        self.zone_threshold = zone_threshold
    
    def analyze(self,
                open_prices: np.ndarray,
                high_prices: np.ndarray,
                low_prices: np.ndarray,
                close_prices: np.ndarray,
                prev_day_high: Optional[float] = None,
                prev_day_low: Optional[float] = None,
                prev_day_close: Optional[float] = None) -> ModuleScore:
        """
        Analyze structural support/resistance levels
        
        Args:
            open_prices: Open prices array
            high_prices: High prices array
            low_prices: Low prices array
            close_prices: Close prices array
            prev_day_high: Previous day high (for pivot calculation)
            prev_day_low: Previous day low (for pivot calculation)
            prev_day_close: Previous day close (for pivot calculation)
            
        Returns:
            ModuleScore with signal and confidence
        """
        if len(close_prices) < 2:
            return ModuleScore(
                signal=SignalType.NEUTRAL,
                confidence=0.0,
                reason="Insufficient data"
            )
        
        current_price = close_prices[-1]
        signal = SignalType.NEUTRAL
        confidence = 0.0
        reasons = []
        
        # 1. Pivot Point Analysis (if data available)
        if prev_day_high and prev_day_low and prev_day_close:
            pivot_levels = self.pivot_calculator.calculate(
                prev_day_high, prev_day_low, prev_day_close
            )
            
            proximity = self.pivot_calculator.check_proximity(
                current_price, pivot_levels, self.pivot_threshold
            )
            
            if proximity.near_level:
                level_type = proximity.level_type
                reasons.append(f"Near {level_type} ({proximity.level_value:.5f})")
                
                # Support levels (S1, S2) suggest buy
                if level_type in ['S1', 'S2']:
                    signal = SignalType.BUY
                    confidence += 0.5
                # Resistance levels (R1, R2) suggest sell
                elif level_type in ['R1', 'R2']:
                    signal = SignalType.SELL
                    confidence += 0.5
                # Pivot is neutral but adds minor confidence
                elif level_type == 'Pivot':
                    confidence += 0.2
        
        # 2. Swing Point Analysis
        swing_high = self.swing_detector.find_recent_swing_high(high_prices)
        swing_low = self.swing_detector.find_recent_swing_low(low_prices)
        
        # Check proximity to swing low (support)
        if swing_low:
            distance_to_low = abs(current_price - swing_low) / swing_low
            if distance_to_low < self.zone_threshold:
                reasons.append(f"Near swing low support ({swing_low:.5f})")
                if signal == SignalType.NEUTRAL:
                    signal = SignalType.BUY
                    confidence += 0.4
                elif signal == SignalType.BUY:
                    confidence += 0.3
        
        # Check proximity to swing high (resistance)
        if swing_high:
            distance_to_high = abs(current_price - swing_high) / swing_high
            if distance_to_high < self.zone_threshold:
                reasons.append(f"Near swing high resistance ({swing_high:.5f})")
                if signal == SignalType.NEUTRAL:
                    signal = SignalType.SELL
                    confidence += 0.4
                elif signal == SignalType.SELL:
                    confidence += 0.3
        
        # 3. Range detection (no pivot data available)
        if not prev_day_high and len(high_prices) >= 20:
            # Use recent 20-bar high/low as range
            recent_high = np.max(high_prices[-20:])
            recent_low = np.min(low_prices[-20:])
            range_size = recent_high - recent_low
            
            if range_size > 0:
                # Near bottom of range
                if (current_price - recent_low) / range_size < 0.2:
                    reasons.append(f"Near range bottom ({recent_low:.5f})")
                    if signal == SignalType.NEUTRAL:
                        signal = SignalType.BUY
                        confidence += 0.3
                    elif signal == SignalType.BUY:
                        confidence += 0.2
                
                # Near top of range
                elif (recent_high - current_price) / range_size < 0.2:
                    reasons.append(f"Near range top ({recent_high:.5f})")
                    if signal == SignalType.NEUTRAL:
                        signal = SignalType.SELL
                        confidence += 0.3
                    elif signal == SignalType.SELL:
                        confidence += 0.2
        
        # Cap confidence at 1.0
        confidence = min(confidence, 1.0)
        
        # Build reason string
        if reasons:
            reason = "Structural: " + ", ".join(reasons)
        else:
            reason = "No significant structural levels detected"
        
        return ModuleScore(
            signal=signal,
            confidence=confidence,
            reason=reason
        )
