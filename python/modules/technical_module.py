"""
テクニカルモジュール

MACD、RSI等のテクニカル指標分析
"""

import numpy as np
from typing import Optional
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from signal_engine.signal_aggregator import ModuleScore


class TechnicalModule:
    """
    テクニカルモジュール
    
    機能:
    1. MACD反転検出
    2. RSIオーバーボート/オーバーソールド判定
    3. MACDヒストグラム分析（Elder流）
    """
    
    def __init__(self,
                 macd_fast: int = 12,
                 macd_slow: int = 26,
                 macd_signal: int = 9,
                 rsi_period: int = 14,
                 rsi_overbought: float = 70.0,
                 rsi_oversold: float = 30.0):
        """
        Args:
            macd_fast: MACD Fast EMA
            macd_slow: MACD Slow EMA
            macd_signal: MACD Signal
            rsi_period: RSI期間
            rsi_overbought: RSI買われすぎライン
            rsi_oversold: RSI売られすぎライン
        """
        self.macd_fast = macd_fast
        self.macd_slow = macd_slow
        self.macd_signal = macd_signal
        self.rsi_period = rsi_period
        self.rsi_overbought = rsi_overbought
        self.rsi_oversold = rsi_oversold
    
    def analyze(self,
                closes: np.ndarray,
                macd_main: np.ndarray,
                macd_signal: np.ndarray,
                rsi: Optional[np.ndarray] = None) -> ModuleScore:
        """
        テクニカル分析
        
        Args:
            closes: 終値配列
            macd_main: MACDメインライン
            macd_signal: MACDシグナルライン
            rsi: RSI配列（オプション）
        
        Returns:
            ModuleScore
        """
        reasons = []
        signal = 0
        confidence = 0.0
        
        # MACD分析
        macd_score, macd_reason = self._analyze_macd(macd_main, macd_signal)
        if macd_score != 0:
            signal = macd_score
            confidence += 0.5
            reasons.append(macd_reason)
        
        # RSI分析
        if rsi is not None:
            rsi_score, rsi_reason = self._analyze_rsi(rsi)
            if rsi_score != 0:
                if signal == 0:
                    signal = rsi_score
                elif signal == rsi_score:
                    # 同じ方向なら確信度アップ
                    confidence += 0.3
                else:
                    # 逆方向なら確信度ダウン
                    confidence -= 0.2
                reasons.append(rsi_reason)
        
        # 最終確信度調整
        confidence = max(0.0, min(1.0, confidence))
        
        if signal == 0:
            return ModuleScore(signal=0, confidence=0.0, reason="テクニカル中立")
        
        reason_text = " + ".join(reasons)
        return ModuleScore(signal=signal, confidence=confidence, reason=reason_text)
    
    def _analyze_macd(self, macd_main: np.ndarray, macd_signal: np.ndarray) -> tuple:
        """
        MACD分析
        
        Returns:
            (signal: int, reason: str)
        """
        # ゴールデンクロス/デッドクロス検出
        prev_diff = macd_main[-2] - macd_signal[-2]
        curr_diff = macd_main[-1] - macd_signal[-1]
        
        # ゴールデンクロス
        if prev_diff < 0 and curr_diff > 0:
            return 1, "MACDゴールデンクロス"
        
        # デッドクロス
        if prev_diff > 0 and curr_diff < 0:
            return -1, "MACDデッドクロス"
        
        # ヒストグラム方向
        histogram = macd_main[-1] - macd_signal[-1]
        if abs(histogram) > 0.0001:
            if histogram > 0:
                return 1, "MACDヒストグラム正"
            else:
                return -1, "MACDヒストグラム負"
        
        return 0, ""
    
    def _analyze_rsi(self, rsi: np.ndarray) -> tuple:
        """
        RSI分析
        
        Returns:
            (signal: int, reason: str)
        """
        current_rsi = rsi[-1]
        
        # 売られすぎからの反発
        if current_rsi < self.rsi_oversold:
            # 前の足から上昇しているか
            if rsi[-1] > rsi[-2]:
                return 1, f"RSI売られすぎ反発({current_rsi:.1f})"
        
        # 買われすぎからの反落
        if current_rsi > self.rsi_overbought:
            # 前の足から下降しているか
            if rsi[-1] < rsi[-2]:
                return -1, f"RSI買われすぎ反落({current_rsi:.1f})"
        
        return 0, ""
    
    def calculate_macd(self, closes: np.ndarray) -> tuple:
        """
        MACD計算
        
        Returns:
            (macd_main, macd_signal, histogram)
        """
        # EMA計算
        def ema(data, period):
            alpha = 2 / (period + 1)
            result = np.zeros_like(data)
            result[0] = data[0]
            for i in range(1, len(data)):
                result[i] = alpha * data[i] + (1 - alpha) * result[i - 1]
            return result
        
        fast_ema = ema(closes, self.macd_fast)
        slow_ema = ema(closes, self.macd_slow)
        macd_main = fast_ema - slow_ema
        macd_signal = ema(macd_main, self.macd_signal)
        histogram = macd_main - macd_signal
        
        return macd_main, macd_signal, histogram
    
    def calculate_rsi(self, closes: np.ndarray) -> np.ndarray:
        """
        RSI計算
        
        Returns:
            RSI配列
        """
        deltas = np.diff(closes)
        gains = np.where(deltas > 0, deltas, 0)
        losses = np.where(deltas < 0, -deltas, 0)
        
        # 初回平均
        avg_gain = np.mean(gains[:self.rsi_period])
        avg_loss = np.mean(losses[:self.rsi_period])
        
        rsi = np.zeros(len(closes))
        rsi[:self.rsi_period] = 50  # 初期値
        
        # RSI計算
        for i in range(self.rsi_period, len(closes)):
            avg_gain = (avg_gain * (self.rsi_period - 1) + gains[i - 1]) / self.rsi_period
            avg_loss = (avg_loss * (self.rsi_period - 1) + losses[i - 1]) / self.rsi_period
            
            if avg_loss == 0:
                rsi[i] = 100
            else:
                rs = avg_gain / avg_loss
                rsi[i] = 100 - (100 / (1 + rs))
        
        return rsi


# ===== テストコード =====
if __name__ == "__main__":
    # サンプルデータ
    closes = np.array([100, 101, 99, 102, 103, 102, 105, 107, 106, 108, 110])
    
    module = TechnicalModule()
    
    # MACD/RSI計算
    macd_main, macd_signal, _ = module.calculate_macd(closes)
    rsi = module.calculate_rsi(closes)
    
    # 分析
    score = module.analyze(closes, macd_main, macd_signal, rsi)
    
    print(f"Signal: {score.signal}")
    print(f"Confidence: {score.confidence:.2f}")
    print(f"Reason: {score.reason}")
