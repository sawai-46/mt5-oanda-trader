"""
トレンドモジュール

EMAパーフェクトオーダー、EMAプルバック検出
既存のEA_PullbackEntry.mq4のロジックをPython化
"""

import numpy as np
from typing import Optional, Tuple
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from signal_engine.signal_aggregator import ModuleScore


class TrendModule:
    """
    トレンドモジュール
    
    機能:
    1. EMAパーフェクトオーダー判定
    2. EMA傾きチェック
    3. EMAプルバック検出（Touch/Cross/Break）
    """
    
    def __init__(self,
                 ema_short: int = 12,
                 ema_mid: int = 25,
                 ema_long: int = 100,
                 require_perfect_order: bool = True,
                 min_slope_fast: float = 0.0001,
                 min_slope_slow: float = 0.00005,
                 slope_bars: int = 3):
        """
        Args:
            ema_short: 短期EMA期間
            ema_mid: 中期EMA期間
            ema_long: 長期EMA期間
            require_perfect_order: パーフェクトオーダー必須
            min_slope_fast: 短期EMA最小傾き
            min_slope_slow: 長期EMA最小傾き
            slope_bars: 傾き計算期間
        """
        self.ema_short = ema_short
        self.ema_mid = ema_mid
        self.ema_long = ema_long
        self.require_perfect_order = require_perfect_order
        self.min_slope_fast = min_slope_fast
        self.min_slope_slow = min_slope_slow
        self.slope_bars = slope_bars
    
    def analyze(self, 
                closes: np.ndarray,
                ema12: np.ndarray,
                ema25: np.ndarray,
                ema100: np.ndarray) -> ModuleScore:
        """
        トレンド分析
        
        Args:
            closes: 終値配列（最新が[-1]）
            ema12: EMA12配列
            ema25: EMA25配列
            ema100: EMA100配列
        
        Returns:
            ModuleScore: スコア（signal, confidence, reason）
        """
        # パーフェクトオーダーチェック
        is_uptrend = (ema12[-1] > ema25[-1]) and (ema25[-1] > ema100[-1])
        is_downtrend = (ema12[-1] < ema25[-1]) and (ema25[-1] < ema100[-1])
        
        if self.require_perfect_order:
            if not is_uptrend and not is_downtrend:
                return ModuleScore(signal=0, confidence=0.0, reason="パーフェクトオーダー不成立")
        
        # トレンド方向
        if is_uptrend:
            trend_signal = 1
            trend_name = "上昇"
        elif is_downtrend:
            trend_signal = -1
            trend_name = "下降"
        else:
            # 簡易判定
            if ema12[-1] > ema100[-1]:
                trend_signal = 1
                trend_name = "上昇(簡易)"
            elif ema12[-1] < ema100[-1]:
                trend_signal = -1
                trend_name = "下降(簡易)"
            else:
                return ModuleScore(signal=0, confidence=0.0, reason="トレンドなし")
        
        # EMA傾きチェック
        slope_fast = (ema12[-1] - ema12[-(self.slope_bars + 1)]) / self.slope_bars
        slope_slow = (ema100[-1] - ema100[-(self.slope_bars + 1)]) / self.slope_bars
        
        if trend_signal == 1:
            # 上昇トレンド: 傾きが正
            if self.min_slope_fast > 0 and slope_fast < self.min_slope_fast:
                return ModuleScore(signal=0, confidence=0.0, reason="EMA12傾き不足")
            if self.min_slope_slow > 0 and slope_slow < self.min_slope_slow:
                return ModuleScore(signal=0, confidence=0.0, reason="EMA100傾き不足")
        else:
            # 下降トレンド: 傾きが負
            if self.min_slope_fast > 0 and slope_fast > -self.min_slope_fast:
                return ModuleScore(signal=0, confidence=0.0, reason="EMA12傾き不足")
            if self.min_slope_slow > 0 and slope_slow > -self.min_slope_slow:
                return ModuleScore(signal=0, confidence=0.0, reason="EMA100傾き不足")
        
        # EMAプルバック検出
        pullback_detected, pullback_type = self._detect_pullback(
            closes, ema25, is_long=(trend_signal == 1)
        )
        
        if not pullback_detected:
            return ModuleScore(
                signal=trend_signal,
                confidence=0.5,  # プルバックなしなので低め
                reason=f"{trend_name}トレンド（プルバックなし）"
            )
        
        # プルバック検出成功
        confidence = 1.0 if self.require_perfect_order else 0.8
        return ModuleScore(
            signal=trend_signal,
            confidence=confidence,
            reason=f"{trend_name}トレンド + {pullback_type}"
        )
    
    def _detect_pullback(self,
                        closes: np.ndarray,
                        ema: np.ndarray,
                        is_long: bool,
                        lookback: int = 5) -> Tuple[bool, str]:
        """
        EMAプルバック検出
        
        Args:
            closes: 終値配列
            ema: EMA配列（基準EMA、通常はEMA25）
            is_long: True=上昇トレンド, False=下降トレンド
            lookback: 過去何本まで探すか
        
        Returns:
            (detected: bool, pullback_type: str)
        """
        # 過去N本をチェック
        for i in range(1, min(lookback + 1, len(closes))):
            idx = -(i + 1)  # -2, -3, -4, ...
            
            # EMAタッチ判定
            if is_long:
                # 上昇トレンド: 安値がEMAにタッチ
                if closes[idx] <= ema[idx] <= closes[idx - 1]:
                    return True, "EMAタッチ(ロング)"
            else:
                # 下降トレンド: 高値がEMAにタッチ
                if closes[idx] >= ema[idx] >= closes[idx - 1]:
                    return True, "EMAタッチ(ショート)"
            
            # EMAクロス判定
            if i < len(closes) - 1:
                prev_idx = idx - 1
                if is_long:
                    # 価格がEMAを下→上クロス
                    if closes[prev_idx] < ema[prev_idx] and closes[idx] > ema[idx]:
                        return True, "EMAクロス(ロング)"
                else:
                    # 価格がEMAを上→下クロス
                    if closes[prev_idx] > ema[prev_idx] and closes[idx] < ema[idx]:
                        return True, "EMAクロス(ショート)"
        
        return False, ""


# ===== テストコード =====
if __name__ == "__main__":
    # サンプルデータ（上昇トレンド + プルバック）
    closes = np.array([100, 101, 102, 103, 104, 102, 103, 105, 106, 107])
    ema12 = np.array([100, 100.5, 101, 101.5, 102, 102, 102.5, 103, 103.5, 104])
    ema25 = np.array([99, 99.5, 100, 100.5, 101, 101, 101.5, 102, 102.5, 103])
    ema100 = np.array([98, 98.2, 98.4, 98.6, 98.8, 99, 99.2, 99.4, 99.6, 99.8])
    
    module = TrendModule(require_perfect_order=True)
    score = module.analyze(closes, ema12, ema25, ema100)
    
    print(f"Signal: {score.signal}")
    print(f"Confidence: {score.confidence:.2f}")
    print(f"Reason: {score.reason}")
