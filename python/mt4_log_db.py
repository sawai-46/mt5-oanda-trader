import sqlite3
import pandas as pd
from pathlib import Path
from datetime import datetime
import logging

class MT4LogDatabase:
    """
    MT4ログおよびAI学習データを集中管理するSQLiteデータベースクラス
    """
    def __init__(self, db_path: str):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = None
        self._init_db()

    def _get_connection(self):
        if self.conn is None:
            self.conn = sqlite3.connect(self.db_path)
            # 辞書形式で結果を取得できるように設定
            self.conn.row_factory = sqlite3.Row
        return self.conn

    def _init_db(self):
        """テーブルの初期化"""
        conn = self._get_connection()
        cursor = conn.cursor()

        # 基本PRAGMA（大量INSERT時の安定性/速度向上）
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA synchronous=NORMAL")

        # 1. 一般ログエントリ (MT4標準ログ)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS log_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME,
                terminal_id TEXT,
                ea_name TEXT,
                log_level TEXT,
                category TEXT,
                message TEXT,
                raw_line TEXT,
                UNIQUE(timestamp, terminal_id, raw_line)
            )
        """)

        # 2. AI学習データ (PullbackEntry & AI_Trader 統合)
        # 両方のフォーマットのカラムを網羅
        # ※ 既存DBでは UNIQUE(timestamp, symbol, direction, entry_price) があるため、
        #    source_system を含めた一意性へ変更するにはテーブル再構築が必要。
        self._ensure_ai_learning_schema(conn)

        # 3. 推論シグナル (AI_TraderのRequest/Response統合)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS inference_signals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME,
                terminal_id TEXT,
                symbol TEXT,
                timeframe TEXT,
                preset TEXT,
                signal INTEGER,
                confidence REAL,
                reason TEXT,
                request_count INTEGER,
                UNIQUE(timestamp, terminal_id, request_count)
            )
        """)

        # 4. トレードイベント (売買実行・決済)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS trade_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME,
                terminal_id TEXT,
                ticket INTEGER,
                type TEXT,                -- ENTRY, EXIT, PARTIAL_CLOSE, SKIP
                order_type TEXT,          -- BUY, SELL
                symbol TEXT,
                lots REAL,
                price REAL,
                profit_pips REAL,
                signal INTEGER,
                confidence REAL,
                message TEXT,
                UNIQUE(timestamp, terminal_id, ticket, type)
            )
        """)

        conn.commit()

    def _ensure_ai_learning_schema(self, conn: sqlite3.Connection):
        """ai_learning_data のスキーマを最新に保つ（必要に応じてマイグレーション）"""
        cursor = conn.cursor()

        # 既存テーブル有無
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
        has_source_system = "source_system" in cols

        # 既存のUNIQUEが旧キー(4列)のままかチェック
        cursor.execute("PRAGMA index_list(ai_learning_data)")
        index_rows = cursor.fetchall()
        unique_indexes = [r for r in index_rows if r[2] == 1]  # seq, name, unique, origin, partial

        def unique_columns(index_name: str):
            cursor.execute(f"PRAGMA index_info({index_name})")
            return [r[2] for r in cursor.fetchall()]

        has_old_unique = False
        has_new_unique = False
        for r in unique_indexes:
            index_name = r[1]
            uc = unique_columns(index_name)
            if uc == ["timestamp", "symbol", "direction", "entry_price"]:
                has_old_unique = True
            if uc == ["timestamp", "symbol", "direction", "entry_price", "source_system"]:
                has_new_unique = True

        if has_source_system and has_new_unique:
            return

        # マイグレーション: テーブル再構築（旧UNIQUE制約はDROP不可のため）
        cursor.execute("BEGIN")
        try:
            create_latest("ai_learning_data_new")

            # 旧テーブル -> 新テーブルへコピー
            # source_system は既存列から推定（confidence優先）
            cursor.execute(
                """
                INSERT OR IGNORE INTO ai_learning_data_new (
                    timestamp, symbol, timeframe, direction, entry_price, pattern_type,
                    ema12, ema25, ema100, atr, adx, channel_width, tick_volume, bar_range,
                    hour, day_of_week, algo_level, noise_ratio, confidence, spread, spread_max,
                    tick_vol_surge, atr_spike_ratio, spoofing_suspect, price_change_pct,
                    terminal_id, source_system
                )
                SELECT
                    timestamp, symbol, timeframe, direction, entry_price, pattern_type,
                    ema12, ema25, ema100, atr, adx, channel_width, tick_volume, bar_range,
                    hour, day_of_week, algo_level, noise_ratio, confidence, spread, spread_max,
                    tick_vol_surge, atr_spike_ratio, spoofing_suspect, price_change_pct,
                    terminal_id,
                    CASE
                        WHEN confidence IS NOT NULL THEN 'ai_trader'
                        WHEN algo_level IS NOT NULL THEN 'pullbackentry'
                        ELSE 'unknown'
                    END
                FROM ai_learning_data
                """
            )

            cursor.execute("DROP TABLE ai_learning_data")
            cursor.execute("ALTER TABLE ai_learning_data_new RENAME TO ai_learning_data")
            cursor.execute("COMMIT")
        except Exception:
            cursor.execute("ROLLBACK")
            raise

    def insert_ai_learning_data(self, data_list, terminal_id, source_system: str | None = None):
        """AI学習データを一括挿入（重複は無視）"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        # DataFrame化してカラムを正規化
        df = pd.DataFrame(data_list)
        df['terminal_id'] = terminal_id
        if source_system is not None:
            df['source_system'] = source_system
        
        # NULL埋めしてカラムを合わせる
        columns = [
            'timestamp', 'symbol', 'timeframe', 'direction', 'entry_price',
            'pattern_type', 'ema12', 'ema25', 'ema100', 'atr', 'adx',
            'channel_width', 'tick_volume', 'bar_range', 'hour', 'day_of_week',
            'algo_level', 'noise_ratio', 'confidence', 'spread', 'spread_max',
            'tick_vol_surge', 'atr_spike_ratio', 'spoofing_suspect', 'price_change_pct',
            'terminal_id', 'source_system'
        ]
        
        for col in columns:
            if col not in df.columns:
                df[col] = None

        # インサートSQL生成
        placeholders = ', '.join(['?'] * len(columns))
        sql = f"INSERT OR IGNORE INTO ai_learning_data ({', '.join(columns)}) VALUES ({placeholders})"
        
        # 実行
        cursor.executemany(sql, df[columns].values.tolist())
        conn.commit()
        return cursor.rowcount

    def insert_inference_signals(self, signals_list):
        """推論シグナルを一括挿入"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        columns = [
            'timestamp', 'terminal_id', 'symbol', 'timeframe', 'preset',
            'signal', 'confidence', 'reason', 'request_count'
        ]
        
        placeholders = ', '.join(['?'] * len(columns))
        sql = f"INSERT OR IGNORE INTO inference_signals ({', '.join(columns)}) VALUES ({placeholders})"
        
        # データをリスト化して実行
        values = []
        for s in signals_list:
            values.append([s.get(col) for col in columns])
            
        cursor.executemany(sql, values)
        conn.commit()
        return cursor.rowcount

    def insert_trade_events(self, events_list):
        """トレードイベントを一括挿入"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        columns = [
            'timestamp', 'terminal_id', 'ticket', 'type', 'order_type',
            'symbol', 'lots', 'price', 'profit_pips', 'signal', 'confidence', 'message'
        ]
        
        placeholders = ', '.join(['?'] * len(columns))
        sql = f"INSERT OR IGNORE INTO trade_events ({', '.join(columns)}) VALUES ({placeholders})"
        
        values = []
        for e in events_list:
            values.append([e.get(col) for col in columns])
            
        cursor.executemany(sql, values)
        conn.commit()
        return cursor.rowcount

    def insert_log_entries(self, entries_list):
        """ログエントリを一括挿入"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        columns = [
            'timestamp', 'terminal_id', 'ea_name', 'log_level',
            'category', 'message', 'raw_line'
        ]
        
        placeholders = ', '.join(['?'] * len(columns))
        sql = f"INSERT OR IGNORE INTO log_entries ({', '.join(columns)}) VALUES ({placeholders})"
        
        values = []
        for l in entries_list:
            values.append([l.get(col) for col in columns])
            
        cursor.executemany(sql, values)
        conn.commit()
        return cursor.rowcount

    def close(self):
        if self.conn:
            self.conn.close()
            self.conn = None

if __name__ == "__main__":
    # テスト用初期化
    db = MT4LogDatabase("test_mt4_logs.db")
    print("Database initialized successfully.")
    db.close()
