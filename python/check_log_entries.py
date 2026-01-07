
import sqlite3
import os
from datetime import datetime, timedelta

db_path = 'unified_logs.db'
if not os.path.exists(db_path):
    print(f"Database not found at {db_path}")
    exit(1)

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

print(f"Checking log_entries for errors in the last 2 days...")

since_date = (datetime.now() - timedelta(days=2)).strftime("%Y-%m-%d")

try:
    target_time = '2026-01-05 17:'
    target_terminal = '10900k-A'
    cursor.execute(f"""
        SELECT timestamp, terminal_id, message
        FROM log_entries 
        WHERE timestamp LIKE '{target_time}%'
        AND terminal_id = '{target_terminal}'
        ORDER BY timestamp ASC
    """)
    rows = cursor.fetchall()

    if not rows:
        print("No matching logs found.")
    else:
        print(f"Found {len(rows)} matching log entries:")
        for row in rows:
            print(f"  [{row['timestamp']}] {row['terminal_id']} : {row['message']}")
            
except Exception as e:
    print(f"Error querying log_entries: {e}")

conn.close()
