"""
PullbackModule - EA_PullbackEntry.mq4 のロジックをPython化

EA側の PullbackCore.mqh + PullbackStrategy.mqh の機能を移植し、
7モジュールおよびAntigravityと統合可能な形式で実装。

機能:
1. EMAプルバック検出 (Touch/Cross/Break)
2. ラウンドナンバープルバック検出 (.00/.50)
3. パーフェクトオーダー + EMA傾き + ADXフィルター
4. 確認足チェック
5. 強トレンドモード判定
"""

import numpy as np
from typing import Optional, Tuple, List
from dataclasses import dataclass
from enum import Enum
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from signal_engine.signal_aggregator import ModuleScore


class PullbackEMAReference(Enum):
    """プルバック検出に使用するEMA"""
    EMA_12 = 12
    EMA_25 = 25
    EMA_100 = 100


class PullbackType(Enum):
    """プルバック検出タイプ"""
    NONE = "none"
    EMA_TOUCH = "ema_touch"
    EMA_CROSS = "ema_cross"
    EMA_BREAK = "ema_break"
    RN_00_BOUNCE = "rn_00_bounce"
    RN_50_BOUNCE = "rn_50_bounce"
    RN_00_DROP = "rn_00_drop"
    RN_50_DROP = "rn_50_drop"


@dataclass
class PullbackResult:
    """プルバック検出結果"""
    detected: bool
    direction: int  # 1=long, -1=short, 0=none
    pullback_type: PullbackType
    entry_level: float
    reason: str


class PullbackModule:
    """
    プルバック検出モジュール
    
    EA_PullbackEntry.mq4 のコアロジックをPython化し、
    7モジュール統合システムに組み込み可能な形式で実装。
    """
    
    def __init__(self,
                 # EMA設定
                 ema_short: int = 12,
                 ema_mid: int = 25,
                 ema_long: int = 100,
                 require_perfect_order: bool = True,
                 
                 # プルバック検出設定
                 pullback_lookback: int = 5,
                 pullback_ema: PullbackEMAReference = PullbackEMAReference.EMA_25,
                 use_touch: bool = True,
                 use_cross: bool = True,
                 use_break: bool = False,
                 
                 # EMA傾き設定
                 ema_slope_bars: int = 3,
                 min_slope_fast: float = 0.0,
                 min_slope_slow: float = 0.0,
                 
                 # ラウンドナンバー設定
                 use_roundnumber: bool = False,
                 rn_use_00_line: bool = True,
                 rn_use_50_line: bool = True,
                 rn_touch_buffer_pips: float = 3.0,
                 rn_lookback_bars: int = 3,
                 rn_digit_level: int = 2,
                 
                 # ADXフィルター設定
                 use_adx_filter: bool = False,
                 adx_period: int = 14,
                 adx_min_level: float = 20.0,
                 
                 # 確認足設定
                 use_confirmation_bar: bool = False,
                 confirm_min_size_pips: float = 5.0,
                 confirm_max_size_pips: float = 50.0,
                 
                 # 銘柄タイプ（自動判定用）
                 pip_size: float = 0.01,
                 is_index: bool = False):
        """
        Args:
            ema_short: 短期EMA期間 (default: 12)
            ema_mid: 中期EMA期間 (default: 25)
            ema_long: 長期EMA期間 (default: 100)
            require_perfect_order: パーフェクトオーダー必須
            pullback_lookback: プルバック検出期間
            pullback_ema: プルバック検出に使用するEMA
            use_touch: タッチ検出有効
            use_cross: クロス検出有効
            use_break: ブレイク検出有効
            ema_slope_bars: 傾き計算期間
            min_slope_fast: 短期EMA最小傾き
            min_slope_slow: 長期EMA最小傾き
            use_roundnumber: ラウンドナンバー検出有効
            rn_use_00_line: .00ライン使用
            rn_use_50_line: .50ライン使用
            rn_touch_buffer_pips: タッチ判定バッファ (pips)
            rn_lookback_bars: ラウンドナンバー検出期間
            rn_digit_level: 桁数レベル (0=1000単位, 1=100単位, 2=1単位)
            use_adx_filter: ADXフィルター有効
            adx_period: ADX期間
            adx_min_level: ADX最小レベル
            use_confirmation_bar: 確認足チェック有効
            confirm_min_size_pips: 確認足最小サイズ (pips)
            confirm_max_size_pips: 確認足最大サイズ (pips)
            pip_size: 1pipの価格単位
            is_index: 指数銘柄フラグ
        """
        self.ema_short = ema_short
        self.ema_mid = ema_mid
        self.ema_long = ema_long
        self.require_perfect_order = require_perfect_order
        
        self.pullback_lookback = pullback_lookback
        self.pullback_ema = pullback_ema
        self.use_touch = use_touch
        self.use_cross = use_cross
        self.use_break = use_break
        
        self.ema_slope_bars = ema_slope_bars
        self.min_slope_fast = min_slope_fast
        self.min_slope_slow = min_slope_slow
        
        self.use_roundnumber = use_roundnumber
        self.rn_use_00_line = rn_use_00_line
        self.rn_use_50_line = rn_use_50_line
        self.rn_touch_buffer_pips = rn_touch_buffer_pips
        self.rn_lookback_bars = rn_lookback_bars
        self.rn_digit_level = rn_digit_level
        
        self.use_adx_filter = use_adx_filter
        self.adx_period = adx_period
        self.adx_min_level = adx_min_level
        
        self.use_confirmation_bar = use_confirmation_bar
        self.confirm_min_size_pips = confirm_min_size_pips
        self.confirm_max_size_pips = confirm_max_size_pips
        
        self.pip_size = pip_size
        self.is_index = is_index
    
    def analyze(self,
                closes: np.ndarray,
                highs: np.ndarray,
                lows: np.ndarray,
                opens: np.ndarray,
                ema12: np.ndarray,
                ema25: np.ndarray,
                ema100: np.ndarray,
                adx: Optional[np.ndarray] = None) -> ModuleScore:
        """
        プルバック分析を実行
        
        Args:
            closes: 終値配列（古い順、最新が[-1]）
            highs: 高値配列
            lows: 安値配列
            opens: 始値配列
            ema12: EMA12配列
            ema25: EMA25配列
            ema100: EMA100配列
            adx: ADX配列（オプション）
        
        Returns:
            ModuleScore: (signal, confidence, reason)
        """
        result = self._evaluate_pullback(
            closes, highs, lows, opens,
            ema12, ema25, ema100, adx
        )
        
        if not result.detected:
            return ModuleScore(
                signal=0,
                confidence=0.0,
                reason=f"プルバックなし: {result.reason}"
            )
        
        # 確認足チェック
        if self.use_confirmation_bar:
            if not self._check_confirmation_bar(highs, lows, opens, closes, result.direction == 1):
                return ModuleScore(
                    signal=0,
                    confidence=0.3,
                    reason="確認足条件不成立"
                )
        
        # 確信度を決定
        confidence = self._calculate_confidence(result)
        
        direction_str = "ロング" if result.direction == 1 else "ショート"
        return ModuleScore(
            signal=result.direction,
            confidence=confidence,
            reason=f"{direction_str}プルバック検出: {result.reason}"
        )
    
    def _evaluate_pullback(self,
                           closes: np.ndarray,
                           highs: np.ndarray,
                           lows: np.ndarray,
                           opens: np.ndarray,
                           ema12: np.ndarray,
                           ema25: np.ndarray,
                           ema100: np.ndarray,
                           adx: Optional[np.ndarray]) -> PullbackResult:
        """プルバック評価の内部実装"""
        
        # トレンド判定
        trend_dir = self._check_trend(ema12, ema25, ema100)
        if trend_dir == 0:
            return PullbackResult(
                detected=False, direction=0,
                pullback_type=PullbackType.NONE,
                entry_level=0, reason="トレンド不成立"
            )
        
        # EMA傾きチェック
        if not self._check_ema_slope(ema12, ema100, trend_dir == 1):
            return PullbackResult(
                detected=False, direction=0,
                pullback_type=PullbackType.NONE,
                entry_level=0, reason="EMA傾き不足"
            )
        
        # ADXフィルター
        if self.use_adx_filter and adx is not None:
            if adx[-1] < self.adx_min_level:
                return PullbackResult(
                    detected=False, direction=0,
                    pullback_type=PullbackType.NONE,
                    entry_level=0, reason=f"ADX低い({adx[-1]:.1f}<{self.adx_min_level})"
                )
        
        # EMAプルバック検出
        pb_result = self._detect_ema_pullback(
            closes, highs, lows, opens,
            ema12, ema25, ema100, trend_dir
        )
        
        # ラウンドナンバープルバック検出
        rn_result = None
        if self.use_roundnumber:
            rn_result = self._detect_roundnumber_pullback(
                highs, lows, opens, closes, trend_dir == 1
            )
        
        # 結果を統合
        if pb_result.detected:
            return pb_result
        elif rn_result is not None and rn_result.detected:
            return rn_result
        else:
            return PullbackResult(
                detected=False, direction=0,
                pullback_type=PullbackType.NONE,
                entry_level=0, reason="プルバックイベントなし"
            )
    
    def _check_trend(self,
                     ema12: np.ndarray,
                     ema25: np.ndarray,
                     ema100: np.ndarray) -> int:
        """
        トレンド判定（パーフェクトオーダー）
        
        Returns:
            1=上昇, -1=下降, 0=なし
        """
        if not self.require_perfect_order:
            if ema12[-1] > ema25[-1]:
                return 1
            elif ema12[-1] < ema25[-1]:
                return -1
            return 0
        
        # パーフェクトオーダー判定
        is_uptrend = (ema12[-1] > ema25[-1]) and (ema25[-1] > ema100[-1])
        is_downtrend = (ema12[-1] < ema25[-1]) and (ema25[-1] < ema100[-1])
        
        if is_uptrend:
            return 1
        elif is_downtrend:
            return -1
        return 0
    
    def _check_ema_slope(self,
                         ema12: np.ndarray,
                         ema100: np.ndarray,
                         is_long: bool) -> bool:
        """EMA傾きチェック"""
        if self.min_slope_fast == 0 and self.min_slope_slow == 0:
            return True
        
        if len(ema12) <= self.ema_slope_bars or len(ema100) <= self.ema_slope_bars:
            return True
        
        slope_fast = (ema12[-1] - ema12[-(self.ema_slope_bars + 1)]) / self.ema_slope_bars
        slope_slow = (ema100[-1] - ema100[-(self.ema_slope_bars + 1)]) / self.ema_slope_bars
        
        if is_long:
            if self.min_slope_fast > 0 and slope_fast < self.min_slope_fast:
                return False
            if self.min_slope_slow > 0 and slope_slow < self.min_slope_slow:
                return False
        else:
            if self.min_slope_fast > 0 and slope_fast > -self.min_slope_fast:
                return False
            if self.min_slope_slow > 0 and slope_slow > -self.min_slope_slow:
                return False
        
        return True
    
    def _detect_ema_pullback(self,
                              closes: np.ndarray,
                              highs: np.ndarray,
                              lows: np.ndarray,
                              opens: np.ndarray,
                              ema12: np.ndarray,
                              ema25: np.ndarray,
                              ema100: np.ndarray,
                              trend_direction: int) -> PullbackResult:
        """
        EMAプルバック検出 (Touch/Cross/Break)
        """
        # ターゲットEMAを選択
        if self.pullback_ema == PullbackEMAReference.EMA_12:
            target_ema = ema12
            ema_name = "EMA12"
        elif self.pullback_ema == PullbackEMAReference.EMA_100:
            target_ema = ema100
            ema_name = "EMA100"
        else:
            target_ema = ema25
            ema_name = "EMA25"
        
        # 過去N本をチェック
        for i in range(1, min(self.pullback_lookback + 1, len(closes))):
            idx = -(i + 1)
            
            bar_high = highs[idx]
            bar_low = lows[idx]
            bar_close = closes[idx]
            bar_open = opens[idx]
            ema_val = target_ema[idx]
            
            if trend_direction == 1:  # 上昇トレンド
                # Touch: 安値がEMAにタッチして終値が上
                if self.use_touch and bar_low <= ema_val and bar_close > ema_val:
                    return PullbackResult(
                        detected=True, direction=1,
                        pullback_type=PullbackType.EMA_TOUCH,
                        entry_level=bar_high,
                        reason=f"{ema_name}タッチ"
                    )
                
                # Cross: 始値がEMA下で終値がEMA上
                if self.use_cross and bar_open < ema_val and bar_close > ema_val:
                    return PullbackResult(
                        detected=True, direction=1,
                        pullback_type=PullbackType.EMA_CROSS,
                        entry_level=bar_high,
                        reason=f"{ema_name}クロス"
                    )
                
                # Break: 前足終値がEMA下、当足終値がEMA上
                if self.use_break and i >= 2:
                    prev_idx = idx - 1
                    if prev_idx >= -len(closes):
                        prev_close = closes[prev_idx]
                        if prev_close < target_ema[prev_idx] and bar_close > ema_val:
                            return PullbackResult(
                                detected=True, direction=1,
                                pullback_type=PullbackType.EMA_BREAK,
                                entry_level=bar_high,
                                reason=f"{ema_name}ブレイク"
                            )
            
            elif trend_direction == -1:  # 下降トレンド
                # Touch: 高値がEMAにタッチして終値が下
                if self.use_touch and bar_high >= ema_val and bar_close < ema_val:
                    return PullbackResult(
                        detected=True, direction=-1,
                        pullback_type=PullbackType.EMA_TOUCH,
                        entry_level=bar_low,
                        reason=f"{ema_name}タッチ"
                    )
                
                # Cross: 始値がEMA上で終値がEMA下
                if self.use_cross and bar_open > ema_val and bar_close < ema_val:
                    return PullbackResult(
                        detected=True, direction=-1,
                        pullback_type=PullbackType.EMA_CROSS,
                        entry_level=bar_low,
                        reason=f"{ema_name}クロス"
                    )
                
                # Break: 前足終値がEMA上、当足終値がEMA下
                if self.use_break and i >= 2:
                    prev_idx = idx - 1
                    if prev_idx >= -len(closes):
                        prev_close = closes[prev_idx]
                        if prev_close > target_ema[prev_idx] and bar_close < ema_val:
                            return PullbackResult(
                                detected=True, direction=-1,
                                pullback_type=PullbackType.EMA_BREAK,
                                entry_level=bar_low,
                                reason=f"{ema_name}ブレイク"
                            )
        
        return PullbackResult(
            detected=False, direction=0,
            pullback_type=PullbackType.NONE,
            entry_level=0, reason="EMAプルバックなし"
        )
    
    def _get_nearest_roundnumber(self, price: float, is_00_line: bool) -> float:
        """最寄りのラウンドナンバーを取得"""
        if self.rn_digit_level == 0:
            divisor = 1000 if is_00_line else 500
        elif self.rn_digit_level == 1:
            divisor = 100 if is_00_line else 50
        else:
            divisor = 1.0 if is_00_line else 0.5
        
        lower = np.floor(price / divisor) * divisor
        upper = lower + divisor
        
        if (price - lower) < (upper - price):
            return lower
        return upper
    
    def _detect_roundnumber_pullback(self,
                                      highs: np.ndarray,
                                      lows: np.ndarray,
                                      opens: np.ndarray,
                                      closes: np.ndarray,
                                      is_long: bool) -> PullbackResult:
        """
        ラウンドナンバープルバック検出
        反発確認必須（陽線/陰線チェック）
        """
        touch_buffer = self.rn_touch_buffer_pips * self.pip_size
        
        for i in range(1, min(self.rn_lookback_bars + 1, len(closes))):
            idx = -(i + 1)
            
            bar_high = highs[idx]
            bar_low = lows[idx]
            bar_open = opens[idx]
            bar_close = closes[idx]
            
            # .00 ライン検出
            if self.rn_use_00_line:
                rn_00 = self._get_nearest_roundnumber(bar_low if is_long else bar_high, True)
                
                if is_long:
                    # ロング: 安値が.00に近接し、陽線で反発
                    if abs(bar_low - rn_00) <= touch_buffer:
                        if bar_close > bar_open:  # 陽線
                            return PullbackResult(
                                detected=True, direction=1,
                                pullback_type=PullbackType.RN_00_BOUNCE,
                                entry_level=bar_high,
                                reason="RN.00反発(ロング)"
                            )
                else:
                    # ショート: 高値が.00に近接し、陰線で反落
                    if abs(bar_high - rn_00) <= touch_buffer:
                        if bar_close < bar_open:  # 陰線
                            return PullbackResult(
                                detected=True, direction=-1,
                                pullback_type=PullbackType.RN_00_DROP,
                                entry_level=bar_low,
                                reason="RN.00反落(ショート)"
                            )
            
            # .50 ライン検出
            if self.rn_use_50_line:
                rn_50 = self._get_nearest_roundnumber(bar_low if is_long else bar_high, False)
                
                if is_long:
                    if abs(bar_low - rn_50) <= touch_buffer:
                        if bar_close > bar_open:
                            return PullbackResult(
                                detected=True, direction=1,
                                pullback_type=PullbackType.RN_50_BOUNCE,
                                entry_level=bar_high,
                                reason="RN.50反発(ロング)"
                            )
                else:
                    if abs(bar_high - rn_50) <= touch_buffer:
                        if bar_close < bar_open:
                            return PullbackResult(
                                detected=True, direction=-1,
                                pullback_type=PullbackType.RN_50_DROP,
                                entry_level=bar_low,
                                reason="RN.50反落(ショート)"
                            )
        
        return PullbackResult(
            detected=False, direction=0,
            pullback_type=PullbackType.NONE,
            entry_level=0, reason="RNプルバックなし"
        )
    
    def _check_confirmation_bar(self,
                                 highs: np.ndarray,
                                 lows: np.ndarray,
                                 opens: np.ndarray,
                                 closes: np.ndarray,
                                 is_long: bool) -> bool:
        """確認足チェック"""
        if len(closes) < 2:
            return False
        
        bar_high = highs[-2]
        bar_low = lows[-2]
        bar_open = opens[-2]
        bar_close = closes[-2]
        
        bar_size_pips = (bar_high - bar_low) / self.pip_size
        
        if bar_size_pips < self.confirm_min_size_pips:
            return False
        if self.confirm_max_size_pips > 0 and bar_size_pips > self.confirm_max_size_pips:
            return False
        
        # 方向確認
        if is_long and bar_close <= bar_open:
            return False
        if not is_long and bar_close >= bar_open:
            return False
        
        return True
    
    def _calculate_confidence(self, result: PullbackResult) -> float:
        """確信度を計算"""
        base_confidence = 0.7
        
        # プルバックタイプによる調整
        if result.pullback_type == PullbackType.EMA_TOUCH:
            base_confidence += 0.15
        elif result.pullback_type == PullbackType.EMA_CROSS:
            base_confidence += 0.10
        elif result.pullback_type == PullbackType.EMA_BREAK:
            base_confidence += 0.05
        elif result.pullback_type in [PullbackType.RN_00_BOUNCE, PullbackType.RN_00_DROP]:
            base_confidence += 0.20  # ラウンドナンバー.00は強力
        elif result.pullback_type in [PullbackType.RN_50_BOUNCE, PullbackType.RN_50_DROP]:
            base_confidence += 0.10
        
        # パーフェクトオーダー必須の場合はボーナス
        if self.require_perfect_order:
            base_confidence += 0.05
        
        return min(1.0, base_confidence)


# ===== 強トレンドモード判定（独立関数） =====
def check_strong_trend_mode(adx: np.ndarray,
                            atr: np.ndarray,
                            volumes: np.ndarray,
                            adx_threshold: float = 30.0,
                            atr_spike_multi: float = 1.5,
                            volume_spike_multi: float = 1.5,
                            detection_period: int = 10) -> bool:
    """
    強トレンドモード判定
    
    ADXが閾値以上かつ、ATRまたはボリュームがスパイクしている場合にTrue
    """
    if len(adx) < 1 or adx[-1] < adx_threshold:
        return False
    
    if len(atr) < detection_period + 1:
        return False
    
    # ATRスパイク判定
    current_atr = atr[-1]
    avg_atr = np.mean(atr[-(detection_period + 1):-1])
    atr_spike = (current_atr >= avg_atr * atr_spike_multi)
    
    # ボリュームスパイク判定
    vol_spike = False
    if volumes is not None and len(volumes) >= detection_period + 1:
        current_vol = volumes[-1]
        avg_vol = np.mean(volumes[-(detection_period + 1):-1])
        if avg_vol > 0:
            vol_spike = (current_vol >= avg_vol * volume_spike_multi)
    
    return atr_spike or vol_spike


# ===== テストコード =====
if __name__ == "__main__":
    # サンプルデータ（上昇トレンド + EMA25タッチ）
    n = 20
    np.random.seed(42)
    
    # 上昇トレンドを模擬
    base = np.linspace(100, 110, n)
    noise = np.random.randn(n) * 0.5
    closes = base + noise
    opens = closes - np.random.rand(n) * 0.3
    highs = closes + np.abs(np.random.randn(n)) * 0.5
    lows = closes - np.abs(np.random.randn(n)) * 0.5
    
    # EMA計算（簡易）
    ema12 = np.convolve(closes, np.ones(3)/3, mode='valid')
    ema12 = np.pad(ema12, (n - len(ema12), 0), mode='edge')
    ema25 = np.convolve(closes, np.ones(5)/5, mode='valid')
    ema25 = np.pad(ema25, (n - len(ema25), 0), mode='edge')
    ema100 = np.convolve(closes, np.ones(10)/10, mode='valid')
    ema100 = np.pad(ema100, (n - len(ema100), 0), mode='edge')
    
    # プルバック条件を満たすようにデータを調整
    lows[-3] = ema25[-3] - 0.1  # EMA25をタッチ
    closes[-3] = ema25[-3] + 0.5
    
    # モジュールテスト
    module = PullbackModule(
        require_perfect_order=False,  # テスト用に緩和
        use_touch=True,
        use_cross=True,
        pip_size=0.01
    )
    
    score = module.analyze(closes, highs, lows, opens, ema12, ema25, ema100)
    
    print("=== PullbackModule テスト結果 ===")
    print(f"Signal: {score.signal}")
    print(f"Confidence: {score.confidence:.2f}")
    print(f"Reason: {score.reason}")
