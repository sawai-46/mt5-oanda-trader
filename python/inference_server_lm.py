"""MT4 File-Based Inference Server (LM Studio) — NON-CANONICAL (legacy/file I/F)

LM Studio を使ってローカルLLMで推論を行うファイル通信版。
通常運用（Docker/MT5 EA）の正本は `inference_server_http_7module.py`。
"""

import os
import sys
import time
import json
import csv
from datetime import datetime
from pathlib import Path

# 統一ロガーをインポート
sys.path.insert(0, str(Path(__file__).parent))
from common.logger import get_inference_logger
from ai_research.lm_client import LMStudioClient

logger = get_inference_logger()

# トレード判断用プロンプト
TRADE_ANALYST_PROMPT = """あなたはFXトレードの判断を行うAIアシスタントです。
提供されたマーケットデータを分析し、以下の形式で回答してください：

判定: BUY または SELL または WAIT
確信度: 0.0〜1.0の数値
理由: 1行で簡潔に

必ずこの形式で回答してください。"""


class LMStudioInferenceServer:
    def __init__(self, data_dir: str, lm_studio_url: str = "http://localhost:1234"):
        """
        LM Studio連携ファイルベース推論サーバー
        
        Args:
            data_dir: MT4とのデータ交換用ディレクトリ
            lm_studio_url: LM StudioのURL
        """
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(exist_ok=True)
        
        # ファイルパス
        self.request_file = self.data_dir / "request_PC1.csv"
        self.response_file = self.data_dir / "response_PC1.csv"
        self.status_file = self.data_dir / "server_status.txt"
        
        self.request_count = 0
        self.last_request_time = None
        
        # LM Studioクライアント
        self.lm_client = LMStudioClient(base_url=lm_studio_url)
        
        logger.info("=" * 60)
        logger.info("MT4 LM Studio Inference Server")
        logger.info("=" * 60)
        logger.info(f"Data Directory: {self.data_dir.absolute()}")
        logger.info(f"LM Studio URL: {lm_studio_url}")
        logger.info("=" * 60)
        
        # LM Studio接続テスト
        self._test_lm_connection()
        
    def _test_lm_connection(self):
        """LM Studio接続テスト"""
        logger.info("Testing LM Studio connection...")
        try:
            response = self.lm_client.chat("テスト。OKと返答してください。", temperature=0.1)
            if "エラー" in response:
                logger.warning(f"LM Studio connection issue: {response}")
            else:
                logger.info(f"LM Studio connected: {response[:50]}...")
        except Exception as e:
            logger.error(f"LM Studio connection failed: {e}")
    
    def update_status(self, status="running"):
        """サーバーステータスを更新"""
        with open(self.status_file, 'w') as f:
            f.write(f"{status}|{datetime.now().isoformat()}|{self.request_count}")
    
    def parse_request(self, file_path: Path) -> dict:
        """リクエストCSVを解析"""
        try:
            with open(file_path, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    return row
        except Exception as e:
            logger.error(f"Request parse error: {e}")
            return None
    
    def analyze_with_llm(self, data: dict) -> tuple:
        """LLMでマーケットデータを分析"""
        symbol = data.get('symbol', 'UNKNOWN')
        timeframe = data.get('timeframe', 'M5')
        price = data.get('price', '0')
        ema12 = data.get('ema12', '0')
        ema25 = data.get('ema25', '0')
        atr = data.get('atr', '0')
        
        # LLM用プロンプト作成
        market_info = f"""
通貨ペア: {symbol}
時間足: {timeframe}
現在価格: {price}
EMA12: {ema12}
EMA25: {ema25}
ATR: {atr}

この状況でトレード判断をしてください。
"""
        
        logger.info(f"Asking LLM for analysis: {symbol} {timeframe}")
        
        try:
            response = self.lm_client.chat(
                prompt=market_info,
                system_prompt=TRADE_ANALYST_PROMPT,
                temperature=0.2,
                max_tokens=200
            )
            
            logger.info(f"LLM Response: {response}")
            
            # レスポンスをパース
            signal, confidence, reason = self._parse_llm_response(response)
            return signal, confidence, reason
            
        except Exception as e:
            logger.error(f"LLM analysis error: {e}")
            return 0, 0.0, f"LLM error: {str(e)}"
    
    def _parse_llm_response(self, response: str) -> tuple:
        """LLMレスポンスをパース"""
        signal = 0
        confidence = 0.5
        reason = response
        
        response_upper = response.upper()
        
        # シグナル判定
        if "BUY" in response_upper:
            signal = 1
        elif "SELL" in response_upper:
            signal = -1
        elif "WAIT" in response_upper:
            signal = 0
        
        # 確信度抽出（簡易版）
        import re
        conf_match = re.search(r'確信度[:\s]*([0-9.]+)', response)
        if conf_match:
            try:
                confidence = float(conf_match.group(1))
                confidence = max(0.0, min(1.0, confidence))
            except:
                pass
        
        # 理由抽出
        reason_match = re.search(r'理由[:\s]*(.+)', response)
        if reason_match:
            reason = reason_match.group(1).strip()
        else:
            # 最初の100文字を理由として使用
            reason = response[:100].replace('\n', ' ')
        
        return signal, confidence, reason
    
    def write_response(self, signal: int, confidence: float, reason: str):
        """レスポンスCSVを書き込み"""
        try:
            with open(self.response_file, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['signal', 'confidence', 'reason', 'timestamp'])
                writer.writerow([signal, confidence, reason, datetime.now().isoformat()])
            logger.info(f"Response written: signal={signal}, confidence={confidence:.2f}")
        except Exception as e:
            logger.error(f"Response write error: {e}")
    
    def run(self, poll_interval: float = 0.5):
        """サーバーメインループ"""
        logger.info("Waiting for requests from MT4...")
        self.update_status("running")
        
        last_mtime = 0
        
        try:
            while True:
                # リクエストファイルをチェック
                if self.request_file.exists():
                    current_mtime = self.request_file.stat().st_mtime
                    
                    if current_mtime > last_mtime:
                        last_mtime = current_mtime
                        self.request_count += 1
                        
                        logger.info(f"Request #{self.request_count} received")
                        
                        # リクエスト解析
                        data = self.parse_request(self.request_file)
                        
                        if data:
                            # LLMで分析
                            signal, confidence, reason = self.analyze_with_llm(data)
                            
                            # レスポンス書き込み
                            self.write_response(signal, confidence, reason)
                        
                        self.update_status("running")
                
                time.sleep(poll_interval)
                
        except KeyboardInterrupt:
            logger.info("=" * 60)
            logger.info("Server stopped by user")
            logger.info(f"Total requests processed: {self.request_count}")
            logger.info("=" * 60)
            self.update_status("stopped")


if __name__ == "__main__":
    # コマンドライン引数からデータディレクトリを取得
    if len(sys.argv) > 1:
        data_dir = sys.argv[1]
    else:
        # MT4 Files フォルダ内の OneDriveLogs/data を使用
        data_dir = r"C:\Users\chanm\AppData\Roaming\MetaQuotes\Terminal\A84B568DA10F82FE5A8FF6A859153D6F\MQL4\Files\OneDriveLogs\data"
    
    # LM Studio URL（デフォルト）
    lm_url = "http://localhost:1234"
    if len(sys.argv) > 2:
        lm_url = sys.argv[2]
    
    server = LMStudioInferenceServer(data_dir=data_dir, lm_studio_url=lm_url)
    server.run(poll_interval=0.5)
