"""
モメンタムモジュール (Momentum Module)

シンプルな価格モメンタム戦略
学術研究（Jegadeesh & Titman, 1993等）で実証済み

理論:
- 上昇している資産は上昇し続ける傾向がある
- 単純な過去リターンが将来リターンを予測

数式:
    momentum_n = (close_t - close_{t-n}) / close_{t-n}
"""

from dataclasses import dataclass
from typing import Optional
import numpy as np
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from signal_engine.signal_aggregator import ModuleScore


@dataclass
class MomentumResult:
    """モメンタム分析結果"""
    momentum_short: float   # 短期モメンタム
    momentum_medium: float  # 中期モメンタム
    momentum_long: float    # 長期モメンタム
    signal: int             # 1=ロング, -1=ショート, 0=中立
    strength: float         # 0.0-1.0
    votes: int              # 期間合意数（-3〜+3）


class MomentumModule:
    """
    モメンタム戦略モジュール
    
    3つの期間でモメンタムを計算し、合意に基づいてシグナルを生成。
    
    パラメータ:
    - short_period: 短期期間（デフォルト5バー）
    - medium_period: 中期期間（デフォルト20バー）
    - long_period: 長期期間（デフォルト60バー）
    - threshold: シグナル発生閾値（デフォルト0.5%）
    
    使用例:
        module = MomentumModule(short_period=5, threshold=0.005)
        score = module.analyze(closes)
    """
    
    def __init__(self,
                 short_period: int = 5,
                 medium_period: int = 20,
                 long_period: int = 60,
                 threshold: float = 0.005,  # 0.5%
                 min_confidence: float = 0.3):
        """
        Args:
            short_period: 短期モメンタム期間
            medium_period: 中期モメンタム期間
            long_period: 長期モメンタム期間
            threshold: シグナル発生閾値（リターン率）
            min_confidence: 最小信頼度
        """
        self.short_period = short_period
        self.medium_period = medium_period
        self.long_period = long_period
        self.threshold = threshold
        self.min_confidence = min_confidence
    
    def analyze(self, closes: np.ndarray) -> ModuleScore:
        """
        モメンタム分析を実行
        
        Args:
            closes: 終値配列（古い→新しい順）
        
        Returns:
            ModuleScore: signal, confidence, reason
        """
        result = self.analyze_detailed(closes)
        
        # ModuleScoreに変換
        if result.signal == 0:
            return ModuleScore(
                signal=0,
                confidence=0.0,
                reason="モメンタム中立"
            )
        
        direction = "上昇" if result.signal > 0 else "下降"
        reason = (f"モメンタム{direction} "
                  f"(短期={result.momentum_short:.2%}, "
                  f"中期={result.momentum_medium:.2%}, "
                  f"合意={result.votes}/3)")
        
        return ModuleScore(
            signal=result.signal,
            confidence=result.strength,
            reason=reason
        )
    
    def analyze_detailed(self, closes: np.ndarray) -> MomentumResult:
        """
        詳細なモメンタム分析
        
        Returns:
            MomentumResult: 詳細分析結果
        """
        # データ不足チェック
        min_required = max(self.short_period, self.medium_period, self.long_period)
        if len(closes) < min_required:
            return MomentumResult(
                momentum_short=0.0,
                momentum_medium=0.0,
                momentum_long=0.0,
                signal=0,
                strength=0.0,
                votes=0
            )
        
        # モメンタム計算
        mom_short = self._calc_momentum(closes, self.short_period)
        mom_medium = self._calc_momentum(closes, self.medium_period)
        mom_long = self._calc_momentum(closes, self.long_period) if len(closes) >= self.long_period else 0.0
        
        # シグナル投票
        def vote(mom: float) -> int:
            if mom > self.threshold:
                return 1
            elif mom < -self.threshold:
                return -1
            return 0
        
        votes = vote(mom_short) + vote(mom_medium) + vote(mom_long)
        
        # シグナル判定（2/3以上の合意）
        if votes >= 2:
            signal = 1
        elif votes <= -2:
            signal = -1
        else:
            signal = 0
        
        # 強度計算（中期モメンタムベース）
        strength = min(abs(mom_medium) / (self.threshold * 3), 1.0)
        
        return MomentumResult(
            momentum_short=mom_short,
            momentum_medium=mom_medium,
            momentum_long=mom_long,
            signal=signal,
            strength=strength,
            votes=votes
        )
    
    def _calc_momentum(self, closes: np.ndarray, period: int) -> float:
        """
        モメンタム（リターン率）を計算
        
        Args:
            closes: 終値配列
            period: 期間
        
        Returns:
            リターン率
        """
        if len(closes) < period or closes[-period] == 0:
            return 0.0
        return (closes[-1] - closes[-period]) / closes[-period]


# ===== テストコード =====
if __name__ == "__main__":
    import numpy as np
    
    # テストデータ生成（上昇トレンド）
    np.random.seed(42)
    n = 100
    trend = np.linspace(0, 10, n)
    noise = np.random.randn(n) * 0.5
    closes = 100 + trend + noise
    
    print("=== Momentum Module Test ===")
    module = MomentumModule(short_period=5, medium_period=20, long_period=60)
    
    score = module.analyze(closes)
    print(f"Signal: {score.signal}")
    print(f"Confidence: {score.confidence:.2f}")
    print(f"Reason: {score.reason}")
    
    result = module.analyze_detailed(closes)
    print(f"\nDetailed:")
    print(f"  Short Momentum: {result.momentum_short:.2%}")
    print(f"  Medium Momentum: {result.momentum_medium:.2%}")
    print(f"  Long Momentum: {result.momentum_long:.2%}")
    print(f"  Votes: {result.votes}/3")
