"""MT4 Hybrid Inference Server — NON-CANONICAL (experimental)

ルールベース + LLM + ログ学習を統合した推論サーバー。
通常運用（Docker/MT5 EA）の正本は `inference_server_http_7module.py`。
"""

import os
import sys
import time
import json
import csv
import re
from datetime import datetime, timedelta
from pathlib import Path
from typing import Tuple, Dict, List, Optional

# 統一ロガーをインポート
sys.path.insert(0, str(Path(__file__).parent))
from common.logger import get_inference_logger
from ai_research.lm_client import LMStudioClient

logger = get_inference_logger()


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
                   confidence: float, reason: str, market_data: Dict):
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
            'result': None,  # 後で更新
            'pips': None
        }
        self.trades.append(trade)
        self._save_history()
        return len(self.trades) - 1  # trade_id
    
    def update_result(self, trade_id: int, result: str, pips: float):
        """トレード結果を更新"""
        if 0 <= trade_id < len(self.trades):
            self.trades[trade_id]['result'] = result  # 'win' or 'loss'
            self.trades[trade_id]['pips'] = pips
            self._save_history()
    
    def get_similar_trades(self, symbol: str, signal: int, 
                          ema_bullish: bool, limit: int = 5) -> List[Dict]:
        """類似条件のトレードを検索"""
        similar = []
        for trade in reversed(self.trades):
            if (trade['symbol'] == symbol and 
                trade['signal'] == signal and
                trade.get('result') is not None):
                # EMA条件が似ているかチェック
                md = trade.get('market_data', {})
                trade_ema_bullish = float(md.get('ema12', 0)) > float(md.get('ema25', 0))
                if trade_ema_bullish == ema_bullish:
                    similar.append(trade)
                    if len(similar) >= limit:
                        break
        return similar
    
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


class RuleBasedAnalyzer:
    """ルールベース分析エンジン"""
    
    @staticmethod
    def analyze(data: Dict) -> Tuple[int, float, str]:
        """
        ルールベースで分析
        Returns: (signal, confidence, reason)
        """
        try:
            prices_str = data.get('prices', '')
            prices = [float(p) for p in prices_str.split(',') if p]
            
            ema12 = float(data.get('ema12', 0))
            ema25 = float(data.get('ema25', 0))
            atr = float(data.get('atr', 0))
            
            signal = 0
            confidence = 0.0
            reasons = []
            
            # EMA判定
            ema_bullish = ema12 > ema25
            if ema_bullish:
                reasons.append("EMA12>EMA25(bullish)")
            else:
                reasons.append("EMA12<EMA25(bearish)")
            
            # 価格トレンド判定
            if len(prices) >= 3:
                if prices[-1] > prices[-2] > prices[-3]:
                    reasons.append("3-bar rising")
                    if ema_bullish:
                        signal = 1
                        confidence = 0.70
                elif prices[-1] < prices[-2] < prices[-3]:
                    reasons.append("3-bar falling")
                    if not ema_bullish:
                        signal = -1
                        confidence = 0.70
            
            # ATRによる調整
            if atr > 0:
                reasons.append(f"ATR={atr:.4f}")
            
            reason = " + ".join(reasons)
            return signal, confidence, reason
            
        except Exception as e:
            return 0, 0.0, f"Rule error: {e}"


class HybridInferenceServer:
    """ハイブリッド推論サーバー"""
    
    # LLM用プロンプト
    TRADE_ANALYST_PROMPT = """あなたはFXトレードの判断を行うAIアシスタントです。
マーケットデータと過去のトレード結果を分析し、以下の形式で回答してください：

判定: BUY または SELL または WAIT
確信度: 0.0〜1.0の数値
理由: 1行で簡潔に

過去のトレード結果も考慮して慎重に判断してください。"""

    def __init__(self, data_dir: str, lm_studio_url: str = "http://localhost:1234"):
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(exist_ok=True)
        
        # ファイルパス
        self.request_file = self.data_dir / "request_PC1.csv"
        self.response_file = self.data_dir / "response_PC1.csv"
        self.status_file = self.data_dir / "server_status.txt"
        self.history_file = self.data_dir / "trade_history.json"
        
        self.request_count = 0
        
        # コンポーネント初期化
        self.trade_history = TradeHistory(self.history_file)
        self.lm_client = LMStudioClient(base_url=lm_studio_url)
        self.rule_analyzer = RuleBasedAnalyzer()
        
        # LLM使用フラグ
        self.use_llm = True
        
        logger.info("=" * 60)
        logger.info("MT4 Hybrid Inference Server")
        logger.info("=" * 60)
        logger.info(f"Data Directory: {self.data_dir.absolute()}")
        logger.info(f"LM Studio URL: {lm_studio_url}")
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
                logger.warning(f"LM Studio unavailable, using rule-based only: {response}")
                self.use_llm = False
            else:
                logger.info("LM Studio connected successfully")
                self.use_llm = True
        except Exception as e:
            logger.warning(f"LM Studio connection failed, using rule-based only: {e}")
            self.use_llm = False
    
    def update_status(self, status="running"):
        with open(self.status_file, 'w') as f:
            f.write(f"{status}|{datetime.now().isoformat()}|{self.request_count}")
    
    def parse_request(self, file_path: Path) -> Optional[Dict]:
        """縦型CSV（key,value形式）をパース"""
        try:
            data = {}
            with open(file_path, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if ',' in line:
                        parts = line.split(',', 1)
                        if len(parts) == 2:
                            key, value = parts
                            data[key.strip()] = value.strip()
            return data if data else None
        except Exception as e:
            logger.error(f"Request parse error: {e}")
            return None
    
    def analyze_with_llm(self, data: Dict, similar_trades: List[Dict]) -> Tuple[int, float, str]:
        """LLMで分析"""
        symbol = data.get('symbol', 'UNKNOWN')
        timeframe = data.get('timeframe', 'M5')
        price = data.get('price', data.get('prices', '').split(',')[-1] if data.get('prices') else '0')
        ema12 = data.get('ema12', '0')
        ema25 = data.get('ema25', '0')
        atr = data.get('atr', '0')
        
        # 過去トレード情報
        history_info = ""
        if similar_trades:
            history_info = "\n過去の類似トレード:\n"
            for t in similar_trades[:3]:
                result_str = f"{t['result']} ({t['pips']:+.1f}pips)" if t.get('pips') else t.get('result', 'unknown')
                history_info += f"- {t['timestamp'][:10]} {t['signal_name']} → {result_str}\n"
            
            wins = sum(1 for t in similar_trades if t.get('result') == 'win')
            history_info += f"類似条件勝率: {wins}/{len(similar_trades)} ({100*wins/len(similar_trades):.0f}%)\n"
        
        prompt = f"""
通貨ペア: {symbol}
時間足: {timeframe}
現在価格: {price}
EMA12: {ema12}
EMA25: {ema25}
ATR: {atr}
{history_info}
この状況でトレード判断をしてください。
"""
        
        try:
            response = self.lm_client.chat(
                prompt=prompt,
                system_prompt=self.TRADE_ANALYST_PROMPT,
                temperature=0.2,
                max_tokens=200
            )
            
            logger.info(f"LLM Response: {response[:100]}...")
            return self._parse_llm_response(response)
            
        except Exception as e:
            logger.error(f"LLM error: {e}")
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
                confidence = max(0.0, min(1.0, confidence))
            except:
                pass
        
        reason_match = re.search(r'理由[:\s]*(.+)', response)
        if reason_match:
            reason = reason_match.group(1).strip()[:100]
        
        return signal, confidence, reason
    
    def integrate_signals(self, rule_signal: int, rule_conf: float, rule_reason: str,
                          llm_signal: int, llm_conf: float, llm_reason: str,
                          win_rate: float, trade_count: int) -> Tuple[int, float, str]:
        """シグナルを統合"""
        
        # 基本: ルールベースとLLMの一致度で判断
        if rule_signal == llm_signal and rule_signal != 0:
            # 完全一致 → 高信頼度
            final_signal = rule_signal
            final_conf = max(rule_conf, llm_conf) * 1.1  # ボーナス
            source = "RULE+LLM"
        elif rule_signal != 0 and llm_signal == 0:
            # ルールのみ → ルール優先
            final_signal = rule_signal
            final_conf = rule_conf * 0.9
            source = "RULE"
        elif rule_signal == 0 and llm_signal != 0:
            # LLMのみ → LLM優先（やや慎重）
            final_signal = llm_signal
            final_conf = llm_conf * 0.8
            source = "LLM"
        elif rule_signal != 0 and llm_signal != 0 and rule_signal != llm_signal:
            # 不一致 → WAIT
            final_signal = 0
            final_conf = 0.3
            source = "CONFLICT"
        else:
            # 両方WAIT
            final_signal = 0
            final_conf = 0.5
            source = "NO_SIGNAL"
        
        # 過去勝率による調整
        if trade_count >= 5:
            if win_rate >= 0.7:
                final_conf *= 1.1  # 高勝率 → 信頼度UP
            elif win_rate <= 0.3:
                final_conf *= 0.8  # 低勝率 → 信頼度DOWN
        
        final_conf = max(0.0, min(1.0, final_conf))
        
        final_reason = f"[{source}] Rule:{rule_reason[:30]} | LLM:{llm_reason[:30]}"
        if trade_count > 0:
            final_reason += f" | WinRate:{win_rate:.0%}({trade_count})"
        
        return final_signal, final_conf, final_reason
    
    def write_response(self, signal: int, confidence: float, reason: str):
        try:
            with open(self.response_file, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['signal', 'confidence', 'reason', 'timestamp'])
                writer.writerow([signal, confidence, reason[:200], datetime.now().isoformat()])
            
            signal_name = {1: "BUY", -1: "SELL", 0: "WAIT"}[signal]
            logger.info(f"[RESPONSE] {signal_name} (conf={confidence:.2f})")
        except Exception as e:
            logger.error(f"Response write error: {e}")
    
    def process_request(self, data: Dict) -> Tuple[int, float, str]:
        """リクエストを処理"""
        symbol = data.get('symbol', 'UNKNOWN')
        timeframe = data.get('timeframe', 'M5')
        
        logger.info(f"[REQUEST] {symbol} {timeframe}")
        
        # 1. ルールベース分析
        rule_signal, rule_conf, rule_reason = self.rule_analyzer.analyze(data)
        logger.info(f"[RULE] signal={rule_signal}, conf={rule_conf:.2f}, reason={rule_reason}")
        
        # 2. 過去トレード検索
        ema_bullish = float(data.get('ema12', 0)) > float(data.get('ema25', 0))
        similar_trades = self.trade_history.get_similar_trades(
            symbol, rule_signal if rule_signal != 0 else 1, ema_bullish
        )
        win_rate, trade_count = self.trade_history.get_win_rate(
            symbol, rule_signal if rule_signal != 0 else 1, ema_bullish
        )
        logger.info(f"[HISTORY] {trade_count} similar trades, win_rate={win_rate:.0%}")
        
        # 3. LLM分析（利用可能な場合）
        if self.use_llm:
            llm_signal, llm_conf, llm_reason = self.analyze_with_llm(data, similar_trades)
            logger.info(f"[LLM] signal={llm_signal}, conf={llm_conf:.2f}")
        else:
            llm_signal, llm_conf, llm_reason = 0, 0.0, "LLM unavailable"
        
        # 4. シグナル統合
        final_signal, final_conf, final_reason = self.integrate_signals(
            rule_signal, rule_conf, rule_reason,
            llm_signal, llm_conf, llm_reason,
            win_rate, trade_count
        )
        
        # 5. 履歴に記録
        self.trade_history.add_signal(
            symbol, timeframe, final_signal, final_conf, final_reason,
            {'ema12': data.get('ema12'), 'ema25': data.get('ema25'), 'atr': data.get('atr')}
        )
        
        return final_signal, final_conf, final_reason
    
    def run(self, poll_interval: float = 0.5):
        """メインループ"""
        logger.info("Waiting for requests from MT4...")
        self.update_status("running")
        
        last_mtime = 0
        
        try:
            while True:
                try:
                    if self.request_file.exists():
                        current_mtime = self.request_file.stat().st_mtime
                        
                        if current_mtime > last_mtime:
                            last_mtime = current_mtime
                            self.request_count += 1
                            
                            data = self.parse_request(self.request_file)
                            
                            if data:
                                signal, confidence, reason = self.process_request(data)
                                self.write_response(signal, confidence, reason)
                            
                            self.update_status("running")
                    
                    time.sleep(poll_interval)
                    
                except Exception as e:
                    logger.error(f"Loop error (continuing): {e}")
                    time.sleep(1)
                
        except KeyboardInterrupt:
            logger.info("=" * 60)
            logger.info("Server stopped")
            logger.info(f"Total requests: {self.request_count}")
            logger.info("=" * 60)
            self.update_status("stopped")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        data_dir = sys.argv[1]
    else:
        # MT4 Files フォルダ内の OneDriveLogs/data を使用
        data_dir = r"C:\Users\chanm\AppData\Roaming\MetaQuotes\Terminal\A84B568DA10F82FE5A8FF6A859153D6F\MQL4\Files\OneDriveLogs\data"
    
    lm_url = sys.argv[2] if len(sys.argv) > 2 else "http://localhost:1234"
    
    server = HybridInferenceServer(data_dir=data_dir, lm_studio_url=lm_url)
    server.run(poll_interval=0.5)
