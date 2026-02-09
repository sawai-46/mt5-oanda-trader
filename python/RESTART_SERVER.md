# MT5 HTTP サーバー 再起動手順

## 方法1: 直接Python実行（推奨・簡単）

現在のサーバーを停止して再起動：

```bash
# 1. 現在のサーバーを停止（Ctrl+C）

# 2. 再起動
cd c:\Users\chanm\OneDrive\VS Code\mt5-oanda-trader\python
python inference_server_http_7module.py
```

## 方法2: Docker（本番環境用）

### ビルド
```bash
cd c:\Users\chanm\OneDrive\VS Code\mt5-oanda-trader\python
docker build -t mt5-inference-server .
```

### 実行
```bash
docker run -d \
  --name mt5-inference \
  -p 5001:5001 \
  -e PORT=5001 \
  mt5-inference-server
```

### 確認
```bash
curl http://localhost:5001/health
curl "http://localhost:5001/market/USDJPY?timeframe=H1&limit=5"
```

### 停止・削除
```bash
docker stop mt5-inference
docker rm mt5-inference
```

---

## 動作確認

サーバー起動後、以下のコマンドでテスト：

```bash
# 1. ヘルスチェック
curl http://localhost:5001/health

# 2. 市場データ取得
curl "http://localhost:5001/market/USDJPY?timeframe=H1&limit=5"

# 3. agentic-trading から統合テスト
cd c:\Users\chanm\OneDrive\VS Code\Musubi-Quant\agentic-trading
python test_market_data.py
```

期待される結果：
- MT5 HTTP から USDJPY のデータが取得できる
- フォールバックせずに MT5 HTTP が優先される
