# MT5 OANDA AI Trader

OANDA MT5用のAI統合自動トレーディングシステム

## 📁 プロジェクト構造

```text
mt5-oanda-trader/
├── mql5/                   # MT5 Expert Advisor
│   ├── Experts/           # EAファイル
│   └── Include/           # 共通ライブラリ
├── python/                # Python推論サーバー
│   ├── server/           # HTTPサーバー
│   ├── models/           # AIモデル
│   └── utils/            # ユーティリティ
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

```bash
python server/inference_server.py
```

### 2b. Docker で推論サーバー起動（推奨）

GPU版（標準 / NVIDIA GPU前提）:

```bash
docker compose up -d --build
```

- コンテナ: `mt5-inference-server`
- ポート: `5001`（ホスト側）

補足: この compose はソースを volume マウントしていないため、コード変更を反映するには `--build` が必要です。

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
