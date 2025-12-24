"""
Trading Modules Package

Integrates detection modules with Ubuntu's enhanced implementations:

=== 従来テクニカルモジュール ===
1. Candle Patterns - Pin Bar, Engulfing, Doji
2. Chart Patterns - Double Top/Bottom, H&S, Triangles  
3. Technical - MACD, RSI
4. Trend - EMA Perfect Order, Pullback
5. False Breakout - ダマシ検出
6. Wave Structure - ツーレッグ構造
7. Structural - ピボット等
8. Volatility - ATRボラティリティ分析
9. Pullback - EA_PullbackEntryロジック移植

=== 金融工学モジュール (NEW) ===
10. Momentum - Jegadeesh & Titman式モメンタム
11. Mean Reversion - Z-score平均回帰
12. Volatility Breakout - Larry Williams式ブレイクアウト
"""

# Core modules (implemented)
from modules.candle_patterns_module import CandlePatternsModule
from modules.chart_patterns_module import ChartPatternsModule
from modules.false_breakout_module import FalseBreakoutModule
from modules.wave_structure_module import WaveStructureModule
from modules.structural_module import StructuralModule
from modules.technical_module import TechnicalModule
from modules.trend_module import TrendModule
from modules.volatility_module import VolatilityModule
from modules.pullback_module import PullbackModule, PullbackEMAReference, PullbackType

# ★NEW: 金融工学モジュール（クオンツ戦略）
from modules.momentum_module import MomentumModule
from modules.mean_reversion_module import MeanReversionModule
from modules.volatility_breakout_module import VolatilityBreakoutModule

# Ubuntu candle pattern detectors (for advanced usage)
from modules.base_detector import BaseCandleDetector, CandleData, PatternResult
from modules.pin_bar import PinBarDetector
from modules.engulfing import EngulfingDetector
from modules.doji import DojiDetector

# Ubuntu chart pattern detectors (for advanced usage)
from modules.base_chart_pattern import BaseChartPattern, ChartPatternResult, PatternType
from modules.double_top_bottom import DoubleTopBottomDetector
from modules.head_shoulders import HeadShouldersDetector
from modules.triangles import TriangleDetector

__all__ = [
    # Main modules for signal engine (9 core + 3 quantitative)
    'CandlePatternsModule',
    'ChartPatternsModule',
    'FalseBreakoutModule',
    'WaveStructureModule',
    'StructuralModule',
    'TechnicalModule',
    'TrendModule',
    'VolatilityModule',
    'PullbackModule',
    'PullbackEMAReference',
    'PullbackType',
    
    # ★NEW: 金融工学モジュール
    'MomentumModule',
    'MeanReversionModule',
    'VolatilityBreakoutModule',
    
    # Candle pattern components
    'BaseCandleDetector',
    'CandleData',
    'PatternResult',
    'PinBarDetector',
    'EngulfingDetector',
    'DojiDetector',
    
    # Chart pattern components
    'BaseChartPattern',
    'ChartPatternResult',
    'PatternType',
    'DoubleTopBottomDetector',
    'HeadShouldersDetector',
    'TriangleDetector',
]
