"""
MT4 File-Based Inference Server
CSVファイルを使用してMT4と通信する推論サーバー
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

logger = get_inference_logger()

class FileBasedInferenceServer:
    def __init__(self, data_dir="data"):
        """
        ファイルベース推論サーバーの初期化
        
        Args:
            data_dir: MT4とのデータ交換用ディレクトリ
        """
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(exist_ok=True)
        
        # ファイルパス
        self.request_file = self.data_dir / "request.csv"
        self.response_file = self.data_dir / "response.csv"
        self.status_file = self.data_dir / "server_status.txt"
        
        self.request_count = 0
        self.last_request_time = None
        
        logger.info("=" * 60)
        logger.info("MT4 File-Based Inference Server")
        logger.info("=" * 60)
        logger.info(f"Data Directory: {self.data_dir.absolute()}")
        logger.info(f"Request File:  {self.request_file.absolute()}")
        logger.info(f"Response File: {self.response_file.absolute()}")
        logger.info(f"Status File:   {self.status_file.absolute()}")
        logger.info("=" * 60)
        logger.info("Waiting for requests from MT4...")
        
    def update_status(self, status="running"):
        """サーバーステータスを更新"""
        with open(self.status_file, 'w') as f:
            f.write(f"{status}|{datetime.now().isoformat()}|{self.request_count}\n")
    
    def read_request(self):
        """リクエストファイルを読み込み"""
        if not self.request_file.exists():
            return None
        
        try:
            with open(self.request_file, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    return row  # 最初の行を返す
        except Exception as e:
            logger.error(f"Failed to read request: {e}")
            return None
    
    def write_response(self, signal, confidence, reason=""):
        """レスポンスファイルを書き込み"""
        try:
            with open(self.response_file, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['signal', 'confidence', 'reason', 'timestamp'])
                writer.writerow([
                    signal,
                    confidence,
                    reason,
                    datetime.now().isoformat()
                ])
            return True
        except Exception as e:
            logger.error(f"Failed to write response: {e}")
            return False
    
    def process_inference(self, request_data):
        """
        推論処理（デモ実装）
        
        Args:
            request_data: リクエストデータ（辞書形式）
            
        Returns:
            tuple: (signal, confidence, reason)
                signal: 1=Buy, -1=Sell, 0=Neutral
                confidence: 0.0-1.0
                reason: シグナルの理由
        """
        try:
            # リクエストデータの解析
            symbol = request_data.get('symbol', 'UNKNOWN')
            timeframe = request_data.get('timeframe', 'M15')
            
            # 価格データ（カンマ区切り文字列を配列に変換）
            prices_str = request_data.get('prices', '')
            prices = [float(p) for p in prices_str.split(',') if p]
            
            # インジケーター
            ema12 = float(request_data.get('ema12', 0))
            ema25 = float(request_data.get('ema25', 0))
            atr = float(request_data.get('atr', 0))
            
            logger.info(f"[REQUEST] {symbol} {timeframe} - Prices: {len(prices)} bars, EMA12: {ema12:.5f}, EMA25: {ema25:.5f}, ATR: {atr:.5f}")
            
            # シンプルなデモロジック
            signal = 0
            confidence = 0.0
            reason = "Neutral - No clear signal"
            
            if len(prices) >= 3:
                # トレンド判定
                if prices[-1] > prices[-2] > prices[-3] and ema12 > ema25:
                    signal = 1
                    confidence = 0.75
                    reason = "Uptrend detected (3-bar rising + EMA12 > EMA25)"
                elif prices[-1] < prices[-2] < prices[-3] and ema12 < ema25:
                    signal = -1
                    confidence = 0.75
                    reason = "Downtrend detected (3-bar falling + EMA12 < EMA25)"
            
            signal_name = {1: "BUY", -1: "SELL", 0: "NEUTRAL"}[signal]
            logger.info(f"[RESPONSE] Signal: {signal_name}, Confidence: {confidence:.2f}, Reason: {reason}")
            
            # シグナルログを記録
            logger.log_signal(symbol, signal_name, confidence, ['EMA', 'Price'], reason)
            
            return signal, confidence, reason
            
        except Exception as e:
            logger.error(f"Inference failed: {e}")
            return 0, 0.0, f"Error: {str(e)}"
    
    def run(self, poll_interval=1.0):
        """
        サーバーのメインループ
        
        Args:
            poll_interval: ポーリング間隔（秒）
        """
        self.update_status("running")
        
        try:
            while True:
                # リクエストファイルをチェック
                request_data = self.read_request()
                
                if request_data:
                    self.request_count += 1
                    self.last_request_time = datetime.now()
                    
                    # 推論処理
                    signal, confidence, reason = self.process_inference(request_data)
                    
                    # レスポンスを書き込み
                    self.write_response(signal, confidence, reason)
                    
                    # リクエストファイルを削除（処理済み）
                    try:
                        self.request_file.unlink()
                    except:
                        pass
                    
                    # ステータス更新
                    self.update_status("running")
                
                # 次のポーリングまで待機
                time.sleep(poll_interval)
                
        except KeyboardInterrupt:
            logger.info("=" * 60)
            logger.info("Server stopped by user")
            logger.info(f"Total requests processed: {self.request_count}")
            logger.info("=" * 60)
            self.update_status("stopped")

if __name__ == "__main__":
    import sys
    
    # コマンドライン引数からデータディレクトリを取得
    if len(sys.argv) > 1:
        data_dir = sys.argv[1]
    else:
        # MT4 Files フォルダ内の OneDriveLogs/data を使用
        data_dir = r"C:\Users\chanm\AppData\Roaming\MetaQuotes\Terminal\A84B568DA10F82FE5A8FF6A859153D6F\MQL4\Files\OneDriveLogs\data"
    
    server = FileBasedInferenceServer(data_dir=data_dir)
    server.run(poll_interval=0.5)  # 0.5秒ごとにチェック
