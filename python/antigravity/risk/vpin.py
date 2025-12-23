import pandas as pd
import numpy as np
from scipy import stats
from typing import List, Tuple


class VPINCalculator:
    """
    VPIN (Volume-Synchronized Probability of Informed Trading) 計算機
    
    参考文献: Easley, López de Prado, O'Hara (2012)
    
    時間ベースではなく、取引量（ボリューム）ベースでデータをサンプリングし、
    インフォームド・トレーダー（情報優位者）の存在確率を推定する。
    高いVPIN値は「毒性フロー」（逆選択リスク）の存在を示唆する。
    """
    
    def __init__(self, bucket_volume: float = 1000.0, n_buckets: int = 50):
        """
        Parameters:
        -----------
        bucket_volume : float
            1つのボリュームバケットを構成する取引量
        n_buckets : int
            VPINを計算する際に使用するバケット数（ウィンドウ長）
        """
        self.bucket_volume = bucket_volume
        self.n_buckets = n_buckets
        
        # 内部状態
        self.buckets: List[Tuple[float, float]] = []  # (buy_vol, sell_vol)のリスト
        self.current_bucket_buy = 0.0
        self.current_bucket_sell = 0.0
        self.current_bucket_total = 0.0
        
        # 価格変動の標準偏差を推定するためのバッファ
        self.price_changes: List[float] = []
        self.price_std = 0.01  # 初期値（後で更新される）
        self.last_price = None
    
    def _bulk_volume_classification(self, price_change: float, volume: float) -> Tuple[float, float]:
        """
        Bulk Volume Classification (BVC)
        
        価格変動と取引量から、買い注文と売り注文の量を推定する。
        正規分布のCDFを用いて確率的に分類する。
        
        数式:
        V_buy = V * Φ(ΔS / σ)
        V_sell = V - V_buy
        
        Parameters:
        -----------
        price_change : float
            価格変動 (S_t - S_{t-1})
        volume : float
            該当期間の取引量
            
        Returns:
        --------
        Tuple[float, float]: (buy_volume, sell_volume)
        """
        if self.price_std <= 0:
            # 標準偏差がゼロの場合、50/50で分割
            return volume * 0.5, volume * 0.5
        
        # 標準正規分布のCDFを使用
        z_score = price_change / self.price_std
        buy_probability = stats.norm.cdf(z_score)
        
        buy_vol = volume * buy_probability
        sell_vol = volume * (1 - buy_probability)
        
        return buy_vol, sell_vol
    
    def _update_price_std(self, price_change: float):
        """
        価格変動の標準偏差を更新（ローリングウィンドウ）
        """
        self.price_changes.append(price_change)
        
        # 直近100期間の変動からσを推定
        window_size = 100
        if len(self.price_changes) > window_size:
            self.price_changes = self.price_changes[-window_size:]
        
        if len(self.price_changes) >= 10:
            self.price_std = np.std(self.price_changes)
            if self.price_std == 0:
                self.price_std = 0.01  # ゼロ除算回避
    
    def update(self, price: float, volume: float):
        """
        新しいバーデータでVPIN計算器を更新する。
        
        Parameters:
        -----------
        price : float
            終値
        volume : float
            取引量
        """
        if self.last_price is None:
            self.last_price = price
            return
        
        price_change = price - self.last_price
        self._update_price_std(price_change)
        
        # BVCで買い/売りを分類
        buy_vol, sell_vol = self._bulk_volume_classification(price_change, volume)
        
        # 現在のバケットに追加
        self.current_bucket_buy += buy_vol
        self.current_bucket_sell += sell_vol
        self.current_bucket_total += volume
        
        # バケットが満たされたかチェック
        while self.current_bucket_total >= self.bucket_volume:
            # バケットを閉じる
            overflow = self.current_bucket_total - self.bucket_volume
            
            # オーバーフロー分を次のバケット用に調整
            ratio = self.bucket_volume / self.current_bucket_total if self.current_bucket_total > 0 else 1
            
            finalized_buy = self.current_bucket_buy * ratio
            finalized_sell = self.current_bucket_sell * ratio
            
            self.buckets.append((finalized_buy, finalized_sell))
            
            # ウィンドウサイズを超えた古いバケットを削除
            if len(self.buckets) > self.n_buckets:
                self.buckets.pop(0)
            
            # 次のバケットを開始（オーバーフロー分）
            remaining_ratio = 1 - ratio
            self.current_bucket_buy = self.current_bucket_buy * remaining_ratio
            self.current_bucket_sell = self.current_bucket_sell * remaining_ratio
            self.current_bucket_total = overflow
        
        self.last_price = price
    
    def calculate_vpin(self) -> float:
        """
        現在のVPIN値を計算する。
        
        数式: VPIN = Σ|V_sell - V_buy| / (n * V)
        
        Returns:
        --------
        float: VPIN値 (0.0 ~ 1.0)
        """
        if len(self.buckets) < self.n_buckets:
            # 十分なバケットがない場合は不定
            return 0.0
        
        order_imbalance_sum = 0.0
        total_volume = 0.0
        
        for buy_vol, sell_vol in self.buckets:
            order_imbalance_sum += abs(sell_vol - buy_vol)
            total_volume += (buy_vol + sell_vol)
        
        if total_volume == 0:
            return 0.0
        
        return order_imbalance_sum / total_volume
    
    def get_toxicity_signal(self, threshold: float = 0.5) -> str:
        """
        VPIN値に基づいて毒性シグナルを返す。
        
        Parameters:
        -----------
        threshold : float
            高毒性と判断するしきい値（デフォルト: 0.5）
            
        Returns:
        --------
        str: 'LOW', 'MEDIUM', 'HIGH'
        """
        vpin = self.calculate_vpin()
        
        if vpin >= threshold:
            return 'HIGH'
        elif vpin >= threshold * 0.6:
            return 'MEDIUM'
        else:
            return 'LOW'
    
    def reset(self):
        """
        内部状態をリセットする。
        """
        self.buckets = []
        self.current_bucket_buy = 0.0
        self.current_bucket_sell = 0.0
        self.current_bucket_total = 0.0
        self.price_changes = []
        self.price_std = 0.01
        self.last_price = None

