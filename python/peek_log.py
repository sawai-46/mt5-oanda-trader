
from pathlib import Path
import os
import datetime

# Mimic the logic to find the log file
# base_dir from config is normally passed, but we know the path from debug output
# C:\Users\chanm\AppData\Roaming\MetaQuotes\Terminal\A84B568DA10F82FE5A8FF6A859153D6F\Logs\20260105.log

log_path = Path(r"C:\Users\chanm\AppData\Roaming\MetaQuotes\Terminal\A84B568DA10F82FE5A8FF6A859153D6F\Logs\20260105.log")

if not log_path.exists():
    print(f"Log file not found at {log_path}")
    # Try to find any log file in that dir
    parent = log_path.parent
    if parent.exists():
        print(f"Listing {parent}:")
        for p in list(parent.glob("*.log"))[:5]:
             print(f" - {p.name}")
             # Peek at this one
             log_path = p
    else:
        print("Log dir not found")
        exit(1)

print(f"Log Size: {log_path.stat().st_size} bytes")
print(f"Last Modified: {datetime.datetime.fromtimestamp(log_path.stat().st_mtime)}")

print(f"\nPeeking at {log_path} with 'ansi' encoding:")
try:
    with open(log_path, 'r', encoding='ansi', errors='replace') as f:
        for i in range(10):
            print(repr(f.readline()))
except Exception as e:
    print(e)
    
print(f"\nPeeking at {log_path} with 'utf-8' encoding:")
try:
    with open(log_path, 'r', encoding='utf-8', errors='replace') as f:
        for i in range(10):
            print(repr(f.readline()))
except Exception as e:
    print(e)

print(f"\nPeeking at {log_path} with 'cp932' encoding:")
try:
    with open(log_path, 'r', encoding='cp932', errors='replace') as f:
        for i in range(10):
            print(repr(f.readline()))
except Exception as e:
    print(e)
