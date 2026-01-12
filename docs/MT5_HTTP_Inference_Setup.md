# MT5 HTTP 推論サーバー接続手順

## 目的

MT5側はファイル通信ではなく **HTTP(WebRequest)** でPython推論サーバーを呼び出す。

このリポジトリにはHTTP推論サーバーが複数あり、EA/スクリプトによって叩くAPIが異なる。

- [mql5/Experts/MT5_AI_Trader_HTTP.mq5](../mql5/Experts/MT5_AI_Trader_HTTP.mq5)
  - `GET /health`（起動時に疎通確認）
  - `POST /analyze`（OHLCV配列を送る）
  - 対応サーバー: [python/inference_server_http_7module.py](../python/inference_server_http_7module.py)

- [mql5/Scripts/InferenceHttpSmoke.mq5](../mql5/Scripts/InferenceHttpSmoke.mq5)
  - `GET /health`
  - `POST /predict`（フラット形式で送る）
  - 対応サーバー: [python/inference_server_http_7module.py](../python/inference_server_http_7module.py)

---

## 1. Pythonサーバー起動（HTTP）

### A) MT5_AI_Trader_HTTP（/analyze）用

PowerShellで以下。

- `cd python`
- `python -m pip install -r requirements.txt`
- `python inference_server_http_7module.py`

デフォルト:

- `http://127.0.0.1:5001`
- `GET /health`
- `POST /analyze`

※ `inference_server_mt5.py` は MT5 Python API（`MetaTrader5`）が未導入でも起動する（ただし機能は限定）。

※ `inference_server_http_7module.py` は Docker 最小依存でも動くHTTPサーバーで、
`/analyze`（OHLCV配列）と `/predict`（フラット形式）の両方を提供する。

#### Dockerで起動（おすすめ：MT4と同じ運用に寄せる）

このリポジトリには MT5用の Docker Compose を用意してある（ルートの `docker-compose.yml`）。

- `cd mt5-oanda-trader`
- `docker compose up -d --build`

確認:

- `http://127.0.0.1:5001/health`

注意:

- `MetaTrader5` Pythonパッケージは基本的にWindows向けのため、Docker（Linux）ではMT5ネイティブ接続は使えない前提。
- Docker運用では `inference_server_http_7module.py` を正本とし、EAは `/health` と `/analyze` を叩く。

### B) 7module/antigravity（/predict）用

PowerShellで以下。

- `cd python`
- `python -m pip install -r requirements.txt`
- `python inference_server_http_7module.py`

デフォルト:

- `http://127.0.0.1:5001`
- `GET /health`
- `POST /predict`
- `POST /analyze`

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

#### `mt4-pullback-trader` を submodule として追加（推奨）

このリポジトリのルートで、以下のように追加します。

- `git submodule add https://github.com/sawai-46/mt4-pullback-trader external/mt4-pullback-trader`
- `git submodule update --init --recursive`

この配置にすると、`python/inference_server_7module.py` が `external/mt4-pullback-trader/python` を自動的に `sys.path` に追加し、`antigravity.core.*` の import を試みます。

※ サブモジュールが private の場合は、認証（SSH鍵/トークン）設定が必要です。

- 依存が解決できているか確認例: `python -c "from antigravity.core.orchestrator import AntigravityOrchestrator; print('ok')"`
- 有効化: `USE_ANTIGRAVITY=1`
- モデル指定（必要に応じて）:
  - `MODEL_TYPE` : `transformer` / `kan` / `ensemble`
  - `TRANSFORMER_MODEL_PATH` : Transformerモデルのパス
  - `KAN_MODEL_PATH` : KANモデルのパス
  - `DAILY_DATA_PATH` : 日足データ（GARCH等で使う場合）

#### 9銘柄（M15）を銘柄別モデルで回す（推奨）

MT4/MT5で指数シンボルが異なる場合（例）:

- MT4: `JP225.mt4, US30.mt4, US500.mt4, NQ100.mt4`
- MT5: `JP225, US30, US500, US100`

このサーバは内部でシンボルを正規化します。

- `.mt4` 接尾辞は落として `JP225` 扱い
- `US100` は `NQ100` 扱い（モデル/閾値を共通化）

その上で、環境変数 `TRANSFORMER_MODEL_PATHS_JSON` に JSON を入れると、銘柄×時間足でモデルを切り替えできます。

PowerShell例（Windowsで直接起動する場合）:

```powershell
cd python

# Antigravity を有効化
$env:USE_ANTIGRAVITY = "1"
$env:MODEL_TYPE = "transformer"

# mt4-pullback-trader 側の antigravity を import できるようにする
$env:MT4_PULLBACK_TRADER_PYTHON = "C:\\Users\\chanm\\OneDrive\\VS Code\\mt4-pullback-trader\\python"

# 9銘柄M15のモデル割当（キーは JP225/US30/US500/NQ100 を基準に統一）
$env:TRANSFORMER_MODEL_PATHS_JSON = '{"USDJPY_M15":"antigravity/data/transformer_model_USDJPY_15.pt","EURUSD_M15":"antigravity/data/transformer_model_EURUSD_15.pt","AUDUSD_M15":"antigravity/data/transformer_model_AUDUSD_15.pt","EURJPY_M15":"antigravity/data/transformer_model_EURJPY_15.pt","AUDJPY_M15":"antigravity/data/transformer_model_AUDJPY_15.pt","JP225_M15":"antigravity/data/transformer_model_JP225.mt4_15.pt","US30_M15":"antigravity/data/transformer_model_US30.mt4_15.pt","US500_M15":"antigravity/data/transformer_model_US500.mt4_15.pt","NQ100_M15":"antigravity/data/transformer_model_NQ100.mt4_15.pt"}'

python inference_server_http_7module.py
```

Docker運用の場合は、ルートの [docker-compose.yml](../docker-compose.yml) に同等の設定例を入れてあります。

※ Antigravity が import できない場合は自動的に無効化され、7moduleのみで推論します。

---

## 2. MT5側のWebRequest許可

MT5はデフォルトで外部URLへのWebRequestがブロックされる。

- MT5: `ツール` → `オプション` → `エキスパートアドバイザ` → `WebRequestを許可したURL` に
  - `http://127.0.0.1:5001`
  - （必要なら）`http://localhost:5001`
  を追加

補足:

- 混乱しやすいので、EA側のURLも `http://127.0.0.1:5001` に揃えるのが安全。

---

## 3. MT5から疎通確認（売買なし）

MT5のスクリプト [mql5/Scripts/InferenceHttpSmoke.mq5](../mql5/Scripts/InferenceHttpSmoke.mq5) を実行。

- `InpServerUrl = http://127.0.0.1:5001`
- `InpPredictEndpoint = /predict`
- `InpPreset = antigravity_pullback`

ログに `HTTP status=200` と `signal/conf/reason` が出ればOK。

### MT5_AI_Trader_HTTP の疎通確認（売買なし）

このEAは `OnInit()` で `GET /health` を叩き、失敗すると `INIT_FAILED` で止まる。

- `InpInferenceServerURL = http://127.0.0.1:5001`
- `InpMT5_ID = 10900k-mt5-fx`（例。指数側は `10900k-mt5-index`）

ログに `✓ 推論サーバー接続OK` が出ればOK。

MT5を介さずに確認したい場合（PowerShell例）:

```powershell
# health
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:5001/health" | ConvertTo-Json -Depth 5

# analyze（最低限の形：20本以上が必要）
$payload = @{
  symbol = "USDJPY"
  timeframe = "M15"
  ohlcv = @{
    open   = @(1..25 | ForEach-Object { 150.0 + $_ * 0.01 })
    high   = @(1..25 | ForEach-Object { 150.1 + $_ * 0.01 })
    low    = @(1..25 | ForEach-Object { 149.9 + $_ * 0.01 })
    close  = @(1..25 | ForEach-Object { 150.0 + $_ * 0.01 })
    volume = @(1..25 | ForEach-Object { 1000 + $_ })
  }
  current_price = 150.25
} | ConvertTo-Json -Depth 6

Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:5001/analyze" -ContentType "application/json" -Body $payload | ConvertTo-Json -Depth 6
```

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
