"""
Unified MT4/MT5 Log Synchronization Script
MT4とMT5の両方のログをSQLiteデータベースに同期する統合スクリプト
"""

import os
import csv
import re
import json
import shutil
import argparse
from pathlib import Path
from datetime import datetime

# 同じディレクトリからインポート
from unified_log_db import UnifiedLogDatabase


def load_config(config_path: str) -> dict:
    """設定ファイルを読み込む（config.local.yamlがあれば上書きマージ）"""
    import yaml
    
    config_path = Path(config_path)
    config = {}
    
    if config_path.exists():
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f) or {}
    
    # config.local.yaml があれば上書き
    local_path = config_path.parent / 'config.local.yaml'
    if local_path.exists():
        with open(local_path, 'r', encoding='utf-8') as f:
            local_config = yaml.safe_load(f) or {}
        # 深いマージ
        for key, value in local_config.items():
            if isinstance(value, dict) and isinstance(config.get(key), dict):
                config[key].update(value)
            else:
                config[key] = value
    
    return config


class UnifiedLogSync:
    """
    MT4/MT5の各種ログファイルをデータベースに同期するクラス
    """
    
    def __init__(self, config_path: str, *, dry_run: bool = False, no_cleanup: bool = False, limit_files: int = None):
        self.config = load_config(config_path)
        self.config_path = str(config_path)
        self.dry_run = dry_run
        self.no_cleanup = no_cleanup
        self.limit_files = limit_files
        
        # データベースパスの取得
        db_path = self.config.get('logging', {}).get('database_path', 'unified_logs.db')
        print(f"Database path: {db_path}")
        self.db = UnifiedLogDatabase(db_path)

        self.delete_after_sync = self.config.get('logging', {}).get('delete_after_sync', False)
        archive_dir = self.config.get('logging', {}).get('archive_dir')
        self.archive_dir = Path(os.path.expandvars(os.path.expanduser(archive_dir))).resolve() if archive_dir else None
        
        # MT4ターミナル設定
        self.mt4_terminals = []
        seen_base_dirs = set()
        for t in self.config.get('mt4_terminals', []) or []:
            terminal_id = t.get('id', 'unknown')
            data_dir = t.get('data_dir')
            if not data_dir:
                continue
            base_dir = Path(data_dir).parent
            base_dir_key = str(base_dir).lower()
            if base_dir_key in seen_base_dirs:
                print(f"  [SKIP] Duplicate path: {base_dir}")
                continue
            seen_base_dirs.add(base_dir_key)
            self.mt4_terminals.append({
                "id": terminal_id, 
                "base_dir": base_dir, 
                "source_system": "MT4",
                "broker": t.get('broker', 'Rakuten')
            })
        
        # MT5ターミナル設定
        self.mt5_terminals = []
        for t in self.config.get('mt5_terminals', []) or []:
            terminal_id = t.get('id', 'unknown')
            data_dir = t.get('data_dir')
            if not data_dir:
                continue
            base_dir = Path(data_dir).parent if Path(data_dir).exists() else Path(data_dir)
            base_dir_key = str(base_dir).lower()
            if base_dir_key in seen_base_dirs:
                print(f"  [SKIP] Duplicate path: {base_dir}")
                continue
            seen_base_dirs.add(base_dir_key)
            self.mt5_terminals.append({
                "id": terminal_id, 
                "base_dir": base_dir,
                "source_system": "MT5",
                "broker": t.get('broker', 'OANDA')
            })

    def sync_all(self):
        """すべてのログタイプを同期"""
        cleanup_mode = "none"
        if self.delete_after_sync and self.archive_dir:
            cleanup_mode = f"archive -> {self.archive_dir}"
        elif self.delete_after_sync:
            cleanup_mode = "delete"
        if self.no_cleanup:
            cleanup_mode = "none (forced by --no-cleanup)"
        if self.dry_run:
            cleanup_mode = f"{cleanup_mode} (dry-run)"
        
        print(f"Starting unified sync (Config: {self.config_path}, Cleanup: {cleanup_mode})...")
        print(f"MT4 terminals: {len(self.mt4_terminals)}, MT5 terminals: {len(self.mt5_terminals)}")

        # MT4ターミナル同期
        for t in self.mt4_terminals:
            self._sync_terminal(t)
        
        # MT5ターミナル同期
        for t in self.mt5_terminals:
            self._sync_terminal(t)

        print("\nSync process completed.")
        print(f"Stats: {self.db.get_stats()}")

    def _sync_terminal(self, terminal: dict):
        """単一ターミナルを同期"""
        terminal_id = terminal["id"]
        base_dir = terminal["base_dir"]
        source_system = terminal["source_system"]
        broker = terminal.get("broker")
        
        print(f"\n=== {source_system}: {terminal_id} ({base_dir}) ===")
        
        if not base_dir.exists():
            print(f"  [WARN] Directory not found: {base_dir}")
            return
        
        # AI学習データの同期
        self._sync_ai_learning_data(base_dir, terminal_id, source_system, broker)
        
        # トレード履歴の同期
        self._sync_trade_history(base_dir, terminal_id, source_system, broker)
        
        # システムログの同期
        self._sync_system_logs(base_dir, terminal_id, source_system)
        
        # 推論ログの同期
        self._sync_inference_logs(base_dir, terminal_id, source_system)

    def _cleanup_file(self, file_path: Path, base_dir: Path = None):
        """同期完了後のファイルクリーンアップ"""
        if self.no_cleanup or self.dry_run:
            return
        if not self.delete_after_sync:
            return
        if not file_path.exists():
            return

        if self.archive_dir:
            try:
                rel = file_path.relative_to(base_dir) if base_dir else Path(file_path.name)
                dest = (self.archive_dir / rel).resolve()
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(file_path), str(dest))
                print(f"  [CLEANUP] Archived: {rel} -> {dest}")
            except Exception as e:
                print(f"  [CLEANUP] Error archiving {file_path}: {e}")
            return

        try:
            os.remove(file_path)
            print(f"  [CLEANUP] Deleted: {file_path.name}")
        except Exception as e:
            print(f"  [CLEANUP] Error deleting {file_path}: {e}")

    def _normalize_timestamp(self, ts: str) -> str:
        if not ts:
            return None
        s = str(ts).strip()
        if not s:
            return None
        s2 = s.replace('.', '-')
        for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%S"):
            try:
                dt = datetime.strptime(s2, fmt)
                return dt.strftime("%Y-%m-%d %H:%M:%S")
            except Exception:
                continue
        return s

    def _terminal_id_from_filename(self, filename: str, prefix: str):
        if not filename or not filename.startswith(prefix):
            return None
        rest = filename[len(prefix):]
        # drop extension
        if "." in rest:
            rest = rest.rsplit(".", 1)[0]
        # terminal_id is the first token before the first underscore
        return rest.split("_", 1)[0] if rest else None

    def _sync_ai_learning_data(self, base_dir: Path, terminal_id: str, source_system: str, broker: str, chunk_size: int = 5000):
        """AI学習データ(CSV)を同期"""
        search_dirs = [
            base_dir / "data" / "AI_Learning",
            base_dir / "AI_Learning",
            base_dir / "OneDriveLogs" / "data" / "AI_Learning"
        ]
        ai_learning_dir = None
        for d in search_dirs:
            if d.exists():
                ai_learning_dir = d
                break
        
        if not ai_learning_dir:
            return

        files = sorted(ai_learning_dir.glob("AI_Learning_Data_*.csv"))
        if self.limit_files:
            files = files[:self.limit_files]
        if not files:
            return
        
        print(f"  Found {len(files)} AI learning data files.")

        for file_path in files:
            file_terminal_id = self._terminal_id_from_filename(file_path.name, "AI_Learning_Data_") or terminal_id
            imported_total = 0
            chunk = []
            try:
                with open(file_path, 'r', encoding='ansi', errors='ignore') as f:
                    first_line = f.readline()
                    if not first_line:
                        self._cleanup_file(file_path, base_dir)
                        continue
                    is_header = "Timestamp" in first_line or "Symbol" in first_line

                with open(file_path, 'r', encoding='ansi', errors='ignore') as f:
                    if is_header:
                        reader = csv.DictReader(f)
                        for row in reader:
                            normalized_row = {
                                str(k).lower().replace(' ', '_'): v
                                for k, v in (row or {}).items()
                                if k
                            }
                            normalized_row['timestamp'] = self._normalize_timestamp(normalized_row.get('timestamp'))
                            normalized_row['source_system'] = source_system
                            chunk.append(normalized_row)
                            if len(chunk) >= chunk_size:
                                imported_total += self.db.insert_ai_learning_data(chunk, file_terminal_id, source_system, broker)
                                chunk = []
                    else:
                        f.seek(0)
                        reader = csv.reader(f)
                        for row in reader:
                            if not row or len(row) < 19:
                                continue
                            cols = [
                                "timestamp", "symbol", "timeframe", "direction", "entry_price", "pattern_type",
                                "ema12", "ema25", "ema100", "atr", "adx", "channel_width", "tick_volume",
                                "bar_range", "hour", "day_of_week", "confidence", "spread", "spread_max"
                            ]
                            d = dict(zip(cols, row[:len(cols)]))
                            d['timestamp'] = self._normalize_timestamp(d.get('timestamp'))
                            d['source_system'] = source_system
                            chunk.append(d)
                            if len(chunk) >= chunk_size:
                                imported_total += self.db.insert_ai_learning_data(chunk, file_terminal_id, source_system, broker)
                                chunk = []

                if chunk:
                    imported_total += self.db.insert_ai_learning_data(chunk, file_terminal_id, source_system, broker)
                
                print(f"    [{file_terminal_id}] Imported {imported_total} rows from {file_path.name}")
                self._cleanup_file(file_path, base_dir)
            except Exception as e:
                print(f"    Error processing {file_path}: {e}")

    def _sync_trade_history(self, base_dir: Path, terminal_id: str, source_system: str, broker: str):
        """トレード履歴を同期"""
        trade_dirs = [base_dir / "Trade_History", base_dir / "data" / "Trade_History"]
        trade_dir = None
        for d in trade_dirs:
            if d.exists():
                trade_dir = d
                break
        if not trade_dir:
            return

        files = sorted(trade_dir.glob("Trade_Log_*.csv"))
        if self.limit_files:
            files = files[:self.limit_files]
        if not files:
            return
        
        print(f"  Found {len(files)} trade log files.")

        for file_path in files:
            file_terminal_id = self._terminal_id_from_filename(file_path.name, "Trade_Log_") or terminal_id
            events = []
            try:
                with open(file_path, 'r', encoding='ansi', errors='ignore') as f:
                    reader = csv.DictReader(f, delimiter=';')
                    for row in reader:
                        normalized = {str(k).lower(): v for k, v in (row or {}).items() if k}
                        # DEBUG: Print keys for the first row of US30 or similar
                        if 'us30' in file_path.name.lower() or 'jp225' in file_path.name.lower():
                            print(f"DEBUG KEYS: {list(normalized.keys())}")
                        
                        ts_raw = (normalized.get('timestamp') or '').replace('.', '-')
                        normalized['timestamp'] = self._normalize_timestamp(ts_raw)
                        normalized['terminal_id'] = file_terminal_id
                        if 'event' in normalized:
                            normalized['type'] = normalized['event']
                        if 'direction' in normalized:
                            normalized['order_type'] = normalized['direction']
                        
                        # Map reason/comment to message
                        if 'message' not in normalized:
                            if 'reason' in normalized:
                                normalized['message'] = normalized['reason']
                            elif 'comment' in normalized:
                                normalized['message'] = normalized['comment']
                            elif 'desc' in normalized:
                                normalized['message'] = normalized['desc']
                            elif 'details' in normalized:
                                normalized['message'] = normalized['details']
                        
                        if normalized.get('event') == 'ENTRY_FAILED':
                             print(f"DEBUG FAIL ROW: {normalized}")

                        events.append(normalized)
                
                if events:
                    count = self.db.insert_trade_events(events, source_system, broker)
                    print(f"    [{file_terminal_id}] Imported {count} trade events from {file_path.name}")
                
                self._cleanup_file(file_path, base_dir)
            except Exception as e:
                print(f"    Error processing trade log {file_path}: {e}")

    def _sync_system_logs(self, base_dir: Path, terminal_id: str, source_system: str):
        """システムログを同期"""
        # base_dir is .../MQL4/Files/OneDriveLogs/data
        # We want .../MQL4/Logs
        mql_logs_dir = base_dir.parent.parent.parent / "Logs"
        if not mql_logs_dir.exists():
             # Try one level up if base_dir was just OneDriveLogs
             mql_logs_dir = base_dir.parent.parent / "Logs"
             
        journal_logs_dir = base_dir.parent.parent.parent.parent / "logs"

        log_dirs = [base_dir / "SystemLogs", base_dir / "data" / "logs", mql_logs_dir, journal_logs_dir]
        print(f"DEBUG: Searching logs in {log_dirs}")
        
        for log_dir in log_dirs:
            if not log_dir.exists():
                continue
            
            files = sorted(list(log_dir.glob("*.log")) + list(log_dir.glob("System_Log_*.csv")))
            if self.limit_files:
                files = files[:self.limit_files]
            
            for file_path in files:
                entries = []
                try:
                    file_ts = datetime.fromtimestamp(file_path.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
                    
                    # Try to get date from filename for YYYYMMDD.log
                    is_daily_log = False
                    date_prefix = ""
                    if re.match(r"\d{8}\.log", file_path.name):
                        is_daily_log = True
                        dstr = file_path.name[:8]
                        date_prefix = f"{dstr[:4]}-{dstr[4:6]}-{dstr[6:]}"

                    encoding = 'cp932'
                    try:
                        with open(file_path, 'rb') as f_chk:
                            head = f_chk.read(2)
                            if head == b'\xff\xfe' or head == b'\xfe\xff':
                                encoding = 'utf-16'
                    except:
                        pass

                    with open(file_path, 'r', encoding=encoding, errors='replace') as f:
                        for line in f:
                            if not line.strip():
                                continue
                            
                            ts = file_ts # default
                            message = line.strip()

                            if is_daily_log:
                                # Start with: Code TAB Time TAB Source TAB Message
                                # e.g. 2	14:05:31.690	Source	Message
                                parts = line.split('\t')
                                if len(parts) >= 3:
                                    # Try to extract time from parts[1]
                                    t_str = parts[1].strip()
                                    if re.match(r"\d{2}:\d{2}:\d{2}", t_str):
                                        ts = f"{date_prefix} {t_str}"
                                        # Message is the rest
                                        message = "\t".join(parts[2:]).strip()
                                
                                # Fallback regex for other formats if split failed
                                if ts == file_ts:
                                     m = re.search(r"(\d{2}:\d{2}:\d{2})", line)
                                     if m:
                                         ts = f"{date_prefix} {m.group(1)}"
                            else:
                                # Existing regex for full date format
                                m = re.search(r"(\d{4}[./-]\d{2}[./-]\d{2}\s+\d{2}:\d{2}(?::\d{2})?)", line)
                                if m:
                                    ts = self._normalize_timestamp(m.group(1))

                            entries.append({
                                "timestamp": ts,
                                "terminal_id": terminal_id,
                                "message": message,
                                "raw_line": line.strip()
                            })
                    
                    if entries:
                        count = self.db.insert_log_entries(entries, source_system)
                        print(f"    Imported {count} log entries from {file_path.name}")
                    
                    self._cleanup_file(file_path, base_dir)
                except Exception as e:
                    print(f"    Error processing log {file_path}: {e}")

    def _sync_inference_logs(self, base_dir: Path, terminal_id: str, source_system: str):
        """推論ログを同期"""
        inf_dir = base_dir / "AI_Trader_Logs"
        if not inf_dir.exists():
            return

        files = sorted(
            list(inf_dir.glob("*.jsonl"))
            + list(inf_dir.glob("inference_*.log"))
        )
        if self.limit_files:
            files = files[:self.limit_files]
        if not files:
            return

        for file_path in files:
            if file_path.suffix.lower() == ".jsonl":
                signals = []
                try:
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                        for line in f:
                            if not line.strip():
                                continue
                            try:
                                obj = json.loads(line)
                                if 'signal' in obj or 'request_count' in obj:
                                    signals.append({
                                        'timestamp': self._normalize_timestamp(obj.get('timestamp')),
                                        'terminal_id': obj.get('terminal_id') or terminal_id,
                                        'symbol': obj.get('symbol'),
                                        'timeframe': obj.get('timeframe'),
                                        'preset': obj.get('preset'),
                                        'signal': obj.get('signal'),
                                        'confidence': obj.get('confidence'),
                                        'reason': obj.get('reason'),
                                        'request_count': obj.get('request_count'),
                                    })
                            except json.JSONDecodeError:
                                continue

                    if signals:
                        inserted = self.db.insert_inference_signals(signals, source_system)
                        print(f"    [{terminal_id}] Imported {inserted} inference signals from {file_path.name}")

                    self._cleanup_file(file_path, base_dir)
                except Exception as e:
                    print(f"    Error processing inference jsonl {file_path}: {e}")

    def close(self):
        self.db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Sync MT4/MT5 logs into unified SQLite DB")
    parser.add_argument("--config", type=str, default=str(Path(__file__).parent / "config.yaml"),
                        help="Path to config.yaml")
    parser.add_argument("--dry-run", action="store_true",
                        help="Do not delete/archive source files")
    parser.add_argument("--no-cleanup", action="store_true",
                        help="Disable delete/archive even if delete_after_sync is true")
    parser.add_argument("--limit-files", type=int, default=None,
                        help="Limit number of files per category")
    parser.add_argument("--print-config", action="store_true",
                        help="Print effective config and exit")
    parser.add_argument("--stats", action="store_true",
                        help="Print database stats and exit")
    args = parser.parse_args()

    if args.print_config:
        config = load_config(args.config)
        print(json.dumps(config, ensure_ascii=False, indent=2))
        raise SystemExit(0)

    sync = UnifiedLogSync(
        args.config,
        dry_run=args.dry_run,
        no_cleanup=args.no_cleanup,
        limit_files=args.limit_files,
    )
    
    if args.stats:
        print(json.dumps(sync.db.get_stats(), ensure_ascii=False, indent=2))
        sync.close()
        raise SystemExit(0)
    
    sync.sync_all()
    sync.close()
