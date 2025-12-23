# MT5 HTTP 推論サーバー接続手順

## 目的
MT5側はファイル通信ではなく **HTTP(WebRequest)** でPython推論サーバーを呼び出す。

このリポジトリでは、7module/antigravity系のロジックをHTTPで受けるために [python/inference_server_http_7module.py](../python/inference_server_http_7module.py) を追加してある。

---

## 1. Pythonサーバー起動（HTTP）

PowerShellで以下。

- `cd python`
- `python -m pip install -r requirements.txt`
- `python inference_server_http_7module.py`

デフォルト:
- `http://127.0.0.1:5001`
- `GET /health`
- `POST /predict`

必要なら環境変数で調整:
- `PORT` (例: `5001`)
- `LM_STUDIO_URL` (例: `http://localhost:1234`)
- `STRATEGY` (例: `full`)
- `PRESET` (例: `antigravity_pullback`)
- `USE_ANTIGRAVITY` (`1`/`0`)

### Antigravity を有効化する場合

このリポジトリの `python/inference_server_7module.py` は `antigravity.core.orchestrator` を import できる場合のみ Antigravity を有効化します。

Antigravity 実体が `mt4-pullback-trader` 側にある場合は、以下いずれかで Python の import パスに含めてください。

- 環境変数（推奨）
  - `MT4_PULLBACK_TRADER_ROOT` = `mt4-pullback-trader` のリポジトリルート（例: `D:\work\mt4-pullback-trader`）
  - もしくは `MT4_PULLBACK_TRADER_PYTHON` = `mt4-pullback-trader\python`（例: `D:\work\mt4-pullback-trader\python`）

- リポジトリ内に配置（サブモジュール/コピー）
  - `external/mt4-pullback-trader/python/antigravity/...` の形で置く（`external` 配下を推奨）

- 依存が解決できているか確認例: `python -c "from antigravity.core.orchestrator import AntigravityOrchestrator; print('ok')"`
- 有効化: `USE_ANTIGRAVITY=1`
- モデル指定（必要に応じて）:
  - `MODEL_TYPE` : `transformer` / `kan` / `ensemble`
  - `TRANSFORMER_MODEL_PATH` : Transformerモデルのパス
  - `KAN_MODEL_PATH` : KANモデルのパス
  - `DAILY_DATA_PATH` : 日足データ（GARCH等で使う場合）

※ Antigravity が import できない場合は自動的に無効化され、7moduleのみで推論します。

---

## 2. MT5側のWebRequest許可
MT5はデフォルトで外部URLへのWebRequestがブロックされる。

- MT5: `ツール` → `オプション` → `エキスパートアドバイザ` → `WebRequestを許可したURL` に
  - `http://127.0.0.1:5001`
  - （必要なら）`http://localhost:5001`
  を追加

---

## 3. MT5から疎通確認（売買なし）
MT5のスクリプト [mql5/Scripts/InferenceHttpSmoke.mq5](../mql5/Scripts/InferenceHttpSmoke.mq5) を実行。

- 入力例:
  - `InpServerUrl = http://127.0.0.1:5001`
  - `InpPredictEndpoint = /predict`
  - `InpPreset = antigravity_pullback`

ログに `HTTP status=200` と `signal/conf/reason` が出ればOK。

---

## JSON I/F（MT5 → Python）
推奨（フラット形式）:

```json
{
  "symbol": "USDJPY",
  "timeframe": "M5",
  "preset": "antigravity_pullback",
  "ema12": 150.12,
  "ema25": 150.05,
  "ema100": 149.90,
  "atr": 0.15,
  "close": 150.10,
  "prices": "150.10,150.09,150.08"
}
```

レスポンス:

```json
{
  "signal": 1,
  "confidence": 0.82,
  "reason": "...",
  "timestamp": "...",
  "request_id": 1
}
```
