"""
ボラティリティモジュール (Volatility Module)

ATRを使用したボラティリティ分析とトレンド強度判定

設計理念:
- ATR閾値チェック: FX=7.0pips、JP225=70pointを推奨
- ATRトレンド判定: ATRの上昇/下降からトレンド強度を判定
- ボラティリティレジーム: 低/中/高ボラティリティの分類

参考: EA側(MQL4)でもATR閾値チェックを行うが、
      Python側でより詳細な分析を行う
"""

import numpy as np
from typing import Optional, Tuple, List
from dataclasses import dataclass
from enum import Enum
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from signal_engine.signal_aggregator import ModuleScore


class VolatilityRegime(Enum):
    """ボラティリティレジーム"""
    LOW = "low"           # 低ボラティリティ（レンジ相場の可能性）
    NORMAL = "normal"     # 通常ボラティリティ
    HIGH = "high"         # 高ボラティリティ（トレンド発生中）
    EXTREME = "extreme"   # 極端なボラティリティ（ニュース等）


class ATRTrend(Enum):
    """ATRのトレンド方向"""
    EXPANDING = "expanding"     # 拡大中（ボラティリティ増加）
    CONTRACTING = "contracting" # 収縮中（ボラティリティ減少）
    STABLE = "stable"           # 安定


@dataclass
class VolatilityAnalysis:
    """ボラティリティ分析結果"""
    atr_current: float              # 現在のATR値
    atr_pips: float                 # pips/points単位のATR
    atr_average: float              # 過去N期間の平均ATR
    atr_ratio: float                # 現在ATR / 平均ATR
    regime: VolatilityRegime        # ボラティリティレジーム
    atr_trend: ATRTrend             # ATRのトレンド
    trend_strength: float           # トレンド強度 (0.0-1.0)
    is_above_threshold: bool        # 閾値以上か
    threshold_pips: float           # 使用した閾値
    reason: str                     # 判定理由


class VolatilityModule:
    """
    ボラティリティモジュール
    
    機能:
    1. ATR閾値チェック（FX: 7.0pips, JP225: 70points推奨）
    2. ボラティリティレジーム判定（低/中/高/極端）
    3. ATRトレンド判定（拡大/収縮/安定）
    4. トレンド強度スコア算出
    
    使用例:
        module = VolatilityModule(
            atr_period=14,
            threshold_pips=7.0,   # FXの場合
            is_index=False
        )
        score = module.analyze(closes, highs, lows, pip_value)
    """
    
    def __init__(self,
                 atr_period: int = 14,
                 threshold_pips: float = 7.0,
                 is_index: bool = False,
                 avg_lookback: int = 20,
                 trend_lookback: int = 5,
                 low_regime_ratio: float = 0.6,
                 high_regime_ratio: float = 1.5,
                 extreme_regime_ratio: float = 2.5):
        """
        Args:
            atr_period: ATR計算期間（デフォルト14）
            threshold_pips: ATR最低閾値（FX: 7.0pips, JP225: 70points）
            is_index: 株価指数かどうか（True=JP225等、False=FX）
            avg_lookback: ATR平均計算の遡り期間
            trend_lookback: ATRトレンド判定の遡り期間
            low_regime_ratio: 低ボラティリティ判定比率（ATR/平均ATR）
            high_regime_ratio: 高ボラティリティ判定比率
            extreme_regime_ratio: 極端なボラティリティ判定比率
        """
        self.atr_period = atr_period
        self.threshold_pips = threshold_pips
        self.is_index = is_index
        self.avg_lookback = avg_lookback
        self.trend_lookback = trend_lookback
        self.low_regime_ratio = low_regime_ratio
        self.high_regime_ratio = high_regime_ratio
        self.extreme_regime_ratio = extreme_regime_ratio
    
    def analyze(self,
                closes: np.ndarray,
                highs: np.ndarray,
                lows: np.ndarray,
                pip_value: float = 0.0001) -> ModuleScore:
        """
        ボラティリティ分析を実行
        
        Args:
            closes: 終値配列（最新が[-1]）
            highs: 高値配列
            lows: 安値配列
            pip_value: 1pipの価格（FX: 0.0001/0.01, JP225: 1.0）
        
        Returns:
            ModuleScore: スコア（signal, confidence, reason）
            
        Note:
            signal: 1=ボラティリティ十分（エントリー可）
                   0=ボラティリティ不足（様子見）
                  -1=極端なボラティリティ（危険）
        """
        # ATR計算
        atr_series = self._calculate_atr_series(highs, lows, closes)
        
        if len(atr_series) < self.avg_lookback:
            return ModuleScore(
                signal=0,
                confidence=0.0,
                reason="データ不足でATR計算不可"
            )
        
        # 詳細分析
        analysis = self._analyze_volatility(atr_series, pip_value)
        
        # ModuleScoreに変換
        return self._to_module_score(analysis)
    
    def analyze_detailed(self,
                         closes: np.ndarray,
                         highs: np.ndarray,
                         lows: np.ndarray,
                         pip_value: float = 0.0001) -> VolatilityAnalysis:
        """
        詳細なボラティリティ分析を実行
        
        Returns:
            VolatilityAnalysis: 詳細分析結果
        """
        atr_series = self._calculate_atr_series(highs, lows, closes)
        return self._analyze_volatility(atr_series, pip_value)
    
    def _calculate_atr_series(self,
                              highs: np.ndarray,
                              lows: np.ndarray,
                              closes: np.ndarray) -> np.ndarray:
        """
        ATR時系列を計算（Wilder's Smoothing Method）
        
        Args:
            highs: 高値配列
            lows: 安値配列
            closes: 終値配列
        
        Returns:
            ATR配列（最新が[-1]）
        """
        n = len(closes)
        if n < 2:
            return np.array([])
        
        # True Range計算
        tr = np.zeros(n)
        tr[0] = highs[0] - lows[0]
        
        for i in range(1, n):
            high_low = highs[i] - lows[i]
            high_close = abs(highs[i] - closes[i - 1])
            low_close = abs(lows[i] - closes[i - 1])
            tr[i] = max(high_low, high_close, low_close)
        
        # ATR計算（Wilder's Smoothing）
        atr = np.zeros(n)
        if n < self.atr_period:
            return np.array([])
        
        # 最初のATRは単純平均
        atr[self.atr_period - 1] = np.mean(tr[:self.atr_period])
        
        # 以降はWilder's Smoothing
        multiplier = 1.0 / self.atr_period
        for i in range(self.atr_period, n):
            atr[i] = atr[i - 1] * (1 - multiplier) + tr[i] * multiplier
        
        return atr
    
    def _analyze_volatility(self,
                            atr_series: np.ndarray,
                            pip_value: float) -> VolatilityAnalysis:
        """
        ボラティリティの詳細分析
        
        Args:
            atr_series: ATR時系列
            pip_value: 1pipの価格
        
        Returns:
            VolatilityAnalysis
        """
        # 現在のATR
        atr_current = atr_series[-1]
        atr_pips = atr_current / pip_value
        
        # 過去N期間の平均ATR
        lookback_start = max(0, len(atr_series) - self.avg_lookback - 1)
        atr_average = np.mean(atr_series[lookback_start:-1])
        
        # ATR比率（現在ATR / 平均ATR）
        atr_ratio = atr_current / atr_average if atr_average > 0 else 1.0
        
        # ボラティリティレジーム判定
        regime = self._determine_regime(atr_ratio)
        
        # ATRトレンド判定
        atr_trend = self._determine_atr_trend(atr_series)
        
        # トレンド強度計算
        trend_strength = self._calculate_trend_strength(atr_ratio, atr_trend, regime)
        
        # 閾値チェック
        is_above_threshold = atr_pips >= self.threshold_pips
        
        # 理由文生成
        reason = self._generate_reason(
            atr_pips, regime, atr_trend, is_above_threshold, atr_ratio
        )
        
        return VolatilityAnalysis(
            atr_current=atr_current,
            atr_pips=atr_pips,
            atr_average=atr_average,
            atr_ratio=atr_ratio,
            regime=regime,
            atr_trend=atr_trend,
            trend_strength=trend_strength,
            is_above_threshold=is_above_threshold,
            threshold_pips=self.threshold_pips,
            reason=reason
        )
    
    def _determine_regime(self, atr_ratio: float) -> VolatilityRegime:
        """
        ボラティリティレジームを判定
        
        Args:
            atr_ratio: 現在ATR / 平均ATR
        
        Returns:
            VolatilityRegime
        """
        if atr_ratio >= self.extreme_regime_ratio:
            return VolatilityRegime.EXTREME
        elif atr_ratio >= self.high_regime_ratio:
            return VolatilityRegime.HIGH
        elif atr_ratio <= self.low_regime_ratio:
            return VolatilityRegime.LOW
        else:
            return VolatilityRegime.NORMAL
    
    def _determine_atr_trend(self, atr_series: np.ndarray) -> ATRTrend:
        """
        ATRのトレンド方向を判定
        
        Args:
            atr_series: ATR時系列
        
        Returns:
            ATRTrend
        """
        if len(atr_series) < self.trend_lookback + 1:
            return ATRTrend.STABLE
        
        # 過去N期間のATR変化を分析
        recent_atr = atr_series[-self.trend_lookback:]
        
        # 線形回帰で傾きを計算
        x = np.arange(len(recent_atr))
        slope = np.polyfit(x, recent_atr, 1)[0]
        
        # 傾きを平均ATRで正規化
        avg_atr = np.mean(recent_atr)
        normalized_slope = slope / avg_atr if avg_atr > 0 else 0
        
        # 閾値で判定（±1%/バーを基準）
        if normalized_slope > 0.01:
            return ATRTrend.EXPANDING
        elif normalized_slope < -0.01:
            return ATRTrend.CONTRACTING
        else:
            return ATRTrend.STABLE
    
    def _calculate_trend_strength(self,
                                   atr_ratio: float,
                                   atr_trend: ATRTrend,
                                   regime: VolatilityRegime) -> float:
        """
        トレンド強度を計算（0.0-1.0）
        
        高ボラティリティ + ATR拡大 = 高強度トレンド
        低ボラティリティ + ATR収縮 = 弱いトレンド/レンジ
        
        Args:
            atr_ratio: 現在ATR / 平均ATR
            atr_trend: ATRトレンド
            regime: ボラティリティレジーム
        
        Returns:
            0.0-1.0の強度スコア
        """
        # 基本スコア（ATR比率から）
        # 1.0 = 平均、1.5 = 高、2.0以上 = 非常に高い
        base_score = min((atr_ratio - 0.5) / 1.5, 1.0) if atr_ratio > 0.5 else 0.0
        
        # ATRトレンドによる調整
        trend_adjustment = 0.0
        if atr_trend == ATRTrend.EXPANDING:
            trend_adjustment = 0.15  # 拡大中は+15%
        elif atr_trend == ATRTrend.CONTRACTING:
            trend_adjustment = -0.10  # 収縮中は-10%
        
        # レジームによる調整
        regime_adjustment = 0.0
        if regime == VolatilityRegime.HIGH:
            regime_adjustment = 0.10
        elif regime == VolatilityRegime.EXTREME:
            regime_adjustment = 0.05  # 極端すぎるのはリスク
        elif regime == VolatilityRegime.LOW:
            regime_adjustment = -0.15
        
        # 最終スコア
        final_score = base_score + trend_adjustment + regime_adjustment
        return max(0.0, min(1.0, final_score))
    
    def _generate_reason(self,
                         atr_pips: float,
                         regime: VolatilityRegime,
                         atr_trend: ATRTrend,
                         is_above_threshold: bool,
                         atr_ratio: float) -> str:
        """
        判定理由文を生成
        """
        unit = "points" if self.is_index else "pips"
        
        # レジーム日本語化
        regime_names = {
            VolatilityRegime.LOW: "低ボラティリティ",
            VolatilityRegime.NORMAL: "通常ボラティリティ",
            VolatilityRegime.HIGH: "高ボラティリティ",
            VolatilityRegime.EXTREME: "極端なボラティリティ"
        }
        
        # ATRトレンド日本語化
        trend_names = {
            ATRTrend.EXPANDING: "拡大中",
            ATRTrend.CONTRACTING: "収縮中",
            ATRTrend.STABLE: "安定"
        }
        
        # 閾値判定
        threshold_status = "十分" if is_above_threshold else "不足"
        
        reason = (
            f"ATR: {atr_pips:.1f}{unit} "
            f"({regime_names[regime]}, {trend_names[atr_trend]}, "
            f"閾値{self.threshold_pips:.1f}{unit}{threshold_status}, "
            f"対平均{atr_ratio:.2f}倍)"
        )
        
        return reason
    
    def _to_module_score(self, analysis: VolatilityAnalysis) -> ModuleScore:
        """
        VolatilityAnalysisをModuleScoreに変換
        
        シグナル判定:
        - 1: ボラティリティ十分かつ良好なトレンド環境
        - 0: ボラティリティ不足または不明確
        - -1: 極端なボラティリティ（危険）
        """
        # 極端なボラティリティは警告シグナル
        if analysis.regime == VolatilityRegime.EXTREME:
            return ModuleScore(
                signal=-1,  # 危険サイン
                confidence=0.8,
                reason=analysis.reason + " (警告: 急激な変動リスク)"
            )
        
        # 閾値未達は様子見
        if not analysis.is_above_threshold:
            return ModuleScore(
                signal=0,  # 様子見
                confidence=0.3,
                reason=analysis.reason + " (ボラティリティ不足)"
            )
        
        # 低ボラティリティは様子見（レンジ相場の可能性）
        if analysis.regime == VolatilityRegime.LOW:
            return ModuleScore(
                signal=0,
                confidence=0.4,
                reason=analysis.reason + " (レンジ相場の可能性)"
            )
        
        # 高ボラティリティ + ATR拡大 = 強いトレンド環境
        if (analysis.regime == VolatilityRegime.HIGH and 
            analysis.atr_trend == ATRTrend.EXPANDING):
            return ModuleScore(
                signal=1,  # 良好
                confidence=analysis.trend_strength,
                reason=analysis.reason + " (強いトレンド環境)"
            )
        
        # 通常ボラティリティ
        if analysis.regime == VolatilityRegime.NORMAL:
            # ATR拡大中なら良好
            if analysis.atr_trend == ATRTrend.EXPANDING:
                return ModuleScore(
                    signal=1,
                    confidence=analysis.trend_strength,
                    reason=analysis.reason + " (ボラティリティ拡大中)"
                )
            # 安定なら普通
            elif analysis.atr_trend == ATRTrend.STABLE:
                return ModuleScore(
                    signal=1,
                    confidence=max(0.5, analysis.trend_strength),
                    reason=analysis.reason + " (安定したトレード環境)"
                )
            # 収縮中は注意
            else:
                return ModuleScore(
                    signal=0,
                    confidence=0.4,
                    reason=analysis.reason + " (ボラティリティ収縮中、様子見)"
                )
        
        # 高ボラティリティだがATR安定/収縮
        return ModuleScore(
            signal=1,
            confidence=max(0.5, analysis.trend_strength),
            reason=analysis.reason
        )
    
    def get_atr_pips(self,
                     closes: np.ndarray,
                     highs: np.ndarray,
                     lows: np.ndarray,
                     pip_value: float = 0.0001) -> float:
        """
        現在のATRをpips単位で取得（簡易メソッド）
        
        Args:
            closes: 終値配列
            highs: 高値配列
            lows: 安値配列
            pip_value: 1pipの価格
        
        Returns:
            ATR（pips単位）
        """
        atr_series = self._calculate_atr_series(highs, lows, closes)
        if len(atr_series) == 0:
            return 0.0
        return atr_series[-1] / pip_value
    
    def is_volatility_sufficient(self,
                                  closes: np.ndarray,
                                  highs: np.ndarray,
                                  lows: np.ndarray,
                                  pip_value: float = 0.0001) -> Tuple[bool, str]:
        """
        ボラティリティが十分かチェック（簡易メソッド）
        
        Returns:
            (is_sufficient: bool, reason: str)
        """
        atr_pips = self.get_atr_pips(closes, highs, lows, pip_value)
        unit = "points" if self.is_index else "pips"
        
        if atr_pips >= self.threshold_pips:
            return True, f"ATR {atr_pips:.1f}{unit} >= 閾値{self.threshold_pips:.1f}{unit}"
        else:
            return False, f"ATR {atr_pips:.1f}{unit} < 閾値{self.threshold_pips:.1f}{unit}"


# ===== テストコード =====
if __name__ == "__main__":
    # サンプルデータ（上昇トレンド + ボラティリティ増加）
    np.random.seed(42)
    n = 100
    
    # 価格生成（上昇トレンド + ランダムノイズ）
    base_price = 150.0
    trend = np.linspace(0, 5, n)  # 上昇トレンド
    noise = np.random.randn(n) * 0.5
    closes = base_price + trend + noise
    
    # 高値・安値（ボラティリティ徐々に増加）
    volatility = np.linspace(0.3, 1.0, n)  # 後半ほどボラティリティ大
    highs = closes + volatility * np.abs(np.random.randn(n))
    lows = closes - volatility * np.abs(np.random.randn(n))
    
    # FX設定でテスト（pip_value=0.01 for USDJPY）
    print("=== FX (USDJPY) テスト ===")
    module_fx = VolatilityModule(
        atr_period=14,
        threshold_pips=7.0,  # FX推奨値
        is_index=False
    )
    
    score_fx = module_fx.analyze(closes, highs, lows, pip_value=0.01)
    print(f"Signal: {score_fx.signal}")
    print(f"Confidence: {score_fx.confidence:.2f}")
    print(f"Reason: {score_fx.reason}")
    
    # 詳細分析
    analysis_fx = module_fx.analyze_detailed(closes, highs, lows, pip_value=0.01)
    print(f"\n詳細分析:")
    print(f"  ATR: {analysis_fx.atr_pips:.2f} pips")
    print(f"  レジーム: {analysis_fx.regime.value}")
    print(f"  ATRトレンド: {analysis_fx.atr_trend.value}")
    print(f"  トレンド強度: {analysis_fx.trend_strength:.2f}")
    print(f"  閾値クリア: {analysis_fx.is_above_threshold}")
    
    # JP225設定でテスト
    print("\n=== JP225 テスト ===")
    # JP225用にスケール調整
    closes_jp = closes * 250  # 約37500円レベル
    highs_jp = highs * 250
    lows_jp = lows * 250
    
    module_jp = VolatilityModule(
        atr_period=14,
        threshold_pips=70.0,  # JP225推奨値
        is_index=True
    )
    
    score_jp = module_jp.analyze(closes_jp, highs_jp, lows_jp, pip_value=1.0)
    print(f"Signal: {score_jp.signal}")
    print(f"Confidence: {score_jp.confidence:.2f}")
    print(f"Reason: {score_jp.reason}")
