"""MT4 Shared File-Based Inference Server — NON-CANONICAL (legacy/file I/F)

OneDrive共有フォルダで複数のMT4インスタンスと通信するファイル通信版。
通常運用（Docker/MT5 EA）の正本は `inference_server_http_7module.py`。
"""

import os
import time
import json
import csv
from datetime import datetime
from pathlib import Path
import glob

class SharedInferenceServer:
    def __init__(self, data_dir="data"):
        """
        複数MT4対応の推論サーバー初期化
        
        Args:
            data_dir: 共有データディレクトリ（OneDrive推奨）
        """
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(exist_ok=True)
        
        self.status_file = self.data_dir / "server_status.txt"
        self.request_count = {}  # MT4ごとのリクエストカウント
        self.total_requests = 0
        
        print("=" * 60)
        print("MT4 Shared File-Based Inference Server")
        print("=" * 60)
        print(f"Data Directory: {self.data_dir.absolute()}")
        print("")
        print("This server supports multiple MT4 instances")
        print("Each MT4 should use a unique ID (e.g., PC1, PC2, MT4_1)")
        print("")
        print("=" * 60)
        print("Waiting for requests from MT4...")
        print("Press Ctrl+C to stop")
        print("=" * 60)
        
    def update_status(self, status="running"):
        """サーバーステータスを更新"""
        with open(self.status_file, 'w') as f:
            status_info = f"{status}|{datetime.now().isoformat()}|{self.total_requests}"
            for mt4_id, count in self.request_count.items():
                status_info += f"|{mt4_id}:{count}"
            f.write(status_info + "\n")
    
    def find_request_files(self):
        """すべてのリクエストファイルを検索"""
        pattern = str(self.data_dir / "request_*.csv")
        return glob.glob(pattern)
    
    def extract_mt4_id(self, request_file_path):
        """ファイル名からMT4 IDを抽出"""
        filename = os.path.basename(request_file_path)
        # request_PC1.csv -> PC1
        mt4_id = filename.replace("request_", "").replace(".csv", "")
        return mt4_id
    
    def read_request(self, request_file):
        """リクエストファイルを読み込み"""
        try:
            with open(request_file, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    return row  # 最初の行を返す
        except Exception as e:
            print(f"[ERROR] Failed to read {request_file}: {e}")
            return None
    
    def write_response(self, mt4_id, signal, confidence, reason=""):
        """レスポンスファイルを書き込み"""
        response_file = self.data_dir / f"response_{mt4_id}.csv"
        try:
            with open(response_file, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['timestamp', 'signal', 'confidence', 'reason'])
                writer.writerow([
                    datetime.now().isoformat(),
                    signal,
                    confidence,
                    reason
                ])
            return True
        except Exception as e:
            print(f"[ERROR] Failed to write response for {mt4_id}: {e}")
            return False
    
    def process_inference(self, mt4_id, request_data):
        """
        推論処理（デモ実装）
        
        Args:
            mt4_id: MT4識別子
            request_data: リクエストデータ（辞書形式）
            
        Returns:
            tuple: (signal, confidence, reason)
        """
        try:
            symbol = request_data.get('symbol', 'UNKNOWN')
            timeframe = request_data.get('timeframe', 'M15')
            
            # 価格データ
            prices_str = request_data.get('prices', '')
            prices = [float(p) for p in prices_str.split(',') if p]
            
            # インジケーター
            ema12 = float(request_data.get('ema12', 0))
            ema25 = float(request_data.get('ema25', 0))
            atr = float(request_data.get('atr', 0))
            
            print(f"\n[{mt4_id}] REQUEST: {symbol} {timeframe}")
            print(f"  Prices: {len(prices)} bars")
            print(f"  EMA12: {ema12:.5f}, EMA25: {ema25:.5f}, ATR: {atr:.5f}")
            
            # シンプルなデモロジック
            signal = 0
            confidence = 0.0
            reason = "Neutral - No clear signal"
            
            if len(prices) >= 3:
                if prices[-1] > prices[-2] > prices[-3] and ema12 > ema25:
                    signal = 1
                    confidence = 0.75
                    reason = "Uptrend detected (3-bar rising + EMA12 > EMA25)"
                elif prices[-1] < prices[-2] < prices[-3] and ema12 < ema25:
                    signal = -1
                    confidence = 0.75
                    reason = "Downtrend detected (3-bar falling + EMA12 < EMA25)"
            
            signal_name = {1: "BUY", -1: "SELL", 0: "NEUTRAL"}[signal]
            print(f"[{mt4_id}] RESPONSE: {signal_name}, Confidence: {confidence:.2f}")
            
            return signal, confidence, reason
            
        except Exception as e:
            print(f"[{mt4_id}] ERROR: {e}")
            return 0, 0.0, f"Error: {str(e)}"
    
    def run(self, poll_interval=0.5):
        """
        サーバーのメインループ
        
        Args:
            poll_interval: ポーリング間隔（秒）
        """
        self.update_status("running")
        
        try:
            while True:
                # すべてのリクエストファイルをチェック
                request_files = self.find_request_files()
                
                for request_file in request_files:
                    mt4_id = self.extract_mt4_id(request_file)
                    
                    # リクエストを読み込み
                    request_data = self.read_request(request_file)
                    
                    if request_data:
                        # カウント更新
                        self.request_count[mt4_id] = self.request_count.get(mt4_id, 0) + 1
                        self.total_requests += 1
                        
                        # 推論処理
                        signal, confidence, reason = self.process_inference(mt4_id, request_data)
                        
                        # レスポンスを書き込み
                        self.write_response(mt4_id, signal, confidence, reason)
                        
                        # リクエストファイルを削除（処理済み）
                        try:
                            os.remove(request_file)
                        except:
                            pass
                        
                        # ステータス更新
                        self.update_status("running")
                
                # 次のポーリングまで待機
                time.sleep(poll_interval)
                
        except KeyboardInterrupt:
            print("\n" + "=" * 60)
            print("Server stopped by user")
            print(f"Total requests processed: {self.total_requests}")
            print("\nRequests by MT4:")
            for mt4_id, count in self.request_count.items():
                print(f"  {mt4_id}: {count}")
            print("=" * 60)
            self.update_status("stopped")

if __name__ == "__main__":
    import sys
    
    # コマンドライン引数からデータディレクトリを取得
    if len(sys.argv) > 1:
        data_dir = sys.argv[1]
    else:
        # デフォルトはOneDrive上の共有フォルダ
        data_dir = r"C:\Users\chanm\OneDrive\VS Code\mt4-pullback-trader\python\data"
    
    print("")
    print("=" * 60)
        print("Log monitoring enabled (running in background)")
        print("=" * 60)
        print("")
    
    server = SharedInferenceServer(data_dir=data_dir)
    server.run(poll_interval=0.3)  # 0.3秒ごとにチェック（複数MT4対応）
