"""
AI統合推論サーバー（7モジュール版）

設計書TRADING_LOGIC_DESIGN.mdに基づく7モジュール統合システム
- CSV通信でMT4からリクエスト受信 → Pythonで分析 → レスポンス返却
"""

import os
import time
import csv
import numpy as np
from pathlib import Path
from typing import Dict, Optional
import argparse

# 自作モジュールインポート
from signal_engine.signal_aggregator import SignalAggregator, ModuleScore
from modules.candle_patterns_module import CandlePatternsModule
from modules.chart_patterns_module import ChartPatternsModule
from modules.false_breakout_module import FalseBreakoutModule
from modules.wave_structure_module import WaveStructureModule
from modules.structural_module import StructuralModule
from modules.technical_module import TechnicalModule
from modules.trend_module import TrendModule


class AI_InferenceServer:
    """
    AI統合推論サーバー (Ubuntu実装統合版)
    
    7モジュールからのシグナルを統合し、最終エントリー判断を行う
    実装済み: candle_patterns(15%), chart_patterns(25%), technical(15%), trend(10%)
    合計65%重み実装済み
    """
    
    def __init__(self, data_dir: Path):
        """
        Args:
            data_dir: CSVデータディレクトリ
        """
        self.data_dir = Path(data_dir)
        
        # 7モジュール初期化 (7/7実装 - 100%完成!)
        self.candle_module = CandlePatternsModule()
        self.chart_module = ChartPatternsModule()
        self.false_breakout_module = FalseBreakoutModule()
        self.wave_structure_module = WaveStructureModule()
        self.structural_module = StructuralModule()
        self.technical_module = TechnicalModule()
        self.trend_module = TrendModule()
        
        # シグナル統合器
        self.aggregator = SignalAggregator()
        
        # 処理済みMT4_ID記録
        self.processed_requests: Dict[str, int] = {}
        
        print("=" * 60)
        print(" AI統合推論サーバー起動 (Ubuntu実装統合版)")
        print("=" * 60)
        print(f"データディレクトリ: {self.data_dir}")
        print(f"実装モジュール:")
        print(f"  [OK] candle_patterns (15% weight) - Pin Bar, Engulfing, Doji")
        print(f"  [OK] chart_patterns (25% weight) - Double Top/Bottom, H&S, Triangles")
        print(f"  [OK] false_breakout (20% weight) - 3-Stage Scoring System")
        print(f"  [OK] wave_structure (10% weight) - Two-Leg Up/Down (Al Brooks)")
        print(f"  [OK] structural (5% weight) - Pivot Points, Swing S/R")
        print(f"  [OK] technical (15% weight) - MACD, RSI")
        print(f"  [OK] trend (10% weight) - EMA Perfect Order, Pullback")
        print(f"合計: 100%重み実装完了!")
        print(f"")
        print(f"[統合完了] Ubuntu実装 + 新規モジュール = 7モジュール体制")
        print("=" * 60)
    
    def run(self):
        """メインループ"""
        print("\n▶ リクエスト監視開始...")
        
        while True:
            try:
                # request_*.csvファイルを検索
                request_files = list(self.data_dir.glob("request_*.csv"))
                
                for req_file in request_files:
                    # MT4_ID抽出
                    mt4_id = req_file.stem.replace("request_", "")
                    
                    # 処理
                    self.process_request(mt4_id, req_file)
                
                # 1秒待機
                time.sleep(1)
            
            except KeyboardInterrupt:
                print("\n\n▶ サーバー停止")
                break
            except Exception as e:
                print(f"❌ エラー: {e}")
                time.sleep(3)
    
    def process_request(self, mt4_id: str, req_file: Path):
        """
        リクエスト処理
        
        Args:
            mt4_id: MT4識別子
            req_file: リクエストファイルパス
        """
        try:
            # リクエスト読み込み
            with open(req_file, 'r') as f:
                reader = csv.DictReader(f)
                row = next(reader)
            
            # 同じリクエストの重複処理回避
            request_count = int(row.get('RequestCount', 0))
            if mt4_id in self.processed_requests:
                if self.processed_requests[mt4_id] >= request_count:
                    return  # 既に処理済み
            
            self.processed_requests[mt4_id] = request_count
            
            # データ解析
            symbol = row['Symbol']
            timeframe = row['Timeframe']
            
            print(f"\n[{mt4_id}] リクエスト #{request_count}")
            print(f"  通貨ペア: {symbol}, 時間足: {timeframe}")
            
            # 市場データ抽出
            market_data = self._parse_market_data(row)
            
            # 7モジュール分析
            module_scores = self._run_modules(market_data)
            
            # シグナル統合
            aggregated = self.aggregator.aggregate(module_scores)
            
            # レスポンス生成
            self._write_response(mt4_id, aggregated)
            
            # ログ出力
            print(self.aggregator.explain_signal(aggregated))
            
        except Exception as e:
            print(f"❌ [{mt4_id}] 処理エラー: {e}")
    
    def _parse_market_data(self, row: dict) -> dict:
        """
        CSVからデータ抽出
        
        Args:
            row: CSVの1行
        
        Returns:
            市場データ辞書
        """
        # OHLC配列（最新10本想定）
        bars = []
        for i in range(10):
            if f'Open_{i}' in row:
                bars.append({
                    'open': float(row[f'Open_{i}']),
                    'high': float(row[f'High_{i}']),
                    'low': float(row[f'Low_{i}']),
                    'close': float(row[f'Close_{i}'])
                })
        
        # NumPy配列化
        opens = np.array([b['open'] for b in bars])
        highs = np.array([b['high'] for b in bars])
        lows = np.array([b['low'] for b in bars])
        closes = np.array([b['close'] for b in bars])
        
        # EMA値（MT4から受信）
        ema12 = np.array([float(row.get(f'EMA12_{i}', 0)) for i in range(10)])
        ema25 = np.array([float(row.get(f'EMA25_{i}', 0)) for i in range(10)])
        ema100 = np.array([float(row.get(f'EMA100_{i}', 0)) for i in range(10)])
        
        # MACD値
        macd_main = np.array([float(row.get(f'MACD_{i}', 0)) for i in range(10)])
        macd_signal = np.array([float(row.get('MACDSignal', 0))] * 10)
        
        # ATR
        atr = float(row.get('ATR', 0))
        
        return {
            'opens': opens,
            'highs': highs,
            'lows': lows,
            'closes': closes,
            'ema12': ema12,
            'ema25': ema25,
            'ema100': ema100,
            'macd_main': macd_main,
            'macd_signal': macd_signal,
            'atr': atr
        }
    
    def _run_modules(self, data: dict) -> Dict[str, ModuleScore]:
        """
        7モジュール実行
        
        Args:
            data: 市場データ
        
        Returns:
            モジュール別スコア
        """
        scores = {}
        
        # 1. ローソク足パターン (15% weight)
        scores['candle_patterns'] = self.candle_module.analyze(
            data['opens'], data['highs'], data['lows'], data['closes']
        )
        
        # 2. False Breakout (20% weight) - 実装済み
        scores['false_breakout'] = self.false_breakout_module.analyze(
            data['opens'], data['highs'], data['lows'], data['closes']
        )
        
        # 3. チャートパターン (25% weight) - Ubuntu実装統合済み
        scores['chart_patterns'] = self.chart_module.analyze(
            data['highs'], data['lows'], data['closes']
        )
        
        # 4. テクニカル (15% weight)
        scores['technical'] = self.technical_module.analyze(
            data['closes'], data['macd_main'], data['macd_signal']
        )
        
        # 5. トレンド
        scores['trend'] = self.trend_module.analyze(
            data['closes'], data['ema12'], data['ema25'], data['ema100']
        )
        
        # 6. 波動構造 (10% weight) - Two-Leg Up/Down
        scores['wave_structure'] = self.wave_structure_module.analyze(
            data['opens'], data['highs'], data['lows'], data['closes']
        )
        
        # 7. 構造的 (5% weight) - Pivot Points & Support/Resistance
        scores['structural'] = self.structural_module.analyze(
            data['opens'], data['highs'], data['lows'], data['closes']
        )
        
        return scores
    
    def _write_response(self, mt4_id: str, aggregated):
        """
        レスポンス書き込み
        
        Args:
            mt4_id: MT4識別子
            aggregated: AggregatedSignal
        """
        response_file = self.data_dir / f"response_{mt4_id}.csv"
        
        with open(response_file, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Signal', 'Confidence', 'Reasons'])
            
            signal_str = aggregated.signal.name  # BUY/SELL/NEUTRAL
            confidence_str = f"{aggregated.confidence:.4f}"
            reasons_str = " | ".join(aggregated.reasons[:3])  # 最大3件
            
            writer.writerow([signal_str, confidence_str, reasons_str])
        
        print(f"  ✅ レスポンス出力: {response_file.name}")


def main():
    """メイン関数"""
    parser = argparse.ArgumentParser(description="AI統合推論サーバー（7モジュール版）")
    parser.add_argument(
        'data_dir',
        nargs='?',
        default=r"C:\Users\chanm\OneDrive\VS Code\mt4-pullback-trader\python\data",
        help="CSVデータディレクトリパス"
    )
    
    args = parser.parse_args()
    
    # サーバー起動
    server = AI_InferenceServer(args.data_dir)
    server.run()


if __name__ == "__main__":
    main()
