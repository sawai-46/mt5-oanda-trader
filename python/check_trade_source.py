
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

print(f"Checking trade activity in the last 3 days...")

# Get column names first to be safe
cursor.execute("PRAGMA table_info(trade_events)")
columns = [row['name'] for row in cursor.fetchall()]
print(f"Columns: {columns}")

# Query recent trades
since_date = (datetime.now() - timedelta(days=3)).strftime("%Y-%m-%d")
try:
    # Just get a dump of recent trades    # Query recent FAILED trades
    cursor.execute(f"""
        SELECT timestamp, terminal_id, symbol, message
        FROM trade_events 
        WHERE timestamp > '{since_date}' AND type = 'ENTRY_FAILED'
        ORDER BY timestamp DESC
        LIMIT 5
    """)
    rows = cursor.fetchall()
    
    if not rows:
        print("No ENTRY_FAILED found in the last 3 days.")
    else:
        print(f"Found {len(rows)} ENTRY_FAILED events:")
        for row in rows:
            message = row['message'] if 'message' in row.keys() else "N/A"
            print(f"  [{row['timestamp']}] {row['terminal_id']} {row['symbol']} Error='{message}'")
            
    # Also count by type mapping to infer EA type
    print("\nSummary by distinctive type pattern:")
    cursor.execute(f"""
        SELECT type, count(*) as cnt 
        FROM trade_events 
        WHERE timestamp > '{since_date}' 
        GROUP BY type
    """)
    for row in cursor.fetchall():
        print(f"  '{row['type']}': {row['cnt']}")

except Exception as e:
    print(f"Error querying trades: {e}")

conn.close()
