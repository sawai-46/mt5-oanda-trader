
import sqlite3
import os
from datetime import datetime

db_path = 'unified_logs.db'
if not os.path.exists(db_path):
    print(f"Database not found at {db_path}")
    exit(1)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

tables = ['ai_learning_data', 'trade_events', 'log_entries', 'inference_signals']

print(f"Checking latest timestamps in {db_path}...")
for table in tables:
    try:
        cursor.execute(f"SELECT MAX(timestamp), COUNT(*) FROM {table}")
        row = cursor.fetchone()
        latest_ts = row[0]
        count = row[1]
        print(f"Table '{table}': Count={count}, Latest Timestamp={latest_ts}")
        
        # Also get a sample of the last few entries to see what they are
        if count > 0:
            cursor.execute(f"SELECT * FROM {table} ORDER BY timestamp DESC LIMIT 1")
            last_row = cursor.fetchone()
            # print(f"  Last Entry: {last_row}")
    except Exception as e:
        print(f"Error querying table {table}: {e}")

conn.close()
