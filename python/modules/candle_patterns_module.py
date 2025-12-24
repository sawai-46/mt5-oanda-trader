"""
Candle Patterns Module - Enhanced Ubuntu Implementation

Integrates advanced candlestick pattern detection with ATR filtering,
confidence scoring, and volume confirmation.
"""

import numpy as np
from typing import List
from signal_engine.signal_aggregator import ModuleScore, SignalType
from modules.base_detector import CandleData, PatternResult
from modules.pin_bar import PinBarDetector
from modules.engulfing import EngulfingDetector
from modules.doji import DojiDetector


class CandlePatternsModule:
    """
    Candlestick pattern detection module (15% weight in signal aggregation)
    
    Uses Ubuntu's enhanced detectors with:
    - ATR-based size filtering (prevents noise)
    - Body/wick ratio validation
    - Volume confirmation
    - Multi-candle context analysis
    
    Patterns:
    - Pin Bar (40% weight)
    - Engulfing (40% weight)
    - Doji (20% weight)
    """
    
    def __init__(self,
                 min_confidence: float = 0.5,
                 min_body_atr_ratio: float = 0.3,
                 min_range_atr_ratio: float = 0.5):
        """
        Initialize candle patterns module
        
        Args:
            min_confidence: Minimum confidence threshold
            min_body_atr_ratio: Minimum body size as ratio of ATR
            min_range_atr_ratio: Minimum range size as ratio of ATR
        """
        self.min_confidence = min_confidence
        
        # Initialize detectors
        self.pin_bar_detector = PinBarDetector(
            min_confidence=min_confidence,
            min_body_atr_ratio=min_body_atr_ratio,
            min_range_atr_ratio=min_range_atr_ratio
        )
        self.engulfing_detector = EngulfingDetector(
            min_confidence=min_confidence,
            min_body_atr_ratio=min_body_atr_ratio
        )
        self.doji_detector = DojiDetector(
            min_confidence=min_confidence,
            min_range_atr_ratio=min_range_atr_ratio
        )
        
        # Pattern weights
        self.pattern_weights = {
            'pin_bar': 0.40,
            'engulfing': 0.40,
            'doji': 0.20
        }
    
    def analyze(self,
                opens: np.ndarray,
                highs: np.ndarray,
                lows: np.ndarray,
                closes: np.ndarray,
                volumes: np.ndarray = None,
                timestamps: List[str] = None) -> ModuleScore:
        """
        Analyze candlestick patterns and generate signal
        
        Args:
            opens: Open prices (most recent last)
            highs: High prices (most recent last)
            lows: Low prices (most recent last)
            closes: Close prices (most recent last)
            volumes: Volume data (optional)
            timestamps: Timestamp strings (optional)
            
        Returns:
            ModuleScore with signal, confidence, and reasoning
        """
        if len(closes) < 3:
            return ModuleScore(
                signal=SignalType.NEUTRAL,
                confidence=0.0,
                reason="Insufficient data for pattern analysis"
            )
        
        # Convert to CandleData format
        candles = self._convert_to_candles(
            opens, highs, lows, closes, volumes, timestamps
        )
        
        # Detect patterns
        patterns = []
        
        # 1. Pin Bar (40% weight)
        pin_bar_result = self.pin_bar_detector.detect(candles)
        if pin_bar_result.detected and pin_bar_result.confidence >= self.min_confidence:
            patterns.append({
                'name': 'Pin Bar',
                'signal': pin_bar_result.signal,
                'confidence': pin_bar_result.confidence,
                'weight': self.pattern_weights['pin_bar'],
                'reasons': pin_bar_result.reasons
            })
        
        # 2. Engulfing (40% weight)
        engulfing_result = self.engulfing_detector.detect(candles)
        if engulfing_result.detected and engulfing_result.confidence >= self.min_confidence:
            patterns.append({
                'name': 'Engulfing',
                'signal': engulfing_result.signal,
                'confidence': engulfing_result.confidence,
                'weight': self.pattern_weights['engulfing'],
                'reasons': engulfing_result.reasons
            })
        
        # 3. Doji (20% weight)
        doji_result = self.doji_detector.detect(candles)
        if doji_result.detected and doji_result.confidence >= self.min_confidence:
            patterns.append({
                'name': 'Doji',
                'signal': doji_result.signal,
                'confidence': doji_result.confidence,
                'weight': self.pattern_weights['doji'],
                'reasons': doji_result.reasons
            })
        
        # Aggregate patterns
        if not patterns:
            return ModuleScore(
                signal=SignalType.NEUTRAL,
                confidence=0.0,
                reason="No significant candlestick patterns detected"
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
        pattern_names = [f"{p['name']} ({p['confidence']:.2f})" for p in patterns]
        reasons_text = " | ".join([r for p in patterns for r in p['reasons'][:1]])
        reason = f"{signal_name} patterns: {', '.join(pattern_names)} - {reasons_text}"
        
        return ModuleScore(
            signal=signal_type,
            confidence=float(avg_confidence),
            reason=reason
        )
    
    def _convert_to_candles(self,
                           opens: np.ndarray,
                           highs: np.ndarray,
                           lows: np.ndarray,
                           closes: np.ndarray,
                           volumes: np.ndarray = None,
                           timestamps: List[str] = None) -> List[CandleData]:
        """
        Convert numpy arrays to list of CandleData objects
        
        Args:
            opens, highs, lows, closes: Price arrays
            volumes: Volume array (optional)
            timestamps: Timestamp strings (optional)
            
        Returns:
            List of CandleData objects
        """
        candles = []
        n = len(closes)
        
        if volumes is None:
            volumes = np.zeros(n)
        if timestamps is None:
            timestamps = [f"bar_{i}" for i in range(n)]
        
        for i in range(n):
            candles.append(CandleData(
                timestamp=timestamps[i],
                open=float(opens[i]),
                high=float(highs[i]),
                low=float(lows[i]),
                close=float(closes[i]),
                volume=float(volumes[i])
            ))
        
        return candles
