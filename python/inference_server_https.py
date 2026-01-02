"""MT4 Inference Server (HTTPS) — NON-CANONICAL

MT4 WebRequest向けにHTTPSで起動するバリアント。
通常運用（Docker/MT5 EA）は `inference_server_http_7module.py` を使用。
"""

import sys
import ssl
from pathlib import Path
from flask import Flask, request, jsonify
from datetime import datetime
from OpenSSL import crypto

# 統一ロガーをインポート
sys.path.insert(0, str(Path(__file__).parent))
from common.logger import get_inference_logger

app = Flask(__name__)
logger = get_inference_logger()

# リクエストカウンター
request_count = 0

def generate_self_signed_cert(cert_file, key_file):
    """自己署名証明書を生成"""
    if Path(cert_file).exists() and Path(key_file).exists():
        logger.info("Using existing SSL certificate")
        return
    
    logger.info("Generating self-signed SSL certificate...")
    
    # キーペア生成
    key = crypto.PKey()
    key.generate_key(crypto.TYPE_RSA, 2048)
    
    # 証明書生成
    cert = crypto.X509()
    cert.get_subject().C = "JP"
    cert.get_subject().ST = "Tokyo"
    cert.get_subject().L = "Tokyo"
    cert.get_subject().O = "MT4 Trading"
    cert.get_subject().OU = "Inference Server"
    cert.get_subject().CN = "localhost"
    
    cert.set_serial_number(1000)
    cert.gmtime_adj_notBefore(0)
    cert.gmtime_adj_notAfter(365 * 24 * 60 * 60)  # 1年有効
    cert.set_issuer(cert.get_subject())
    cert.set_pubkey(key)
    cert.sign(key, 'sha256')
    
    # ファイル保存
    with open(cert_file, "wb") as f:
        f.write(crypto.dump_certificate(crypto.FILETYPE_PEM, cert))
    with open(key_file, "wb") as f:
        f.write(crypto.dump_privatekey(crypto.FILETYPE_PEM, key))
    
    logger.info(f"SSL certificate generated: {cert_file}")

@app.route('/health', methods=['GET'])
def health_check():
    """ヘルスチェックエンドポイント"""
    return jsonify({
        'status': 'ok',
        'message': 'MT4 Inference Server (HTTPS) is running',
        'timestamp': datetime.now().isoformat(),
        'requests_handled': request_count,
        'ssl': True
    }), 200

@app.route('/predict', methods=['POST'])
def predict():
    """推論エンドポイント"""
    global request_count
    request_count += 1
    
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'No JSON data received'}), 400
        
        symbol = data.get('symbol', 'UNKNOWN')
        timeframe = data.get('timeframe', 'UNKNOWN')
        prices = data.get('prices', [])
        indicators = data.get('indicators', {})
        
        logger.info(f"Prediction request #{request_count}: {symbol} {timeframe}, Prices: {len(prices)}, Indicators: {indicators}")
        
        # ダミー推論ロジック
        signal = 0
        confidence = 0.0
        reason = "No clear signal"
        
        if len(prices) >= 3:
            price_change = prices[-1] - prices[-3]
            
            if price_change > 0:
                reason = "Upward trend"
                signal = 1
                confidence = min(0.5 + abs(price_change) * 10, 0.9)
            elif price_change < 0:
                reason = "Downward trend"
                signal = -1
                confidence = min(0.5 + abs(price_change) * 10, 0.9)
        
        # EMA判定
        ema12 = indicators.get('ema12', 0)
        ema25 = indicators.get('ema25', 0)
        if ema12 > 0 and ema25 > 0:
            if ema12 > ema25:
                reason += " + EMA12 > EMA25 (bullish)"
                if signal >= 0:
                    signal = 1
                    confidence = min(confidence + 0.15, 0.95)
            else:
                reason += " + EMA12 < EMA25 (bearish)"
                if signal <= 0:
                    signal = -1
                    confidence = min(confidence + 0.15, 0.95)
        
        logger.info(f"Response: Signal={signal}, Confidence={confidence:.2f}, Reason={reason}")
        
        return jsonify({
            'signal': signal,
            'confidence': round(confidence, 2),
            'reason': reason,
            'request_id': request_count,
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"Prediction error: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/status', methods=['GET'])
def status():
    """サーバーステータス"""
    return jsonify({
        'server': 'MT4 Inference Server (HTTPS)',
        'version': '1.1.0',
        'requests_handled': request_count,
        'uptime': datetime.now().isoformat(),
        'ssl': True
    }), 200

if __name__ == '__main__':
    # SSL証明書のパス
    cert_dir = Path(__file__).parent / 'ssl'
    cert_dir.mkdir(exist_ok=True)
    cert_file = cert_dir / 'server.crt'
    key_file = cert_dir / 'server.key'
    
    # 証明書生成
    generate_self_signed_cert(str(cert_file), str(key_file))
    
    print("=" * 60)
    logger.info("MT4 Inference Server (HTTPS) Starting...")
    print("=" * 60)
    logger.info("Endpoints: GET /health, POST /predict, GET /status")
    logger.info("Server will run on: https://localhost:5000")
    print("=" * 60)
    
    # HTTPS で起動
    app.run(
        host='0.0.0.0',
        port=5000,
        debug=False,  # HTTPS時はdebug=Falseが安全
        ssl_context=(str(cert_file), str(key_file))
    )
