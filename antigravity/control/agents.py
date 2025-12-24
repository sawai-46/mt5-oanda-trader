import numpy as np
from typing import Optional
from antigravity.core.interfaces import TradingAgent


class RewardCalculator:
    """
    報酬計算機
    
    HFT/Intraday取引向けの報酬関数を実装。
    参考: Cartea & Jaimungal らの研究
    
    数式:
    R_t = ΔPnL - c * |Δq| - φ * σ² * q²
    
    - ΔPnL: 損益の変動
    - c * |Δq|: 取引コスト（ポジション変更量に比例）
    - φ * σ² * q²: 在庫リスクペナルティ（ポジション保有に対するペナルティ）
    """
    
    def __init__(
        self, 
        transaction_cost: float = 0.001,  # 0.1% (スプレッド + 手数料)
        inventory_penalty: float = 0.01,  # φ: inventory risk aversion
    ):
        """
        Parameters:
        -----------
        transaction_cost : float
            1単位の取引に対するコスト係数
        inventory_penalty : float
            在庫リスク回避パラメータ φ
        """
        self.transaction_cost = transaction_cost
        self.inventory_penalty = inventory_penalty
    
    def calculate(
        self,
        pnl_delta: float,
        position_change: float,
        current_inventory: float,
        volatility: float
    ) -> float:
        """
        報酬を計算する。
        
        Parameters:
        -----------
        pnl_delta : float
            前回から今回までの損益変動
        position_change : float
            ポジション変更量（絶対値で使用）
        current_inventory : float
            現在のポジション（+ for long, - for short）
        volatility : float
            現在のボラティリティ推定値（σ）
            
        Returns:
        --------
        float: 計算された報酬
        """
        # 取引コスト
        cost = self.transaction_cost * abs(position_change)
        
        # 在庫リスクペナルティ: φ * σ² * q²
        inventory_risk = self.inventory_penalty * (volatility ** 2) * (current_inventory ** 2)
        
        # 総報酬
        reward = pnl_delta - cost - inventory_risk
        
        return reward
    
    def calculate_terminal_penalty(
        self,
        final_inventory: float,
        market_impact: float = 0.001
    ) -> float:
        """
        エピソード終了時の清算ペナルティを計算する。
        
        数式: Penalty = -α * q² (一時的なマーケットインパクト)
        
        Parameters:
        -----------
        final_inventory : float
            最終ポジション
        market_impact : float
            マーケットインパクト係数 α
            
        Returns:
        --------
        float: 清算ペナルティ（負の値）
        """
        return -market_impact * (final_inventory ** 2)


class PPOAgent(TradingAgent):
    """
    PPO (Proximal Policy Optimization) エージェント
    
    強気相場（トレンド相場）で高いリターンを生成する傾向がある。
    攻撃的な取引スタイル。
    
    状態ベクトル: [LogReturn, GK_Vol, Alpha, Sentiment, Inventory]
    """
    
    def __init__(self, momentum_threshold: float = 0.0005):
        """
        Parameters:
        -----------
        momentum_threshold : float
            トレードを発生させるモメンタムのしきい値
        """
        self.momentum_threshold = momentum_threshold
        self.reward_history = []
    
    def act(self, state: np.ndarray) -> int:
        """
        状態を受け取りアクションを返す。
        MACD/CCI/ADXを活用したポジション認識ロジック。
        
        State: [Close_Change, RSI, SMA_Ratio, Sentiment, Position, MACD, CCI, ADX]
        Returns: 0=HOLD, 1=BUY, 2=SELL
        """
        if len(state) < 5:
            return 0  # 状態が不完全ならHOLD
        
        # 状態ベクトルを解析
        log_return = state[0]    # 対数リターン（モメンタム）
        alpha = state[2]         # Formulaic Alpha / SMA Ratio
        inventory = state[4]     # 現在のポジション
        
        # 新指標（存在する場合）
        macd = state[5] if len(state) > 5 else 0.0
        cci = state[6] if len(state) > 6 else 0.0
        adx = state[7] if len(state) > 7 else 0.25  # デフォルト: 普通のトレンド
        
        # モメンタム = 対数リターン + アルファ + MACDヒストグラム
        momentum = log_return + alpha * 0.3 + macd * 0.5
        
        # ADXが高い場合（強いトレンド）はエントリーを積極的に
        trend_strength = adx * 4  # ADX/100 -> 0-1 scale, *4 -> 0-4 scale
        adjusted_threshold = self.momentum_threshold / (1 + trend_strength * 0.5)
        
        # ポジション認識ロジック
        if inventory >= 1:  # すでにロング
            if momentum < -adjusted_threshold:
                return 2  # SELL（ポジションクローズ）
            else:
                return 0  # HOLD（ポジション維持）
                
        elif inventory <= -1:  # すでにショート
            if momentum > adjusted_threshold:
                return 1  # BUY（ポジションクローズ）
            else:
                return 0  # HOLD（ポジション維持）
                
        else:  # ノーポジション
            # CCIをフィルターとして使用（極端な過買い/過売りではエントリーしない）
            if momentum > adjusted_threshold and cci < 0.5:  # CCI < 100 (normalized)
                return 1  # BUY
            elif momentum < -adjusted_threshold and cci > -0.5:  # CCI > -100
                return 2  # SELL
            else:
                return 0  # HOLD
    
    def update(self, state: np.ndarray, action: int, reward: float, 
               next_state: np.ndarray, done: bool):
        """
        経験から学習する（スタブ実装）。
        """
        self.reward_history.append(reward)
        # 実際のPPO更新ロジックはここに実装する


class A2CAgent(TradingAgent):
    """
    A2C (Advantage Actor Critic) エージェント
    
    ボラティリティが高い弱気相場において、リスクを抑える能力が高い。
    守備的な取引スタイル。
    
    状態ベクトル: [LogReturn, GK_Vol, Alpha, Sentiment, Inventory]
    """
    
    def __init__(self, momentum_threshold: float = 0.001):
        """
        Parameters:
        -----------
        momentum_threshold : float
            トレードを発生させるモメンタムのしきい値（保守的なので高め）
        """
        self.momentum_threshold = momentum_threshold
        self.reward_history = []
    
    def act(self, state: np.ndarray) -> int:
        """
        状態を受け取りアクションを返す。
        A2Cは保守的: ADXでトレンド強度の無い場合はオンリートレード。
        
        State: [Close_Change, RSI, SMA_Ratio, Sentiment, Position, MACD, CCI, ADX]
        Returns: 0=HOLD, 1=BUY, 2=SELL
        """
        if len(state) < 5:
            return 0  # 状態が不完全ならHOLD
        
        # 状態ベクトルを解析
        log_return = state[0]    # 対数リターン
        volatility = state[1]    # GKボラティリティ / RSI
        alpha = state[2]         # SMA Ratio
        inventory = state[4]     # 現在のポジション
        
        # 新指標
        macd = state[5] if len(state) > 5 else 0.0
        cci = state[6] if len(state) > 6 else 0.0
        adx = state[7] if len(state) > 7 else 0.25
        
        # モメンタム
        momentum = log_return
        
        # A2Cは守備的: ADXが低い（レンジ相場）場合はトレードを避ける
        trend_strength = adx * 4  # ADX normalized scale
        
        if trend_strength < 0.5:  # ADX < 12.5 = 弱いトレンド -> エントリーしない
            # ポジションがある場合のみクローズを検討
            if inventory >= 1 and momentum < 0:
                return 2  # SELL
            elif inventory <= -1 and momentum > 0:
                return 1  # BUY
            return 0  # HOLD
        
        # A2Cは守備的: ポジションを持っている場合、クローズを優先
        if inventory >= 1:  # ロング中
            if momentum < 0:
                return 2  # SELL（ポジションクローズ）
            else:
                return 0  # HOLD
                
        elif inventory <= -1:  # ショート中
            if momentum > 0:
                return 1  # BUY（ポジションクローズ）
            else:
                return 0  # HOLD
                
        else:  # ノーポジション
            # 強いシグナルのみエントリー（CCIも確認）
            if momentum > self.momentum_threshold and macd > 0 and cci > -0.25:
                return 1  # BUY
            elif momentum < -self.momentum_threshold and macd < 0 and cci < 0.25:
                return 2  # SELL
            else:
                return 0  # HOLD（基本は待機）
    
    def update(self, state: np.ndarray, action: int, reward: float, 
               next_state: np.ndarray, done: bool):
        """
        経験から学習する（スタブ実装）。
        """
        self.reward_history.append(reward)
        # 実際のA2C更新ロジックはここに実装する


class EnsembleSelector:
    """
    アンサンブルエージェントセレクター
    
    市場環境（レジーム）とVPIN（毒性フロー）に基づいて、
    最適なエージェントを動的に選択する。
    
    - PPO: トレンド相場（低VPIN）で攻撃的に使用
    - A2C: レンジ相場（高VPIN）で守備的に使用
    """
    
    def __init__(self, vpin_threshold: float = 0.4):
        """
        Parameters:
        -----------
        vpin_threshold : float
            VPINがこの値を超えると、安全モード（A2C）に切り替える
        """
        self.ppo_agent = PPOAgent()
        self.a2c_agent = A2CAgent()
        self.vpin_threshold = vpin_threshold
        
        # パフォーマンス追跡
        self.ppo_sharpe_window = []
        self.a2c_sharpe_window = []
    
    def select_action(
        self, 
        state: np.ndarray, 
        market_regime: str,
        vpin_value: Optional[float] = None
    ) -> int:
        """
        市場環境に基づいてエージェントを選択し、アクションを返す。
        
        Parameters:
        -----------
        state : np.ndarray
            現在の状態ベクトル
        market_regime : str
            'trend', 'range', 'high_vol' のいずれか
        vpin_value : Optional[float]
            現在のVPIN値（0.0 ~ 1.0）
            
        Returns:
        --------
        int: 選択されたアクション (0=HOLD, 1=BUY, 2=SELL)
        """
        # VPINによるオーバーライド
        if vpin_value is not None and vpin_value >= self.vpin_threshold:
            # 高毒性環境 -> 保守的なエージェント（A2C）を使用
            return self.a2c_agent.act(state)
        
        # 市場レジームに基づく選択
        if market_regime == 'trend':
            return self.ppo_agent.act(state)
        elif market_regime == 'range':
            return self.a2c_agent.act(state)
        elif market_regime == 'high_vol':
            # 高ボラティリティ -> 守備的
            return self.a2c_agent.act(state)
        else:
            # デフォルト: A2C（安全策）
            return self.a2c_agent.act(state)
    
    def get_selected_agent_name(
        self, 
        market_regime: str, 
        vpin_value: Optional[float] = None
    ) -> str:
        """
        どのエージェントが選択されるかを返す（デバッグ用）。
        """
        if vpin_value is not None and vpin_value >= self.vpin_threshold:
            return "A2C (Safe Mode - High VPIN)"
        
        if market_regime == 'trend':
            return "PPO (Trend)"
        elif market_regime == 'range':
            return "A2C (Range)"
        elif market_regime == 'high_vol':
            return "A2C (High Volatility)"
        else:
            return "A2C (Default)"

