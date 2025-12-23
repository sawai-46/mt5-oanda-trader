#!/usr/bin/env python
"""7モジュール詳細テスト"""

import sys
import numpy as np

# モジュールを個別にテスト
print("=" * 60)
print("7モジュール個別テスト")
print("=" * 60)

# テストデータ生成 - より多くのデータ点
np.random.seed(42)
n = 100

# 上昇トレンドのテストデータ
base_price = 150.0
trend = np.linspace(0, 2, n)  # 上昇トレンド
noise = np.random.randn(n) * 0.05

closes = base_price + trend + noise
opens = closes - 0.02 + np.random.randn(n) * 0.01
highs = np.maximum(opens, closes) + np.abs(np.random.randn(n) * 0.03)
lows = np.minimum(opens, closes) - np.abs(np.random.randn(n) * 0.03)
volumes = np.random.randint(1000, 5000, n).astype(float)

# EMAを計算
def ema(data, period):
    alpha = 2 / (period + 1)
    result = np.zeros_like(data)
    result[0] = data[0]
    for i in range(1, len(data)):
        result[i] = alpha * data[i] + (1 - alpha) * result[i-1]
    return result

ema12 = ema(closes, 12)
ema25 = ema(closes, 25)
ema100 = ema(closes, 100)

# MACD
macd_main = ema12 - ema25
signal_line = ema(macd_main, 9)

# RSI
def rsi(data, period=14):
    delta = np.diff(data)
    gains = np.where(delta > 0, delta, 0)
    losses = np.where(delta < 0, -delta, 0)
    
    avg_gain = np.zeros(len(data))
    avg_loss = np.zeros(len(data))
    
    avg_gain[period] = np.mean(gains[:period])
    avg_loss[period] = np.mean(losses[:period])
    
    for i in range(period + 1, len(data)):
        avg_gain[i] = (avg_gain[i-1] * (period - 1) + gains[i-1]) / period
        avg_loss[i] = (avg_loss[i-1] * (period - 1) + losses[i-1]) / period
    
    rs = np.where(avg_loss > 0, avg_gain / avg_loss, 100)
    return 100 - (100 / (1 + rs))

rsi_values = rsi(closes)

print(f"\nテストデータ: {n}本のバー")
print(f"価格範囲: {closes.min():.3f} - {closes.max():.3f}")
print(f"最新価格: Open={opens[-1]:.3f}, High={highs[-1]:.3f}, Low={lows[-1]:.3f}, Close={closes[-1]:.3f}")
print(f"EMA: 12={ema12[-1]:.3f}, 25={ema25[-1]:.3f}, 100={ema100[-1]:.3f}")
print(f"RSI: {rsi_values[-1]:.1f}")

# 各モジュールをテスト
print("\n" + "-" * 60)
print("個別モジュールテスト")
print("-" * 60)

# 1. Candle Patterns Module
try:
    from modules.candle_patterns_module import CandlePatternsModule
    cp = CandlePatternsModule()
    result = cp.analyze(opens, highs, lows, closes, volumes)
    print(f"✅ CandlePatterns: signal={result.signal}, conf={result.confidence:.2f}, reason={result.reason}")
except Exception as e:
    print(f"❌ CandlePatterns: {e}")

# 2. Chart Patterns Module
try:
    from modules.chart_patterns_module import ChartPatternsModule
    chart = ChartPatternsModule()
    result = chart.analyze(opens, highs, lows, closes)
    print(f"✅ ChartPatterns: signal={result.signal}, conf={result.confidence:.2f}, reason={result.reason}")
except Exception as e:
    print(f"❌ ChartPatterns: {e}")

# 3. False Breakout Module
try:
    from modules.false_breakout_module import FalseBreakoutModule
    fb = FalseBreakoutModule()
    result = fb.analyze(opens, highs, lows, closes)
    print(f"✅ FalseBreakout: signal={result.signal}, conf={result.confidence:.2f}, reason={result.reason}")
except Exception as e:
    print(f"❌ FalseBreakout: {e}")

# 4. Technical Module
try:
    from modules.technical_module import TechnicalModule
    tech = TechnicalModule()
    result = tech.analyze(closes, macd_main, signal_line, rsi_values)
    print(f"✅ Technical: signal={result.signal}, conf={result.confidence:.2f}, reason={result.reason}")
except Exception as e:
    print(f"❌ Technical: {e}")

# 5. Trend Module
try:
    from modules.trend_module import TrendModule
    trend_mod = TrendModule()
    result = trend_mod.analyze(closes, ema12, ema25, ema100)
    print(f"✅ Trend: signal={result.signal}, conf={result.confidence:.2f}, reason={result.reason}")
except Exception as e:
    print(f"❌ Trend: {e}")

# 6. Wave Structure Module
try:
    from modules.wave_structure_module import WaveStructureModule
    wave = WaveStructureModule()
    result = wave.analyze(opens, highs, lows, closes, lookback=50)
    print(f"✅ WaveStructure: signal={result.signal}, conf={result.confidence:.2f}, reason={result.reason}")
except Exception as e:
    print(f"❌ WaveStructure: {e}")

# 7. Structural Module
try:
    from modules.structural_module import StructuralModule
    struct = StructuralModule()
    # 前日データ（50本前を前日終値として使用）
    prev_close = closes[-50]
    prev_high = highs[-50:-1].max()
    prev_low = lows[-50:-1].min()
    result = struct.analyze(opens, highs, lows, closes, prev_high, prev_low, prev_close)
    print(f"✅ Structural: signal={result.signal}, conf={result.confidence:.2f}, reason={result.reason}")
except Exception as e:
    print(f"❌ Structural: {e}")

# SignalAggregatorをテスト
print("\n" + "-" * 60)
print("SignalAggregatorテスト")
print("-" * 60)

try:
    from signal_engine.signal_aggregator import SignalAggregator
    from signal_engine.signal_types import SignalScore, SignalType
    
    aggregator = SignalAggregator()
    
    # テスト用スコア
    scores = {
        'candle_patterns': SignalScore(SignalType.BUY, 0.7, "Pin Bar detected"),
        'chart_patterns': SignalScore(SignalType.NEUTRAL, 0.5, "No pattern"),
        'false_breakout': SignalScore(SignalType.BUY, 0.8, "False breakout buy"),
        'technical': SignalScore(SignalType.BUY, 0.6, "MACD bullish"),
        'trend': SignalScore(SignalType.BUY, 0.9, "Perfect Order UP"),
        'wave_structure': SignalScore(SignalType.BUY, 0.7, "Two-leg pullback"),
        'structural': SignalScore(SignalType.BUY, 0.6, "Support level"),
    }
    
    final_score = aggregator.aggregate(scores)
    print(f"✅ Aggregated: signal={final_score.signal}, conf={final_score.confidence:.2f}, reason={final_score.reason}")
    
except Exception as e:
    import traceback
    print(f"❌ SignalAggregator: {e}")
    traceback.print_exc()

# SevenModuleAnalyzerをテスト
print("\n" + "-" * 60)
print("SevenModuleAnalyzer統合テスト")
print("-" * 60)

try:
    from inference_server_7module import SevenModuleAnalyzer
    
    analyzer = SevenModuleAnalyzer()
    
    # CSVデータ形式でテストデータを準備
    test_data = {
        'symbol': 'USDJPY',
        'timeframe': 'M5',
        # pricesは最新から古い順で渡す
        'prices': ','.join([f"{p:.3f}" for p in closes[-50:][::-1]]),
        'close_1': f"{closes[-1]:.3f}",
        'close_2': f"{closes[-2]:.3f}",
        'close_3': f"{closes[-3]:.3f}",
        'high_1': f"{highs[-1]:.3f}",
        'high_2': f"{highs[-2]:.3f}",
        'low_1': f"{lows[-1]:.3f}",
        'low_2': f"{lows[-2]:.3f}",
        'open_1': f"{opens[-1]:.3f}",
        'open_2': f"{opens[-2]:.3f}",
        'ema12': f"{ema12[-1]:.3f}",
        'ema25': f"{ema25[-1]:.3f}",
        'atr': '0.050'
    }
    
    signal, conf, reason, breakdown = analyzer.analyze(test_data)
    
    print(f"\n✅ 7Module分析結果:")
    print(f"   Signal: {signal} ({'BUY' if signal == 1 else 'SELL' if signal == -1 else 'NEUTRAL'})")
    print(f"   Confidence: {conf:.2f}")
    print(f"   Reason: {reason}")
    print(f"\n   モジュール別:")
    for name, info in breakdown.items():
        sig_text = 'BUY' if info['signal'] == 1 else 'SELL' if info['signal'] == -1 else 'NEUTRAL'
        print(f"     {name}: {sig_text} (conf={info['confidence']:.2f})")
    
except Exception as e:
    import traceback
    print(f"❌ SevenModuleAnalyzer: {e}")
    traceback.print_exc()

print("\n" + "=" * 60)
print("テスト完了")
print("=" * 60)
