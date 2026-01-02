# MT5 OANDA AI Trader

OANDA MT5用のAI統合自動トレーディングシステム

## 📁 プロジェクト構造

```text
mt5-oanda-trader/
├── mql5/                   # MT5 Expert Advisor
│   ├── Experts/           # EAファイル
│   └── Include/           # 共通ライブラリ
├── python/                # Python推論サーバー
│   ├── inference_server_http_7module.py  # HTTP推論サーバー（正本）
│   ├── inference_server_7module.py       # 推論エンジン本体
│   ├── modules/                         # 分析モジュール
│   └── signal_engine/                   # 集約/スコアリング
├── config/                # 設定ファイル
├── docs/                  # ドキュメント
└── README.md
```

## 🚀 セットアップ

### 1. Python環境

```bash
cd python
pip install -r requirements.txt
```

### 2. 推論サーバー起動

運用の正本は HTTP 推論サーバーです。

- `GET  /health`
- `POST /analyze`（MT5 EA: OHLCV配列）
- `POST /predict`（フラット形式）

```bash
cd python
python inference_server_http_7module.py
```

### 2b. Docker で推論サーバー起動（推奨）

GPU版（標準 / NVIDIA GPU前提）:

```bash
docker compose up -d --build
```

- コンテナ: `mt5-inference-server`
- ポート: `5001`（ホスト側）

補足: この compose はソースを volume マウントしていないため、コード変更を反映するには `--build` が必要です。

詳細手順: [docs/MT5_HTTP_Inference_Setup.md](docs/MT5_HTTP_Inference_Setup.md)

### 3. MT5設定

1. EAをコンパイル
2. チャートにアタッチ
3. 自動売買を有効化

## 📊 機能

- AI推論によるシグナル生成
- リスク管理
- 部分決済機能
- マルチタイムフレーム分析
- OANDA MT5対応

## 🔧 開発中

このプロジェクトは開発中です。

注記:
- `python/` 配下には検証用の `inference_server_*.py` が複数ありますが、通常運用は `inference_server_http_7module.py` に統一してください。
