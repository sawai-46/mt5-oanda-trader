# CANONICAL: MT5 HTTP Inference Server

このリポジトリで「通常運用で起動する推論サーバー」は **これだけ**。

- 正本: `python/inference_server_http_7module.py`
- Docker(GPU)もこのサーバーを起動する（`docker-compose.yml` / `python/Dockerfile.gpu`）

---

## 提供API（固定）

- `GET  /health`
- `POST /analyze`  ← MT5 EA（OHLCV配列）
- `POST /predict`  ← スモークテスト等（フラット形式）

---

## 起動（推奨: Docker / GPU）

リポジトリルートで:

```bash
docker compose up -d --build
```

確認:

```powershell
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:5001/health" | ConvertTo-Json -Depth 5
```

---

## 起動（ローカル: Python）

```bash
cd python
pip install -r requirements.txt
python inference_server_http_7module.py
```

---

## MT5 側の必須設定（WebRequest許可）

MT5: `ツール` → `オプション` → `エキスパートアドバイザ` → `WebRequestを許可したURL`

- `http://127.0.0.1:5001`
- （必要なら）`http://localhost:5001`

---

## 運用で触る環境変数（任意）

`docker-compose.yml` 側で固定するのが安全。

- `REQUEST_TIMEOUT_SEC`（例: `3.0`）
- `MAX_WORKERS`（例: `4`）
- `PRESET`（例: `antigravity_pullback`）
- `STRATEGY`（例: `full`）
- `LM_STUDIO_URL`（例: `http://host.docker.internal:1234`）

---

## 注意（迷いの元を切る）

`python/` 配下には `inference_server_*.py` が複数ありますが、
通常運用は **必ず** `inference_server_http_7module.py` に統一してください。
