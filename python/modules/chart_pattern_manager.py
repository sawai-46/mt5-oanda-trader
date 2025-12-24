"""
Chart Pattern Manager

Coordinates all chart pattern detectors and provides unified interface
"""

import numpy as np
from typing import List, Optional
from dataclasses import dataclass

from .base_chart_pattern import ChartPatternResult, PatternType, PatternStrength
from .head_shoulders import HeadShouldersDetector
from .double_top_bottom import DoubleTopBottomDetector
from .triangles import TriangleDetector


@dataclass
class ChartPatternAnalysis:
    """
    Combined result from all chart pattern detectors
    """
    primary_pattern: ChartPatternResult
    all_patterns: List[ChartPatternResult]
    strongest_signal: int  # -1, 0, 1
    max_confidence: float
    pattern_count: int
    
    def to_dict(self) -> dict:
        """Convert to dictionary for serialization"""
        return {
            'primary_pattern': {
                'type': self.primary_pattern.pattern_type.name,
                'detected': self.primary_pattern.detected,
                'confidence': self.primary_pattern.confidence,
                'strength': self.primary_pattern.strength.name,
                'signal': self.primary_pattern.signal,
                'entry_price': self.primary_pattern.entry_price,
                'stop_loss': self.primary_pattern.stop_loss,
                'take_profit': self.primary_pattern.take_profit,
                'reasons': self.primary_pattern.reasons
            },
            'all_patterns': [
                {
                    'type': p.pattern_type.name,
                    'detected': p.detected,
                    'confidence': p.confidence,
                    'signal': p.signal
                }
                for p in self.all_patterns if p.detected
            ],
            'strongest_signal': self.strongest_signal,
            'max_confidence': self.max_confidence,
            'pattern_count': self.pattern_count
        }


class ChartPatternManager:
    """
    Manages all chart pattern detectors and provides unified analysis
    """
    
    def __init__(self,
                 enable_head_shoulders: bool = True,
                 enable_double_patterns: bool = True,
                 enable_triangles: bool = True,
                 min_confidence: float = 0.5):
        """
        Initialize Chart Pattern Manager
        
        Args:
            enable_head_shoulders: Enable H&S detection
            enable_double_patterns: Enable Double Top/Bottom detection
            enable_triangles: Enable Triangle detection
            min_confidence: Minimum confidence to consider pattern valid
        """
        self.min_confidence = min_confidence
        
        # Initialize detectors
        self.detectors = []
        
        if enable_head_shoulders:
            self.detectors.append(HeadShouldersDetector())
        
        if enable_double_patterns:
            self.detectors.append(DoubleTopBottomDetector())
        
        if enable_triangles:
            self.detectors.append(TriangleDetector())
    
    def analyze(self,
                high: np.ndarray,
                low: np.ndarray,
                close: np.ndarray,
                volume: Optional[np.ndarray] = None) -> ChartPatternAnalysis:
        """
        Analyze price data for all chart patterns
        
        Args:
            high: High prices
            low: Low prices
            close: Close prices
            volume: Volume data (optional)
        
        Returns:
            ChartPatternAnalysis with all detected patterns
        """
        all_results = []
        
        # Run all detectors
        for detector in self.detectors:
            result = detector.detect(high, low, close, volume)
            if result.detected and result.confidence >= self.min_confidence:
                all_results.append(result)
        
        # Find primary pattern (highest confidence)
        if all_results:
            primary = max(all_results, key=lambda x: x.confidence)
            strongest_signal = primary.signal
            max_confidence = primary.confidence
            pattern_count = len(all_results)
        else:
            # No patterns detected
            primary = ChartPatternResult(
                pattern_type=PatternType.HEAD_SHOULDERS,
                detected=False,
                confidence=0.0,
                strength=PatternStrength.WEAK,
                signal=0,
                formation_start=0,
                formation_end=0,
                reasons=["No chart patterns detected"]
            )
            strongest_signal = 0
            max_confidence = 0.0
            pattern_count = 0
        
        return ChartPatternAnalysis(
            primary_pattern=primary,
            all_patterns=all_results,
            strongest_signal=strongest_signal,
            max_confidence=max_confidence,
            pattern_count=pattern_count
        )
    
    def get_trading_signal(self,
                          high: np.ndarray,
                          low: np.ndarray,
                          close: np.ndarray,
                          volume: Optional[np.ndarray] = None,
                          require_breakout: bool = True) -> dict:
        """
        Get simplified trading signal from chart patterns
        
        Args:
            high, low, close: Price data
            volume: Volume data
            require_breakout: Only signal if breakout confirmed
        
        Returns:
            Dictionary with signal, confidence, and details
        """
        analysis = self.analyze(high, low, close, volume)
        
        if not analysis.primary_pattern.detected:
            return {
                'signal': 0,
                'confidence': 0.0,
                'pattern': None,
                'reasons': ["No patterns detected"]
            }
        
        primary = analysis.primary_pattern
        
        # Check breakout requirement
        if require_breakout and primary.breakout_point is None:
            return {
                'signal': 0,
                'confidence': primary.confidence,
                'pattern': primary.pattern_type.name,
                'reasons': [f"{primary.pattern_type.name} detected but awaiting breakout"]
            }
        
        return {
            'signal': primary.signal,
            'confidence': primary.confidence,
            'pattern': primary.pattern_type.name,
            'strength': primary.strength.name,
            'entry_price': primary.entry_price,
            'stop_loss': primary.stop_loss,
            'take_profit': primary.take_profit,
            'reasons': primary.reasons,
            'volume_confirmed': primary.volume_confirmation,
            'additional_patterns': len(analysis.all_patterns) - 1
        }
    
    def get_pattern_confirmation(self,
                                high: np.ndarray,
                                low: np.ndarray,
                                close: np.ndarray,
                                volume: Optional[np.ndarray] = None,
                                signal_direction: Optional[int] = None) -> bool:
        """
        Check if chart patterns confirm a given signal direction
        
        Args:
            high, low, close: Price data
            volume: Volume data
            signal_direction: Direction to confirm (1=bullish, -1=bearish, None=any)
        
        Returns:
            True if chart pattern confirms signal
        """
        analysis = self.analyze(high, low, close, volume)
        
        if not analysis.primary_pattern.detected:
            return False
        
        # Check if pattern has breakout (for stronger confirmation)
        if analysis.primary_pattern.breakout_point is None:
            return False
        
        # Check confidence threshold
        if analysis.primary_pattern.confidence < self.min_confidence:
            return False
        
        # Check signal direction
        if signal_direction is not None:
            return analysis.primary_pattern.signal == signal_direction
        
        # Any strong pattern
        return True
    
    def get_all_patterns_summary(self,
                                high: np.ndarray,
                                low: np.ndarray,
                                close: np.ndarray,
                                volume: Optional[np.ndarray] = None) -> str:
        """
        Get human-readable summary of all detected patterns
        
        Args:
            high, low, close: Price data
            volume: Volume data
        
        Returns:
            Formatted string with pattern summary
        """
        analysis = self.analyze(high, low, close, volume)
        
        if not analysis.all_patterns:
            return "No chart patterns detected"
        
        lines = [f"Detected {analysis.pattern_count} chart pattern(s):"]
        lines.append("")
        
        for i, pattern in enumerate(analysis.all_patterns, 1):
            signal_str = "BULLISH" if pattern.signal == 1 else "BEARISH" if pattern.signal == -1 else "NEUTRAL"
            
            lines.append(f"{i}. {pattern.pattern_type.name}")
            lines.append(f"   Signal: {signal_str}")
            lines.append(f"   Confidence: {pattern.confidence:.2%}")
            lines.append(f"   Strength: {pattern.strength.name}")
            
            if pattern.breakout_point is not None:
                lines.append(f"   Breakout: Confirmed at index {pattern.breakout_point}")
            else:
                lines.append(f"   Breakout: Not yet confirmed")
            
            if pattern.volume_confirmation:
                lines.append(f"   Volume: Confirmed")
            
            if pattern.entry_price:
                lines.append(f"   Entry: {pattern.entry_price:.2f}")
                lines.append(f"   SL: {pattern.stop_loss:.2f}, TP: {pattern.take_profit:.2f}")
            
            lines.append("")
        
        return "\n".join(lines)
