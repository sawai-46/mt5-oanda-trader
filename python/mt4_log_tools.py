import sqlite3
import pandas as pd
import argparse
from pathlib import Path
from config_loader import load_config

class MT4LogTools:
    def __init__(self, db_path: str):
        self.db_path = Path(db_path)
        if not self.db_path.exists():
            print(f"Error: Database not found at {db_path}")
            return
            
    def show_stats(self):
        """データベースの統計情報を表示"""
        with sqlite3.connect(self.db_path) as conn:
            print("\n=== MT4 Log Database Statistics ===")
            
            # 各テーブルの件数
            for table in ['log_entries', 'ai_learning_data', 'inference_signals', 'trade_events']:
                count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                print(f"{table:18}: {count:>6} rows")
            
            # AI学習データのシンボル別内訳
            print("\n--- AI Learning Data by Symbol ---")
            df = pd.read_sql_query("SELECT symbol, COUNT(*) as count FROM ai_learning_data GROUP BY symbol", conn)
            print(df.to_string(index=False))
            
            # 直近のレコード
            print("\n--- Recent AI Learning Data ---")
            df_recent = pd.read_sql_query("SELECT timestamp, symbol, direction, entry_price, pattern_type FROM ai_learning_data ORDER BY timestamp DESC LIMIT 5", conn)
            print(df_recent.to_string(index=False))

    def export_training_data(self, output_path: str):
        """学習用データをCSVにエクスポート"""
        with sqlite3.connect(self.db_path) as conn:
            df = pd.read_sql_query("SELECT * FROM ai_learning_data ORDER BY timestamp ASC", conn)
            df.to_csv(output_path, index=False)
            print(f"Exported {len(df)} rows to {output_path}")

def main():
    parser = argparse.ArgumentParser(description="MT4 Log Database Tools")
    parser.add_argument("--stats", action="store_true", help="Show database statistics")
    parser.add_argument("--export", type=str, help="Export all data to CSV")
    default_config = str(Path(__file__).parent / "config.yaml")
    parser.add_argument("--config", type=str, default=default_config, help="Path to config.yaml")
    
    args = parser.parse_args()
    
    # ConfigからDBパスを取得
    db_path = "mt4_logs.db"
    config = load_config(args.config)
    db_path = config.get('logging', {}).get('database_path', db_path)
    
    tools = MT4LogTools(db_path)
    
    if args.stats:
        tools.show_stats()
    elif args.export:
        tools.export_training_data(args.export)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
