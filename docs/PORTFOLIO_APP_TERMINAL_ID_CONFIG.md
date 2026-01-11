# ポートフォリオアプリ向け：Terminal ID と連携設定ガイド

## 結論（おすすめ）

- **Terminal ID（例：`10900k-mt5-index`）は、全システム共通の「固定キー（主キー）」として扱う**
- **MT4はファイル連携（CSV）**、**MT5はHTTP連携** を正本にする
- 物理パスやPC固有情報は **`config.local.yaml`（git管理外）** に分離する

この方針にすると、2PC/OneDrive集約でも「ログ・DB・EA・アプリ」が同一の `terminal_id` で整合します。

---

## 1) Terminal ID（命名ルール）

### 推奨フォーマット

```
{pc}-{mt4|mt5}-{fx|index}
```

例：

- `10900k-mt4-fx`
- `10900k-mt4-index`
- `10900k-mt5-fx`
- `10900k-mt5-index`

例外（運用上必要な場合のみ）：

- `matsu-mt4-demo`

### 重要：live/demo はIDに入れない

`live` / `demo` は **Terminal IDに入れず**、アプリのメタデータ（`account_env` など）として保持してください。
理由：

- 同じIDで「口座切替」をしたいケースが出る
- IDを変えると、ログ/DBの時系列が分断される

---

## 2) 連携方式（ポートフォリオアプリ側の推奨）

### A. MT4（ファイル/CSV）

- request/response CSV の仕組みを正本として扱う
- ファイル名に **必ず `terminal_id` を含める**（衝突回避と集計のため）

ファイル名規約（既存運用に合わせる）：

```
request_{terminal_id}_{Symbol}_{Timeframe}.csv
response_{terminal_id}_{Symbol}_{Timeframe}.csv
Trade_Log_{terminal_id}_{Symbol}_{Timeframe}.csv
AI_Learning_Data_{terminal_id}_{Symbol}_{Timeframe}.csv
```

### B. MT5（HTTP）

MT5側はファイル通信ではなく **HTTP(WebRequest)** で推論サーバーを呼び出します。

- `GET /health`
- `POST /analyze`
- `POST /predict`

詳細は [MT5_HTTP_Inference_Setup.md](./MT5_HTTP_Inference_Setup.md) を参照。

ポートフォリオアプリがMT5推論を叩く場合は、リクエストに `terminal_id` を必ず含めてください（JSONのフィールド等）。

---

## 3) 設定ファイルの分離（おすすめ構成）

### ポートフォリオアプリ側

#### `config.yaml`（git管理）

端末台帳（terminal registry）＝論理情報を管理します。

```yaml
terminals:
  - id: 10900k-mt5-fx
    platform: mt5
    asset_bucket: fx
    broker: OANDA

  - id: 10900k-mt5-index
    platform: mt5
    asset_bucket: index
    broker: OANDA
```

#### `config.local.yaml`（git管理外）

PC固有の物理情報（パス/URL/DB）を管理します。

```yaml
paths:
  ea_logs_root: "C:\\Users\\chanm\\OneDrive\\EA_Logs"

mt5_http:
  base_url: "http://127.0.0.1:5001"
  health_endpoint: "/health"
  analyze_endpoint: "/analyze"
  predict_endpoint: "/predict"
  timeout_sec: 3
```

---

## 4) このリポジトリの既存設定との整合

- `python/config.yaml` に `mt4_terminals` / `mt5_terminals` があり、`id` が Terminal ID です
- `python/config.local.yaml` があれば上書きマージされます（git管理外）

重要：

- OneDrive集約運用では、**同一 `data_dir`（同一フォルダ）を複数IDで重複定義しない**（重複パスはスキップされます）
