"""MT5 Native Inference Server — NON-CANONICAL (Windows/MT5専用)

注意:
- これは MetaTrader5 Python API に依存する「MT5ネイティブ接続」用途。
- Docker(GPU) の正本は `inference_server_http_7module.py`（/health,/analyze,/predict）。

"""
MT5 Native Inference Server
OANDA MT5 ネイティブ接続を使用した推論サーバー

MetaTrader5 Python APIを使用して直接市場データを取得し、
16モジュール推論エンジンを実行します。

使用方法:
1. OANDA MT5 ターミナルを起動
2. このスクリプトを実行: python inference_server_mt5.py
3. API経由で推論リクエストを送信: POST /predict
"""

import os
import sys
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import numpy as np

# Flask
from flask import Flask, request, jsonify

# MetaTrader5 ライブラリ
try:
    import MetaTrader5 as Mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False
    print("[WARNING] MetaTrader5 library not installed. Run: pip install MetaTrader5")

# サブモジュールへのパスを追加
SCRIPT_DIR = Path(__file__).parent.resolve()
SUBMODULE_PYTHON = SCRIPT_DIR / "external" / "mt4-pullback-trader" / "python"
if SUBMODULE_PYTHON.exists():
    sys.path.insert(0, str(SUBMODULE_PYTHON))

# ロガー（サブモジュールから、なければ標準ログ）
try:
    from common.logger import get_inference_logger
    logger = get_inference_logger()
except ImportError:
    import logging
    logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
    logger = logging.getLogger("MT5InferenceServer")
    logger.log_signal = lambda *args, **kwargs: None  # ダミー

# シグナル分析モジュール（サブモジュールから）
try:
    from modules import (
        CandlePatternsModule,
        ChartPatternsModule,
        FalseBreakoutModule,
        WaveStructureModule,
        StructuralModule,
        TechnicalModule,
        TrendModule,
        VolatilityModule,
    )
    from signal_engine.signal_aggregator import SignalAggregator, ModuleScore
    MODULES_AVAILABLE = True
except ImportError as e:
    MODULES_AVAILABLE = False
    print(f"[WARNING] Signal modules not available: {e}")

# =============================================================================
# MT5 データプロバイダ
# =============================================================================

class MT5DataProvider:
    """OANDA MT5からリアルタイムデータを取得するプロバイダ"""
    
    TIMEFRAME_MAP = {
        'M1': Mt5.TIMEFRAME_M1 if MT5_AVAILABLE else 1,
        'M5': Mt5.TIMEFRAME_M5 if MT5_AVAILABLE else 5,
        'M15': Mt5.TIMEFRAME_M15 if MT5_AVAILABLE else 15,
        'M30': Mt5.TIMEFRAME_M30 if MT5_AVAILABLE else 30,
        'H1': Mt5.TIMEFRAME_H1 if MT5_AVAILABLE else 60,
        'H4': Mt5.TIMEFRAME_H4 if MT5_AVAILABLE else 240,
        'D1': Mt5.TIMEFRAME_D1 if MT5_AVAILABLE else 1440,
        'W1': Mt5.TIMEFRAME_W1 if MT5_AVAILABLE else 10080,
    }
    
    def __init__(self):
        self.initialized = False
        self.account_info = None
    
    def initialize(self) -> bool:
        """MT5ターミナルに接続"""
        if not MT5_AVAILABLE:
            logger.error("MetaTrader5 library is not installed")
            return False
        
        if not Mt5.initialize():
            logger.error(f"MT5 initialize failed: {Mt5.last_error()}")
            return False
        
        self.account_info = Mt5.account_info()
        if self.account_info is None:
            logger.error("Failed to get account info")
            Mt5.shutdown()
            return False
        
        self.initialized = True
        logger.info(f"MT5 connected: Account={self.account_info.login}, Server={self.account_info.server}")
        return True
    
    def shutdown(self):
        """MT5接続を切断"""
        if MT5_AVAILABLE and self.initialized:
            Mt5.shutdown()
            self.initialized = False
            logger.info("MT5 disconnected")
    
    def get_rates(self, symbol: str, timeframe: str, count: int = 100) -> Optional[np.ndarray]:
        """
        指定銘柄・時間足のOHLCVデータを取得
        
        Returns:
            numpy structured array with columns: time, open, high, low, close, tick_volume, spread, real_volume
        """
        if not self.initialized:
            logger.warning("MT5 not initialized")
            return None
        
        tf = self.TIMEFRAME_MAP.get(timeframe.upper())
        if tf is None:
            logger.warning(f"Unknown timeframe: {timeframe}")
            return None
        
        # シンボル正規化（OANDAフォーマット）
        oanda_symbol = self._normalize_symbol(symbol)
        
        rates = Mt5.copy_rates_from_pos(oanda_symbol, tf, 0, count)
        if rates is None or len(rates) == 0:
            logger.warning(f"No data for {oanda_symbol} {timeframe}: {Mt5.last_error()}")
            return None
        
        return rates
    
    def get_tick(self, symbol: str) -> Optional[Dict]:
        """最新ティックを取得"""
        if not self.initialized:
            return None
        
        oanda_symbol = self._normalize_symbol(symbol)
        tick = Mt5.symbol_info_tick(oanda_symbol)
        if tick is None:
            return None
        
        return {
            'bid': tick.bid,
            'ask': tick.ask,
            'last': tick.last,
            'volume': tick.volume,
            'time': datetime.fromtimestamp(tick.time),
        }
    
    def get_symbol_info(self, symbol: str) -> Optional[Dict]:
        """シンボル情報を取得"""
        if not self.initialized:
            return None
        
        oanda_symbol = self._normalize_symbol(symbol)
        info = Mt5.symbol_info(oanda_symbol)
        if info is None:
            return None
        
        return {
            'name': info.name,
            'digits': info.digits,
            'point': info.point,
            'spread': info.spread,
            'trade_mode': info.trade_mode,
            'volume_min': info.volume_min,
            'volume_max': info.volume_max,
            'volume_step': info.volume_step,
        }
    
    def _normalize_symbol(self, symbol: str) -> str:
        """
        シンボル名をOANDAフォーマットに変換
        例: USDJPY -> USD/JPY, JP225 -> JP225_JPY
        """
        symbol = symbol.upper().replace('.MT4', '').replace('.MT5', '')
        
        # FX通貨ペア（6文字）
        if len(symbol) == 6 and symbol.isalpha():
            return f"{symbol[:3]}/{symbol[3:]}"
        
        # 株価指数
        index_map = {
            'JP225': 'JP225_JPY',
            'US30': 'US30_USD',
            'US500': 'SPX500_USD',
            'NQ100': 'NAS100_USD',
            'NIKKEI225': 'JP225_JPY',
        }
        return index_map.get(symbol, symbol)


# =============================================================================
# 8モジュール分析エンジン
# =============================================================================

class MT5SignalAnalyzer:
    """MT5データを分析する8モジュール統合エンジン"""
    
    def __init__(self, data_provider: MT5DataProvider):
        self.data_provider = data_provider
        
        if MODULES_AVAILABLE:
            self.candle_patterns = CandlePatternsModule(min_confidence=0.5)
            self.chart_patterns = ChartPatternsModule()
            self.false_breakout = FalseBreakoutModule()
            self.technical = TechnicalModule()
            self.trend = TrendModule()
            self.wave_structure = WaveStructureModule()
            self.structural = StructuralModule()
            self.volatility = VolatilityModule(atr_period=14, threshold_pips=7.0, is_index=False)
            logger.info("8-Module Analyzer initialized")
        else:
            logger.warning("Modules not available, using dummy analyzer")
    
    def analyze(self, symbol: str, timeframe: str = 'M15') -> Dict:
        """
        指定銘柄・時間足を分析してシグナルを返す
        
        Returns:
            {
                'signal': 1/-1/0,
                'confidence': 0.0-1.0,
                'reason': str,
                'module_breakdown': {...},
                'market_data': {...}
            }
        """
        # データ取得
        rates = self.data_provider.get_rates(symbol, timeframe, count=100)
        if rates is None:
            return {
                'signal': 0,
                'confidence': 0.0,
                'reason': f'No data available for {symbol} {timeframe}',
                'error': True
            }
        
        # numpy配列に変換
        opens = rates['open']
        highs = rates['high']
        lows = rates['low']
        closes = rates['close']
        volumes = rates['tick_volume'].astype(float)
        
        if not MODULES_AVAILABLE:
            # モジュールがない場合は簡易分析
            return self._simple_analysis(opens, highs, lows, closes, symbol, timeframe)
        
        # テクニカル指標を計算
        ema12 = self._calc_ema(closes, 12)
        ema25 = self._calc_ema(closes, 25)
        ema100 = self._calc_ema(closes, 100)
        macd_main = ema12 - ema25
        macd_signal = self._calc_ema(macd_main, 9)
        rsi = self._calc_rsi(closes, 14)
        
        # 各モジュールで分析
        module_scores = {}
        
        try:
            module_scores['candle_patterns'] = self.candle_patterns.analyze(
                opens=opens, highs=highs, lows=lows, closes=closes, volumes=volumes
            )
        except Exception as e:
            module_scores['candle_patterns'] = ModuleScore(0, 0.0, f"Error: {e}")
        
        try:
            module_scores['chart_patterns'] = self.chart_patterns.analyze(
                opens=opens, highs=highs, lows=lows, closes=closes
            )
        except Exception as e:
            module_scores['chart_patterns'] = ModuleScore(0, 0.0, f"Error: {e}")
        
        try:
            module_scores['false_breakout'] = self.false_breakout.analyze(
                opens=opens, highs=highs, lows=lows, closes=closes
            )
        except Exception as e:
            module_scores['false_breakout'] = ModuleScore(0, 0.0, f"Error: {e}")
        
        try:
            module_scores['technical'] = self.technical.analyze(
                closes=closes, macd_main=macd_main, macd_signal=macd_signal, rsi=rsi
            )
        except Exception as e:
            module_scores['technical'] = ModuleScore(0, 0.0, f"Error: {e}")
        
        try:
            module_scores['trend'] = self.trend.analyze(
                closes=closes, ema12=ema12, ema25=ema25, ema100=ema100
            )
        except Exception as e:
            module_scores['trend'] = ModuleScore(0, 0.0, f"Error: {e}")
        
        try:
            module_scores['wave_structure'] = self.wave_structure.analyze(
                open_prices=opens, high_prices=highs, low_prices=lows, close_prices=closes
            )
        except Exception as e:
            module_scores['wave_structure'] = ModuleScore(0, 0.0, f"Error: {e}")
        
        try:
            module_scores['structural'] = self.structural.analyze(
                open_prices=opens, high_prices=highs, low_prices=lows, close_prices=closes
            )
        except Exception as e:
            module_scores['structural'] = ModuleScore(0, 0.0, f"Error: {e}")
        
        # シグナル統合
        return self._aggregate_signals(module_scores, symbol, timeframe, closes, ema12, ema25)
    
    def _aggregate_signals(self, module_scores: Dict, symbol: str, timeframe: str,
                           closes: np.ndarray, ema12: np.ndarray, ema25: np.ndarray) -> Dict:
        """モジュールスコアを統合してシグナルを生成"""
        # 重み付け
        weights = {
            'chart_patterns': 0.25,
            'false_breakout': 0.20,
            'candle_patterns': 0.15,
            'technical': 0.15,
            'trend': 0.10,
            'wave_structure': 0.10,
            'structural': 0.05,
        }
        
        total_score = 0.0
        total_weight = 0.0
        breakdown = {}
        
        for name, score in module_scores.items():
            if name not in weights:
                continue
            
            weight = weights[name]
            signal_value = score.signal.value if hasattr(score.signal, 'value') else int(score.signal)
            weighted = signal_value * score.confidence * weight
            total_score += weighted
            total_weight += weight
            
            breakdown[name] = {
                'signal': signal_value,
                'confidence': round(score.confidence, 3),
                'reason': score.reason,
                'weighted': round(weighted, 3)
            }
        
        # 最終シグナル
        if total_weight > 0:
            avg_score = total_score / total_weight
        else:
            avg_score = 0.0
        
        if avg_score > 0.3:
            signal = 1
        elif avg_score < -0.3:
            signal = -1
        else:
            signal = 0
        
        confidence = min(abs(avg_score) * 1.5, 1.0)
        signal_name = {1: 'BUY', -1: 'SELL', 0: 'NEUTRAL'}[signal]
        
        return {
            'signal': signal,
            'signal_name': signal_name,
            'confidence': round(confidence, 3),
            'reason': f"8-Module Analysis: avg_score={avg_score:.3f}",
            'module_breakdown': breakdown,
            'market_data': {
                'symbol': symbol,
                'timeframe': timeframe,
                'close': float(closes[-1]),
                'ema12': float(ema12[-1]),
                'ema25': float(ema25[-1]),
            },
            'timestamp': datetime.now().isoformat()
        }
    
    def _simple_analysis(self, opens, highs, lows, closes, symbol, timeframe) -> Dict:
        """モジュールがない場合の簡易分析"""
        ema12 = self._calc_ema(closes, 12)
        ema25 = self._calc_ema(closes, 25)
        
        signal = 0
        confidence = 0.5
        reason = "Simple EMA analysis"
        
        if ema12[-1] > ema25[-1] and closes[-1] > closes[-2] > closes[-3]:
            signal = 1
            confidence = 0.65
            reason = "EMA12 > EMA25 + 3-bar uptrend"
        elif ema12[-1] < ema25[-1] and closes[-1] < closes[-2] < closes[-3]:
            signal = -1
            confidence = 0.65
            reason = "EMA12 < EMA25 + 3-bar downtrend"
        
        return {
            'signal': signal,
            'signal_name': {1: 'BUY', -1: 'SELL', 0: 'NEUTRAL'}[signal],
            'confidence': confidence,
            'reason': reason,
            'market_data': {
                'symbol': symbol,
                'timeframe': timeframe,
                'close': float(closes[-1]),
                'ema12': float(ema12[-1]),
                'ema25': float(ema25[-1]),
            },
            'timestamp': datetime.now().isoformat()
        }
    
    @staticmethod
    def _calc_ema(data: np.ndarray, period: int) -> np.ndarray:
        """EMA計算"""
        alpha = 2 / (period + 1)
        result = np.zeros_like(data, dtype=float)
        result[0] = data[0]
        for i in range(1, len(data)):
            result[i] = alpha * data[i] + (1 - alpha) * result[i-1]
        return result
    
    @staticmethod
    def _calc_rsi(closes: np.ndarray, period: int = 14) -> np.ndarray:
        """RSI計算"""
        if len(closes) < period + 1:
            return np.ones_like(closes) * 50.0
        
        deltas = np.diff(closes)
        gains = np.where(deltas > 0, deltas, 0)
        losses = np.where(deltas < 0, -deltas, 0)
        
        rsi = np.zeros(len(closes))
        rsi[:period] = 50.0
        
        avg_gain = np.mean(gains[:period])
        avg_loss = np.mean(losses[:period])
        
        for i in range(period, len(closes) - 1):
            avg_gain = (avg_gain * (period - 1) + gains[i]) / period
            avg_loss = (avg_loss * (period - 1) + losses[i]) / period
            
            if avg_loss > 0:
                rs = avg_gain / avg_loss
                rsi[i + 1] = 100 - (100 / (1 + rs))
            else:
                rsi[i + 1] = 100
        
        return rsi


# =============================================================================
# Flask API
# =============================================================================

app = Flask(__name__)
data_provider: Optional[MT5DataProvider] = None
analyzer: Optional[MT5SignalAnalyzer] = None


@app.route('/health', methods=['GET'])
def health_check():
    """ヘルスチェック"""
    mt5_status = "connected" if (data_provider and data_provider.initialized) else "disconnected"
    return jsonify({
        'status': 'ok',
        'mt5_status': mt5_status,
        'modules_available': MODULES_AVAILABLE,
        'timestamp': datetime.now().isoformat(),
    }), 200


@app.route('/predict', methods=['POST'])
def predict():
    """
    推論エンドポイント（MT5ネイティブ版）
    
    リクエスト形式:
    {
        "symbol": "USDJPY",
        "timeframe": "M15"
    }
    """
    if analyzer is None:
        return jsonify({'error': 'Analyzer not initialized'}), 500
    
    try:
        data = request.get_json() or {}
        symbol = data.get('symbol', 'USDJPY')
        timeframe = data.get('timeframe', 'M15')
        
        result = analyzer.analyze(symbol, timeframe)
        
        # ログ記録
        logger.info(f"Prediction: {symbol} {timeframe} -> {result['signal_name']} ({result['confidence']:.2f})")
        if hasattr(logger, 'log_signal'):
            logger.log_signal(symbol, result['signal_name'], result['confidence'], 
                             list(result.get('module_breakdown', {}).keys()), result['reason'])
        
        return jsonify(result), 200
        
    except Exception as e:
        logger.error(f"Prediction error: {e}")
        return jsonify({'error': str(e), 'timestamp': datetime.now().isoformat()}), 500


@app.route('/analyze', methods=['POST'])
def analyze():
    """
    分析エンドポイント（MT4/MT5 HTTP EA互換）
    
    リクエスト形式:
    {
        "symbol": "USD/JPY",
        "timeframe": "M15",
        "ohlcv": {
            "open": [...],
            "high": [...],
            "low": [...],
            "close": [...],
            "volume": [...]
        },
        "current_price": 150.123
    }
    
    レスポンス形式:
    {
        "signal": 1/-1/0,
        "confidence": 0.75,
        "entry_allowed": true/false,
        "reason": "...",
        "module_breakdown": {...}
    }
    """
    try:
        data = request.get_json() or {}
        symbol = data.get('symbol', 'USDJPY')
        timeframe = data.get('timeframe', 'M15')
        ohlcv = data.get('ohlcv', {})
        
        if not ohlcv:
            return jsonify({
                'signal': 0,
                'confidence': 0.0,
                'entry_allowed': False,
                'reason': 'No OHLCV data provided'
            }), 400
        
        # OHLCV データを numpy 配列に変換
        opens = np.array(ohlcv.get('open', []), dtype=float)
        highs = np.array(ohlcv.get('high', []), dtype=float)
        lows = np.array(ohlcv.get('low', []), dtype=float)
        closes = np.array(ohlcv.get('close', []), dtype=float)
        volumes = np.array(ohlcv.get('volume', []), dtype=float)
        
        if len(closes) < 20:
            return jsonify({
                'signal': 0,
                'confidence': 0.0,
                'entry_allowed': False,
                'reason': f'Insufficient data: {len(closes)} bars (need >= 20)'
            }), 400
        
        # モジュール分析実行
        if analyzer is None or not MODULES_AVAILABLE:
            # 簡易分析
            result = simple_analyze(opens, highs, lows, closes, symbol)
        else:
            # 16モジュール分析
            result = full_module_analyze(opens, highs, lows, closes, volumes, symbol, timeframe)
        
        logger.info(f"Analyze: {symbol} {timeframe} -> signal={result['signal']} conf={result['confidence']:.3f}")
        
        return jsonify(result), 200
        
    except Exception as e:
        logger.error(f"Analyze error: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'signal': 0,
            'confidence': 0.0,
            'entry_allowed': False,
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500


def simple_analyze(opens, highs, lows, closes, symbol):
    """モジュールがない場合の簡易分析"""
    # EMA計算
    def calc_ema(data, period):
        alpha = 2 / (period + 1)
        result = np.zeros_like(data, dtype=float)
        result[0] = data[0]
        for i in range(1, len(data)):
            result[i] = alpha * data[i] + (1 - alpha) * result[i-1]
        return result
    
    ema12 = calc_ema(closes, 12)
    ema25 = calc_ema(closes, 25)
    
    signal = 0
    confidence = 0.5
    reason = "Simple EMA analysis"
    
    if ema12[-1] > ema25[-1] and closes[-1] > closes[-2] > closes[-3]:
        signal = 1
        confidence = 0.65
        reason = "EMA12 > EMA25 + 3-bar uptrend"
    elif ema12[-1] < ema25[-1] and closes[-1] < closes[-2] < closes[-3]:
        signal = -1
        confidence = 0.65
        reason = "EMA12 < EMA25 + 3-bar downtrend"
    
    return {
        'signal': signal,
        'confidence': confidence,
        'entry_allowed': abs(signal) > 0 and confidence >= 0.6,
        'reason': reason,
        'module_breakdown': {},
        'timestamp': datetime.now().isoformat()
    }


def full_module_analyze(opens, highs, lows, closes, volumes, symbol, timeframe):
    """16モジュール分析"""
    # テクニカル指標計算
    def calc_ema(data, period):
        alpha = 2 / (period + 1)
        result = np.zeros_like(data, dtype=float)
        result[0] = data[0]
        for i in range(1, len(data)):
            result[i] = alpha * data[i] + (1 - alpha) * result[i-1]
        return result
    
    def calc_rsi(closes, period=14):
        if len(closes) < period + 1:
            return np.ones_like(closes) * 50.0
        deltas = np.diff(closes)
        gains = np.where(deltas > 0, deltas, 0)
        losses = np.where(deltas < 0, -deltas, 0)
        rsi = np.zeros(len(closes))
        rsi[:period] = 50.0
        avg_gain = np.mean(gains[:period])
        avg_loss = np.mean(losses[:period])
        for i in range(period, len(closes) - 1):
            avg_gain = (avg_gain * (period - 1) + gains[i]) / period
            avg_loss = (avg_loss * (period - 1) + losses[i]) / period
            if avg_loss > 0:
                rs = avg_gain / avg_loss
                rsi[i + 1] = 100 - (100 / (1 + rs))
            else:
                rsi[i + 1] = 100
        return rsi
    
    ema12 = calc_ema(closes, 12)
    ema25 = calc_ema(closes, 25)
    ema100 = calc_ema(closes, 100)
    macd_main = ema12 - ema25
    macd_signal = calc_ema(macd_main, 9)
    rsi = calc_rsi(closes, 14)
    
    module_scores = {}
    
    # 各モジュールで分析
    try:
        from modules import (
            CandlePatternsModule, ChartPatternsModule, FalseBreakoutModule,
            TechnicalModule, TrendModule, WaveStructureModule, StructuralModule
        )
        
        candle = CandlePatternsModule(min_confidence=0.5)
        module_scores['candle_patterns'] = candle.analyze(
            opens=opens, highs=highs, lows=lows, closes=closes, volumes=volumes
        )
    except Exception as e:
        logger.warning(f"Candle module error: {e}")
    
    try:
        chart = ChartPatternsModule()
        module_scores['chart_patterns'] = chart.analyze(
            opens=opens, highs=highs, lows=lows, closes=closes
        )
    except Exception as e:
        logger.warning(f"Chart module error: {e}")
    
    try:
        technical = TechnicalModule()
        module_scores['technical'] = technical.analyze(
            closes=closes, macd_main=macd_main, macd_signal=macd_signal, rsi=rsi
        )
    except Exception as e:
        logger.warning(f"Technical module error: {e}")
    
    try:
        trend = TrendModule()
        module_scores['trend'] = trend.analyze(
            closes=closes, ema12=ema12, ema25=ema25, ema100=ema100
        )
    except Exception as e:
        logger.warning(f"Trend module error: {e}")
    
    # シグナル統合
    weights = {
        'chart_patterns': 0.25,
        'candle_patterns': 0.20,
        'technical': 0.20,
        'trend': 0.15,
        'wave_structure': 0.10,
        'structural': 0.10,
    }
    
    total_score = 0.0
    total_weight = 0.0
    breakdown = {}
    
    for name, score in module_scores.items():
        if name not in weights:
            continue
        
        weight = weights[name]
        signal_value = score.signal.value if hasattr(score.signal, 'value') else int(score.signal)
        weighted = signal_value * score.confidence * weight
        total_score += weighted
        total_weight += weight
        
        breakdown[name] = {
            'signal': signal_value,
            'confidence': round(score.confidence, 3),
            'reason': score.reason,
            'weighted': round(weighted, 3)
        }
    
    # 最終シグナル
    if total_weight > 0:
        avg_score = total_score / total_weight
    else:
        avg_score = 0.0
    
    if avg_score > 0.3:
        signal = 1
    elif avg_score < -0.3:
        signal = -1
    else:
        signal = 0
    
    confidence = min(abs(avg_score) * 1.5, 1.0)
    entry_allowed = abs(signal) > 0 and confidence >= 0.6
    
    return {
        'signal': signal,
        'confidence': round(confidence, 3),
        'entry_allowed': entry_allowed,
        'reason': f"Module analysis: avg_score={avg_score:.3f}",
        'module_breakdown': breakdown,
        'timestamp': datetime.now().isoformat()
    }


@app.route('/test_data/<symbol>', methods=['GET'])
def test_data(symbol: str):
    """MT5データ取得テスト"""
    if data_provider is None or not data_provider.initialized:
        return jsonify({'error': 'MT5 not connected'}), 500
    
    timeframe = request.args.get('timeframe', 'M15')
    count = int(request.args.get('count', 10))
    
    rates = data_provider.get_rates(symbol, timeframe, count)
    if rates is None:
        return jsonify({'error': f'No data for {symbol}'}), 404
    
    # numpy配列をリストに変換
    data_list = []
    for r in rates:
        data_list.append({
            'time': datetime.fromtimestamp(r['time']).isoformat(),
            'open': float(r['open']),
            'high': float(r['high']),
            'low': float(r['low']),
            'close': float(r['close']),
            'volume': int(r['tick_volume']),
        })
    
    return jsonify({
        'symbol': symbol,
        'timeframe': timeframe,
        'count': len(data_list),
        'data': data_list
    }), 200


@app.route('/symbols', methods=['GET'])
def list_symbols():
    """利用可能なシンボル一覧"""
    if not MT5_AVAILABLE or data_provider is None or not data_provider.initialized:
        return jsonify({'error': 'MT5 not connected'}), 500
    
    symbols = Mt5.symbols_get()
    if symbols is None:
        return jsonify({'error': 'Failed to get symbols'}), 500
    
    symbol_list = [s.name for s in symbols if s.visible]
    return jsonify({
        'count': len(symbol_list),
        'symbols': symbol_list[:50]  # 最初の50個のみ
    }), 200


# =============================================================================
# メイン
# =============================================================================

def main():
    global data_provider, analyzer
    
    logger.info("=" * 60)
    logger.info("MT5 Native Inference Server Starting...")
    logger.info("=" * 60)
    
    # MT5接続
    data_provider = MT5DataProvider()
    if not data_provider.initialize():
        logger.error("Failed to connect to MT5. Make sure OANDA MT5 terminal is running.")
        logger.info("Server will start in limited mode (no live data)")
    
    # アナライザー初期化
    analyzer = MT5SignalAnalyzer(data_provider)
    
    logger.info(f"Modules available: {MODULES_AVAILABLE}")
    logger.info("Endpoints: GET /health, POST /predict, GET /test_data/<symbol>, GET /symbols")
    logger.info("Server running on: http://localhost:5001")
    logger.info("=" * 60)
    
    try:
        app.run(host='0.0.0.0', port=5001, debug=False, use_reloader=False)
    finally:
        if data_provider:
            data_provider.shutdown()


if __name__ == '__main__':
    main()
