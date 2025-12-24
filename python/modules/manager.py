"""
Candle Pattern Manager
Integrates all pattern detectors and generates final trading signals
"""

from typing import List, Dict, Optional
from .base_detector import CandleData, PatternResult
from .pin_bar import PinBarDetector
from .engulfing import EngulfingDetector
from .doji import DojiDetector


class CandlePatternManager:
    """
    Manages multiple candle pattern detectors and aggregates their signals
    
    Combines signals from:
    - Pin Bar (reversal)
    - Engulfing (strong reversal)
    - Doji (indecision/potential reversal)
    
    Returns aggregated signal with confidence score
    """
    
    def __init__(self, 
                 min_confidence: float = 0.5,
                 enable_pin_bar: bool = True,
                 enable_engulfing: bool = True,
                 enable_doji: bool = True):
        """
        Args:
            min_confidence: Minimum confidence threshold for final signal
            enable_pin_bar: Enable Pin Bar detector
            enable_engulfing: Enable Engulfing detector
            enable_doji: Enable Doji detector
        """
        self.min_confidence = min_confidence
        
        # Initialize detectors
        self.detectors = {}
        
        if enable_pin_bar:
            self.detectors['pin_bar'] = PinBarDetector(min_confidence=min_confidence)
        
        if enable_engulfing:
            self.detectors['engulfing'] = EngulfingDetector(min_confidence=min_confidence)
        
        if enable_doji:
            self.detectors['doji'] = DojiDetector(min_confidence=min_confidence)
    
    def analyze(self, candles: List[CandleData]) -> Dict:
        """
        Analyze candle data with all enabled detectors
        
        Args:
            candles: List of candle data
        
        Returns:
            Dictionary with aggregated analysis:
            {
                'signal': int (1=BUY, -1=SELL, 0=NEUTRAL),
                'confidence': float (0.0-1.0),
                'patterns_detected': List[str],
                'pattern_results': Dict[str, PatternResult],
                'reasons': List[str],
                'metadata': Dict
            }
        """
        if not candles:
            return self._create_neutral_result("No candle data provided")
        
        # Run all detectors
        pattern_results = {}
        for name, detector in self.detectors.items():
            result = detector.detect(candles)
            pattern_results[name] = result
        
        # Aggregate results
        return self._aggregate_signals(pattern_results, candles)
    
    def _aggregate_signals(self, pattern_results: Dict[str, PatternResult], 
                          candles: List[CandleData]) -> Dict:
        """
        Aggregate signals from multiple pattern detectors
        
        Strategy:
        1. Collect all detected patterns
        2. Weight by confidence
        3. Count BUY vs SELL signals
        4. Generate final signal if consensus exists
        """
        detected_patterns = []
        buy_signals = []
        sell_signals = []
        all_reasons = []
        
        # Collect signals from each detector
        for name, result in pattern_results.items():
            if result.detected:
                detected_patterns.append(result.pattern_name)
                all_reasons.extend([f"[{result.pattern_name}] {r}" for r in result.reasons])
                
                if result.signal == 1:
                    buy_signals.append((name, result.confidence))
                elif result.signal == -1:
                    sell_signals.append((name, result.confidence))
        
        # Calculate weighted signals
        buy_score = sum(conf for _, conf in buy_signals)
        sell_score = sum(conf for _, conf in sell_signals)
        
        # Determine final signal
        if not detected_patterns:
            return self._create_neutral_result("No patterns detected", pattern_results)
        
        # Signal weights (Engulfing > Pin Bar > Doji)
        weights = {
            'engulfing': 1.5,
            'pin_bar': 1.2,
            'doji': 0.8
        }
        
        # Apply weights
        weighted_buy = sum(conf * weights.get(name, 1.0) for name, conf in buy_signals)
        weighted_sell = sum(conf * weights.get(name, 1.0) for name, conf in sell_signals)
        
        # Determine signal direction
        if weighted_buy > weighted_sell and weighted_buy > 0:
            final_signal = 1
            final_confidence = min(weighted_buy / len(self.detectors), 1.0)
            signal_type = "BUY"
        elif weighted_sell > weighted_buy and weighted_sell > 0:
            final_signal = -1
            final_confidence = min(weighted_sell / len(self.detectors), 1.0)
            signal_type = "SELL"
        else:
            final_signal = 0
            final_confidence = 0.0
            signal_type = "NEUTRAL"
        
        # Check minimum confidence
        if final_confidence < self.min_confidence:
            final_signal = 0
            signal_type = "NEUTRAL"
            all_reasons.append(f"Confidence {final_confidence:.2f} below threshold {self.min_confidence}")
        
        # Build metadata
        metadata = {
            'buy_count': len(buy_signals),
            'sell_count': len(sell_signals),
            'buy_score': buy_score,
            'sell_score': sell_score,
            'weighted_buy': weighted_buy,
            'weighted_sell': weighted_sell,
            'detectors_used': list(self.detectors.keys()),
            'patterns_checked': len(self.detectors),
            'patterns_found': len(detected_patterns)
        }
        
        return {
            'signal': final_signal,
            'signal_type': signal_type,
            'confidence': final_confidence,
            'patterns_detected': detected_patterns,
            'pattern_results': pattern_results,
            'reasons': all_reasons,
            'metadata': metadata
        }
    
    def _create_neutral_result(self, reason: str, 
                               pattern_results: Optional[Dict[str, PatternResult]] = None) -> Dict:
        """Create neutral result when no signals"""
        return {
            'signal': 0,
            'signal_type': 'NEUTRAL',
            'confidence': 0.0,
            'patterns_detected': [],
            'pattern_results': pattern_results or {},
            'reasons': [reason],
            'metadata': {
                'detectors_used': list(self.detectors.keys()),
                'patterns_checked': len(self.detectors),
                'patterns_found': 0
            }
        }
    
    def get_summary(self, analysis: Dict) -> str:
        """
        Get human-readable summary of analysis
        
        Args:
            analysis: Result from analyze()
        
        Returns:
            Summary string
        """
        lines = []
        lines.append("="*60)
        lines.append("CANDLE PATTERN ANALYSIS SUMMARY")
        lines.append("="*60)
        
        lines.append(f"\nSignal: {analysis['signal_type']}")
        lines.append(f"Confidence: {analysis['confidence']:.2%}")
        lines.append(f"Patterns Detected: {len(analysis['patterns_detected'])}")
        
        if analysis['patterns_detected']:
            lines.append(f"  - {', '.join(analysis['patterns_detected'])}")
        
        lines.append(f"\nDetectors Used: {', '.join(analysis['metadata']['detectors_used'])}")
        lines.append(f"Buy Signals: {analysis['metadata']['buy_count']}")
        lines.append(f"Sell Signals: {analysis['metadata']['sell_count']}")
        
        if analysis['reasons']:
            lines.append("\nReasons:")
            for reason in analysis['reasons'][:5]:  # Limit to first 5
                lines.append(f"  - {reason}")
        
        lines.append("="*60)
        
        return "\n".join(lines)
