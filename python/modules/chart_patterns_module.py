"""
Chart Patterns Module

Integrates chart pattern detection (Head & Shoulders, Double Top/Bottom, Triangles)
into the 7-module signal system with 25% weight.
"""

import numpy as np
from typing import List
from signal_engine.signal_aggregator import ModuleScore, SignalType
from modules.base_chart_pattern import PatternType, PatternStrength
from modules.double_top_bottom import DoubleTopBottomDetector
from modules.head_shoulders import HeadShouldersDetector
from modules.triangles import TriangleDetector


class ChartPatternsModule:
    """
    Chart patterns detection module (25% weight in signal aggregation)
    
    Detects:
    - Head & Shoulders / Inverse Head & Shoulders
    - Double Top / Double Bottom
    - Triangles (Ascending, Descending, Symmetrical)
    
    Weight breakdown:
    - Double patterns: 40%
    - Head & Shoulders: 35%
    - Triangles: 25%
    """
    
    def __init__(self,
                 min_pattern_bars: int = 30,
                 max_pattern_bars: int = 100,
                 min_confidence: float = 0.6):
        """
        Initialize chart patterns module
        
        Args:
            min_pattern_bars: Minimum bars for pattern formation
            max_pattern_bars: Maximum lookback period
            min_confidence: Minimum confidence threshold for pattern
        """
        self.min_pattern_bars = min_pattern_bars
        self.max_pattern_bars = max_pattern_bars
        self.min_confidence = min_confidence
        
        # Initialize detectors
        self.double_detector = DoubleTopBottomDetector(
            min_pattern_bars=min_pattern_bars,
            max_pattern_bars=max_pattern_bars
        )
        self.hs_detector = HeadShouldersDetector(
            min_pattern_bars=min_pattern_bars,
            max_pattern_bars=max_pattern_bars
        )
        self.triangle_detector = TriangleDetector(
            min_pattern_bars=min_pattern_bars,
            max_pattern_bars=max_pattern_bars
        )
        
        # Detector weights
        self.detector_weights = {
            'double': 0.40,
            'head_shoulders': 0.35,
            'triangle': 0.25
        }
    
    def analyze(self,
                high: np.ndarray,
                low: np.ndarray,
                close: np.ndarray,
                volume: np.ndarray = None) -> ModuleScore:
        """
        Analyze chart patterns and generate signal
        
        Args:
            high: High prices (most recent last)
            low: Low prices (most recent last)
            close: Close prices (most recent last)
            volume: Volume data (optional)
            
        Returns:
            ModuleScore with signal, confidence, and reasoning
        """
        if len(close) < self.min_pattern_bars:
            return ModuleScore(
                signal=SignalType.NEUTRAL,
                confidence=0.0,
                reason="Insufficient data for chart pattern analysis"
            )
        
        # Detect patterns with each detector
        patterns = []
        reasons = []
        
        # 1. Double Top/Bottom (40% weight)
        double_result = self.double_detector.detect(high, low, close, volume)
        if double_result.detected and double_result.confidence >= self.min_confidence:
            patterns.append({
                'type': 'double',
                'signal': double_result.signal,
                'confidence': double_result.confidence,
                'weight': self.detector_weights['double'],
                'reason': f"{double_result.pattern_type.value}: {double_result.reasons[0] if double_result.reasons else 'detected'}"
            })
        
        # 2. Head & Shoulders (35% weight)
        hs_result = self.hs_detector.detect(high, low, close, volume)
        if hs_result.detected and hs_result.confidence >= self.min_confidence:
            patterns.append({
                'type': 'head_shoulders',
                'signal': hs_result.signal,
                'confidence': hs_result.confidence,
                'weight': self.detector_weights['head_shoulders'],
                'reason': f"{hs_result.pattern_type.value}: {hs_result.reasons[0] if hs_result.reasons else 'detected'}"
            })
        
        # 3. Triangles (25% weight)
        triangle_result = self.triangle_detector.detect(high, low, close, volume)
        if triangle_result.detected and triangle_result.confidence >= self.min_confidence:
            patterns.append({
                'type': 'triangle',
                'signal': triangle_result.signal,
                'confidence': triangle_result.confidence,
                'weight': self.detector_weights['triangle'],
                'reason': f"{triangle_result.pattern_type.value}: {triangle_result.reasons[0] if triangle_result.reasons else 'detected'}"
            })
        
        # Aggregate patterns
        if not patterns:
            return ModuleScore(
                signal=SignalType.NEUTRAL,
                confidence=0.0,
                reason="No chart patterns detected"
            )
        
        # Weighted aggregation
        total_weight = sum(p['weight'] * p['confidence'] for p in patterns)
        weighted_signal = sum(p['signal'] * p['weight'] * p['confidence'] for p in patterns)
        
        if total_weight == 0:
            return ModuleScore(
                signal=SignalType.NEUTRAL,
                confidence=0.0,
                reason="Pattern signals canceled out"
            )
        
        # Calculate final signal and confidence
        normalized_signal = weighted_signal / total_weight
        avg_confidence = total_weight / sum(p['weight'] for p in patterns)
        
        # Determine signal type
        if normalized_signal > 0.3:
            signal_type = SignalType.BUY
            signal_name = "Bullish"
        elif normalized_signal < -0.3:
            signal_type = SignalType.SELL
            signal_name = "Bearish"
        else:
            signal_type = SignalType.NEUTRAL
            signal_name = "Neutral"
        
        # Build reason string
        pattern_names = [p['reason'] for p in patterns]
        reason = f"{signal_name} chart patterns: {', '.join(pattern_names)}"
        
        return ModuleScore(
            signal=signal_type,
            confidence=float(avg_confidence),
            reason=reason
        )
    
    def get_pattern_details(self,
                           high: np.ndarray,
                           low: np.ndarray,
                           close: np.ndarray,
                           volume: np.ndarray = None) -> dict:
        """
        Get detailed information about detected patterns
        
        Returns:
            Dictionary with pattern details for each detector
        """
        double_result = self.double_detector.detect(high, low, close, volume)
        hs_result = self.hs_detector.detect(high, low, close, volume)
        triangle_result = self.triangle_detector.detect(high, low, close, volume)
        
        return {
            'double_pattern': {
                'detected': double_result.detected,
                'type': double_result.pattern_type.value,
                'confidence': double_result.confidence,
                'signal': double_result.signal,
                'entry': double_result.entry_price,
                'stop_loss': double_result.stop_loss,
                'take_profit': double_result.take_profit
            },
            'head_shoulders': {
                'detected': hs_result.detected,
                'type': hs_result.pattern_type.value,
                'confidence': hs_result.confidence,
                'signal': hs_result.signal,
                'entry': hs_result.entry_price,
                'stop_loss': hs_result.stop_loss,
                'take_profit': hs_result.take_profit
            },
            'triangle': {
                'detected': triangle_result.detected,
                'type': triangle_result.pattern_type.value,
                'confidence': triangle_result.confidence,
                'signal': triangle_result.signal,
                'entry': triangle_result.entry_price,
                'stop_loss': triangle_result.stop_loss,
                'take_profit': triangle_result.take_profit
            }
        }
