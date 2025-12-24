"""
平均回帰モジュール (Mean Reversion Module)

統計的な平均回帰戦略
Ornstein-Uhlenbeck過程に基づく

理論:
- 価格は長期平均に回帰する傾向がある
- Z-scoreが極端な値を示すとき、逆張りエントリー

数式:
    z_score = (price - μ) / σ
    
エントリー条件:
    z_score > +2.0 → ショート（割高）
    z_score < -2.0 → ロング（割安）
"""

from dataclasses import dataclass
from typing import Optional
import numpy as np
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from signal_engine.signal_aggregator import ModuleScore


@dataclass
class MeanReversionResult:
    """平均回帰分析結果"""
    z_score: float          # 現在のZ-score
    mean: float             # 平均値
    std: float              # 標準偏差
    half_life: float        # 平均回帰の半減期（バー数）
    signal: int             # 1=ロング(割安), -1=ショート(割高), 0=中立
    confidence: float       # 信頼度


class MeanReversionModule:
    """
    平均回帰戦略モジュール
    
    Z-scoreに基づいて逆張りシグナルを生成。
    統計的に有意な乖離からの回帰を狙う。
    
    パラメータ:
    - lookback: 平均・標準偏差計算の遡り期間
    - entry_threshold: エントリー閾値（Z-score）
    - exit_threshold: エグジット閾値（Z-score）
    
    使用例:
        module = MeanReversionModule(lookback=20, entry_threshold=2.0)
        score = module.analyze(closes)
    """
    
    def __init__(self,
                 lookback: int = 20,
                 entry_threshold: float = 2.0,
                 exit_threshold: float = 0.5,
                 min_confidence: float = 0.3):
        """
        Args:
            lookback: 平均計算の遡り期間
            entry_threshold: エントリー用Z-score閾値
            exit_threshold: エグジット用Z-score閾値
            min_confidence: 最小信頼度
        """
        self.lookback = lookback
        self.entry_threshold = entry_threshold
        self.exit_threshold = exit_threshold
        self.min_confidence = min_confidence
    
    def analyze(self, closes: np.ndarray) -> ModuleScore:
        """
        平均回帰分析を実行
        
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
                reason=f"平均回帰中立 (Z={result.z_score:.2f})"
            )
        
        if result.signal > 0:
            direction = "割安→ロング"
        else:
            direction = "割高→ショート"
        
        reason = (f"平均回帰: {direction} "
                  f"(Z={result.z_score:.2f}, "
                  f"半減期={result.half_life:.1f}バー)")
        
        return ModuleScore(
            signal=result.signal,
            confidence=result.confidence,
            reason=reason
        )
    
    def analyze_detailed(self, closes: np.ndarray) -> MeanReversionResult:
        """
        詳細な平均回帰分析
        
        Returns:
            MeanReversionResult: 詳細分析結果
        """
        # データ不足チェック
        if len(closes) < self.lookback:
            return MeanReversionResult(
                z_score=0.0,
                mean=0.0,
                std=0.0,
                half_life=999.0,
                signal=0,
                confidence=0.0
            )
        
        # 統計量計算
        window = closes[-self.lookback:]
        mean = np.mean(window)
        std = np.std(window)
        
        if std < 1e-10:
            return MeanReversionResult(
                z_score=0.0,
                mean=mean,
                std=0.0,
                half_life=999.0,
                signal=0,
                confidence=0.0
            )
        
        # Z-score計算
        z_score = (closes[-1] - mean) / std
        
        # 半減期推定（AR(1)係数から）
        half_life = self._estimate_half_life(closes)
        
        # シグナル判定
        if z_score > self.entry_threshold:
            signal = -1  # 割高 → ショート
        elif z_score < -self.entry_threshold:
            signal = 1   # 割安 → ロング
        else:
            signal = 0
        
        # 信頼度（Z-scoreの大きさに比例、上限1.0）
        confidence = min(abs(z_score) / 3.0, 1.0)
        
        return MeanReversionResult(
            z_score=z_score,
            mean=mean,
            std=std,
            half_life=half_life,
            signal=signal,
            confidence=confidence
        )
    
    def _estimate_half_life(self, closes: np.ndarray) -> float:
        """
        平均回帰の半減期を推定（AR(1)モデル）
        
        半減期 = -ln(2) / ln(|ρ|)
        ρ: AR(1)係数
        
        Args:
            closes: 終値配列
        
        Returns:
            半減期（バー数）
        """
        if len(closes) < self.lookback:
            return 999.0
        
        returns = np.diff(closes[-self.lookback:])
        if len(returns) < 2:
            return 999.0
        
        lag_returns = returns[:-1]
        curr_returns = returns[1:]
        
        if np.std(lag_returns) < 1e-10:
            return 999.0
        
        try:
            ar1_coef = np.corrcoef(lag_returns, curr_returns)[0, 1]
            if np.isnan(ar1_coef) or abs(ar1_coef) >= 1:
                return 999.0
            half_life = -np.log(2) / np.log(abs(ar1_coef))
            return min(max(half_life, 1.0), 999.0)
        except:
            return 999.0


# ===== テストコード =====
if __name__ == "__main__":
    import numpy as np
    
    # テストデータ生成（平均回帰的な動き）
    np.random.seed(42)
    n = 100
    
    # Ornstein-Uhlenbeck過程をシミュレート
    mean_level = 100.0
    theta = 0.1  # 回帰速度
    sigma = 1.0
    
    closes = np.zeros(n)
    closes[0] = mean_level + 5  # 初期値は平均より高い
    
    for i in range(1, n):
        closes[i] = closes[i-1] + theta * (mean_level - closes[i-1]) + sigma * np.random.randn()
    
    print("=== Mean Reversion Module Test ===")
    module = MeanReversionModule(lookback=20, entry_threshold=2.0)
    
    score = module.analyze(closes)
    print(f"Signal: {score.signal}")
    print(f"Confidence: {score.confidence:.2f}")
    print(f"Reason: {score.reason}")
    
    result = module.analyze_detailed(closes)
    print(f"\nDetailed:")
    print(f"  Z-score: {result.z_score:.2f}")
    print(f"  Mean: {result.mean:.2f}")
    print(f"  Std: {result.std:.2f}")
    print(f"  Half-life: {result.half_life:.1f} bars")
