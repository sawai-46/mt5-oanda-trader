# MT5 HTTP inference server (Docker)
# Intended for MT5_AI_Trader_HTTP.mq5 which calls /health and /analyze.
# NOTE: MetaTrader5 Python package is Windows-only, so this image runs in
#       "limited mode" for MT5-native data access, but /analyze works.

FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TZ=Asia/Tokyo

# System deps (kept minimal)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install Python deps first (better layer caching)
COPY python/requirements.docker.txt /app/requirements.docker.txt
RUN pip install --no-cache-dir -r /app/requirements.docker.txt

# Copy server + modules
COPY python/ /app/

EXPOSE 5001

CMD ["python", "inference_server_http_7module.py"]
