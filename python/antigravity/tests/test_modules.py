import unittest
import pandas as pd
import numpy as np
from antigravity.risk.vpin import VPINCalculator
from antigravity.forecasting.features import (
    TechnicalIndicators, 
    GarmanKlassVolatility, 
    VWAPGap,
    FormulaicAlpha,
    WindowNormalizer
)
from antigravity.control.agents import RewardCalculator, PPOAgent, A2CAgent, EnsembleSelector


class TestVPIN(unittest.TestCase):
    """VPINモジュールのテスト"""
    
    def test_vpin_initialization(self):
        """VPINCalculatorの初期化テスト"""
        vpin = VPINCalculator(bucket_volume=500.0, n_buckets=10)
        self.assertEqual(vpin.bucket_volume, 500.0)
        self.assertEqual(vpin.n_buckets, 10)
    
    def test_vpin_calculation(self):
        """VPINの計算テスト"""
        vpin = VPINCalculator(bucket_volume=100.0, n_buckets=5)
        
        # 価格上昇パターン（買い優勢）を入力
        prices = [100.0, 101.0, 102.0, 103.0, 104.0, 105.0, 106.0, 107.0, 108.0, 109.0]
        for price in prices:
            vpin.update(price, volume=200.0)
        
        result = vpin.calculate_vpin()
        print(f"VPIN Result (uptrend): {result}")
        self.assertTrue(0.0 <= result <= 1.0)
    
    def test_vpin_toxicity_signal(self):
        """毒性シグナルのテスト"""
        vpin = VPINCalculator(bucket_volume=100.0, n_buckets=5)
        
        # データを投入
        for i in range(20):
            vpin.update(100.0 + i * 0.5, volume=200.0)
        
        signal = vpin.get_toxicity_signal(threshold=0.5)
        self.assertIn(signal, ['LOW', 'MEDIUM', 'HIGH'])
        print(f"Toxicity Signal: {signal}")


class TestFeatures(unittest.TestCase):
    """特徴量モジュールのテスト"""
    
    def setUp(self):
        """テスト用のダミーDataFrameを作成"""
        np.random.seed(42)
        dates = pd.date_range(start='2023-01-01', periods=50, freq='5min')
        base_price = 100
        
        self.df = pd.DataFrame({
            'Open': base_price + np.random.randn(50).cumsum(),
            'Close': base_price + 1 + np.random.randn(50).cumsum(),
            'High': base_price + 3 + np.abs(np.random.randn(50).cumsum()),
            'Low': base_price - 2 - np.abs(np.random.randn(50).cumsum()),
            'Volume': np.random.randint(1000, 5000, 50)
        }, index=dates)
        
        # High > Close > Low を保証
        self.df['High'] = self.df[['Open', 'Close', 'High']].max(axis=1) + 0.5
        self.df['Low'] = self.df[['Open', 'Close', 'Low']].min(axis=1) - 0.5
        
    def test_technical_indicators(self):
        """テクニカル指標のテスト"""
        ti = TechnicalIndicators()
        features = ti.calculate(self.df)
        
        print("Features Columns:", features.columns.tolist())
        self.assertIn('SMA_20', features.columns)
        self.assertIn('RSI_14', features.columns)
        self.assertIn('BB_Upper', features.columns)
        self.assertIn('BB_Lower', features.columns)
        self.assertFalse(features.empty)
    
    def test_garman_klass_volatility(self):
        """Garman-Klassボラティリティのテスト"""
        gk = GarmanKlassVolatility(window=10)
        volatility = gk.calculate(self.df)
        
        print(f"GK Volatility (last 5): {volatility.tail().tolist()}")
        
        # ボラティリティは0以上であるべき
        valid_values = volatility.dropna()
        self.assertTrue((valid_values >= 0).all())
    
    def test_vwap_gap(self):
        """VWAP乖離率のテスト"""
        vwap_gap = VWAPGap(window=10)
        gap = vwap_gap.calculate(self.df)
        
        print(f"VWAP Gap (last 5): {gap.tail().tolist()}")
        self.assertEqual(len(gap), len(self.df))
    
    def test_formulaic_alpha(self):
        """Formulaic Alphaのテスト"""
        alpha = FormulaicAlpha(sma_window=10)
        
        # センチメントなしでテスト
        result = alpha.calculate(self.df)
        print(f"Alpha without sentiment (last 5): {result.tail().tolist()}")
        self.assertEqual(len(result), len(self.df))
        
        # センチメントありでテスト
        sentiment = pd.Series(np.random.randn(50) * 0.5, index=self.df.index)
        result_with_sentiment = alpha.calculate(self.df, sentiment=sentiment)
        print(f"Alpha with sentiment (last 5): {result_with_sentiment.tail().tolist()}")
    
    def test_window_normalizer(self):
        """ウィンドウ正規化のテスト"""
        normalizer = WindowNormalizer(window=10)
        
        series = self.df['Close']
        normalized = normalizer.normalize(series)
        
        print(f"Normalized Close (last 5): {normalized.tail().tolist()}")
        
        # 正規化後の値の範囲を確認（極端に大きくならないこと）
        valid = normalized.dropna()
        self.assertTrue((valid.abs() < 10).all())  # Zスコアなので極端に大きくならない


class TestAgents(unittest.TestCase):
    """エージェントモジュールのテスト"""
    
    def test_reward_calculator(self):
        """報酬計算のテスト"""
        calc = RewardCalculator(transaction_cost=0.001, inventory_penalty=0.01)
        
        # 基本的な報酬計算
        reward = calc.calculate(
            pnl_delta=10.0,
            position_change=1.0,
            current_inventory=2.0,
            volatility=0.02
        )
        
        # 報酬 = 10 - 0.001*1 - 0.01 * (0.02)^2 * (2)^2
        #      = 10 - 0.001 - 0.01 * 0.0004 * 4
        #      = 10 - 0.001 - 0.000016
        print(f"Calculated Reward: {reward}")
        self.assertLess(reward, 10.0)  # コストとペナルティで減少
        self.assertGreater(reward, 9.99)  # でも大幅には下がらない
    
    def test_reward_inventory_penalty(self):
        """在庫ペナルティの効果テスト"""
        calc = RewardCalculator(transaction_cost=0.001, inventory_penalty=0.01)
        
        # 在庫が増えると報酬が減少することを確認
        reward_low_inv = calc.calculate(pnl_delta=0, position_change=0, current_inventory=1.0, volatility=0.1)
        reward_high_inv = calc.calculate(pnl_delta=0, position_change=0, current_inventory=5.0, volatility=0.1)
        
        print(f"Reward (inventory=1): {reward_low_inv}")
        print(f"Reward (inventory=5): {reward_high_inv}")
        
        self.assertGreater(reward_low_inv, reward_high_inv)
    
    def test_ppo_agent(self):
        """PPOエージェントのテスト"""
        agent = PPOAgent()
        state = np.array([0.01, 0.02, 0.5, 0.1, 0.0])
        
        action = agent.act(state)
        self.assertIn(action, [0, 1, 2])
        print(f"PPO Action: {action}")
    
    def test_a2c_agent(self):
        """A2Cエージェントのテスト"""
        agent = A2CAgent()
        state = np.array([0.01, 0.02, 0.1, 0.1, 0.0])
        
        action = agent.act(state)
        self.assertIn(action, [0, 1, 2])
        print(f"A2C Action: {action}")
    
    def test_ensemble_selector_regime(self):
        """アンサンブルセレクターのレジーム切替テスト"""
        selector = EnsembleSelector(vpin_threshold=0.4)
        state = np.array([0.01, 0.02, 0.1, 0.1, 0.0])
        
        # トレンド相場
        action_trend = selector.select_action(state, 'trend', vpin_value=0.1)
        agent_trend = selector.get_selected_agent_name('trend', 0.1)
        print(f"Trend: {agent_trend} -> Action {action_trend}")
        
        # 高VPIN（安全モード）
        action_high_vpin = selector.select_action(state, 'trend', vpin_value=0.6)
        agent_high_vpin = selector.get_selected_agent_name('trend', 0.6)
        print(f"High VPIN: {agent_high_vpin} -> Action {action_high_vpin}")
        
        self.assertIn('PPO', agent_trend)
        self.assertIn('A2C', agent_high_vpin)


class TestTransformer(unittest.TestCase):
    """Transformerモデルのテスト"""
    
    def test_transformer_initialization(self):
        """TransformerPredictorの初期化テスト"""
        from antigravity.forecasting.models import TransformerPredictor
        
        predictor = TransformerPredictor(input_dim=5, d_model=32, nhead=2, num_layers=1)
        self.assertFalse(predictor.trained)
        print("Transformer initialized successfully")
    
    def test_transformer_prediction(self):
        """Transformerの予測テスト"""
        from antigravity.forecasting.models import TransformerPredictor
        
        predictor = TransformerPredictor(input_dim=5)
        
        # ダミーシーケンス [batch=1, seq_len=20, features=5]
        X = np.random.randn(1, 20, 5).astype(np.float32)
        
        reg_pred, dir_probs = predictor.predict(X)
        
        print(f"Regression prediction shape: {reg_pred.shape}")
        print(f"Direction probabilities: {dir_probs}")
        
        self.assertEqual(reg_pred.shape, (1, 1))
        self.assertEqual(dir_probs.shape, (1, 3))
        self.assertAlmostEqual(dir_probs.sum(), 1.0, places=5)
    
    def test_transformer_direction(self):
        """方向予測テスト"""
        from antigravity.forecasting.models import TransformerPredictor
        
        predictor = TransformerPredictor(input_dim=5)
        X = np.random.randn(1, 20, 5).astype(np.float32)
        
        direction = predictor.predict_direction(X)
        
        self.assertIn(direction, [0, 1, 2])
        print(f"Predicted direction: {direction} (0=DOWN, 1=FLAT, 2=UP)")
    
    def test_transformer_training(self):
        """Transformerの学習テスト"""
        from antigravity.forecasting.models import TransformerPredictor
        
        predictor = TransformerPredictor(input_dim=5)
        
        # ダミーデータ
        X = np.random.randn(4, 20, 5).astype(np.float32)
        y_reg = np.random.randn(4, 1).astype(np.float32)
        y_cls = np.array([0, 1, 2, 1])  # Direction labels
        
        loss = predictor.train(X, y_reg, y_cls)
        
        self.assertTrue(predictor.trained)
        self.assertGreater(loss, 0)
        print(f"Training loss: {loss:.4f}")


if __name__ == '__main__':
    unittest.main(verbosity=2)


