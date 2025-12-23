import pandas as pd
import numpy as np
from scipy import stats
from antigravity.core.interfaces import AlphaFactor


class TechnicalIndicators(AlphaFactor):
    """基本的なテクニカル指標を計算するクラス"""
    
    def calculate(self, data: pd.DataFrame) -> pd.DataFrame:
        """
        Calculates basic technical indicators.
        Expects data to have columns: 'Close', 'High', 'Low'
        """
        df = data.copy()
        
        # SMA
        df['SMA_20'] = df['Close'].rolling(window=20).mean()
        
        # RSI
        delta = df['Close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
        rs = gain / loss
        df['RSI_14'] = 100 - (100 / (1 + rs))
        
        # Bollinger Bands
        df['BB_Mid'] = df['Close'].rolling(window=20).mean()
        df['BB_Std'] = df['Close'].rolling(window=20).std()
        df['BB_Upper'] = df['BB_Mid'] + (df['BB_Std'] * 2)
        df['BB_Lower'] = df['BB_Mid'] - (df['BB_Std'] * 2)
        
        return df[['SMA_20', 'RSI_14', 'BB_Upper', 'BB_Lower']]


class LogReturn(AlphaFactor):
    """対数変化率を計算するクラス"""
    
    def calculate(self, data: pd.DataFrame) -> pd.Series:
        return np.log(data['Close'] / data['Close'].shift(1))


class GarmanKlassVolatility(AlphaFactor):
    """
    Garman-Klass ボラティリティ推定量
    
    終値ベースの推定よりも効率的で、
    高値・安値を考慮することで日中の価格変動を捉える。
    数式: σ² = 0.5 * [ln(H/L)]² - (2*ln2 - 1) * [ln(C/O)]²
    """
    
    def __init__(self, window: int = 20):
        self.window = window
    
    def calculate(self, data: pd.DataFrame) -> pd.Series:
        """
        Expects data to have columns: 'Open', 'High', 'Low', 'Close'
        Returns: pd.Series of Garman-Klass volatility
        """
        log_hl = np.log(data['High'] / data['Low'])
        log_co = np.log(data['Close'] / data['Open'])
        
        # Garman-Klass単期の分散推定
        gk_var = 0.5 * (log_hl ** 2) - (2 * np.log(2) - 1) * (log_co ** 2)
        
        # ローリングウィンドウで平均して平滑化
        gk_volatility = gk_var.rolling(window=self.window).mean().apply(
            lambda x: np.sqrt(x) if x > 0 else 0
        )
        
        return gk_volatility


class VWAPGap(AlphaFactor):
    """
    VWAP乖離率
    
    機関投資家のベンチマークであるVWAPと現在価格の乖離を計算。
    数式: VWAPGap = VWAP / Close(-1) - 1
    """
    
    def __init__(self, window: int = 20):
        self.window = window
    
    def calculate(self, data: pd.DataFrame) -> pd.Series:
        """
        Expects data to have columns: 'Close', 'Volume', 'High', 'Low'
        Returns: pd.Series of VWAP Gap
        """
        # Typical Price = (High + Low + Close) / 3
        typical_price = (data['High'] + data['Low'] + data['Close']) / 3
        
        # VWAP = Σ(TP * Volume) / Σ(Volume)
        cumulative_tp_vol = (typical_price * data['Volume']).rolling(window=self.window).sum()
        cumulative_vol = data['Volume'].rolling(window=self.window).sum()
        
        vwap = cumulative_tp_vol / cumulative_vol
        
        # VWAP Gap = (VWAP / Previous Close) - 1
        vwap_gap = (vwap / data['Close'].shift(1)) - 1
        
        return vwap_gap


class FormulaicAlpha(AlphaFactor):
    """
    LLM生成型アルファ (Formulaic Alpha)
    
    価格乖離率とセンチメントを掛け合わせた非線形特徴量。
    数式: Alpha = ((P - SMA) / SMA) * log(1 + Sentiment)
    
    センチメントデータがない場合は価格乖離率のみを返す。
    """
    
    def __init__(self, sma_window: int = 20):
        self.sma_window = sma_window
    
    def calculate(self, data: pd.DataFrame, sentiment: pd.Series = None) -> pd.Series:
        """
        Expects data to have columns: 'Close'
        Optional: sentiment Series (same index as data)
        Returns: pd.Series of Formulaic Alpha
        """
        sma = data['Close'].rolling(window=self.sma_window).mean()
        price_deviation = (data['Close'] - sma) / sma
        
        if sentiment is not None:
            # センチメントスコアを対数変換して乗算
            # sentiment の符号を保持しつつ log(1 + |s|) を適用
            sentiment_factor = np.sign(sentiment) * np.log1p(np.abs(sentiment))
            alpha = price_deviation * sentiment_factor
        else:
            # センチメントがない場合は価格乖離率のみ
            alpha = price_deviation
        
        return alpha


class WindowNormalizer:
    """
    ウィンドウ正規化 (Zスコア)
    
    スライディングウィンドウごとにZスコア正規化を適用。
    急激な市場環境の変化（分布シフト）に対応する。
    """
    
    def __init__(self, window: int = 60):
        self.window = window
    
    def normalize(self, series: pd.Series) -> pd.Series:
        """
        Apply rolling Z-score normalization.
        """
        rolling_mean = series.rolling(window=self.window).mean()
        rolling_std = series.rolling(window=self.window).std()
        
        # ゼロ除算を回避
        z_score = (series - rolling_mean) / rolling_std.replace(0, 1)
        
        return z_score
    
    def normalize_df(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Apply rolling Z-score normalization to all columns of a DataFrame.
        """
        normalized = df.apply(self.normalize)
        return normalized


class MACD(AlphaFactor):
    """
    MACD (Moving Average Convergence Divergence)
    
    トレンドの方向性とモメンタムを測定する指標。
    
    計算:
    - MACD Line = EMA(12) - EMA(26)
    - Signal Line = EMA(9) of MACD Line
    - Histogram = MACD Line - Signal Line
    """
    
    def __init__(self, fast: int = 12, slow: int = 26, signal: int = 9):
        self.fast = fast
        self.slow = slow
        self.signal = signal
    
    def calculate(self, data: pd.DataFrame) -> pd.DataFrame:
        """
        Expects data to have column: 'Close'
        Returns: DataFrame with MACD, Signal, Histogram
        """
        close = data['Close']
        
        # EMA計算
        ema_fast = close.ewm(span=self.fast, adjust=False).mean()
        ema_slow = close.ewm(span=self.slow, adjust=False).mean()
        
        # MACD Line
        macd_line = ema_fast - ema_slow
        
        # Signal Line
        signal_line = macd_line.ewm(span=self.signal, adjust=False).mean()
        
        # Histogram
        histogram = macd_line - signal_line
        
        return pd.DataFrame({
            'MACD': macd_line,
            'MACD_Signal': signal_line,
            'MACD_Hist': histogram
        })


class CCI(AlphaFactor):
    """
    CCI (Commodity Channel Index)
    
    買われすぎ/売られすぎを判定する指標。
    +100以上で買われすぎ、-100以下で売られすぎ。
    
    計算:
    CCI = (TP - SMA(TP)) / (0.015 × MAD(TP))
    TP (Typical Price) = (High + Low + Close) / 3
    """
    
    def __init__(self, period: int = 20):
        self.period = period
    
    def calculate(self, data: pd.DataFrame) -> pd.Series:
        """
        Expects data to have columns: 'High', 'Low', 'Close'
        Returns: pd.Series of CCI values
        """
        # Typical Price
        tp = (data['High'] + data['Low'] + data['Close']) / 3
        
        # SMA of Typical Price
        sma_tp = tp.rolling(window=self.period).mean()
        
        # Mean Absolute Deviation
        mad = tp.rolling(window=self.period).apply(
            lambda x: np.abs(x - x.mean()).mean(), raw=True
        )
        
        # CCI計算 (0.015は定数)
        cci = (tp - sma_tp) / (0.015 * mad)
        
        return cci


class ADX(AlphaFactor):
    """
    ADX (Average Directional Index)
    
    トレンドの強さを測定する指標（0-100）。
    25以上でトレンドあり、40以上で強いトレンド。
    
    計算:
    - +DM = High(t) - High(t-1) (if > 0 and > -DM)
    - -DM = Low(t-1) - Low(t) (if > 0 and > +DM)
    - +DI = 100 × Smoothed(+DM) / ATR
    - -DI = 100 × Smoothed(-DM) / ATR
    - DX = 100 × |+DI - -DI| / (+DI + -DI)
    - ADX = Smoothed(DX)
    """
    
    def __init__(self, period: int = 14):
        self.period = period
    
    def calculate(self, data: pd.DataFrame) -> pd.DataFrame:
        """
        Expects data to have columns: 'High', 'Low', 'Close'
        Returns: DataFrame with ADX, +DI, -DI
        """
        high = data['High']
        low = data['Low']
        close = data['Close']
        
        # True Range
        tr1 = high - low
        tr2 = abs(high - close.shift(1))
        tr3 = abs(low - close.shift(1))
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        
        # +DM, -DM
        up_move = high - high.shift(1)
        down_move = low.shift(1) - low
        
        plus_dm = np.where((up_move > down_move) & (up_move > 0), up_move, 0)
        minus_dm = np.where((down_move > up_move) & (down_move > 0), down_move, 0)
        
        plus_dm = pd.Series(plus_dm, index=data.index)
        minus_dm = pd.Series(minus_dm, index=data.index)
        
        # Smoothed values (Wilder's smoothing)
        atr = tr.ewm(alpha=1/self.period, adjust=False).mean()
        plus_di = 100 * plus_dm.ewm(alpha=1/self.period, adjust=False).mean() / atr
        minus_di = 100 * minus_dm.ewm(alpha=1/self.period, adjust=False).mean() / atr
        
        # DX
        dx = 100 * abs(plus_di - minus_di) / (plus_di + minus_di + 1e-10)
        
        # ADX (smoothed DX)
        adx = dx.ewm(alpha=1/self.period, adjust=False).mean()
        
        return pd.DataFrame({
            'ADX': adx,
            'Plus_DI': plus_di,
            'Minus_DI': minus_di
        })


class GARCHVolatilityFeature(AlphaFactor):
    """
    GARCH(1,3)ボラティリティ予測に基づくシグナル生成

    日足データを用いてGARCHモデルを構築し、
    予測プレミアム（予測分散 vs 実現分散の乖離）からシグナルを生成する。
    
    シグナル:
    - +1: High Volatility Premium (プレミアム > +1.5σ)
    - -1: Low Volatility Premium (プレミアム < -1.5σ)
    - 0: Neutral
    """
    
    def __init__(self, rolling_window: int = 180, sigma_threshold: float = 1.5):
        """
        Args:
            rolling_window: GARCHモデルを適用するローリングウィンドウ日数
            sigma_threshold: シグナル判定の標準偏差閾値
        """
        self.rolling_window = rolling_window
        self.sigma_threshold = sigma_threshold
        self._daily_signals = None  # キャッシュ用
        
    def fit_daily(self, daily_data: pd.DataFrame) -> pd.DataFrame:
        """
        日足データからGARCHシグナルを計算し、日付-シグナルのDataFrameを返す。
        
        Args:
            daily_data: 日足データ (OHLC)。Timestampインデックス必須。
        
        Returns:
            DataFrame with columns: ['Date', 'GARCH_Signal', 'Prediction_Premium']
        """
        try:
            from arch import arch_model
        except ImportError:
            print("[WARNING] arch library not installed. Using fallback volatility.")
            return self._fallback_signal(daily_data)
        
        # 対数リターンを計算
        returns = np.log(daily_data['Close'] / daily_data['Close'].shift(1)).dropna() * 100
        
        signals = []
        premiums = []
        dates = []
        
        # ローリングウィンドウでGARCHを適用
        for i in range(self.rolling_window, len(returns)):
            window_returns = returns.iloc[i - self.rolling_window:i]
            
            try:
                # GARCH(1,3)モデルを適合
                model = arch_model(window_returns, vol='Garch', p=1, q=3, rescale=False)
                result = model.fit(disp='off', show_warning=False)
                
                # 1日先の分散を予測
                forecast = result.forecast(horizon=1)
                predicted_var = forecast.variance.iloc[-1, 0]
                
                # 実現分散（次の日の実際のリターン^2）
                if i < len(returns):
                    realized_var = returns.iloc[i] ** 2
                else:
                    realized_var = predicted_var  # フォールバック
                
                # 予測プレミアム
                if realized_var > 0:
                    premium = (predicted_var - realized_var) / realized_var
                else:
                    premium = 0.0
                    
            except Exception as e:
                # モデルが収束しない場合など
                premium = 0.0
            
            premiums.append(premium)
            dates.append(returns.index[i])
        
        # プレミアムのローリング標準偏差
        premium_series = pd.Series(premiums)
        rolling_std = premium_series.rolling(window=126).std()  # 約6ヶ月
        
        # シグナル生成
        for i, premium in enumerate(premiums):
            if i < 126:  # 標準偏差計算に必要な最低期間
                signal = 0
            else:
                std = rolling_std.iloc[i]
                if std > 0:
                    if premium > self.sigma_threshold * std:
                        signal = 1  # High Vol Premium -> Short signal
                    elif premium < -self.sigma_threshold * std:
                        signal = -1  # Low Vol Premium -> Long signal
                    else:
                        signal = 0
                else:
                    signal = 0
            signals.append(signal)
        
        result_df = pd.DataFrame({
            'Date': dates,
            'GARCH_Signal': signals,
            'Prediction_Premium': premiums
        })
        result_df['Date'] = pd.to_datetime(result_df['Date']).dt.date
        
        self._daily_signals = result_df
        return result_df
    
    def _fallback_signal(self, daily_data: pd.DataFrame) -> pd.DataFrame:
        """archがインストールされていない場合のフォールバック"""
        dates = daily_data.index[self.rolling_window:].date
        signals = [0] * len(dates)
        premiums = [0.0] * len(dates)
        
        return pd.DataFrame({
            'Date': dates,
            'GARCH_Signal': signals,
            'Prediction_Premium': premiums
        })
    
    def get_signal_for_date(self, date) -> int:
        """
        指定された日付のGARCHシグナルを返す。
        fit_daily()を事前に呼び出す必要がある。
        """
        if self._daily_signals is None:
            return 0
        
        if hasattr(date, 'date'):
            date = date.date()
        
        match = self._daily_signals[self._daily_signals['Date'] == date]
        if not match.empty:
            return int(match['GARCH_Signal'].iloc[0])
        return 0
    
    def calculate(self, data: pd.DataFrame) -> pd.Series:
        """
        AlphaFactorインターフェース互換。
        日足データが渡された場合、シグナルのSeriesを返す。
        """
        result = self.fit_daily(data)
        return pd.Series(result['GARCH_Signal'].values, index=result['Date'])

