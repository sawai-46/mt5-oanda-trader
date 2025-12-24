"""
拡張シグナルアグリゲーター

7モジュール + PullbackModule + Antigravityを統合
将来の戦略構築に対応した拡張版
"""

import numpy as np
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field
from enum import Enum
import sys
from pathlib import Path

# パス設定
sys.path.insert(0, str(Path(__file__).parent.parent))

# 既存のsignal_aggregatorをインポート
from signal_engine.signal_aggregator import (
    SignalType, ModuleScore, AggregatedSignal, SignalAggregator
)


@dataclass
class ExtendedModuleScore(ModuleScore):
    """拡張モジュールスコア（メタデータ付き）"""
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass  
class StrategyResult:
    """戦略実行結果"""
    signal: SignalType
    confidence: float
    weighted_score: float
    reasons: List[str]
    module_breakdown: Dict[str, ModuleScore]
    strategy_name: str
    filters_passed: Dict[str, bool]


class ModuleCategory(Enum):
    """モジュールカテゴリ"""
    CORE = "core"               # 既存7モジュール
    PULLBACK = "pullback"       # プルバックモジュール
    ANTIGRAVITY = "antigravity" # Antigravity高度分析
    FILTER = "filter"           # フィルター（VPIN等）


class ExtendedSignalAggregator(SignalAggregator):
    """
    Antigravity中心シグナルアグリゲーター v3.0
    
    アーキテクチャ:
    ┌─────────────────────────────────────────────────────────┐
    │                  Antigravity Core (60%)                  │
    │  Transformer (25%) + KAN (20%) + GARCH/VPIN (15%)       │
    │  → 機械学習ベースのシグナル生成（メイン）               │
    └─────────────────────────────────────────────────────────┘
                           ↓
    ┌─────────────────────────────────────────────────────────┐
    │              Sub-Modules Filter (40%)                    │
    │  Technical (15%) + Trend (10%) + Pullback (10%)         │
    │  + Others (5%)                                          │
    │  → ルールベースのフィルター/確認（サブ）                │
    └─────────────────────────────────────────────────────────┘
    
    戦略パターン:
    - antigravity: Antigravity主導（デフォルト）
    - hybrid: Antigravity + ルールベース均等
    - legacy: 従来の7モジュール主導（後方互換）
    """
    
    # Antigravity中心の重み設定（デフォルト）
    DEFAULT_WEIGHTS = {
        # ===== Antigravity Core (60%) =====
        'antigravity_transformer': 0.25,  # Transformer時系列予測
        'antigravity_kan': 0.20,          # KAN非線形予測
        'gk_volatility': 0.10,            # Garman-Klassボラティリティ
        'vpin': 0.05,                     # VPIN流動性リスク
        
        # ===== Sub-Modules Filter (40%) =====
        'technical': 0.15,                # RSI/MACD（アルゴリズム）
        'trend': 0.10,                    # EMA構造（アルゴリズム）
        'pullback': 0.10,                 # プルバック検出
        'chart_patterns': 0.02,           # チャートパターン
        'false_breakout': 0.02,           # ダマシ検出
        'candle_patterns': 0.01,          # ローソク足
        'wave_structure': 0.00,           # 波動構造（無効化）
        'structural': 0.00,               # サポレジ（無効化）
    }
    
    # 戦略別重み設定
    STRATEGY_WEIGHTS = {
        # Antigravity主導（推奨）
        'antigravity': {
            'antigravity_transformer': 0.25,
            'antigravity_kan': 0.20,
            'gk_volatility': 0.10,
            'vpin': 0.05,
            'technical': 0.15,
            'trend': 0.10,
            'pullback': 0.10,
            'chart_patterns': 0.02,
            'false_breakout': 0.02,
            'candle_patterns': 0.01,
        },
        # ハイブリッド（均等配分）
        'hybrid': {
            'antigravity_transformer': 0.15,
            'antigravity_kan': 0.15,
            'gk_volatility': 0.05,
            'vpin': 0.05,
            'technical': 0.15,
            'trend': 0.15,
            'pullback': 0.15,
            'chart_patterns': 0.05,
            'false_breakout': 0.05,
            'candle_patterns': 0.05,
        },
        # レガシー（従来の7モジュール主導）
        'legacy': {
            'chart_patterns': 0.20,
            'false_breakout': 0.15,
            'technical': 0.15,
            'trend': 0.15,
            'pullback': 0.15,
            'candle_patterns': 0.10,
            'wave_structure': 0.05,
            'structural': 0.05,
        },
        'full': DEFAULT_WEIGHTS,
    }
    
    def __init__(self, strategy: str = 'full'):
        """
        Args:
            strategy: 戦略名 ('conservative', 'momentum', 'contrarian', 'full')
        """
        super().__init__()
        self.strategy = strategy
        self.weights = self.STRATEGY_WEIGHTS.get(strategy, self.DEFAULT_WEIGHTS).copy()
        
        # フィルターモジュール（シグナルではなくフィルターとして機能）
        self.filter_modules = {'vpin'}
        
        # 閾値設定
        self.entry_threshold = 0.25
        self.high_confidence_threshold = 0.5
        self.vpin_danger_threshold = 0.7  # 高VPIN時はエントリー控えめ
    
    def set_strategy(self, strategy: str):
        """戦略を変更"""
        if strategy in self.STRATEGY_WEIGHTS:
            self.strategy = strategy
            self.weights = self.STRATEGY_WEIGHTS[strategy].copy()
        else:
            raise ValueError(f"Unknown strategy: {strategy}")
    
    def set_custom_weights(self, weights: Dict[str, float]):
        """カスタム重みを設定"""
        self.weights = weights.copy()
    
    def aggregate_extended(self, 
                           module_scores: Dict[str, ModuleScore],
                           filters: Optional[Dict[str, float]] = None) -> StrategyResult:
        """
        拡張統合処理
        
        Args:
            module_scores: 各モジュールのスコア
            filters: フィルター値（例: {'vpin': 0.65}）
        
        Returns:
            StrategyResult: 戦略実行結果
        """
        filters = filters or {}
        
        # フィルターチェック
        filters_passed = {}
        
        # VPINフィルター（高いと危険）
        if 'vpin' in filters:
            vpin_value = filters['vpin']
            filters_passed['vpin'] = vpin_value < self.vpin_danger_threshold
            if not filters_passed['vpin']:
                # 高VPINの場合、確信度を下げる
                pass
        
        # 加重スコア計算
        weighted_sum = 0.0
        total_weight = 0.0
        reasons = []
        
        for module_name, weight in self.weights.items():
            if module_name in module_scores:
                score = module_scores[module_name]
                signal_val = self._get_signal_value(score.signal)
                contribution = signal_val * score.confidence * weight
                weighted_sum += contribution
                total_weight += weight
                
                if score.confidence > 0.3:
                    direction = "買い" if signal_val > 0 else "売り" if signal_val < 0 else "中立"
                    reasons.append(f"[{module_name}] {direction} {score.confidence:.2f}: {score.reason}")
        
        # 正規化
        weighted_score = weighted_sum / total_weight if total_weight > 0 else 0.0
        
        # VPINフィルター適用（高VPINで確信度ダウン）
        if 'vpin' in filters and filters['vpin'] >= self.vpin_danger_threshold:
            weighted_score *= 0.5
            reasons.append(f"[VPIN警告] 高毒性フロー検出 ({filters['vpin']:.2f})")
        
        # シグナル判定
        signal_type = SignalType.NEUTRAL
        confidence = min(1.0, abs(weighted_score))
        
        if weighted_score >= self.entry_threshold:
            signal_type = SignalType.BUY
        elif weighted_score <= -self.entry_threshold:
            signal_type = SignalType.SELL
        
        return StrategyResult(
            signal=signal_type,
            confidence=confidence,
            weighted_score=weighted_score,
            reasons=reasons,
            module_breakdown=module_scores,
            strategy_name=self.strategy,
            filters_passed=filters_passed
        )
    
    def _get_signal_value(self, sig) -> int:
        """SignalTypeまたはintからint値を取得"""
        if hasattr(sig, 'value'):
            return sig.value
        return int(sig) if sig else 0
    
    def explain_extended(self, result: StrategyResult) -> str:
        """拡張結果の説明"""
        lines = []
        lines.append(f"=== 戦略実行結果 [{result.strategy_name.upper()}] ===")
        lines.append(f"最終シグナル: {result.signal.name}")
        lines.append(f"確信度: {result.confidence:.2%}")
        lines.append(f"加重スコア: {result.weighted_score:.3f}")
        lines.append("")
        
        # フィルター状態
        if result.filters_passed:
            lines.append("【フィルター状態】")
            for name, passed in result.filters_passed.items():
                status = "✓ PASS" if passed else "✗ WARN"
                lines.append(f"  {name}: {status}")
            lines.append("")
        
        # モジュール別内訳
        lines.append("【モジュール別内訳】")
        sorted_modules = sorted(
            result.module_breakdown.items(),
            key=lambda x: self.weights.get(x[0], 0),
            reverse=True
        )
        
        for module_name, score in sorted_modules:
            weight = self.weights.get(module_name, 0)
            signal_val = self._get_signal_value(score.signal)
            contribution = signal_val * score.confidence * weight
            lines.append(
                f"  {module_name:18s} (重み {weight:.0%}): "
                f"信号={signal_val:+2d}, 確信度={score.confidence:.2f}, "
                f"貢献度={contribution:+.3f}"
            )
        
        lines.append("")
        lines.append("【判断根拠】")
        for reason in result.reasons:
            lines.append(f"  - {reason}")
        
        return "\n".join(lines)


class AntigravityAdapter:
    """
    Antigravityモジュールを7モジュール形式に変換するアダプター
    """
    
    @staticmethod
    def adapt_vpin(vpin_value: float) -> ModuleScore:
        """
        VPIN値をModuleScoreに変換
        
        高VPIN = 毒性フロー = 逆選択リスク高 = 様子見推奨
        """
        if vpin_value >= 0.8:
            return ModuleScore(
                signal=0,
                confidence=0.9,
                reason=f"極高VPIN({vpin_value:.2f}): エントリー非推奨"
            )
        elif vpin_value >= 0.6:
            return ModuleScore(
                signal=0,
                confidence=0.5,
                reason=f"高VPIN({vpin_value:.2f}): 注意"
            )
        else:
            return ModuleScore(
                signal=0,
                confidence=0.0,
                reason=f"VPIN正常({vpin_value:.2f})"
            )
    
    @staticmethod
    def adapt_gk_volatility(gk_vol: float, 
                            threshold_low: float = 0.005,
                            threshold_high: float = 0.02) -> ModuleScore:
        """
        Garman-Klassボラティリティをシグナルに変換
        
        低ボラ: レンジ相場（様子見）
        高ボラ: 動きあり（トレンドフォロー有利）
        """
        if gk_vol < threshold_low:
            return ModuleScore(
                signal=0,
                confidence=0.6,
                reason=f"低ボラティリティ({gk_vol:.4f}): レンジ警戒"
            )
        elif gk_vol > threshold_high:
            return ModuleScore(
                signal=0,  # 方向性は他モジュールに任せる
                confidence=0.7,
                reason=f"高ボラティリティ({gk_vol:.4f}): トレンド有利"
            )
        else:
            return ModuleScore(
                signal=0,
                confidence=0.3,
                reason=f"通常ボラティリティ({gk_vol:.4f})"
            )
    
    @staticmethod
    def adapt_vwap_gap(vwap_gap: float,
                       threshold: float = 0.005) -> ModuleScore:
        """
        VWAP乖離率をシグナルに変換
        
        正の乖離: 買われすぎ傾向
        負の乖離: 売られすぎ傾向
        """
        if abs(vwap_gap) < threshold:
            return ModuleScore(
                signal=0,
                confidence=0.2,
                reason=f"VWAP乖離小({vwap_gap:+.4f})"
            )
        elif vwap_gap > threshold:
            return ModuleScore(
                signal=-1,  # 買われすぎ→売り有利
                confidence=min(0.8, abs(vwap_gap) * 50),
                reason=f"VWAP上方乖離({vwap_gap:+.4f}): 売り優勢"
            )
        else:
            return ModuleScore(
                signal=1,  # 売られすぎ→買い有利
                confidence=min(0.8, abs(vwap_gap) * 50),
                reason=f"VWAP下方乖離({vwap_gap:+.4f}): 買い優勢"
            )
    
    @staticmethod
    def adapt_sentiment(sentiment_score: float) -> ModuleScore:
        """
        センチメントスコア (-1.0 ~ 1.0) をシグナルに変換
        """
        if abs(sentiment_score) < 0.3:
            return ModuleScore(
                signal=0,
                confidence=0.2,
                reason=f"センチメント中立({sentiment_score:+.2f})"
            )
        elif sentiment_score >= 0.3:
            return ModuleScore(
                signal=1,
                confidence=abs(sentiment_score),
                reason=f"ポジティブセンチメント({sentiment_score:+.2f})"
            )
        else:
            return ModuleScore(
                signal=-1,
                confidence=abs(sentiment_score),
                reason=f"ネガティブセンチメント({sentiment_score:+.2f})"
            )

    @staticmethod
    def adapt_garch(garch_signal: int, prediction_premium: float = 0.0) -> ModuleScore:
        """
        GARCHボラティリティシグナルをModuleScoreに変換
        
        garch_signal:
        - +1: High Vol Premium（予測ボラ > 実現ボラ）→ 逆張り有利
        - -1: Low Vol Premium（予測ボラ < 実現ボラ）→ 順張り有利
        - 0: Neutral
        """
        if garch_signal == 1:
            return ModuleScore(
                signal=-1,  # 高ボラ予測 → 逆張り（売り優勢）
                confidence=min(0.8, 0.5 + abs(prediction_premium) * 0.3),
                reason=f"GARCH高ボラ予測(+1): 逆張り有利, Premium={prediction_premium:.3f}"
            )
        elif garch_signal == -1:
            return ModuleScore(
                signal=1,  # 低ボラ予測 → 順張り（トレンドフォロー）
                confidence=min(0.8, 0.5 + abs(prediction_premium) * 0.3),
                reason=f"GARCH低ボラ予測(-1): 順張り有利, Premium={prediction_premium:.3f}"
            )
        else:
            return ModuleScore(
                signal=0,
                confidence=0.3,
                reason="GARCH中立(0)"
            )


# ===== テストコード =====
if __name__ == "__main__":
    # テストデータ
    test_scores = {
        # 既存7モジュール
        'candle_patterns': ModuleScore(signal=1, confidence=0.7, reason="強気ピンバー"),
        'false_breakout': ModuleScore(signal=1, confidence=0.8, reason="上抜け失敗"),
        'chart_patterns': ModuleScore(signal=1, confidence=0.6, reason="逆三尊"),
        'technical': ModuleScore(signal=1, confidence=0.5, reason="MACDゴールデンクロス"),
        'trend': ModuleScore(signal=1, confidence=1.0, reason="パーフェクトオーダー"),
        'wave_structure': ModuleScore(signal=0, confidence=0.0, reason="未検出"),
        'structural': ModuleScore(signal=1, confidence=0.4, reason="ピボットサポート"),
        
        # Pullbackモジュール
        'pullback': ModuleScore(signal=1, confidence=0.85, reason="EMA25タッチ"),
        
        # Antigravityモジュール
        'vpin': AntigravityAdapter.adapt_vpin(0.45),
        'gk_volatility': AntigravityAdapter.adapt_gk_volatility(0.012),
        'vwap_gap': AntigravityAdapter.adapt_vwap_gap(-0.008),
        'sentiment': AntigravityAdapter.adapt_sentiment(0.4),
    }
    
    # 各戦略でテスト
    for strategy in ['conservative', 'momentum', 'full']:
        print(f"\n{'='*60}")
        aggregator = ExtendedSignalAggregator(strategy=strategy)
        result = aggregator.aggregate_extended(test_scores, filters={'vpin': 0.45})
        print(aggregator.explain_extended(result))
        print(f"\n>>> エントリー判定: {result.signal.name} (確信度 {result.confidence:.2%})")
