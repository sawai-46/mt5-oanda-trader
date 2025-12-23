import pandas as pd
import numpy as np
import os
from typing import Dict, Any, List, Optional, Literal

from antigravity.forecasting.features import (
    TechnicalIndicators, 
    LogReturn, 
    GarmanKlassVolatility,
    FormulaicAlpha,
    WindowNormalizer,
    GARCHVolatilityFeature
)
from antigravity.forecasting.models import TransformerPredictor, KANForecaster
from antigravity.sentiment.analyzer import SentimentAnalyzer
from antigravity.risk.vpin import VPINCalculator
from antigravity.control.agents import EnsembleSelector, RewardCalculator


# モデルタイプの型定義
ModelType = Literal['transformer', 'kan', 'ensemble']


class AntigravityOrchestrator:
    """
    Antigravity トレーディングシステム オーケストレーター
    
    全モジュール（特徴量、リスク管理、強化学習エージェント）を統合し、
    バーデータを受け取ってトレード判断を行うメインパイプライン。
    
    モデル選択:
    - transformer: Transformer単体（1D-CNN + Time2Vec）
    - kan: KAN単体（Kolmogorov-Arnold Network）
    - ensemble: Transformer + KAN のアンサンブル（多数決/加重平均）
    """

    def __init__(
        self, 
        run_mode: str = 'SHADOW',
        vpin_safety_threshold: float = 0.5,
        feature_window: int = 60,
        max_position: int = 1,
        model_path: Optional[str] = None,
        kan_model_path: Optional[str] = None,
        daily_data_path: Optional[str] = None,
        model_type: ModelType = 'transformer',
        ensemble_weights: tuple = (0.6, 0.4)  # (transformer_weight, kan_weight)
    ):
        """
        Parameters:
        -----------
        run_mode : str
            'SHADOW' (シミュレーションのみ) or 'LIVE' (実取引)
        vpin_safety_threshold : float
            VPINがこの値を超えると安全モード（取引抑制）に移行
        feature_window : int
            特徴量計算に使用するウィンドウサイズ
        max_position : int
            1銘柄あたりの最大ポジション数 (デフォルト: 1)
        model_path : str, optional
            学習済みTransformerモデルのパス
        kan_model_path : str, optional
            学習済みKANモデルのパス
        daily_data_path : str, optional
            GARCHシグナル生成用の日足データパス
        model_type : str
            'transformer', 'kan', または 'ensemble'
        ensemble_weights : tuple
            アンサンブル時の重み (transformer_weight, kan_weight)
        """
        self.run_mode = run_mode
        self.vpin_safety_threshold = vpin_safety_threshold
        self.max_position = max_position
        self.model_type = model_type
        self.ensemble_weights = ensemble_weights
        
        # 特徴量計算モジュール
        self.tech_indicators = TechnicalIndicators()
        self.log_return = LogReturn()
        self.gk_volatility = GarmanKlassVolatility(window=20)
        self.formulaic_alpha = FormulaicAlpha(sma_window=20)
        self.normalizer = WindowNormalizer(window=feature_window)
        
        # 予測モデル初期化
        self.transformer_model: Optional[TransformerPredictor] = None
        self.kan_model: Optional[KANForecaster] = None
        
        self._init_models(model_path, kan_model_path)
        
        # センチメント分析
        self.sentiment = SentimentAnalyzer()
        
        # リスク管理 (VPIN)
        self.vpin_calc = VPINCalculator(bucket_volume=1000.0, n_buckets=50)
        
        # 強化学習エージェント
        self.agent_selector = EnsembleSelector(vpin_threshold=vpin_safety_threshold)
        self.reward_calculator = RewardCalculator(
            transaction_cost=0.001,
            inventory_penalty=0.01
        )
        
        # GARCHボラティリティ予測（マルチタイムフレーム）
        self.garch_feature = GARCHVolatilityFeature(rolling_window=180)
        self.garch_signal: int = 0  # キャッシュした日次シグナル
        
        if daily_data_path and os.path.exists(daily_data_path):
            self._load_daily_data(daily_data_path)
        
        # 内部状態
        self.bar_history: List[Dict[str, float]] = []
        self.current_inventory: float = 0.0  # 現在のポジション
        self.last_price: Optional[float] = None
        self.current_volatility: float = 0.01
        self.cumulative_pnl: float = 0.0
        
    def _init_models(self, model_path: Optional[str], kan_model_path: Optional[str]):
        """予測モデルを初期化"""
        # デバイス設定（CUDA優先）
        import torch
        device = 'cuda' if torch.cuda.is_available() else 'cpu'
        print(f"[INFO] Using device: {device}")
        
        # Transformer
        if self.model_type in ('transformer', 'ensemble'):
            self.transformer_model = TransformerPredictor(input_dim=5, device=device)
            if model_path and os.path.exists(model_path):
                try:
                    self.transformer_model.load(model_path)
                    print(f"[INFO] Loaded Transformer model from: {model_path}")
                except Exception as e:
                    print(f"[WARNING] Failed to load Transformer model: {e}")
        
        # KAN
        if self.model_type in ('kan', 'ensemble'):
            self.kan_model = KANForecaster(input_dim=5, seq_len=20, device=device)
            if kan_model_path and os.path.exists(kan_model_path):
                try:
                    self.kan_model.load(kan_model_path)
                    print(f"[INFO] Loaded KAN model from: {kan_model_path}")
                except Exception as e:
                    print(f"[WARNING] Failed to load KAN model: {e}")
        
        # 後方互換性のため self.model を設定
        if self.model_type == 'transformer':
            self.model = self.transformer_model
        elif self.model_type == 'kan':
            self.model = self.kan_model
        else:
            # ensemble の場合は transformer をプライマリとする
            self.model = self.transformer_model
        
        print(f"[INFO] Model type: {self.model_type}")
        if self.model_type == 'ensemble':
            print(f"[INFO] Ensemble weights: Transformer={self.ensemble_weights[0]:.1%}, KAN={self.ensemble_weights[1]:.1%}")
        
        # Transformerのシーケンス長
        self.seq_len: int = 20
        self.transformer_prediction: int = 1  # 0=DOWN, 1=FLAT, 2=UP
        
    def _load_daily_data(self, daily_data_path: str):
        """
        日足データを読み込み、GARCHシグナルを事前計算する。
        """
        try:
            # 堅牢な読み込みロジック (run_backtest.pyと同様)
            try:
                # ヘッダーありを想定して読み込み
                daily_df = pd.read_csv(daily_data_path)
                
                # 標準的なMT4ヘッダー (Date, Time, Open...) がない場合、ヘッダーなしとして再読み込み
                if 'Open' not in daily_df.columns and 'Expected_Column' not in daily_df.columns:
                     # MT4デフォルト: Date, Time, Open, High, Low, Close, Vol...
                     daily_df = pd.read_csv(daily_data_path, names=['Date', 'Time', 'Open', 'High', 'Low', 'Close', 'TickVol', 'Vol', 'Spread'])
            except:
                # 失敗時はヘッダーなしとして読み込み
                daily_df = pd.read_csv(daily_data_path, names=['Date', 'Time', 'Open', 'High', 'Low', 'Close', 'TickVol', 'Vol', 'Spread'])

            # カラム名を小文字に正規化
            daily_df.columns = [c.lower() for c in daily_df.columns]
            
            # 日付カラムの処理
            if 'date' in daily_df.columns and 'time' in daily_df.columns:
                daily_df['Timestamp'] = pd.to_datetime(daily_df['date'].astype(str) + ' ' + daily_df['time'].astype(str))
            elif 'time' in daily_df.columns:
                daily_df['Timestamp'] = pd.to_datetime(daily_df['time'])
            else:
                # 日付列が見つからない場合
                print(f"[WARNING] No 'Date'/'Time' column in daily data. Columns: {daily_df.columns}")
                return

            daily_df.set_index('Timestamp', inplace=True)
            
            # カラム名の修正 (Capitalize for compatibility)
            col_map = {'open': 'Open', 'high': 'High', 'low': 'Low', 'close': 'Close', 'volume': 'Volume', 'vol': 'Volume'}
            daily_df = daily_df.rename(columns=col_map)
            
            print(f"[INFO] Loading daily data from: {daily_data_path}")
            print(f"[INFO] Daily bars: {len(daily_df)}")
            
            # GARCHシグナルを計算
            self.garch_feature.fit_daily(daily_df)
            print("[INFO] GARCH signals computed successfully.")
            print("[INFO] GARCH signals computed successfully.")
            
        except Exception as e:
            print(f"[WARNING] Failed to load daily data: {e}")
        
    def _update_bar_history(self, bar_data: Dict[str, float]):
        """バー履歴を更新"""
        self.bar_history.append(bar_data)
        # メモリ管理: 直近200本のみ保持
        if len(self.bar_history) > 200:
            self.bar_history = self.bar_history[-200:]
    
    def _compute_features(self, sentiment_score: float = 0.0) -> np.ndarray:
        """
        現在の状態ベクトルを計算する。
        
        Returns: np.ndarray (状態ベクトル)
        """
        if len(self.bar_history) < 25:
            # 履歴が不足している場合はダミーを返す
            return np.zeros(5)
        
        # DataFrameに変換
        df = pd.DataFrame(self.bar_history)
        
        # 各種特徴量を計算
        try:
            log_ret = self.log_return.calculate(df)
            gk_vol = self.gk_volatility.calculate(df)
            alpha = self.formulaic_alpha.calculate(df)
            
            # 最新の値を取得
            latest_log_ret = log_ret.iloc[-1] if not log_ret.isna().all() else 0.0
            latest_gk_vol = gk_vol.iloc[-1] if not gk_vol.isna().all() else 0.01
            latest_alpha = alpha.iloc[-1] if not alpha.isna().all() else 0.0
            
            # ボラティリティを更新
            self.current_volatility = latest_gk_vol if latest_gk_vol > 0 else 0.01
            
            # 状態ベクトルを構築
            state = np.array([
                latest_log_ret,       # 対数リターン
                latest_gk_vol,        # Garman-Klassボラティリティ
                latest_alpha,         # Formulaic Alpha
                sentiment_score,      # センチメントスコア
                self.current_inventory  # 現在のポジション（正規化）
            ])
            
            # NaNを0に置換
            state = np.nan_to_num(state, nan=0.0, posinf=0.0, neginf=0.0)
            
            return state
            
        except Exception as e:
            print(f"[WARNING] Feature computation error: {e}")
            return np.zeros(5)
    
    def _build_sequence(self) -> Optional[np.ndarray]:
        """
        バー履歴からTransformer入力用のシーケンスを構築する。
        
        Returns:
            np.ndarray: [1, seq_len, 5] の形式のシーケンス
            または履歴不足の場合はNone
        """
        if len(self.bar_history) < self.seq_len:
            return None
        
        # 直近seq_len本のバーを取得
        recent_bars = self.bar_history[-self.seq_len:]
        df = pd.DataFrame(recent_bars)
        
        try:
            # 各バーの特徴量を計算
            log_returns = self.log_return.calculate(df).fillna(0).values
            gk_vols = self.gk_volatility.calculate(df).fillna(0.01).values
            alphas = self.formulaic_alpha.calculate(df).fillna(0).values
            
            # シーケンスを構築 [seq_len, 5]
            # 特徴量: [log_return, gk_vol, alpha, price_normalized, volume_normalized]
            prices = df['Close'].values
            volumes = df['Volume'].values
            
            # 正規化
            price_norm = (prices - prices.mean()) / (prices.std() + 1e-8)
            vol_norm = (volumes - volumes.mean()) / (volumes.std() + 1e-8)
            
            sequence = np.stack([
                log_returns,
                gk_vols,
                alphas,
                price_norm,
                vol_norm
            ], axis=1)  # [seq_len, 5]
            
            # NaNを置換
            sequence = np.nan_to_num(sequence, nan=0.0, posinf=0.0, neginf=0.0)
            
            # バッチ次元を追加 [1, seq_len, 5]
            return sequence[np.newaxis, :, :].astype(np.float32)
            
        except Exception as e:
            print(f"[WARNING] Sequence build error: {e}")
            return None
    
    def _get_transformer_prediction(self) -> int:
        """
        モデルから方向予測を取得する（後方互換性のためのラッパー）
        
        Returns:
            0 = DOWN, 1 = FLAT, 2 = UP
        """
        return self._get_model_prediction()
    
    def _get_model_prediction(self) -> int:
        """
        設定されたモデル（Transformer/KAN/Ensemble）から方向予測を取得する。
        
        Returns:
            0 = DOWN, 1 = FLAT, 2 = UP
        """
        sequence = self._build_sequence()
        
        if sequence is None:
            return 1  # データ不足の場合はFLAT
        
        try:
            if self.model_type == 'transformer':
                direction = self._predict_transformer(sequence)
            elif self.model_type == 'kan':
                direction = self._predict_kan(sequence)
            elif self.model_type == 'ensemble':
                direction = self._predict_ensemble(sequence)
            else:
                direction = 1  # 不明な場合はFLAT
            
            self.transformer_prediction = direction
            return direction
        except Exception as e:
            print(f"[WARNING] Model prediction error: {e}")
            return 1  # エラー時はFLAT
    
    def _predict_transformer(self, sequence: np.ndarray) -> int:
        """Transformer単体の予測"""
        if self.transformer_model is None:
            return 1
        return self.transformer_model.predict_direction(sequence)
    
    def _predict_kan(self, sequence: np.ndarray) -> int:
        """KAN単体の予測"""
        if self.kan_model is None:
            return 1
        return self.kan_model.predict_direction(sequence)
    
    def _predict_ensemble(self, sequence: np.ndarray) -> int:
        """
        Transformer + KAN のアンサンブル予測
        
        方法: 加重投票 (Weighted Voting)
        - 各モデルの予測クラスに重みを掛けて合算
        - 最も高いスコアのクラスを選択
        """
        trans_weight, kan_weight = self.ensemble_weights
        
        # 各モデルの確率分布を取得
        scores = np.zeros(3)  # [DOWN, FLAT, UP]
        
        if self.transformer_model is not None:
            try:
                trans_dir = self.transformer_model.predict_direction(sequence)
                scores[trans_dir] += trans_weight
            except Exception as e:
                print(f"[WARNING] Transformer ensemble error: {e}")
        
        if self.kan_model is not None:
            try:
                kan_dir = self.kan_model.predict_direction(sequence)
                scores[kan_dir] += kan_weight
            except Exception as e:
                print(f"[WARNING] KAN ensemble error: {e}")
        
        # 最高スコアのクラスを返す
        final_direction = int(np.argmax(scores))
        
        # デバッグ出力
        dir_names = ['DOWN', 'FLAT', 'UP']
        print(f"  [Ensemble] scores={scores}, result={dir_names[final_direction]}")
        
        return final_direction
    
    def _determine_regime(
        self, 
        sentiment_score: float, 
        vpin_value: float,
        volatility: float
    ) -> str:
        """
        市場レジーム（相場環境）を判定する。
        
        Returns: 'trend', 'range', 'high_vol'
        """
        # 高ボラティリティ判定
        if volatility > 0.03:  # 3%以上のボラティリティ
            return 'high_vol'
        
        # センチメントが強い場合はトレンド
        if abs(sentiment_score) > 0.5:
            return 'trend'
        
        # VPINが高い場合はレンジ（情報の非対称性が高い）
        if vpin_value > 0.3:
            return 'range'
        
        # デフォルト
        return 'trend'
    
    def _calculate_pnl_delta(self, current_price: float) -> float:
        """
        前回の価格からの損益変動を計算する。
        """
        if self.last_price is None:
            return 0.0
        
        price_change = current_price - self.last_price
        pnl_delta = self.current_inventory * price_change
        
        return pnl_delta
    
    def _can_take_action(self, action: int) -> bool:
        """
        指定されたアクションがポジションリミットに照らして実行可能かを判定する。
        """
        if action == 1:  # BUY
            return self.current_inventory < self.max_position
        elif action == 2:  # SELL
            return self.current_inventory > -self.max_position
        return True  # HOLD は常に可能
    
    def _update_inventory(self, action: int, price: float):
        """
        アクションに基づいてポジションを更新する。
        ポジションリミット（max_position）を超えないよう制御。
        
        Action: 0=HOLD, 1=BUY, 2=SELL
        
        Returns:
        --------
        Tuple[float, bool]: (position_change, was_limited)
        """
        position_change = 0.0
        was_limited = False
        
        if action == 1:  # BUY
            # ポジションリミットチェック
            if self.current_inventory >= self.max_position:
                was_limited = True
                position_change = 0.0  # すでに最大ロング
            else:
                position_change = 1.0
        elif action == 2:  # SELL
            # ポジションリミットチェック
            if self.current_inventory <= -self.max_position:
                was_limited = True
                position_change = 0.0  # すでに最大ショート
            else:
                position_change = -1.0
        
        self.current_inventory += position_change
        
        return position_change, was_limited
        
    def process_bar(
        self, 
        bar_data: Dict[str, float], 
        news: str = ""
    ) -> Dict[str, Any]:
        """
        新しいバーを処理し、トレード判断を行うメインパイプライン。
        
        Parameters:
        -----------
        bar_data : Dict
            'Open', 'High', 'Low', 'Close', 'Volume' を含む辞書
        news : str
            ニューステキスト（オプション）
            
        Returns:
        --------
        Dict: トレード判断結果
        """
        current_price = bar_data['Close']
        
        # 1. バー履歴を更新
        self._update_bar_history(bar_data)
        print(f"[{self.run_mode}] Processing bar: Close={current_price:.4f}")
        
        # 2. センチメント分析
        sentiment_score = 0.0
        if news:
            sentiment_score = self.sentiment.analyze_news(news)
            print(f"  Sentiment: {sentiment_score:.3f}")

        # 3. VPIN（毒性フロー）を更新・計算
        self.vpin_calc.update(current_price, bar_data['Volume'])
        vpin_val = self.vpin_calc.calculate_vpin()
        toxicity_signal = self.vpin_calc.get_toxicity_signal(self.vpin_safety_threshold)
        print(f"  VPIN: {vpin_val:.4f} ({toxicity_signal})")
        
        # 4. 特徴量を計算
        state = self._compute_features(sentiment_score)
        
        # 5. Transformer予測を取得
        transformer_dir = self._get_transformer_prediction()
        dir_map = {0: 'DOWN', 1: 'FLAT', 2: 'UP'}
        print(f"  Transformer: {dir_map[transformer_dir]}")
        
        # 6. 状態ベクトルにTransformer予測を追加 (正規化: -1, 0, 1)
        transformer_signal = (transformer_dir - 1)  # 0=DOWN->-1, 1=FLAT->0, 2=UP->1
        state_with_prediction = np.append(state, transformer_signal)
        print(f"  State: {state_with_prediction}")
        
        # 7. 市場レジームを判定
        regime = self._determine_regime(sentiment_score, vpin_val, self.current_volatility)
        print(f"  Regime: {regime}")
        
        # 8. 損益変動を計算
        pnl_delta = self._calculate_pnl_delta(current_price)
        
        # 9. エージェントからアクションを取得（Transformer予測を加味）
        selected_agent = self.agent_selector.get_selected_agent_name(regime, vpin_val)
        
        # 9a. GARCHシグナルを取得（日付ベース）
        if 'Time' in bar_data:
            current_date = pd.to_datetime(bar_data['Time']).date()
        else:
            current_date = None
        
        garch_sig = 0
        if current_date:
            garch_sig = self.garch_feature.get_signal_for_date(current_date)
        
        # 9b. RSI/Bollinger による日中シグナル判定
        intraday_signal = 0  # 0=Neutral, 1=Overbought, -1=Oversold
        if len(self.bar_history) >= 25:
            df = pd.DataFrame(self.bar_history)
            tech = self.tech_indicators.calculate(df)
            latest_rsi = tech['RSI_14'].iloc[-1]
            latest_bb_upper = tech['BB_Upper'].iloc[-1]
            latest_bb_lower = tech['BB_Lower'].iloc[-1]
            
            if not pd.isna(latest_rsi) and not pd.isna(latest_bb_upper):
                if latest_rsi > 70 and current_price > latest_bb_upper:
                    intraday_signal = 1  # Overbought
                elif latest_rsi < 30 and current_price < latest_bb_lower:
                    intraday_signal = -1  # Oversold
        
        # 9c. GARCH + RSI/Bollinger Mean Reversion ロジック
        # 日次シグナル (+1 = High Vol Premium) × 日中シグナル (+1 = Overbought) → Short
        # 日次シグナル (-1 = Low Vol Premium) × 日中シグナル (-1 = Oversold) → Long
        mean_reversion_action = None
        if garch_sig == 1 and intraday_signal == 1:
            mean_reversion_action = 2  # SELL (Mean Reversion Short)
            print(f"  [GARCH-MR] High Vol + Overbought → SHORT")
        elif garch_sig == -1 and intraday_signal == -1:
            mean_reversion_action = 1  # BUY (Mean Reversion Long)
            print(f"  [GARCH-MR] Low Vol + Oversold → LONG")
        
        # 最終アクション決定（優先順位: Mean Reversion > Transformer > Agent）
        if mean_reversion_action is not None and self._can_take_action(mean_reversion_action):
            action = mean_reversion_action
        elif transformer_dir == 2 and self.current_inventory < self.max_position:  # UP
            action = 1  # BUY
        elif transformer_dir == 0 and self.current_inventory > -self.max_position:  # DOWN
            action = 2  # SELL
        else:
            # Transformerが中立またはポジション制限の場合、エージェントに委任
            action = self.agent_selector.select_action(state, regime, vpin_val)
        
        action_map = {0: 'HOLD', 1: 'BUY', 2: 'SELL'}
        decision = action_map[action]
        
        # 8. ポジションを更新（リミットチェック込み）
        position_change, was_limited = self._update_inventory(action, current_price)
        
        # 9. 報酬を計算
        reward = self.reward_calculator.calculate(
            pnl_delta=pnl_delta,
            position_change=position_change,
            current_inventory=self.current_inventory,
            volatility=self.current_volatility
        )
        
        # 10. 累積損益を更新
        self.cumulative_pnl += pnl_delta
        
        # 11. 価格を更新
        self.last_price = current_price
        
        # ログ出力
        print(f"  Agent: {selected_agent}")
        limit_msg = " [LIMIT]" if was_limited else ""
        print(f"  Decision: {decision}{limit_msg} | Inventory: {self.current_inventory:.0f} | Reward: {reward:.4f}")
        print(f"  Cumulative PnL: {self.cumulative_pnl:.4f}")
        
        return {
            'action': decision,
            'action_code': action,
            'mode': self.run_mode,
            'vpin': vpin_val,
            'toxicity': toxicity_signal,
            'sentiment': sentiment_score,
            'regime': regime,
            'agent': selected_agent,
            'inventory': self.current_inventory,
            'reward': reward,
            'cumulative_pnl': self.cumulative_pnl,
            'volatility': self.current_volatility,
            'position_limited': was_limited,
            'transformer_direction': dir_map[transformer_dir]
        }
    
    def reset(self):
        """
        オーケストレーターの状態をリセットする。
        """
        self.bar_history = []
        self.current_inventory = 0.0
        self.last_price = None
        self.current_volatility = 0.01
        self.cumulative_pnl = 0.0
        self.vpin_calc.reset()
        print("[INFO] Orchestrator reset complete.")

