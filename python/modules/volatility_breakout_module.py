"""
ボラティリティ・ブレイクアウトモジュール (Volatility Breakout Module)

Larry Williamsのボラティリティ・ブレイクアウト戦略
タートルズのドンチャン・ブレイクアウトの数理的改良版

理論:
- ボラティリティ拡大時に価格がトレンド形成
- ATRの一定倍率を超える動きでエントリー

数式:
    upper_band = open + k * ATR
    lower_band = open - k * ATR
    
    close > upper_band → ロング
    close < lower_band → ショート
"""

from dataclasses import dataclass
from typing import Optional
import numpy as np
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from signal_engine.signal_aggregator import ModuleScore


@dataclass
class VolatilityBreakoutResult:
    """ブレイクアウト分析結果"""
    atr: float                  # ATR値
    upper_band: float           # 上方バンド
    lower_band: float           # 下方バンド
    range_ratio: float          # 今日のレンジ / ATR
    signal: int                 # 1=ロング(上ブレイク), -1=ショート(下ブレイク), 0=中立
    breakout_strength: float    # ブレイクアウト強度


class VolatilityBreakoutModule:
    """
    ボラティリティ・ブレイクアウト戦略モジュール
    
    ATRベースのバンドを計算し、ブレイクアウトでシグナルを生成。
    
    パラメータ:
    - atr_period: ATR計算期間
    - k_factor: ATR倍率（バンド幅）
    
    使用例:
        module = VolatilityBreakoutModule(atr_period=14, k_factor=0.5)
        score = module.analyze(opens, highs, lows, closes)
    """
    
    def __init__(self,
                 atr_period: int = 14,
                 k_factor: float = 0.5,
                 min_confidence: float = 0.3):
        """
        Args:
            atr_period: ATR計算期間
            k_factor: ATR倍率（バンド幅）
            min_confidence: 最小信頼度
        """
        self.atr_period = atr_period
        self.k_factor = k_factor
        self.min_confidence = min_confidence
    
    def analyze(self,
                opens: np.ndarray,
                highs: np.ndarray,
                lows: np.ndarray,
                closes: np.ndarray) -> ModuleScore:
        """
        ブレイクアウト分析を実行
        
        Args:
            opens: 始値配列（古い→新しい順）
            highs: 高値配列
            lows: 安値配列
            closes: 終値配列
        
        Returns:
            ModuleScore: signal, confidence, reason
        """
        result = self.analyze_detailed(opens, highs, lows, closes)
        
        # ModuleScoreに変換
        if result.signal == 0:
            return ModuleScore(
                signal=0,
                confidence=0.0,
                reason=f"ブレイクアウトなし (ATR={result.atr:.4f})"
            )
        
        if result.signal > 0:
            direction = "上方ブレイク→ロング"
        else:
            direction = "下方ブレイク→ショート"
        
        reason = (f"ボラティリティブレイクアウト: {direction} "
                  f"(強度={result.breakout_strength:.2f}, "
                  f"レンジ比={result.range_ratio:.2f})")
        
        return ModuleScore(
            signal=result.signal,
            confidence=result.breakout_strength,
            reason=reason
        )
    
    def analyze_detailed(self,
                         opens: np.ndarray,
                         highs: np.ndarray,
                         lows: np.ndarray,
                         closes: np.ndarray) -> VolatilityBreakoutResult:
        """
        詳細なブレイクアウト分析
        
        Returns:
            VolatilityBreakoutResult: 詳細分析結果
        """
        # データ不足チェック
        if len(closes) < self.atr_period + 1:
            return VolatilityBreakoutResult(
                atr=0.0,
                upper_band=0.0,
                lower_band=0.0,
                range_ratio=0.0,
                signal=0,
                breakout_strength=0.0
            )
        
        # ATR計算
        atr = self._calculate_atr(highs, lows, closes)
        
        if atr < 1e-10:
            return VolatilityBreakoutResult(
                atr=0.0,
                upper_band=0.0,
                lower_band=0.0,
                range_ratio=0.0,
                signal=0,
                breakout_strength=0.0
            )
        
        # ブレイクアウトバンド計算
        today_open = opens[-1]
        today_close = closes[-1]
        today_range = highs[-1] - lows[-1]
        
        upper_band = today_open + self.k_factor * atr
        lower_band = today_open - self.k_factor * atr
        
        range_ratio = today_range / atr
        
        # シグナル判定
        if today_close > upper_band:
            signal = 1  # 上方ブレイク → ロング
            breakout_strength = min((today_close - upper_band) / atr, 1.0)
        elif today_close < lower_band:
            signal = -1  # 下方ブレイク → ショート
            breakout_strength = min((lower_band - today_close) / atr, 1.0)
        else:
            signal = 0
            breakout_strength = 0.0
        
        return VolatilityBreakoutResult(
            atr=atr,
            upper_band=upper_band,
            lower_band=lower_band,
            range_ratio=range_ratio,
            signal=signal,
            breakout_strength=breakout_strength
        )
    
    def _calculate_atr(self,
                       highs: np.ndarray,
                       lows: np.ndarray,
                       closes: np.ndarray) -> float:
        """
        ATR（Average True Range）を計算
        
        True Range = max(
            high - low,
            |high - prev_close|,
            |low - prev_close|
        )
        
        Args:
            highs: 高値配列
            lows: 安値配列
            closes: 終値配列
        
        Returns:
            ATR値
        """
        if len(closes) < 2:
            return 0.0
        
        # True Range計算
        tr = np.maximum(
            highs[1:] - lows[1:],
            np.maximum(
                np.abs(highs[1:] - closes[:-1]),
                np.abs(lows[1:] - closes[:-1])
            )
        )
        
        # ATR（単純平均）
        lookback = min(self.atr_period, len(tr))
        atr = np.mean(tr[-lookback:])
        
        return atr


# ===== テストコード =====
if __name__ == "__main__":
    import numpy as np
    
    # テストデータ生成（ブレイクアウト発生）
    np.random.seed(42)
    n = 50
    
    # 基本的なレンジ相場 + 最後にブレイクアウト
    base = 100.0
    volatility = 1.0
    
    opens = np.full(n, base) + np.random.randn(n) * volatility * 0.5
    closes = opens + np.random.randn(n) * volatility
    highs = np.maximum(opens, closes) + np.abs(np.random.randn(n)) * volatility * 0.5
    lows = np.minimum(opens, closes) - np.abs(np.random.randn(n)) * volatility * 0.5
    
    # 最後の足でブレイクアウト
    opens[-1] = base
    highs[-1] = base + 5
    lows[-1] = base - 0.5
    closes[-1] = base + 4  # 大きく上昇
    
    print("=== Volatility Breakout Module Test ===")
    module = VolatilityBreakoutModule(atr_period=14, k_factor=0.5)
    
    score = module.analyze(opens, highs, lows, closes)
    print(f"Signal: {score.signal}")
    print(f"Confidence: {score.confidence:.2f}")
    print(f"Reason: {score.reason}")
    
    result = module.analyze_detailed(opens, highs, lows, closes)
    print(f"\nDetailed:")
    print(f"  ATR: {result.atr:.4f}")
    print(f"  Upper Band: {result.upper_band:.2f}")
    print(f"  Lower Band: {result.lower_band:.2f}")
    print(f"  Range Ratio: {result.range_ratio:.2f}")
    print(f"  Breakout Strength: {result.breakout_strength:.2f}")
