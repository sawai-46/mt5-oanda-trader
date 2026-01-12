FROM python:3.11-slim

WORKDIR /app/python

# System deps (kept minimal)
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.docker.txt ./requirements.docker.txt
RUN python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir -r requirements.docker.txt

# Copy server code
COPY . .

ENV PORT=5001
EXPOSE 5001

CMD ["python", "inference_server_http_7module.py"]
