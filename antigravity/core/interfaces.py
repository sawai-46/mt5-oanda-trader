from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional
import pandas as pd
import numpy as np

class AlphaFactor(ABC):
    """
    Base class for any alpha factor (feature) calculation.
    """
    @abstractmethod
    def calculate(self, data: pd.DataFrame) -> pd.Series:
        """
        Calculates the alpha factor values.
        :param data: Input DataFrame (OHLCV)
        :return: Series containing the factor values
        """
        pass

class PredictionModel(ABC):
    """
    Base class for predictive models (e.g., Transformer, LSTM).
    """
    @abstractmethod
    def train(self, X: Any, y: Any):
        pass

    @abstractmethod
    def predict(self, X: Any) -> Any:
        pass

class TradingAgent(ABC):
    """
    Base class for RL agents.
    """
    @abstractmethod
    def act(self, state: np.ndarray) -> int:
        pass

    @abstractmethod
    def update(self, state: np.ndarray, action: int, reward: float, next_state: np.ndarray, done: bool):
        pass
