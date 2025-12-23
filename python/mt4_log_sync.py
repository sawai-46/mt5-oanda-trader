import os
import csv
import re
import json
import shutil
import argparse
from pathlib import Path
from datetime import datetime
from mt4_log_db import MT4LogDatabase
from config_loader import load_config

class MT4LogSync:
    """
    MT4の各種ログファイルをデータベースに同期するクラス
    """
    def __init__(self, config_path: str, *, dry_run: bool = False, no_cleanup: bool = False, limit_files: int | None = None):
        self.config = load_config(config_path)
        self.config_path = str(config_path)
        self.dry_run = dry_run
        self.no_cleanup = no_cleanup
        self.limit_files = limit_files
        
        # データベースパスの取得
        db_path = self.config.get('logging', {}).get('database_path', 'mt4_logs.db')
        self.db = MT4LogDatabase(db_path)

        self.delete_after_sync = self.config.get('logging', {}).get('delete_after_sync', False)
        archive_dir = (
            self.config.get('logging', {}).get('archive_dir')
            or self.config.get('archive_dir')
        )
        self.archive_dir = Path(os.path.expandvars(os.path.expanduser(archive_dir))).resolve() if archive_dir else None
        
        # 同期対象の設定
        self.terminals = []
        # loggingセクション、またはトップレベルから探索
        ea_logs_dir = self.config.get('logging', {}).get('ea_logs_dir') or self.config.get('ea_logs_dir')
        
        if ea_logs_dir and os.path.exists(ea_logs_dir):
            print(f"Using aggregate log directory: {ea_logs_dir}")
            self.ea_logs_base = Path(ea_logs_dir)
            self.terminals.append({"id": "aggregate", "base_dir": self.ea_logs_base})
        else:
            self.ea_logs_base = None
            seen_base_dirs = set()
            for t in self.config.get('mt4_terminals', []) or []:
                terminal_cfg_id = t.get('id', 'unknown')
                data_dir = t.get('data_dir')
                if not data_dir:
                    continue
                
                base_dir = Path(data_dir).parent
                base_dir_key = str(base_dir).lower()
                if base_dir_key in seen_base_dirs:
                    continue
                seen_base_dirs.add(base_dir_key)
                self.terminals.append({"id": terminal_cfg_id, "base_dir": base_dir})

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
        print(f"Starting sync process (Config: {self.config_path}, Cleanup: {cleanup_mode})...")

        for t in self.terminals:
            terminal_id = t["id"]
            base_dir = t["base_dir"]
            print(f"\n=== Target: {terminal_id} ({base_dir}) ===")

            # 1. AI学習データの同期
            self.sync_ai_learning_data(base_dir)

            # 2. トレード履歴の同期
            self.sync_trade_history(base_dir)

            # 3. システムログの同期
            self.sync_system_logs(base_dir, terminal_id)
            
            # 4. 推論ログの同期
            self.sync_inference_logs(base_dir, terminal_id)

        print("\nSync process completed.")

    def _cleanup_file(self, file_path: Path, base_dir: Path | None = None):
        """同期完了後のファイルクリーンアップ（削除 or アーカイブ移動）"""
        if self.no_cleanup or self.dry_run:
            return
        if not self.delete_after_sync:
            return
        if not file_path.exists():
            return

        # archive_dir が指定されている場合は、削除ではなく移動（退避）する
        if self.archive_dir:
            try:
                if base_dir is not None:
                    rel = file_path.relative_to(base_dir)
                else:
                    rel = Path(file_path.name)
                dest = (self.archive_dir / rel).resolve()
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(file_path), str(dest))
                print(f"  [CLEANUP] Archived: {rel} -> {dest}")
            except Exception as e:
                # アーカイブ失敗時は削除しない（安全側）
                print(f"  [CLEANUP] Error archiving {file_path}: {e}")
            return

        # archive_dir が無ければ従来どおり削除
        try:
            os.remove(file_path)
            print(f"  [CLEANUP] Deleted: {file_path.name}")
        except Exception as e:
            print(f"  [CLEANUP] Error deleting {file_path}: {e}")

    def _normalize_timestamp(self, ts: str | None) -> str | None:
        if not ts:
            return None
        s = str(ts).strip()
        if not s:
            return None
        # common MT4 formats: YYYY.MM.DD HH:MM(:SS)
        s2 = s.replace('.', '-')
        for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
            try:
                dt = datetime.strptime(s2, fmt)
                return dt.strftime("%Y-%m-%d %H:%M:%S")
            except Exception:
                continue
        return s

    def sync_ai_learning_data(self, base_dir: Path, chunk_size: int = 5000):
        """AI学習データ(CSV)を同期"""
        search_dirs = [base_dir / "data" / "AI_Learning", base_dir / "AI_Learning"]
        ai_learning_dir = None
        for d in search_dirs:
            if d.exists():
                ai_learning_dir = d
                break
        
        if not ai_learning_dir:
            return

        files = sorted(ai_learning_dir.glob("AI_Learning_Data_*.csv"))
        if self.limit_files is not None:
            files = files[: self.limit_files]
        if not files: return
        print(f"Found {len(files)} AI learning data files.")

        for file_path in files:
            match = re.search(r"AI_Learning_Data_(.*)\.csv", file_path.name)
            terminal_id = "unknown"
            if match:
                parts = match.group(1).split("_")
                if parts and parts[0]: terminal_id = parts[0]

            imported_total = 0
            chunk = []
            try:
                with open(file_path, 'r', encoding='ansi') as f:
                    first_line = f.readline()
                    if not first_line: 
                        self._cleanup_file(file_path, base_dir)
                        continue
                    is_header = "Timestamp" in first_line or "Symbol" in first_line

                with open(file_path, 'r', encoding='ansi') as f:
                    if is_header:
                        reader = csv.DictReader(f)
                        for row in reader:
                            normalized_row = {k.lower().replace(' ', '_'): v for k, v in row.items()}

                            # 出所判定（値が入っている方を優先）
                            if normalized_row.get('confidence') not in (None, ''):
                                normalized_row['source_system'] = 'ai_trader'
                            elif normalized_row.get('algo_level') not in (None, ''):
                                normalized_row['source_system'] = 'pullbackentry'
                            else:
                                normalized_row['source_system'] = normalized_row.get('source_system') or 'unknown'

                            # timestamp正規化
                            normalized_row['timestamp'] = self._normalize_timestamp(normalized_row.get('timestamp'))
                            chunk.append(normalized_row)
                            if len(chunk) >= chunk_size:
                                imported_total += self.db.insert_ai_learning_data(chunk, terminal_id)
                                chunk = []
                    else:
                        f.seek(0)
                        reader = csv.reader(f)
                        for row in reader:
                            if not row:
                                continue
                            source = None
                            cols = None
                            if len(row) == 19:
                                source = 'ai_trader'
                                cols = [
                                    "timestamp", "symbol", "timeframe", "direction", "entry_price", "pattern_type",
                                    "ema12", "ema25", "ema100", "atr", "adx", "channel_width", "tick_volume",
                                    "bar_range", "hour", "day_of_week", "confidence", "spread", "spread_max",
                                ]
                            elif len(row) == 24:
                                source = 'pullbackentry'
                                cols = [
                                    "timestamp", "symbol", "timeframe", "direction", "entry_price", "pattern_type",
                                    "ema12", "ema25", "ema100", "atr", "adx", "channel_width", "tick_volume",
                                    "bar_range", "hour", "day_of_week", "algo_level", "noise_ratio", "spread",
                                    "spread_max", "tick_vol_surge", "atr_spike_ratio", "spoofing_suspect", "price_change_pct",
                                ]
                            else:
                                continue

                            d = dict(zip(cols, row))
                            d = {k.lower().replace(' ', '_'): v for k, v in d.items()}
                            d['source_system'] = source
                            d['timestamp'] = self._normalize_timestamp(d.get('timestamp'))
                            chunk.append(d)
                            if len(chunk) >= chunk_size:
                                imported_total += self.db.insert_ai_learning_data(chunk, terminal_id)
                                chunk = []

                if chunk:
                    imported_total += self.db.insert_ai_learning_data(chunk, terminal_id)
                
                print(f"  [{terminal_id}] Imported {imported_total} rows from {file_path.name}")
                self._cleanup_file(file_path, base_dir)
            except Exception as e:
                print(f"  Error processing {file_path}: {e}")

    def sync_trade_history(self, base_dir: Path):
        """トレード履歴を同期"""
        trade_dirs = [base_dir / "Trade_History", base_dir / "data" / "Trade_History"]
        trade_dir = None
        for d in trade_dirs:
            if d.exists():
                trade_dir = d
                break
        if not trade_dir: return

        files = sorted(trade_dir.glob("Trade_Log_*.csv"))
        if self.limit_files is not None:
            files = files[: self.limit_files]
        if not files: return
        print(f"Found {len(files)} trade log files.")

        for file_path in files:
            terminal_id = "unknown"
            match = re.search(r"Trade_Log_(.*)\.csv", file_path.name)
            if match: terminal_id = match.group(1).split("_")[0]

            events = []
            try:
                with open(file_path, 'r', encoding='ansi') as f:
                    reader = csv.DictReader(f, delimiter=';')
                    for row in reader:
                        normalized = {k.lower(): v for k, v in row.items()}
                        ts = normalized.get('timestamp', '').replace('.', '-')
                        if ts:
                            normalized['timestamp'] = self._normalize_timestamp(ts)
                        normalized['terminal_id'] = terminal_id
                        # マッピング調整
                        if 'event' in normalized: normalized['type'] = normalized['event']
                        if 'direction' in normalized: normalized['order_type'] = normalized['direction']
                        events.append(normalized)
                
                if events:
                    count = self.db.insert_trade_events(events)
                    print(f"  [{terminal_id}] Imported {count} trade events from {file_path.name}")
                
                self._cleanup_file(file_path, base_dir)
            except Exception as e:
                print(f"  Error processing trade log {file_path}: {e}")

    def sync_system_logs(self, base_dir: Path, default_terminal_id: str):
        """システムログを同期"""
        log_dirs = [base_dir / "SystemLogs", base_dir / "data" / "logs"]
        for log_dir in log_dirs:
            if not log_dir.exists(): continue
            
            files = sorted(list(log_dir.glob("*.log")) + list(log_dir.glob("System_Log_*.csv")))
            if self.limit_files is not None:
                files = files[: self.limit_files]
            for file_path in files:
                entries = []
                try:
                    file_ts = datetime.fromtimestamp(file_path.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
                    with open(file_path, 'r', encoding='ansi', errors='ignore') as f:
                        for line in f:
                            if not line.strip(): continue
                            # 行頭にタイムスタンプが含まれる場合は優先
                            m = re.search(r"(\d{4}[./-]\d{2}[./-]\d{2}\s+\d{2}:\d{2}(?::\d{2})?)", line)
                            ts = self._normalize_timestamp(m.group(1)) if m else file_ts
                            entries.append({
                                "timestamp": ts,
                                "terminal_id": default_terminal_id,
                                "message": line.strip(),
                                "raw_line": line.strip()
                            })
                    
                    if entries:
                        count = self.db.insert_log_entries(entries)
                        print(f"  Imported {count} log entries from {file_path.name}")
                    
                    self._cleanup_file(file_path, base_dir)
                except Exception as e:
                    print(f"  Error processing log {file_path}: {e}")

    def sync_inference_logs(self, base_dir: Path, default_terminal_id: str):
        """推論ログを同期（可能なら inference_signals、難しければ log_entries へ）"""
        inf_dir = base_dir / "AI_Trader_Logs"
        if not inf_dir.exists():
            return

        files = sorted(
            list(inf_dir.glob("*.jsonl"))
            + list(inf_dir.glob("inference_*.log"))
            + list(inf_dir.glob("request_*.csv"))
            + list(inf_dir.glob("response_*.csv"))
        )
        if self.limit_files is not None:
            files = files[: self.limit_files]
        if not files:
            return

        def infer_terminal_id_from_filename(p: Path) -> str:
            for prefix in ("request_", "response_", "inference_"):
                if p.name.startswith(prefix):
                    rest = p.name[len(prefix):]
                    return rest.split("_")[0] if rest else default_terminal_id
            return default_terminal_id

        for file_path in files:
            terminal_id = infer_terminal_id_from_filename(file_path)

            # jsonl: inference_signals に寄せられるなら寄せる
            if file_path.suffix.lower() == ".jsonl":
                signals = []
                fallback_lines = []
                try:
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                        for line in f:
                            if not line.strip():
                                continue
                            try:
                                obj = json.loads(line)
                            except Exception:
                                fallback_lines.append(line.strip())
                                continue

                            if not isinstance(obj, dict):
                                fallback_lines.append(line.strip())
                                continue

                            # inference_signals っぽいキーが揃っている場合のみ投入
                            if 'request_count' in obj or 'signal' in obj:
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
                            else:
                                fallback_lines.append(json.dumps(obj, ensure_ascii=False))

                    inserted = 0
                    if signals:
                        inserted = self.db.insert_inference_signals(signals)
                        print(f"  [{terminal_id}] Imported {inserted} inference signals from {file_path.name}")

                    if fallback_lines:
                        # 解析できない行は log_entries に保存
                        file_ts = datetime.fromtimestamp(file_path.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
                        entries = [
                            {
                                'timestamp': file_ts,
                                'terminal_id': terminal_id,
                                'category': 'inference_jsonl',
                                'message': ln,
                                'raw_line': ln,
                            }
                            for ln in fallback_lines
                        ]
                        self.db.insert_log_entries(entries)

                    self._cleanup_file(file_path, base_dir)
                except Exception as e:
                    print(f"  Error processing inference jsonl {file_path}: {e}")
                continue

            # csv/log は log_entries へ（最低限DB化）
            try:
                file_ts = datetime.fromtimestamp(file_path.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
                entries = []
                if file_path.suffix.lower() == ".csv":
                    with open(file_path, 'r', encoding='ansi', errors='ignore') as f:
                        reader = csv.DictReader(f)
                        for row in reader:
                            payload = json.dumps(row, ensure_ascii=False)
                            ts = self._normalize_timestamp(row.get('timestamp') or row.get('time')) or file_ts
                            entries.append({
                                'timestamp': ts,
                                'terminal_id': terminal_id,
                                'category': 'inference_csv',
                                'message': payload,
                                'raw_line': payload,
                            })
                else:
                    with open(file_path, 'r', encoding='ansi', errors='ignore') as f:
                        for line in f:
                            if not line.strip():
                                continue
                            m = re.search(r"(\d{4}[./-]\d{2}[./-]\d{2}\s+\d{2}:\d{2}(?::\d{2})?)", line)
                            ts = self._normalize_timestamp(m.group(1)) if m else file_ts
                            ln = line.strip()
                            entries.append({
                                'timestamp': ts,
                                'terminal_id': terminal_id,
                                'category': 'inference_log',
                                'message': ln,
                                'raw_line': ln,
                            })

                if entries:
                    cnt = self.db.insert_log_entries(entries)
                    print(f"  [{terminal_id}] Imported {cnt} inference log entries from {file_path.name}")

                self._cleanup_file(file_path, base_dir)
            except Exception as e:
                print(f"  Error processing inference log {file_path}: {e}")

    def close(self):
        self.db.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Sync MT4 EA_Logs/OneDriveLogs into SQLite DB")
    parser.add_argument(
        "--config",
        type=str,
        default=str(Path(__file__).parent / "config.yaml"),
        help="Path to config.yaml (config.local.yaml will be merged if present)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not delete/archive source files (still reads/parses and writes to DB)",
    )
    parser.add_argument(
        "--no-cleanup",
        action="store_true",
        help="Disable delete/archive even if delete_after_sync is true",
    )
    parser.add_argument(
        "--limit-files",
        type=int,
        default=None,
        help="Limit number of files per category (for quick validation)",
    )
    parser.add_argument(
        "--print-config",
        action="store_true",
        help="Print effective config (after merging config.local.yaml) and exit",
    )
    args = parser.parse_args()

    effective = load_config(args.config)
    if args.print_config:
        print(json.dumps(effective, ensure_ascii=False, indent=2))
        raise SystemExit(0)

    sync = MT4LogSync(
        args.config,
        dry_run=args.dry_run,
        no_cleanup=args.no_cleanup,
        limit_files=args.limit_files,
    )
    sync.sync_all()
    sync.close()
