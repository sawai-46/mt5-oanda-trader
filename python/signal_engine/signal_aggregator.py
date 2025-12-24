"""
シグナル統合エンジン

7モジュールからの信号を重み付けして統合
- candle_patterns: 15% (ピンバー、包み足等)
- false_breakout: 20% (ダマシ検出)
- chart_patterns: 25% (三尊、Wトップ等)
- technical: 15% (MACD、RSI等)
- trend: 10% (トレンド判定)
- wave_structure: 10% (ツーレッグ)
- structural: 5% (ピボット等)
"""

import numpy as np
from typing import Dict, List, Optional
from dataclasses import dataclass
from enum import Enum


class SignalType(Enum):
    """シグナルタイプ"""
    BUY = 1
    SELL = -1
    NEUTRAL = 0


@dataclass
class ModuleScore:
    """各モジュールのスコア"""
    signal: int  # 1=買い, -1=売り, 0=中立
    confidence: float  # 0.0-1.0
    reason: str
    
    
@dataclass
class AggregatedSignal:
    """統合シグナル"""
    signal: SignalType
    confidence: float  # 0.0-1.0
    reasons: List[str]
    breakdown: Dict[str, ModuleScore]
    weighted_score: float  # -1.0 ~ 1.0


class SignalAggregator:
    """
    7モジュールシグナル統合クラス
    
    設計書v2.2（アルゴリズム重視版）の重み付け体系:
    - technical (25%): モメンタム・RSI・MACD（アルゴリズム最重要）
    - trend (20%): トレンド方向性・EMA構造（アルゴリズム）
    - wave_structure (15%): ツーレッグ構造・波動分析（アルゴリズム）
    - chart_patterns (15%): 構造的転換点
    - false_breakout (15%): ダマシ検出
    - candle_patterns (5%): ローソク足パターン（主観的要素あり）
    - structural (5%): ゾーン確認
    """
    
    def __init__(self):
        # アルゴリズム重視の重み設定 (v2.2)
        self.weights = {
            'technical': 0.25,          # テクニカル指標（アルゴリズム最重要）
            'trend': 0.20,              # トレンド分析（アルゴリズム）
            'wave_structure': 0.15,     # 波動構造（アルゴリズム）
            'chart_patterns': 0.15,     # チャートパターン
            'false_breakout': 0.15,     # ダマシ検出
            'candle_patterns': 0.05,    # ローソク足（主観的）
            'structural': 0.05          # サポレジゾーン
        }
        
        # 閾値設定
        self.entry_threshold = 0.3  # エントリー閾値（weighted_score）
        self.high_confidence_threshold = 0.6  # 高確信度閾値
    
    def aggregate(self, module_scores: Dict[str, ModuleScore]) -> AggregatedSignal:
        """
        7モジュールのスコアを統合
        
        Args:
            module_scores: {
                'candle_patterns': ModuleScore(...),
                'false_breakout': ModuleScore(...),
                ...
            }
        
        Returns:
            AggregatedSignal: 統合シグナル
        """
        # 加重平均スコア計算
        weighted_sum = 0.0
        total_weight = 0.0
        reasons = []
        
        def get_signal_value(sig):
            """SignalTypeまたはintからint値を取得"""
            if hasattr(sig, 'value'):
                return sig.value
            return int(sig) if sig else 0
        
        for module_name, weight in self.weights.items():
            if module_name in module_scores:
                score = module_scores[module_name]
                signal_val = get_signal_value(score.signal)
                contribution = signal_val * score.confidence * weight
                weighted_sum += contribution
                total_weight += weight
                
                # 理由を収集（confidence > 0.3のみ）
                if score.confidence > 0.3:
                    direction = "買い" if signal_val > 0 else "売り" if signal_val < 0 else "中立"
                    reasons.append(f"[{module_name}] {direction} {score.confidence:.2f}: {score.reason}")
        
        # 正規化（-1.0 ~ 1.0）
        weighted_score = weighted_sum / total_weight if total_weight > 0 else 0.0
        
        # シグナル判定
        signal_type = SignalType.NEUTRAL
        confidence = abs(weighted_score)
        
        if weighted_score >= self.entry_threshold:
            signal_type = SignalType.BUY
        elif weighted_score <= -self.entry_threshold:
            signal_type = SignalType.SELL
        
        return AggregatedSignal(
            signal=signal_type,
            confidence=confidence,
            reasons=reasons,
            breakdown=module_scores,
            weighted_score=weighted_score
        )
    
    def explain_signal(self, aggregated: AggregatedSignal) -> str:
        """
        シグナルの詳細説明
        
        Args:
            aggregated: 統合シグナル
        
        Returns:
            str: 説明テキスト
        """
        lines = []
        lines.append(f"=== シグナル統合結果 ===")
        lines.append(f"最終シグナル: {aggregated.signal.name}")
        lines.append(f"確信度: {aggregated.confidence:.2%}")
        lines.append(f"加重スコア: {aggregated.weighted_score:.3f}")
        lines.append("")
        lines.append("【モジュール別内訳】")
        
        # 重みの大きい順にソート
        sorted_modules = sorted(
            aggregated.breakdown.items(),
            key=lambda x: self.weights.get(x[0], 0),
            reverse=True
        )
        
        for module_name, score in sorted_modules:
            weight = self.weights.get(module_name, 0)
            signal_val = score.signal.value if hasattr(score.signal, 'value') else int(score.signal or 0)
            contribution = signal_val * score.confidence * weight
            lines.append(
                f"  {module_name:18s} (重み {weight:.0%}): "
                f"信号={signal_val:+2d}, 確信度={score.confidence:.2f}, "
                f"貢献度={contribution:+.3f}"
            )
        
        lines.append("")
        lines.append("【判断根拠】")
        for reason in aggregated.reasons:
            lines.append(f"  - {reason}")
        
        return "\n".join(lines)


# ===== サンプルコード =====
if __name__ == "__main__":
    # テストデータ
    test_scores = {
        'candle_patterns': ModuleScore(signal=1, confidence=0.7, reason="強気ピンバー検出"),
        'false_breakout': ModuleScore(signal=1, confidence=0.9, reason="上抜け失敗→強い反転"),
        'chart_patterns': ModuleScore(signal=1, confidence=0.8, reason="逆三尊形成"),
        'technical': ModuleScore(signal=1, confidence=0.6, reason="MACDゴールデンクロス"),
        'trend': ModuleScore(signal=1, confidence=1.0, reason="パーフェクトオーダー上昇"),
        'wave_structure': ModuleScore(signal=0, confidence=0.0, reason="ツーレッグ未検出"),
        'structural': ModuleScore(signal=1, confidence=0.5, reason="ピボットサポート付近")
    }
    
    aggregator = SignalAggregator()
    result = aggregator.aggregate(test_scores)
    
    print(aggregator.explain_signal(result))
    print(f"\n>>> エントリー判定: {result.signal.name} (確信度 {result.confidence:.2%})")
