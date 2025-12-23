import gymnasium as gym
from gymnasium import spaces
import numpy as np
import pandas as pd
from typing import Optional

class TradingEnv(gym.Env):
    """
    Custom Environment that follows gym interface
    """
    metadata = {'render.modes': ['human']}

    def __init__(self, df: pd.DataFrame, initial_balance: float = 10000.0):
        super(TradingEnv, self).__init__()
        
        self.df = df
        self.initial_balance = initial_balance
        self.current_step = 0
        self.balance = initial_balance
        self.position = 0 # 0: Flat, 1: Long, -1: Short
        self.entry_price = 0.0
        
        # Action Space: 0=Hold, 1=Buy, 2=Sell
        self.action_space = spaces.Discrete(3)
        
        # Observation Space: [Price Change, RSI, SMA_Ratio, Sentiment, Position, MACD, CCI, ADX]
        # Extended to include new technical indicators for Ensemble DRL strategy
        self.observation_space = spaces.Box(low=-np.inf, high=np.inf, shape=(8,), dtype=np.float32)

    def reset(self, seed: Optional[int] = None, options: Optional[dict] = None):
        super().reset(seed=seed)
        self.current_step = 0
        self.balance = self.initial_balance
        self.position = 0
        self.entry_price = 0.0
        return self._next_observation(), {}

    def _next_observation(self):
        # Get data for current step
        # Enhanced observation with MACD, CCI, ADX for Ensemble DRL strategy
        row = self.df.iloc[self.current_step]
        
        obs = np.array([
            row.get('Close_Change', 0.0),
            row.get('RSI_14', 50.0) / 100.0,
            row['Close'] / row.get('SMA_20', row['Close']),
            row.get('Sentiment', 0.0),
            float(self.position),
            row.get('MACD', 0.0) / 100.0,  # Normalized MACD
            row.get('CCI', 0.0) / 200.0,   # CCI normalized to ~[-1, 1]
            row.get('ADX', 25.0) / 100.0   # ADX normalized to [0, 1]
        ], dtype=np.float32)
        return obs

    def step(self, action):
        current_price = self.df.iloc[self.current_step]['Close']
        reward = 0.0
        
        # Execute Action
        if action == 1: # Buy
            if self.position == 0:
                self.position = 1
                self.entry_price = current_price
            elif self.position == -1: # Close Short and Buy (Flip)
                reward += (self.entry_price - current_price) # Profit from Short
                self.position = 1
                self.entry_price = current_price
                
        elif action == 2: # Sell
            if self.position == 0:
                self.position = -1
                self.entry_price = current_price
            elif self.position == 1: # Close Long and Sell (Flip)
                reward += (current_price - self.entry_price) # Profit from Long
                self.position = -1
                self.entry_price = current_price
                
        elif action == 0: # Hold
            # Calculate unrealized PnL step reward (optional, sometimes helps learning)
            if self.position == 1:
                reward += (self.df.iloc[self.current_step]['Close'] - self.df.iloc[self.current_step-1]['Close'])
            elif self.position == -1:
                reward += (self.df.iloc[self.current_step-1]['Close'] - self.df.iloc[self.current_step]['Close'])

        self.current_step += 1
        done = self.current_step >= len(self.df) - 1
        
        obs = self._next_observation()
        
        return obs, reward, done, False, {}

    def render(self, mode='human'):
        print(f'Step: {self.current_step}, Balance: {self.balance}, Position: {self.position}')
