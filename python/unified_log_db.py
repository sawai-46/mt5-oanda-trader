"""
Unified MT4/MT5 Log Database
MT4とMT5のログを統合管理するSQLiteデータベースクラス
"""

import sqlite3
import pandas as pd
from pathlib import Path
from datetime import datetime
import logging


class UnifiedLogDatabase:
    """
    MT4/MT5ログおよびAI学習データを集中管理するSQLiteデータベースクラス
    
    既存の MT4LogDatabase と互換性を保ちつつ、source_system カラムで
    MT4/MT5 を区別できるように拡張。
    """
    
    def __init__(self, db_path: str):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = None
        self._init_db()

    def _get_connection(self):
        if self.conn is None:
            self.conn = sqlite3.connect(self.db_path)
            self.conn.row_factory = sqlite3.Row
        return self.conn

    def _init_db(self):
        """テーブルの初期化"""
        conn = self._get_connection()
        cursor = conn.cursor()

        # 基本PRAGMA（大量INSERT時の安定性/速度向上）
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA synchronous=NORMAL")

        # 1. 一般ログエントリ (MT4/MT5標準ログ)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS log_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME,
                terminal_id TEXT,
                source_system TEXT DEFAULT 'MT4',
                ea_name TEXT,
                log_level TEXT,
                category TEXT,
                message TEXT,
                raw_line TEXT,
                UNIQUE(timestamp, terminal_id, source_system, raw_line)
            )
        """)

        # 2. AI学習データ (MT4/MT5統合)
        self._ensure_ai_learning_schema(conn)

        # 3. 推論シグナル
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS inference_signals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME,
                terminal_id TEXT,
                source_system TEXT DEFAULT 'MT4',
                symbol TEXT,
                timeframe TEXT,
                preset TEXT,
                signal INTEGER,
                confidence REAL,
                reason TEXT,
                request_count INTEGER,
                UNIQUE(timestamp, terminal_id, source_system, request_count)
            )
        """)

        # 4. トレードイベント (売買実行・決済)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS trade_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME,
                terminal_id TEXT,
                source_system TEXT DEFAULT 'MT4',
                broker TEXT,
                ticket INTEGER,
                type TEXT,
                order_type TEXT,
                symbol TEXT,
                lots REAL,
                price REAL,
                profit_pips REAL,
                signal INTEGER,
                confidence REAL,
                message TEXT,
                UNIQUE(timestamp, terminal_id, source_system, ticket, type)
            )
        """)

        conn.commit()

    def _ensure_ai_learning_schema(self, conn: sqlite3.Connection):
        """ai_learning_data のスキーマを最新に保つ"""
        cursor = conn.cursor()

        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='ai_learning_data'"
        )
        exists = cursor.fetchone() is not None

        def create_latest(table_name: str):
            cursor.execute(
                f"""
                CREATE TABLE IF NOT EXISTS {table_name} (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp DATETIME,
                    symbol TEXT,
                    timeframe TEXT,
                    direction TEXT,
                    entry_price REAL,
                    pattern_type TEXT,
                    ema12 REAL,
                    ema25 REAL,
                    ema100 REAL,
                    atr REAL,
                    adx REAL,
                    channel_width REAL,
                    tick_volume INTEGER,
                    bar_range REAL,
                    hour INTEGER,
                    day_of_week INTEGER,
                    algo_level REAL,
                    noise_ratio REAL,
                    confidence REAL,
                    spread INTEGER,
                    spread_max INTEGER,
                    tick_vol_surge REAL,
                    atr_spike_ratio REAL,
                    spoofing_suspect TEXT,
                    price_change_pct REAL,
                    terminal_id TEXT,
                    source_system TEXT,
                    broker TEXT,
                    UNIQUE(timestamp, symbol, direction, entry_price, source_system)
                )
                """
            )

        if not exists:
            create_latest("ai_learning_data")
            return

        # 既存列チェック
        cursor.execute("PRAGMA table_info(ai_learning_data)")
        cols = [r[1] for r in cursor.fetchall()]
        
        # broker カラムがなければ追加
        if "broker" not in cols:
            try:
                cursor.execute("ALTER TABLE ai_learning_data ADD COLUMN broker TEXT")
                conn.commit()
            except Exception:
                pass  # 既に存在する場合は無視

    def insert_ai_learning_data(self, data_list, terminal_id, source_system: str = 'MT4', broker: str = None):
        """AI学習データを一括挿入（重複は無視）"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        df = pd.DataFrame(data_list)
        df['terminal_id'] = terminal_id
        df['source_system'] = source_system
        if broker:
            df['broker'] = broker
        
        columns = [
            'timestamp', 'symbol', 'timeframe', 'direction', 'entry_price',
            'pattern_type', 'ema12', 'ema25', 'ema100', 'atr', 'adx',
            'channel_width', 'tick_volume', 'bar_range', 'hour', 'day_of_week',
            'algo_level', 'noise_ratio', 'confidence', 'spread', 'spread_max',
            'tick_vol_surge', 'atr_spike_ratio', 'spoofing_suspect', 'price_change_pct',
            'terminal_id', 'source_system', 'broker'
        ]
        
        for col in columns:
            if col not in df.columns:
                df[col] = None

        placeholders = ', '.join(['?'] * len(columns))
        sql = f"INSERT OR IGNORE INTO ai_learning_data ({', '.join(columns)}) VALUES ({placeholders})"
        
        cursor.executemany(sql, df[columns].values.tolist())
        conn.commit()
        return cursor.rowcount

    def insert_inference_signals(self, signals_list, source_system: str = 'MT4'):
        """推論シグナルを一括挿入"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        columns = [
            'timestamp', 'terminal_id', 'source_system', 'symbol', 'timeframe', 
            'preset', 'signal', 'confidence', 'reason', 'request_count'
        ]
        
        placeholders = ', '.join(['?'] * len(columns))
        sql = f"INSERT OR IGNORE INTO inference_signals ({', '.join(columns)}) VALUES ({placeholders})"
        
        values = []
        for s in signals_list:
            row = [s.get(col) if col != 'source_system' else source_system for col in columns]
            values.append(row)
            
        cursor.executemany(sql, values)
        conn.commit()
        return cursor.rowcount

    def insert_trade_events(self, events_list, source_system: str = 'MT4', broker: str = None):
        """トレードイベントを一括挿入"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        columns = [
            'timestamp', 'terminal_id', 'source_system', 'broker', 'ticket', 
            'type', 'order_type', 'symbol', 'lots', 'price', 'profit_pips', 
            'signal', 'confidence', 'message'
        ]
        
        placeholders = ', '.join(['?'] * len(columns))
        sql = f"INSERT OR IGNORE INTO trade_events ({', '.join(columns)}) VALUES ({placeholders})"
        
        values = []
        for e in events_list:
            row = []
            for col in columns:
                if col == 'source_system':
                    row.append(source_system)
                elif col == 'broker' and broker:
                    row.append(broker)
                else:
                    row.append(e.get(col))
            values.append(row)
            
        cursor.executemany(sql, values)
        conn.commit()
        return cursor.rowcount

    def insert_log_entries(self, entries_list, source_system: str = 'MT4'):
        """ログエントリを一括挿入"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        columns = [
            'timestamp', 'terminal_id', 'source_system', 'ea_name', 
            'log_level', 'category', 'message', 'raw_line'
        ]
        
        placeholders = ', '.join(['?'] * len(columns))
        sql = f"INSERT OR IGNORE INTO log_entries ({', '.join(columns)}) VALUES ({placeholders})"
        
        values = []
        for entry in entries_list:
            row = [entry.get(col) if col != 'source_system' else source_system for col in columns]
            values.append(row)
            
        cursor.executemany(sql, values)
        conn.commit()
        return cursor.rowcount

    def get_stats(self) -> dict:
        """データベース統計を取得"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        stats = {}
        for table in ['ai_learning_data', 'inference_signals', 'trade_events', 'log_entries']:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            total = cursor.fetchone()[0]
            
            cursor.execute(f"SELECT source_system, COUNT(*) FROM {table} GROUP BY source_system")
            by_source = {row[0] or 'unknown': row[1] for row in cursor.fetchall()}
            
            stats[table] = {'total': total, 'by_source': by_source}
        
        return stats

    def export_ai_learning_csv(self, output_path: str, source_system: str = None) -> int:
        """AI学習データをCSVにエクスポート"""
        conn = self._get_connection()
        
        query = "SELECT * FROM ai_learning_data"
        params = []
        if source_system:
            query += " WHERE source_system = ?"
            params.append(source_system)
        query += " ORDER BY timestamp"
        
        df = pd.read_sql_query(query, conn, params=params)
        df.to_csv(output_path, index=False)
        return len(df)

    def close(self):
        if self.conn:
            self.conn.close()
            self.conn = None


if __name__ == "__main__":
    # テスト用初期化
    db = UnifiedLogDatabase("test_unified_logs.db")
    print("Database initialized successfully.")
    print(f"Stats: {db.get_stats()}")
    db.close()
