"""
MT4 7-Module Inference Server
7モジュール統合 + PullbackModule + Antigravity + LLM + ログ学習を統合した推論サーバー

設計書TRADING_LOGIC_DESIGN.mdに基づく9モジュール:
- chart_patterns (15%): 三尊、Wトップ等
- false_breakout (12%): ダマシ検出
- candle_patterns (9%): ピンバー、包み足等
- technical (9%): MACD、RSI
- trend (6%): トレンド判定
- wave_structure (6%): ツーレッグ構造
- structural (3%): ピボット等
- pullback (20%): EMAプルバック/ラウンドナンバー ★NEW
- antigravity (20%): VPIN/GK-Vol/VWAP-Gap ★NEW
"""

import os
import sys
import time
import json
import csv
import os
import tempfile
import re
import numpy as np
from datetime import datetime, timedelta
from pathlib import Path
from typing import Tuple, Dict, List, Optional

# パスを追加
sys.path.insert(0, str(Path(__file__).parent))

# 統一ロガーをインポート
from common.logger import get_inference_logger
from ai_research.lm_client import LMStudioClient

# 9モジュールをインポート（7コアモジュール + PullbackModule + VolatilityModule）
from signal_engine.signal_aggregator import SignalAggregator, ModuleScore
from signal_engine.extended_aggregator import ExtendedSignalAggregator, AntigravityAdapter
from modules import (
    CandlePatternsModule,
    ChartPatternsModule,
    FalseBreakoutModule,
    WaveStructureModule,
    StructuralModule,
    TechnicalModule,
    TrendModule,
    VolatilityModule,
    PullbackModule,
    PullbackEMAReference,
    # ★NEW: 金融工学モジュール
    MomentumModule,
    MeanReversionModule,
    VolatilityBreakoutModule,
)

# ★NEW: 戦略プリセット
from strategy_presets import (
    get_preset, 
    get_atr_threshold, 
    get_enabled_modules,
    is_index_symbol,
    STRATEGY_PRESETS
)

# ★NEW: Antigravity Orchestrator（Transformer/KAN/VPIN/GARCH統合）
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))
try:
    from antigravity.core.orchestrator import AntigravityOrchestrator
    ANTIGRAVITY_AVAILABLE = True
except ImportError as e:
    ANTIGRAVITY_AVAILABLE = False
    print(f"[WARNING] Antigravity not available: {e}")

logger = get_inference_logger()


class BrainAdapter:
    """Brain (AI Market Dashboard) との連携アダプター"""
    
    def __init__(self, data_dir: str, enabled: bool = True, veto_mode: bool = True):
        self.enabled = enabled
        self.veto_mode = veto_mode
        self.plans_dir = Path(data_dir) / "plans"
        self.cached_plan = None
        self.cache_time = 0
        self.cache_ttl = 60  # 1分キャッシュ
        
        if self.enabled:
            logger.info(f"★ Brain Integration ENABLED (dir={self.plans_dir}, veto={veto_mode})")
        else:
            logger.info("Brain Integration DISABLED")

    def get_plan(self, symbol: str) -> Optional[Dict]:
        """指定されたシンボルの最新のアクティブなプランを取得"""
        if not self.enabled:
            return None
            
        current_time = time.time()
        # キャッシュ有効期限切れ、またはシンボル切り替え時（簡易実装のため毎回チェック推奨だが負荷軽減）
        # ファイルアクセスはそこまで重くないので、TTL内ならメモリキャッシュを返す
        if self.cached_plan and (current_time - self.cache_time < self.cache_ttl):
            if self.cached_plan.get('asset') == symbol:
                return self.cached_plan

        try:
            if not self.plans_dir.exists():
                return None
                
            # 今日の日付のプランを探す (e.g., plan_2025-12-16_USDJPY.json)
            today_str = datetime.now().strftime('%Y-%m-%d')
            # ファイル名パターン検索
            # symbolが "USDJPY" の場合、"USDJPY" を含むファイルを探す
            candidates = list(self.plans_dir.glob(f"plan_{today_str}_*.json"))
            
            target_plan = None
            for p in candidates:
                if symbol in p.name:
                    with open(p, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                        # status check (activeかどうか)
                        if data.get('status') == 'active' or data.get('status') is None:
                            target_plan = data
                            break
            
            if target_plan:
                self.cached_plan = target_plan
                self.cache_time = current_time
                return target_plan
                
        except Exception as e:
            logger.error(f"Brain plan load error: {e}")
            
        return None


class TradeHistory:
    """トレード履歴管理（ログ学習用）"""
    
    def __init__(self, history_file: Path):
        self.history_file = history_file
        self.trades: List[Dict] = []
        self._load_history()
    
    def _load_history(self):
        """履歴ファイルを読み込み"""
        if self.history_file.exists():
            try:
                with open(self.history_file, 'r', encoding='utf-8') as f:
                    self.trades = json.load(f)
                logger.info(f"Loaded {len(self.trades)} trades from history")
            except Exception as e:
                logger.error(f"Failed to load history: {e}")
                self.trades = []
    
    def _save_history(self):
        """履歴ファイルに保存"""
        try:
            with open(self.history_file, 'w', encoding='utf-8') as f:
                json.dump(self.trades, f, indent=2, ensure_ascii=False)
        except Exception as e:
            logger.error(f"Failed to save history: {e}")
    
    def add_signal(self, symbol: str, timeframe: str, signal: int, 
                   confidence: float, reason: str, market_data: Dict,
                   module_breakdown: Dict = None):
        """シグナル発生を記録"""
        trade = {
            'timestamp': datetime.now().isoformat(),
            'symbol': symbol,
            'timeframe': timeframe,
            'signal': signal,
            'signal_name': {1: 'BUY', -1: 'SELL', 0: 'WAIT'}[signal],
            'confidence': confidence,
            'reason': reason,
            'market_data': market_data,
            'module_breakdown': module_breakdown,
            'result': None,
            'pips': None
        }
        self.trades.append(trade)
        self._save_history()
        return len(self.trades) - 1
    
    def get_win_rate(self, symbol: str, signal: int, 
                     ema_bullish: bool, lookback_days: int = 30) -> Tuple[float, int]:
        """勝率を計算"""
        cutoff = datetime.now() - timedelta(days=lookback_days)
        wins = 0
        total = 0
        
        for trade in self.trades:
            try:
                trade_time = datetime.fromisoformat(trade['timestamp'])
                if trade_time < cutoff:
                    continue
            except:
                continue
            
            if (trade['symbol'] == symbol and 
                trade['signal'] == signal and
                trade.get('result') is not None):
                md = trade.get('market_data', {})
                trade_ema_bullish = float(md.get('ema12', 0)) > float(md.get('ema25', 0))
                if trade_ema_bullish == ema_bullish:
                    total += 1
                    if trade['result'] == 'win':
                        wins += 1
        
        win_rate = wins / total if total > 0 else 0.5
        return win_rate, total


class SevenModuleAnalyzer:
    """Antigravity Core + Sub-Modules 統合分析エンジン v4.0
    
    アーキテクチャ:
    - Antigravity Core (60%): Transformer + KAN + GARCH/VPIN
    - Sub-Modules (40%): Technical + Trend + Pullback + Others
    
    ★NEW: プリセットベースのモジュール選択
    - antigravity_only: AI予測のみ
    - antigravity_pullback: AI + プルバック（推奨）
    - antigravity_hedge: ヘッジモード特化
    - quantitative_pure: クオンツ純粋戦略
    - full: 全モジュール有効
    """
    
    def __init__(self, 
                 atr_threshold_fx: float = 7.0,
                 atr_threshold_index: float = 70.0,
                 strategy: str = 'antigravity',
                 preset_name: str = 'antigravity_pullback',  # ★NEW
                 enabled_modules: dict = None,  # ★NEW: 個別指定
                 use_antigravity: bool = True,
                 model_type: str = 'ensemble',
                 transformer_model_path: str = None,
                 kan_model_path: str = None,
                 daily_data_path: str = None,
                 max_position: int = 2,
                 hedge_mode: bool = False,
                 hedge_skip_trend: bool = True,
                 hedge_prioritize_mr: bool = True,
                 hedge_min_confidence: float = 0.70,
                 brain_enabled: bool = False,
                 brain_veto_mode: bool = True,
                 brain_plan_dir: str = None,
                 data_dir: str = "data"):
        """
        Args:
            atr_threshold_fx: FX用ATR閾値（pips）
            atr_threshold_index: 株価指数用ATR閾値（points）
            strategy: 戦略パターン ('antigravity', 'hybrid', 'legacy')
            preset_name: プリセット名 (★NEW)
            enabled_modules: モジュール有効/無効の個別指定 (★NEW)
            use_antigravity: Antigravity Orchestratorを使用するか
            model_type: 'transformer', 'kan', 'ensemble'
            transformer_model_path: Transformerモデルのパス
            kan_model_path: KANモデルのパス
            daily_data_path: GARCH用日足データのパス
            hedge_mode: ヘッジモード有効化（PullbackEntry補完）
            hedge_skip_trend: トレンド相場でエントリースキップ
            hedge_prioritize_mr: Mean Reversionシグナル優先
            hedge_min_confidence: ヘッジモード時の最小信頼度閾値
        """
        # ★NEW: プリセットからモジュール有効/無効を取得
        self.preset_name = preset_name
        if enabled_modules:
            self.enabled_modules = enabled_modules
        else:
            self.enabled_modules = get_enabled_modules(preset_name)
        
        logger.info(f"★ Preset: {preset_name} (enabled: {sum(1 for v in self.enabled_modules.values() if v)} modules)")
        
        # ヘッジモード設定
        self.hedge_mode = hedge_mode
        self.hedge_skip_trend = hedge_skip_trend
        self.hedge_prioritize_mr = hedge_prioritize_mr
        self.hedge_min_confidence = hedge_min_confidence
        
        if self.hedge_mode:
            logger.info(f"★ Hedge Mode ENABLED (skip_trend={hedge_skip_trend}, mr_priority={hedge_prioritize_mr}, min_conf={hedge_min_confidence})")
            
        # Brain初期化
        self.brain = BrainAdapter(data_dir=data_dir, enabled=brain_enabled, veto_mode=brain_veto_mode)
        
        # 7コアモジュール初期化
        self.candle_patterns = CandlePatternsModule(min_confidence=0.5)
        self.chart_patterns = ChartPatternsModule()
        self.false_breakout = FalseBreakoutModule()
        self.technical = TechnicalModule()
        self.trend = TrendModule()
        self.wave_structure = WaveStructureModule()
        self.structural = StructuralModule()
        
        # ★NEW: PullbackModule（EA_PullbackEntryロジック移植）
        self.pullback = PullbackModule(
            ema_short=12,
            ema_mid=25,
            ema_long=100,
            require_perfect_order=True,
            pullback_lookback=5,
            pullback_ema=PullbackEMAReference.EMA_25,
            use_touch=True,
            use_cross=True,
            use_break=False,
            use_roundnumber=False,  # デフォルトはOFF
            use_adx_filter=False,
            pip_size=0.01,  # 後で銘柄に応じて調整
            is_index=False
        )
        
        # ボラティリティモジュール（補助フィルター）
        self.volatility_fx = VolatilityModule(
            atr_period=14,
            threshold_pips=atr_threshold_fx,
            is_index=False
        )
        self.volatility_index = VolatilityModule(
            atr_period=14,
            threshold_pips=atr_threshold_index,
            is_index=True
        )
        
        # ★NEW: 金融工学モジュール（クオンツ戦略）
        self.momentum = MomentumModule(
            short_period=5,
            medium_period=20,
            long_period=60,
            threshold=0.005
        )
        self.mean_reversion = MeanReversionModule(
            lookback=20,
            entry_threshold=2.0
        )
        self.volatility_breakout = VolatilityBreakoutModule(
            atr_period=14,
            k_factor=0.5
        )

    def set_preset(self, preset_name: str) -> bool:
        """プリセットを動的に切り替える（単一スレッド想定）。

        Args:
            preset_name: STRATEGY_PRESETS のキー

        Returns:
            True: 切替が行われた / False: 無変更（無効名・同一名など）
        """
        name = (preset_name or "").strip()
        if not name:
            return False
        if name == self.preset_name:
            return False
        if name not in STRATEGY_PRESETS:
            logger.warning(f"Unknown preset requested (ignored): {name}")
            return False

        self.preset_name = name
        self.enabled_modules = get_enabled_modules(name)
        logger.info(
            f"★ Preset switched: {name} (enabled: {sum(1 for v in self.enabled_modules.values() if v)} modules)"
        )
        return True
        
        # ★NEW: 拡張シグナルアグリゲーター（戦略パターン対応）
        self.strategy = strategy
        self.aggregator = ExtendedSignalAggregator(strategy=strategy)
        
        # ★NEW: Antigravity Orchestrator（Transformer/KAN/VPIN/GARCH）
        self.use_antigravity = use_antigravity and ANTIGRAVITY_AVAILABLE
        self.orchestrator = None
        
        if self.use_antigravity:
            try:
                self.orchestrator = AntigravityOrchestrator(
                    run_mode='SHADOW',
                    model_type=model_type,
                    model_path=transformer_model_path,
                    kan_model_path=kan_model_path,
                    daily_data_path=daily_data_path,
                    max_position=max_position
                )
                logger.info(f"Antigravity Orchestrator initialized (model_type={model_type})")
            except Exception as e:
                logger.warning(f"Failed to initialize Antigravity: {e}")
                self.use_antigravity = False
        
        modules_count = "9+Antigravity" if self.use_antigravity else "9"
        logger.info(f"{modules_count}-Module Analyzer initialized (Strategy={strategy}, ATR: FX={atr_threshold_fx}pips, Index={atr_threshold_index}points)")
    
    def analyze(self, data: Dict) -> Tuple[int, float, str, Dict]:
        """
        7モジュールで分析
        
        Returns: (signal, confidence, reason, breakdown)
        """
        try:
            # データ抽出 - prices は最新から古い順
            prices_str = data.get('prices', '')
            prices = [float(p) for p in prices_str.split(',') if p] if prices_str else []
            
            # 個別値も取得
            # NOTE: 一部EAが `close` のみ送るケースがあるためフォールバックを用意
            close_fallback = data.get('close', 0)
            close_1 = float(data.get('close_1', prices[0] if prices else close_fallback))
            close_2 = float(data.get('close_2', prices[1] if len(prices) > 1 else close_fallback))
            close_3 = float(data.get('close_3', prices[2] if len(prices) > 2 else close_fallback))
            
            high_1 = float(data.get('high_1', close_1))
            high_2 = float(data.get('high_2', close_2))
            low_1 = float(data.get('low_1', close_1))
            low_2 = float(data.get('low_2', close_2))
            open_1 = float(data.get('open_1', close_2))
            open_2 = float(data.get('open_2', close_3))
            
            ema12 = float(data.get('ema12', 0))
            ema25 = float(data.get('ema25', 0))
            atr = float(data.get('atr', 0.001))
            
            # pricesを時系列順（古い→新しい）に反転
            if len(prices) >= 3:
                closes = np.array(prices[::-1])  # 古い順に並べ替え
                n = len(closes)
                # High/Low/Openを推定（終値から±ATR）
                highs = closes + atr * 0.5
                lows = closes - atr * 0.5
                opens = np.roll(closes, 1)
                opens[0] = opens[1]
            else:
                # 最低限のデータ
                closes = np.array([close_3, close_2, close_1])
                highs = np.array([high_2, high_2, high_1])
                lows = np.array([low_2, low_2, low_1])
                opens = np.array([open_2, open_2, open_1])
            
            # ボリュームはダミー
            volumes = np.ones_like(closes)
            
            # EMA配列を計算
            def calc_ema(data, period):
                alpha = 2 / (period + 1)
                result = np.zeros_like(data, dtype=float)
                result[0] = data[0]
                for i in range(1, len(data)):
                    result[i] = alpha * data[i] + (1 - alpha) * result[i-1]
                return result
            
            # テクニカル指標を計算
            if len(closes) >= 26:
                ema12_arr = calc_ema(closes, 12)
                ema25_arr = calc_ema(closes, 25)
                ema100_arr = calc_ema(closes, 100) if len(closes) >= 100 else calc_ema(closes, len(closes))
                macd_main = ema12_arr - ema25_arr
                macd_signal = calc_ema(macd_main, 9)
            else:
                # データ不足時はパラメータから
                ema12_arr = np.array([ema12 * 0.999, ema12 * 0.9995, ema12, ema12])
                ema25_arr = np.array([ema25 * 0.999, ema25 * 0.9995, ema25, ema25])
                ema100_arr = np.array([ema25 * 0.995, ema25 * 0.997, ema25 * 0.999, ema25])
                macd_main = np.zeros_like(closes)
                macd_signal = np.zeros_like(closes)
            
            # RSI計算
            if len(closes) >= 15:
                deltas = np.diff(closes)
                gains = np.where(deltas > 0, deltas, 0)
                losses = np.where(deltas < 0, -deltas, 0)
                avg_gain = np.zeros(len(closes))
                avg_loss = np.zeros(len(closes))
                avg_gain[14] = np.mean(gains[:14])
                avg_loss[14] = np.mean(losses[:14])
                for i in range(15, len(closes)):
                    avg_gain[i] = (avg_gain[i-1] * 13 + gains[i-1]) / 14
                    avg_loss[i] = (avg_loss[i-1] * 13 + losses[i-1]) / 14
                rs = np.where(avg_loss > 0, avg_gain / avg_loss, 100)
                rsi = 100 - (100 / (1 + rs))
            else:
                rsi = np.ones_like(closes) * 50.0
            
            # 各モジュールの分析（★enabled_modulesで条件付き実行）
            module_scores = {}
            
            # 1. ローソク足パターン
            if self.enabled_modules.get('candle_patterns', False):
                try:
                    candle_result = self.candle_patterns.analyze(
                        opens=opens, highs=highs, lows=lows, closes=closes,
                        volumes=volumes
                    )
                    module_scores['candle_patterns'] = candle_result
                    logger.debug(f"Candle: signal={candle_result.signal}, conf={candle_result.confidence:.2f}")
                except Exception as e:
                    logger.debug(f"Candle module error: {e}")
                    module_scores['candle_patterns'] = ModuleScore(0, 0.0, f"Error: {e}")
            
            # 2. チャートパターン
            if self.enabled_modules.get('chart_patterns', False):
                try:
                    chart_result = self.chart_patterns.analyze(
                        opens=opens, highs=highs, lows=lows, closes=closes
                    )
                    module_scores['chart_patterns'] = chart_result
                    logger.debug(f"Chart: signal={chart_result.signal}, conf={chart_result.confidence:.2f}")
                except Exception as e:
                    logger.debug(f"Chart module error: {e}")
                    module_scores['chart_patterns'] = ModuleScore(0, 0.0, f"Error: {e}")
            
            # 3. False Breakout
            if self.enabled_modules.get('false_breakout', False):
                try:
                    fb_result = self.false_breakout.analyze(
                        opens=opens,
                        highs=highs,
                        lows=lows,
                        closes=closes
                    )
                    module_scores['false_breakout'] = fb_result
                    logger.debug(f"FalseBreakout: signal={fb_result.signal}, conf={fb_result.confidence:.2f}")
                except Exception as e:
                    logger.debug(f"FalseBreakout module error: {e}")
                    module_scores['false_breakout'] = ModuleScore(0, 0.0, f"Error: {e}")
            
            # 4. テクニカル
            if self.enabled_modules.get('technical', False):
                try:
                    tech_result = self.technical.analyze(
                        closes=closes,
                        macd_main=macd_main,
                        macd_signal=macd_signal,
                        rsi=rsi
                    )
                    module_scores['technical'] = tech_result
                    logger.debug(f"Technical: signal={tech_result.signal}, conf={tech_result.confidence:.2f}")
                except Exception as e:
                    logger.debug(f"Technical module error: {e}")
                    module_scores['technical'] = ModuleScore(0, 0.0, f"Error: {e}")
            
            # 5. トレンド
            if self.enabled_modules.get('trend', False):
                try:
                    # データ十分な場合は計算済みのEMA配列を使用
                    if len(closes) >= 26 and len(ema12_arr) == len(closes):
                        trend_result = self.trend.analyze(
                            closes=closes,
                            ema12=ema12_arr,
                            ema25=ema25_arr,
                            ema100=ema100_arr
                        )
                    else:
                        # データ不足時はパラメータから推定
                        n = len(closes)
                        ema12_arr_tmp = np.array([ema12] * n)
                        ema25_arr_tmp = np.array([ema25] * n)
                        ema100_arr_tmp = np.array([ema25 * 0.99] * n)
                        trend_result = self.trend.analyze(
                            closes=closes,
                            ema12=ema12_arr_tmp,
                            ema25=ema25_arr_tmp,
                            ema100=ema100_arr_tmp
                        )
                    module_scores['trend'] = trend_result
                    logger.debug(f"Trend: signal={trend_result.signal}, conf={trend_result.confidence:.2f}")
                except Exception as e:
                    logger.debug(f"Trend module error: {e}")
                    module_scores['trend'] = ModuleScore(0, 0.0, f"Error: {e}")
            
            # 6. 波動構造
            if self.enabled_modules.get('wave_structure', False):
                try:
                    wave_result = self.wave_structure.analyze(
                        open_prices=opens,
                        high_prices=highs,
                        low_prices=lows,
                        close_prices=closes
                    )
                    module_scores['wave_structure'] = wave_result
                    logger.debug(f"Wave: signal={wave_result.signal}, conf={wave_result.confidence:.2f}")
                except Exception as e:
                    logger.debug(f"Wave module error: {e}")
                    module_scores['wave_structure'] = ModuleScore(0, 0.0, f"Error: {e}")
            
            # 7. 構造的サポレジ
            if self.enabled_modules.get('structural', False):
                try:
                    struct_result = self.structural.analyze(
                        open_prices=opens,
                        high_prices=highs,
                        low_prices=lows,
                        close_prices=closes
                    )
                    module_scores['structural'] = struct_result
                    logger.debug(f"Structural: signal={struct_result.signal}, conf={struct_result.confidence:.2f}")
                except Exception as e:
                    logger.debug(f"Structural module error: {e}")
                    module_scores['structural'] = ModuleScore(0, 0.0, f"Error: {e}")
            
            # ★NEW: 8. PullbackModule（EA_PullbackEntryロジック）
            # 銘柄タイプをあらかじめ判定
            symbol = data.get('symbol', '').upper()
            is_index = is_index_symbol(symbol)
            
            # pip_sizeを銘柄に応じて設定
            if is_index:
                pip_size = 1.0
            elif 'JPY' in symbol:
                pip_size = 0.01
            else:
                pip_size = 0.0001
            
            if self.enabled_modules.get('pullback', False):
                try:
                    # PullbackModuleのpip_sizeを動的に更新
                    self.pullback.pip_size = pip_size
                    self.pullback.is_index = is_index
                    
                    # ADX配列を計算（簡易版）
                    adx_arr = None
                    
                    pullback_result = self.pullback.analyze(
                        closes=closes,
                        highs=highs,
                        lows=lows,
                        opens=opens,
                        ema12=ema12_arr if len(ema12_arr) == len(closes) else np.full(len(closes), ema12),
                        ema25=ema25_arr if len(ema25_arr) == len(closes) else np.full(len(closes), ema25),
                        ema100=ema100_arr if len(ema100_arr) == len(closes) else np.full(len(closes), ema25 * 0.99),
                        adx=adx_arr
                    )
                    module_scores['pullback'] = pullback_result
                    logger.info(f"Pullback: signal={pullback_result.signal}, conf={pullback_result.confidence:.2f}, reason={pullback_result.reason}")
                except Exception as e:
                    logger.debug(f"Pullback module error: {e}")
                    module_scores['pullback'] = ModuleScore(0, 0.0, f"Error: {e}")
            
            # 9. ボラティリティ分析（補助フィルター + Antigravity GK-Volアダプター）
            volatility_result = None
            vpin_value = 0.0  # VPINは将来実装
            gk_vol_value = 0.0
            
            # GK-Volatility（gk_volatility）
            if self.enabled_modules.get('gk_volatility', False):
                try:
                    # Antigravity GK-Volatilityアダプター（簡易版）
                    if len(closes) >= 2:
                        log_hl = np.log(highs[-1] / lows[-1]) if lows[-1] > 0 else 0
                        gk_vol_value = abs(log_hl) * 0.5
                    
                    gk_vol_score = AntigravityAdapter.adapt_gk_volatility(gk_vol_value)
                    module_scores['gk_volatility'] = gk_vol_score
                except Exception as e:
                    logger.debug(f"GK-Volatility module error: {e}")
            
            # ATRベースのボラティリティ（volatility）
            if self.enabled_modules.get('volatility', False):
                try:
                    # 適切なモジュールを選択
                    vol_module = self.volatility_index if is_index else self.volatility_fx
                    pip_value = pip_size
                    
                    volatility_result = vol_module.analyze(
                        closes=closes,
                        highs=highs,
                        lows=lows,
                        pip_value=pip_value
                    )
                    module_scores['volatility'] = volatility_result
                    logger.info(f"Volatility: signal={volatility_result.signal}, conf={volatility_result.confidence:.2f}")
                except Exception as e:
                    logger.debug(f"Volatility module error: {e}")
                    volatility_result = ModuleScore(0, 0.0, f"Error: {e}")
            
            # ★NEW: 10-12. 金融工学モジュール
            # 10. Momentum
            if self.enabled_modules.get('momentum', False):
                try:
                    momentum_result = self.momentum.analyze(closes)
                    module_scores['momentum'] = momentum_result
                    logger.debug(f"Momentum: signal={momentum_result.signal}, conf={momentum_result.confidence:.2f}")
                except Exception as e:
                    logger.debug(f"Momentum module error: {e}")
                    module_scores['momentum'] = ModuleScore(0, 0.0, f"Error: {e}")
            
            # 11. Mean Reversion
            if self.enabled_modules.get('mean_reversion', False):
                try:
                    mr_result = self.mean_reversion.analyze(closes)
                    module_scores['mean_reversion'] = mr_result
                    logger.debug(f"MeanReversion: signal={mr_result.signal}, conf={mr_result.confidence:.2f}")
                except Exception as e:
                    logger.debug(f"Mean Reversion module error: {e}")
                    module_scores['mean_reversion'] = ModuleScore(0, 0.0, f"Error: {e}")
            
            # 12. Volatility Breakout
            if self.enabled_modules.get('volatility_breakout', False):
                try:
                    vb_result = self.volatility_breakout.analyze(opens, highs, lows, closes)
                    module_scores['volatility_breakout'] = vb_result
                    logger.debug(f"VolatilityBreakout: signal={vb_result.signal}, conf={vb_result.confidence:.2f}")
                except Exception as e:
                    logger.debug(f"Volatility Breakout module error: {e}")
                    module_scores['volatility_breakout'] = ModuleScore(0, 0.0, f"Error: {e}")
            
            # ★NEW: 拡張アグリゲーターで統合
            # volatilityは補助情報なので統合からは除外
            integration_scores = {k: v for k, v in module_scores.items() if k != 'volatility'}
            
            # フィルター情報（VPIN等）
            filters = {'vpin': vpin_value}
            
            aggregated = self.aggregator.aggregate_extended(integration_scores, filters)
            
            # 結果を構築
            signal = aggregated.signal.value  # 1, -1, 0
            confidence = aggregated.confidence
            
            # ★ボラティリティによるシグナルフィルター（volatilityモジュールが有効な場合のみ）
            if self.enabled_modules.get('volatility', False) and volatility_result:
                if volatility_result.signal == -1:
                    confidence = confidence * 0.7
                    logger.warning(f"Extreme volatility detected, confidence reduced: {volatility_result.reason}")
                elif volatility_result.signal == 0:
                    confidence = confidence * 0.8
                    logger.info(f"Low volatility, confidence reduced: {volatility_result.reason}")
            
            # 理由を構築（SignalTypeをintに変換）
            def get_signal_int(score):
                s = score.signal
                if hasattr(s, 'value'):
                    return s.value
                return int(s) if s else 0
            
            # 全モジュールを表示（volatilityは別途表示）
            active_modules = [
                f"{name}:{get_signal_int(score):+d}({score.confidence:.2f})" 
                for name, score in module_scores.items() 
                if score.confidence > 0.3 and name != 'volatility'
            ]
            
            # ボラティリティ情報を追加
            vol_info = ""
            if volatility_result:
                vol_status = "OK" if volatility_result.signal == 1 else ("WARN" if volatility_result.signal == -1 else "LOW")
                vol_info = f" | ATR:{vol_status}"
            
            # VPINフィルター情報を追加（現在は将来実装として常にOK）
            vpin_filter_passed = vpin_value < 0.7  # VPIN閾値（将来実装時に使用）
            vpin_info = ""  # VPINは将来実装のため表示省略
            
            # Pullback情報を追加
            pullback_info = ""
            if pullback_result and pullback_result.confidence > 0.5:
                pullback_info = f" | PB:{get_signal_int(pullback_result):+d}"
            
            # モジュール数を動的に計算（volatility除く）
            module_count = len([m for m in module_scores.keys() if m != 'volatility'])
            
            # ★NEW: Antigravity Orchestratorの予測を統合
            antigravity_info = ""
            if self.use_antigravity and self.orchestrator is not None:
                try:
                    # 履歴が不足している場合、過去データから初期化を試みる
                    if len(self.orchestrator.bar_history) < 20 and len(closes) >= 20:
                        logger.info(f"Initializing Antigravity history with {len(closes)} past bars")
                        # 最新の足は後で追加するので、それ以前のデータを追加
                        # opens, highs, lows, closes は全て古い順に並んでいる
                        for i in range(len(closes) - 1):
                            b_data = {
                                'Open': float(opens[i]),
                                'High': float(highs[i]),
                                'Low': float(lows[i]),
                                'Close': float(closes[i]),
                                'Volume': float(volumes[i]) if i < len(volumes) else 1000.0
                            }
                            self.orchestrator._update_bar_history(b_data)

                    # 最新のバーデータをOrchestratorに投入
                    bar_data = {
                        'Open': opens[-1] if len(opens) > 0 else closes[-1],
                        'High': highs[-1] if len(highs) > 0 else closes[-1],
                        'Low': lows[-1] if len(lows) > 0 else closes[-1],
                        'Close': closes[-1],
                        'Volume': float(data.get('volume', 1000))
                    }
                    self.orchestrator._update_bar_history(bar_data)
                    
                    # モデル予測を取得（Transformer/KAN/Ensemble）
                    if len(self.orchestrator.bar_history) >= 20:
                        model_pred = self.orchestrator._get_model_prediction()
                        dir_names = ['DOWN', 'FLAT', 'UP']
                        
                        # モデル予測をシグナルに変換（-1, 0, +1）
                        model_signal = model_pred - 1  # 0=DOWN->-1, 1=FLAT->0, 2=UP->+1
                        
                        # ★ Antigravity Core v3.0: メインシグナル生成 ★
                        # Antigravityが60%の重みを持つため、ここでメインシグナルを決定
                        model_confidence = 0.75 if model_pred != 1 else 0.35
                        
                        # Transformer予測をモジュールスコアに追加
                        module_scores['antigravity_transformer'] = ModuleScore(
                            signal=model_signal,
                            confidence=model_confidence,
                            reason=f"Transformer:{dir_names[model_pred]}"
                        )
                        
                        # KAN予測（Ensembleモードの場合は別途取得、そうでなければ同じ）
                        if self.orchestrator.model_type == 'ensemble':
                            # Ensemble: 既にTransformer+KANの統合結果
                            module_scores['antigravity_kan'] = ModuleScore(
                                signal=model_signal,
                                confidence=model_confidence * 0.9,
                                reason=f"KAN:{dir_names[model_pred]}"
                            )
                        else:
                            # 単体モデル: 同じ予測を使用
                            module_scores['antigravity_kan'] = ModuleScore(
                                signal=model_signal,
                                confidence=model_confidence * 0.8,
                                reason=f"{self.orchestrator.model_type}:{dir_names[model_pred]}"
                            )
                        
                        # ★ Antigravity主導のシグナル判定 ★
                        # Antigravity Core (60%) vs Sub-Modules (40%)
                        antigravity_weight = 0.60
                        submodule_weight = 0.40
                        
                        # Antigravityシグナル（-1, 0, +1）
                        antigravity_signal = model_signal
                        antigravity_conf = model_confidence
                        
                        # Sub-Modulesのシグナル（既存aggregated結果）
                        submodule_signal = signal  # 従来の7モジュール結果
                        submodule_conf = aggregated.confidence
                        
                        # 統合スコア計算
                        combined_score = (antigravity_signal * antigravity_conf * antigravity_weight + 
                                         submodule_signal * submodule_conf * submodule_weight)
                        
                        # 最終シグナル判定
                        if abs(combined_score) >= 0.25:
                            signal = 1 if combined_score > 0 else -1
                            confidence = min(abs(combined_score) * 1.2, 0.95)
                        elif antigravity_signal != 0 and antigravity_conf >= 0.6:
                            # Antigravityが高確信度ならそれを優先
                            signal = antigravity_signal
                            confidence = antigravity_conf * 0.8
                        else:
                            signal = 0
                            confidence = 0.5
                        
                        # シグナル一致ボーナス
                        if antigravity_signal != 0 and antigravity_signal == submodule_signal:
                            confidence = min(confidence * 1.15, 0.95)
                            logger.info(f"★ CONSENSUS: Antigravity + SubModules agree on {'BUY' if signal > 0 else 'SELL'}")
                        
                        antigravity_info = f" | AG:{dir_names[model_pred]}({antigravity_conf:.2f})"
                        logger.info(f"Antigravity Core: {self.orchestrator.model_type}={dir_names[model_pred]} (conf={antigravity_conf:.2f}), "
                                   f"SubModules={aggregated.weighted_score:+.3f}, combined_score={combined_score:.3f} -> final={signal}")
                except Exception as e:
                    logger.debug(f"Antigravity integration error: {e}")
            
            reason = f"{module_count}Module[{aggregated.weighted_score:+.3f}]{vol_info}{vpin_info}{pullback_info}{antigravity_info} " + ", ".join(active_modules[:4])
            
            # ★ Brain (Dashboard) Integration ★
            # Brainによる戦略的フィルター (Veto)
            brain_plan = self.brain.get_plan(data.get('symbol', ''))
            if brain_plan:
                bias = brain_plan.get('bias', 'NEUTRAL')
                brain_info = ""
                
                # VETO LOGIC
                if self.brain.veto_mode:
                    if bias == 'BULLISH' and signal == -1:
                        # Brainが強気なのに、AIが売ろうとしている -> ブロック
                        signal = 0
                        confidence = 0.0
                        brain_info = " [BRAIN:VETO_SELL]"
                        logger.info(f"★ BRAIN VETO: Blocked SELL signal due to BULLISH plan. (Asset: {brain_plan.get('asset')})")
                    elif bias == 'BEARISH' and signal == 1:
                        # Brainが弱気なのに、AIが買おうとしている -> ブロック
                        signal = 0
                        confidence = 0.0
                        brain_info = " [BRAIN:VETO_BUY]"
                        logger.info(f"★ BRAIN VETO: Blocked BUY signal due to BEARISH plan. (Asset: {brain_plan.get('asset')})")
                    elif bias == 'BULLISH' and signal == 1:
                        # 方向一致 -> 確信度ボーナス
                        confidence = min(confidence * 1.1, 0.98)
                        brain_info = " [BRAIN:CONFIRM]"
                    elif bias == 'BEARISH' and signal == -1:
                        # 方向一致 -> 確信度ボーナス
                        confidence = min(confidence * 1.1, 0.98)
                        brain_info = " [BRAIN:CONFIRM]"
                
                if brain_info:
                    reason += brain_info

            # ★ヘッジモード処理★
            hedge_info = ""
            if self.hedge_mode:
                # レジーム判定（簡易版: RSI + ボラティリティベース）
                regime = "trend"  # デフォルト
                mean_reversion_signal = 0
                latest_rsi = 50.0 # デフォルト
                
                # RSI計算（既にrsi配列がある）
                if len(rsi) > 0 and not np.isnan(rsi[-1]):
                    latest_rsi = rsi[-1]
                    
                    # Mean Reversion検出（RSI過熱 + BB）
                    if latest_rsi > 70:
                        mean_reversion_signal = -1  # SELL（過熱からの反転）
                        regime = "range"
                    elif latest_rsi < 30:
                        mean_reversion_signal = 1  # BUY（売られすぎからの反転）
                        regime = "range"
                    elif 40 <= latest_rsi <= 60:
                        regime = "range"
                
                # 高ボラティリティ判定
                if gk_vol_value > 0.02:  # 2%以上
                    regime = "high_vol"
                
                # ヘッジモードロジック適用
                original_signal = signal
                original_confidence = confidence
                
                # 1. トレンド相場スキップ
                if self.hedge_skip_trend and regime == "trend" and signal != 0:
                    signal = 0
                    confidence = 0.5
                    hedge_info = " [HEDGE:TrendSkip]"
                    logger.info(f"★ Hedge Mode[SKIP]: Trend regime detected (RSI={latest_rsi:.1f}), skipping original signal {original_signal}")
                
                # 2. Mean Reversion優先
                elif self.hedge_prioritize_mr and mean_reversion_signal != 0:
                    signal = mean_reversion_signal
                    confidence = 0.75  # 中程度の確信度
                    hedge_info = f" [HEDGE:MeanReversion RSI={latest_rsi:.0f}]"
                    logger.info(f"★ Hedge Mode[ACTIVE]: Mean Reversion triggered signal={mean_reversion_signal} (RSI={latest_rsi:.1f})")
                
                # 3. 信頼度閾値フィルター
                elif signal != 0 and confidence < self.hedge_min_confidence:
                    signal = 0
                    confidence = original_confidence
                    hedge_info = f" [HEDGE:LowConf<{self.hedge_min_confidence}]"
                    logger.info(f"★ Hedge Mode[FILTER]: Confidence {original_confidence:.2f} < threshold {self.hedge_min_confidence}")
                
                # デバッグ情報：なぜエントリーしなかったか
                elif signal == 0 and original_signal == 0 and mean_reversion_signal == 0:
                    # そもそもシグナルがない場合
                    pass 
                    
                # レジーム情報追加
                if not hedge_info:
                    hedge_info_short = f" [HEDGE:regime={regime}]"
                    if signal == 0:
                        # エントリーしない理由（WAIT）をログに出す
                        logger.info(f"Hedge Mode[WAIT]: regime={regime}, RSI={latest_rsi:.1f}, MR_Sig={mean_reversion_signal}, Org_Sig={original_signal}")
                        
                    reason += hedge_info_short
                else:
                    reason += hedge_info
            
            # ブレークダウン（SignalTypeをintに変換）
            breakdown = {
                name: {
                    'signal': get_signal_int(score), 
                    'confidence': score.confidence, 
                    'reason': score.reason
                }
                for name, score in module_scores.items()
            }
            
            return signal, confidence, reason, breakdown
            
        except Exception as e:
            logger.error(f"7Module analysis error: {e}")
            return 0, 0.0, f"Error: {e}", {}


class SevenModuleInferenceServer:
    """7モジュール推論サーバー（複数MT4対応）"""
    
    TRADE_ANALYST_PROMPT = """あなたはFXトレードの判断を行うAIアシスタントです。
Antigravity Core（機械学習）とSub-Modules（ルールベース）の分析結果を考慮し、以下の形式で回答してください：

判定: BUY または SELL または WAIT
確信度: 0.0〜1.0の数値
理由: 1行で簡潔に

Antigravity予測を重視しつつ、Sub-Modulesによるフィルタリングを考慮してください。"""

    def __init__(self, data_dirs: list = None, data_dir: str = None, 
                 lm_studio_url: str = "http://localhost:1234",
                 strategy: str = 'antigravity',
                 preset_name: str = 'antigravity_pullback',  # ★NEW
                 atr_threshold_fx: float = 7.0,
                 atr_threshold_index: float = 70.0,
                 use_antigravity: bool = True,
                 model_type: str = 'ensemble',
                 transformer_model_path: str = None,
                 kan_model_path: str = None,
                 daily_data_path: str = None,
                 max_position: int = 2,
                 hedge_mode: bool = False,
                 hedge_skip_trend: bool = True,
                 hedge_prioritize_mr: bool = True,
                 hedge_min_confidence: float = 0.70,
                 brain_enabled: bool = False,
                 brain_veto_mode: bool = True,
                 brain_plan_dir: str = None):
        """
        Args:
            data_dirs: 複数MT4のデータディレクトリリスト [{"id": "PC1", "data_dir": "..."}, ...]
            data_dir: 単一ディレクトリ（後方互換性のため）
            lm_studio_url: LM StudioのURL
            strategy: 戦略パターン ('conservative', 'momentum', 'contrarian', 'full')
            preset_name: 戦略プリセット名 (★NEW)
            atr_threshold_fx: FX用ATR閾値（pips）
            atr_threshold_index: 株価指数用ATR閾値（points）
            use_antigravity: Antigravity Orchestratorを使用するか
            model_type: 'transformer', 'kan', 'ensemble'
            transformer_model_path: Transformerモデルのパス
            kan_model_path: KANモデルのパス
            daily_data_path: GARCH用日足データのパス
            hedge_mode: ヘッジモード有効化（PullbackEntry補完）
            hedge_skip_trend: トレンド相場でエントリースキップ
            hedge_prioritize_mr: Mean Reversionシグナル優先
            hedge_min_confidence: ヘッジモード時の最小信頼度閾値
        """
        # 複数ディレクトリ対応
        if data_dirs:
            self.data_dirs = data_dirs
        elif data_dir:
            self.data_dirs = [{"id": "PC1", "data_dir": data_dir}]
        else:
            raise ValueError("data_dirs or data_dir must be specified")

        # 同一ディレクトリの重複定義を除去（同じフォルダを複数IDで監視すると二重処理の温床になる）
        deduped_dirs = []
        seen_dirs = set()
        for d in self.data_dirs:
            dir_str = str(d.get('data_dir', '')).strip()
            if not dir_str:
                continue

            try:
                norm = str(Path(dir_str).resolve()).lower()
            except Exception:
                norm = dir_str.lower()

            if norm in seen_dirs:
                logger.warning(f"Duplicate data_dir ignored: id={d.get('id')} dir={dir_str}")
                continue

            seen_dirs.add(norm)
            deduped_dirs.append(d)

        if not deduped_dirs:
            raise ValueError("No valid data_dir entries found")

        self.data_dirs = deduped_dirs
        
        # 各ディレクトリを作成
        for d in self.data_dirs:
            Path(d['data_dir']).mkdir(parents=True, exist_ok=True)

        # メインディレクトリ（履歴用）
        self.data_dir = Path(self.data_dirs[0]['data_dir'])

        # ステータスは全ディレクトリに書き出す（各MT4が自分のFiles配下を読むため）
        self.status_files = [Path(d['data_dir']) / "server_status.txt" for d in self.data_dirs]
        self.history_file = self.data_dir / "trade_history.json"
        
        # 複数EAのリクエストを追跡（MT4_ID -> last_mtime）
        self.request_mtimes: Dict[str, float] = {}
        self.request_count = 0
        
        # コンポーネント初期化
        self.trade_history = TradeHistory(self.history_file)
        self.lm_client = LMStudioClient(base_url=lm_studio_url)
        self.module_analyzer = SevenModuleAnalyzer(
            atr_threshold_fx=atr_threshold_fx,
            atr_threshold_index=atr_threshold_index,
            strategy=strategy,
            preset_name=preset_name,  # ★NEW
            use_antigravity=use_antigravity,
            model_type=model_type,
            transformer_model_path=transformer_model_path,
            kan_model_path=kan_model_path,
            daily_data_path=daily_data_path,
            max_position=max_position,
            hedge_mode=hedge_mode,
            hedge_skip_trend=hedge_skip_trend,
            hedge_prioritize_mr=hedge_prioritize_mr,
            hedge_min_confidence=hedge_min_confidence,
            brain_enabled=brain_enabled,
            brain_veto_mode=brain_veto_mode,
            brain_plan_dir=brain_plan_dir
        )
        
        # LLM使用フラグ
        self.use_llm = True
        
        logger.info("=" * 60)
        logger.info("MT4 9-Module Inference Server")
        logger.info("=" * 60)
        logger.info(f"Data Directory: {self.data_dir.absolute()}")
        logger.info(f"LM Studio URL: {lm_studio_url}")
        logger.info(f"Strategy: {strategy}")
        logger.info(f"Trade History: {len(self.trade_history.trades)} trades loaded")
        logger.info("=" * 60)
        
        # LM Studio接続テスト
        self._test_lm_connection()
    
    def _test_lm_connection(self):
        """LM Studio接続テスト"""
        logger.info("Testing LM Studio connection...")
        try:
            response = self.lm_client.chat("OK", temperature=0.1)
            if "エラー" in response:
                logger.warning(f"LM Studio unavailable: {response}")
                self.use_llm = False
            else:
                logger.info("LM Studio connected successfully")
                self.use_llm = True
        except Exception as e:
            logger.warning(f"LM Studio connection failed: {e}")
            self.use_llm = False
    
    def update_status(self, status="running"):
        payload = f"{status}|{datetime.now().isoformat()}|{self.request_count}"
        for status_file in getattr(self, 'status_files', []):
            try:
                with open(status_file, 'w') as f:
                    f.write(payload)
            except Exception as e:
                logger.warning(f"Failed to write status file {status_file}: {e}")
    
    def parse_request(self, file_path: Path) -> Optional[Dict]:
        """横型CSV（ヘッダー行+データ行）または縦型CSV（key,value形式）をパース
        セミコロン区切りとカンマ区切り両方に対応
        """
        try:
            data = {}
            with open(file_path, 'r', encoding='utf-8') as f:
                lines = [line.strip() for line in f if line.strip()]
            
            if len(lines) == 0:
                return None
            
            # 区切り文字を検出（セミコロンまたはカンマ）
            delimiter = ';' if ';' in lines[0] else ','
            
            # 横型CSV（ヘッダー行+データ行）かどうか判断
            if len(lines) >= 2:
                header_parts = lines[0].split(delimiter)
                data_parts = lines[1].split(delimiter)
                
                # ヘッダーとデータの列数が一致すれば横型CSV
                if len(header_parts) == len(data_parts) and len(header_parts) > 2:
                    for i, key in enumerate(header_parts):
                        data[key.strip()] = data_parts[i].strip()
                    return data
            
            # 縦型CSV（key,value形式）としてパース
            for line in lines:
                if delimiter in line:
                    parts = line.split(delimiter, 1)
                    if len(parts) == 2:
                        key, value = parts
                        data[key.strip()] = value.strip()
            
            return data if data else None
        except Exception as e:
            logger.error(f"Request parse error: {e}")
            return None
    
    def analyze_with_llm(self, data: Dict, module_result: Dict) -> Tuple[int, float, str]:
        """LLMで分析（7モジュール結果を含む）"""
        symbol = data.get('symbol', 'UNKNOWN')
        timeframe = data.get('timeframe', 'M5')
        ema12 = data.get('ema12', '0')
        ema25 = data.get('ema25', '0')
        atr = data.get('atr', '0')
        
        # モジュール結果をプロンプトに含める
        module_summary = "\n".join([
            f"- {name}: signal={info['signal']:+d}, confidence={info['confidence']:.2f}"
            for name, info in module_result.items()
            if info['confidence'] > 0.2
        ])
        
        prompt = f"""
通貨ペア: {symbol}
時間足: {timeframe}
EMA12: {ema12}
EMA25: {ema25}
ATR: {atr}

【7モジュール分析結果】
{module_summary if module_summary else "特筆すべきシグナルなし"}

この状況でトレード判断をしてください。
"""
        
        try:
            response = self.lm_client.chat(
                prompt=prompt,
                system_prompt=self.TRADE_ANALYST_PROMPT,
                temperature=0.2,
                max_tokens=200
            )
            
            # エラーレスポンスチェック
            if response.startswith("エラー:"):
                logger.warning(f"LLM timeout/error - falling back to 7-module only: {response[:50]}")
                return 0, 0.0, "LLM timeout - using 7-module only"
            
            logger.info(f"LLM Response: {response[:100]}...")
            return self._parse_llm_response(response)
            
        except Exception as e:
            logger.warning(f"LLM exception - falling back to 7-module only: {e}")
            return 0, 0.0, f"LLM error: {str(e)}"
    
    def _parse_llm_response(self, response: str) -> Tuple[int, float, str]:
        """LLMレスポンスをパース"""
        signal = 0
        confidence = 0.5
        reason = response[:100]
        
        response_upper = response.upper()
        
        if "BUY" in response_upper:
            signal = 1
        elif "SELL" in response_upper:
            signal = -1
        elif "WAIT" in response_upper:
            signal = 0
        
        conf_match = re.search(r'確信度[:\s]*([0-9.]+)', response)
        if conf_match:
            try:
                confidence = float(conf_match.group(1))
                if confidence > 1.0:
                    confidence = confidence / 100.0
            except:
                pass
        
        return signal, confidence, reason
    
    def integrate_signals(self, 
                         module_signal: int, module_conf: float, module_reason: str,
                         llm_signal: int, llm_conf: float, llm_reason: str,
                         win_rate: float, trade_count: int) -> Tuple[int, float, str]:
        """シグナル統合（7モジュール重視）"""
        
        # 7モジュールを70%、LLMを30%で統合
        MODULE_WEIGHT = 0.70
        LLM_WEIGHT = 0.30
        
        if module_signal != 0 and llm_signal != 0:
            if module_signal == llm_signal:
                # 両方一致 → 高確信度
                final_signal = module_signal
                final_conf = (module_conf * MODULE_WEIGHT + llm_conf * LLM_WEIGHT) * 1.2
                source = "CONSENSUS"
            else:
                # 不一致 → 7モジュールを優先（重みが高い）
                if module_conf > 0.6:
                    final_signal = module_signal
                    final_conf = module_conf * 0.8
                    source = "7MODULE_PRIORITY"
                else:
                    final_signal = 0
                    final_conf = 0.3
                    source = "CONFLICT"
        elif module_signal != 0:
            final_signal = module_signal
            final_conf = module_conf
            source = "7MODULE_ONLY"
        elif llm_signal != 0:
            final_signal = llm_signal
            final_conf = llm_conf * LLM_WEIGHT
            source = "LLM_ONLY"
        else:
            final_signal = 0
            final_conf = 0.5
            source = "NO_SIGNAL"
        
        # 過去勝率による調整
        if trade_count >= 5:
            if win_rate >= 0.7:
                final_conf *= 1.1
            elif win_rate <= 0.3:
                final_conf *= 0.8
        
        final_conf = max(0.0, min(1.0, final_conf))
        
        final_reason = f"[{source}] {module_reason[:50]}"
        if trade_count > 0:
            final_reason += f" | WinRate:{win_rate:.0%}({trade_count})"
        
        return final_signal, final_conf, final_reason
    
    def write_response(self, mt4_id: str, signal: int, confidence: float, reason: str, data_path: Path = None):
        """指定されたMT4_IDのレスポンスファイルに書き込み
        mt4_id="DEFAULT" → response.csv
        mt4_id="PC1" → response_PC1.csv
        data_path: 書き込み先ディレクトリ（指定なしはself.data_dir）
        """
        target_dir = data_path if data_path else self.data_dir
        if mt4_id == "DEFAULT":
            response_file = target_dir / "response.csv"
        else:
            response_file = target_dir / f"response_{mt4_id}.csv"
        try:
            # MT4(EA) 側がファイル生成直後に読み込みを開始すると、ヘッダだけ/空ファイルを読んで
            # signal=0, conf=0.000, reason="" になることがある。
            # そのため、一旦 temp に全量を書いてから os.replace で原子的に差し替える。
            response_file.parent.mkdir(parents=True, exist_ok=True)

            tmp_path: str | None = None
            try:
                with tempfile.NamedTemporaryFile(
                    mode="w",
                    newline="",
                    encoding="utf-8",
                    delete=False,
                    dir=str(response_file.parent),
                    prefix=response_file.name + ".",
                    suffix=".tmp",
                ) as f:
                    tmp_path = f.name
                    # MT4はセミコロン区切りCSVを使用するため、delimiter=';'を指定
                    writer = csv.writer(f, delimiter=';')
                    writer.writerow(["signal", "confidence", "reason", "timestamp"])
                    writer.writerow([signal, confidence, reason[:200], datetime.now().isoformat()])
                    f.flush()
                    os.fsync(f.fileno())

                os.replace(tmp_path, response_file)
            finally:
                if tmp_path and os.path.exists(tmp_path):
                    try:
                        os.remove(tmp_path)
                    except OSError:
                        pass
            
            signal_name = {1: "BUY", -1: "SELL", 0: "WAIT"}[signal]
            logger.info(f"[RESPONSE:{mt4_id}] {signal_name} (conf={confidence:.2f}) -> {response_file}")
        except Exception as e:
            logger.error(f"Response write error [{mt4_id}]: {e}")
    
    def process_request(self, mt4_id: str, data: Dict) -> Tuple[int, float, str]:
        """リクエストを処理"""
        symbol = data.get('symbol', 'UNKNOWN')
        timeframe = data.get('timeframe', 'M5')

        # リクエスト単位のプリセット指定（EAから preset 列で渡す）
        req_preset = (data.get('preset') or '').strip()
        if req_preset:
            self.module_analyzer.set_preset(req_preset)
        
        logger.info(f"[REQUEST:{mt4_id}] {symbol} {timeframe}")
        
        # 1. 7モジュール分析
        module_signal, module_conf, module_reason, breakdown = self.module_analyzer.analyze(data)
        logger.info(f"[7MODULE] signal={module_signal}, conf={module_conf:.2f}")
        
        # アクティブなモジュールをログ
        for name, info in breakdown.items():
            if info['confidence'] > 0.3:
                logger.info(f"  [{name}] {info['signal']:+d} ({info['confidence']:.2f})")
        
        # 2. 過去トレード検索
        ema_bullish = float(data.get('ema12', 0)) > float(data.get('ema25', 0))
        win_rate, trade_count = self.trade_history.get_win_rate(
            symbol, module_signal if module_signal != 0 else 1, ema_bullish
        )
        logger.info(f"[HISTORY] {trade_count} similar trades, win_rate={win_rate:.0%}")
        
        # 3. LLM分析（利用可能な場合）
        if self.use_llm:
            llm_signal, llm_conf, llm_reason = self.analyze_with_llm(data, breakdown)
            logger.info(f"[LLM] signal={llm_signal}, conf={llm_conf:.2f}")
        else:
            llm_signal, llm_conf, llm_reason = 0, 0.0, "LLM unavailable"
        
        # 4. シグナル統合
        final_signal, final_conf, final_reason = self.integrate_signals(
            module_signal, module_conf, module_reason,
            llm_signal, llm_conf, llm_reason,
            win_rate, trade_count
        )
        
        # 5. 履歴に記録
        self.trade_history.add_signal(
            symbol, timeframe, final_signal, final_conf, final_reason,
            {'ema12': data.get('ema12'), 'ema25': data.get('ema25'), 'atr': data.get('atr')},
            breakdown
        )
        
        return final_signal, final_conf, final_reason
    
    def _get_mt4_id_from_filename(self, filename: str) -> str:
        """ファイル名からMT4_IDを抽出
        request_PC1.csv → PC1
        request.csv → DEFAULT
        """
        import re
        if filename == "request.csv":
            return "DEFAULT"
        match = re.match(r'request_(.+)\.csv', filename)
        return match.group(1) if match else "UNKNOWN"
    
    def run(self, poll_interval: float = 0.5):
        """メインループ - 複数MT4ディレクトリ対応"""
        logger.info("Waiting for requests from MT4 (multi-terminal mode)...")
        logger.info(f"Monitoring {len(self.data_dirs)} data directories:")
        for d in self.data_dirs:
            logger.info(f"  - {d['id']}: {d['data_dir']}")
        self.update_status("running")
        
        try:
            while True:
                try:
                    # 全てのdataディレクトリをスキャン
                    for dir_info in self.data_dirs:
                        data_path = Path(dir_info['data_dir'])
                        if not data_path.exists():
                            continue
                        
                        # request*.csv パターンで全リクエストファイルをスキャン
                        request_files = list(data_path.glob("request*.csv"))
                        
                        for request_file in request_files:
                            mt4_id = self._get_mt4_id_from_filename(request_file.name)
                            # ディレクトリIDとMT4_IDを組み合わせてユニークキー作成
                            unique_key = f"{dir_info['id']}_{mt4_id}"
                            
                            current_mtime = request_file.stat().st_mtime
                            last_mtime = self.request_mtimes.get(unique_key, 0)
                            
                            if current_mtime > last_mtime:
                                self.request_mtimes[unique_key] = current_mtime
                                self.request_count += 1
                                
                                data = self.parse_request(request_file)
                                
                                if data:
                                    signal, confidence, reason = self.process_request(mt4_id, data)
                                    self.write_response(mt4_id, signal, confidence, reason, data_path)
                                
                                self.update_status("running")
                    
                    time.sleep(poll_interval)
                    
                except Exception as e:
                    logger.error(f"Loop error (continuing): {e}")
                    time.sleep(1)
                
        except KeyboardInterrupt:
            logger.info("=" * 60)
            logger.info("Server stopped")
            logger.info(f"Total requests: {self.request_count}")
            logger.info(f"Active MT4 IDs: {list(self.request_mtimes.keys())}")
            logger.info("=" * 60)
            self.update_status("stopped")


def load_config():
    """設定ファイルを読み込む"""
    from config_loader import load_config as _load_config
    config_path = Path(__file__).parent / "config.yaml"

    config = _load_config(config_path)
    return config or None


def auto_detect_mt4_terminals():
    """MetaQuotesフォルダからMT4ターミナルを自動検出"""
    terminals = []
    
    # MetaQuotesのTerminalフォルダを探す
    appdata = os.environ.get('APPDATA', '')
    if not appdata:
        return terminals
    
    terminal_base = Path(appdata) / 'MetaQuotes' / 'Terminal'
    if not terminal_base.exists():
        return terminals
    
    # 各ターミナルフォルダを探索
    for i, terminal_dir in enumerate(terminal_base.iterdir()):
        if terminal_dir.is_dir() and len(terminal_dir.name) == 32:  # MT4のターミナルIDは32文字
            data_dir = terminal_dir / 'MQL4' / 'Files' / 'OneDriveLogs' / 'data'
            if data_dir.exists() or (terminal_dir / 'MQL4' / 'Files' / 'OneDriveLogs').exists():
                # dataフォルダがなくても親フォルダがあれば追加
                if not data_dir.exists():
                    data_dir = terminal_dir / 'MQL4' / 'Files' / 'OneDriveLogs' / 'data'
                terminals.append({
                    'id': f'PC{i+1}',
                    'data_dir': str(data_dir),
                    'terminal_id': terminal_dir.name
                })
    
    return terminals


if __name__ == "__main__":
    data_dirs = []
    lm_url = "http://localhost:1234"
    
    # 1. コマンドライン引数を優先（単一ディレクトリ）
    if len(sys.argv) > 1:
        data_dirs = [{"id": "CLI", "data_dir": sys.argv[1]}]
        lm_url = sys.argv[2] if len(sys.argv) > 2 else lm_url
    else:
        # 2. 設定ファイルを読み込み
        config = load_config()
        
        if config:
            lm_url = config.get('lm_studio', {}).get('url', lm_url)
            
            # 自動検出フラグをチェック
            if config.get('auto_detect', False):
                data_dirs = auto_detect_mt4_terminals()
                if data_dirs:
                    logger.info(f"Auto-detected {len(data_dirs)} MT4 terminal(s)")
            elif 'mt4_terminals' in config and config['mt4_terminals']:
                # 設定ファイルの全ターミナルを使用
                data_dirs = config['mt4_terminals']
                logger.info(f"Config loaded: {len(data_dirs)} MT4 terminal(s)")
        
        # 設定からターミナルが見つからなければ自動検出
        if not data_dirs:
            data_dirs = auto_detect_mt4_terminals()
            if data_dirs:
                logger.info(f"Auto-detected {len(data_dirs)} MT4 terminal(s)")
        
        # それでも見つからなければデフォルト
        if not data_dirs:
            logger.warning("No MT4 terminals found, using default path")
            data_dirs = [{
                "id": "DEFAULT",
                "data_dir": r"C:\Users\chanm\AppData\Roaming\MetaQuotes\Terminal\A84B568DA10F82FE5A8FF6A859153D6F\MQL4\Files\OneDriveLogs\data"
            }]
    
    # 戦略設定を取得
    # host config.yaml:   strategy: { pattern, preset, atr_threshold_* }
    # docker config.yaml: inference: { strategy, preset, atr_threshold_* }
    strategy_config = {}
    if config:
        strategy_config = config.get('strategy') or config.get('inference') or {}

    strategy_pattern = strategy_config.get('pattern', strategy_config.get('strategy', 'full'))
    preset_name = strategy_config.get('preset', 'antigravity_pullback')  # ★NEW
    atr_threshold_fx = strategy_config.get('atr_threshold_fx', 7.0)
    atr_threshold_index = strategy_config.get('atr_threshold_index', 70.0)
    
    # Antigravity Orchestrator設定を取得
    # host config.yaml:   antigravity_orchestrator: { enabled, model_type, transformer_model_path, kan_model_path, ... }
    # docker config.yaml: antigravity: { enabled, model_type, transformer_path, kan_path, max_position, ... }
    antigravity_config = {}
    if config:
        antigravity_config = config.get('antigravity_orchestrator') or config.get('antigravity') or {}

    use_antigravity = antigravity_config.get('enabled', False)
    model_type = antigravity_config.get('model_type', 'ensemble')
    transformer_model_path = antigravity_config.get('transformer_model_path', antigravity_config.get('transformer_path', ''))
    kan_model_path = antigravity_config.get('kan_model_path', antigravity_config.get('kan_path', ''))
    daily_data_path = antigravity_config.get('daily_data_path', '')
    max_position = int(antigravity_config.get('max_position', 2))
    
    # ★ヘッジモード設定を取得★
    hedge_config = config.get('hedge_mode', {}) if config else {}
    hedge_mode = hedge_config.get('enabled', False)
    hedge_skip_trend = hedge_config.get('skip_trend_regime', True)
    hedge_prioritize_mr = hedge_config.get('prioritize_mean_reversion', True)
    hedge_min_confidence = float(hedge_config.get('min_confidence_threshold', 0.70))
    
    # ★Brain設定を取得★
    brain_config = config.get('brain_integration', {}) if config else {}
    brain_enabled = brain_config.get('enabled', True)
    brain_veto_mode = brain_config.get('veto_mode', True)
    brain_plan_dir = brain_config.get('plan_dir', None)
    
    # 各データディレクトリを作成
    for d in data_dirs:
        os.makedirs(d['data_dir'], exist_ok=True)
    
    logger.info("=" * 60)
    logger.info(f"Monitoring {len(data_dirs)} MT4 terminal(s):")
    for d in data_dirs:
        logger.info(f"  - {d['id']}: {d['data_dir']}")
    logger.info(f"LM Studio URL: {lm_url}")
    logger.info(f"Strategy: {strategy_pattern} (ATR FX={atr_threshold_fx}, Index={atr_threshold_index})")
    if use_antigravity:
        logger.info(f"Antigravity Orchestrator: ENABLED (model={model_type})")
        logger.info(f"  Transformer: {transformer_model_path}")
        logger.info(f"  KAN: {kan_model_path}")
        logger.info(f"  Max Position: {max_position}")
    else:
        logger.info("Antigravity Orchestrator: DISABLED")
    
    # ヘッジモード情報
    if hedge_mode:
        logger.info(f"★ Hedge Mode: ENABLED")
        logger.info(f"  Skip Trend Regime: {hedge_skip_trend}")
        logger.info(f"  Prioritize Mean Reversion: {hedge_prioritize_mr}")
        logger.info(f"  Min Confidence Threshold: {hedge_min_confidence}")
    else:
        logger.info("Hedge Mode: DISABLED")
    logger.info("=" * 60)
    
    server = SevenModuleInferenceServer(
        data_dirs=data_dirs, 
        lm_studio_url=lm_url,
        strategy=strategy_pattern,
        preset_name=preset_name,  # ★NEW
        atr_threshold_fx=atr_threshold_fx,
        atr_threshold_index=atr_threshold_index,
        use_antigravity=use_antigravity,
        model_type=model_type,
        transformer_model_path=transformer_model_path,
        kan_model_path=kan_model_path,
        daily_data_path=daily_data_path,
        max_position=max_position,
        hedge_mode=hedge_mode,
        hedge_skip_trend=hedge_skip_trend,
        hedge_prioritize_mr=hedge_prioritize_mr,
        hedge_min_confidence=hedge_min_confidence,
        brain_enabled=brain_enabled,
        brain_veto_mode=brain_veto_mode,
        brain_plan_dir=brain_plan_dir
    )
    server.run(poll_interval=0.5)