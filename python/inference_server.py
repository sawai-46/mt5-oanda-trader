# MT4 Inference Server - Simple Test Version
# Flaskベースの軽量推論サーバー

import sys
from pathlib import Path
from flask import Flask, request, jsonify
from datetime import datetime

# 統一ロガーをインポート
sys.path.insert(0, str(Path(__file__).parent))
from common.logger import get_inference_logger

app = Flask(__name__)
logger = get_inference_logger()

# リクエストカウンター
request_count = 0

@app.route('/health', methods=['GET'])
def health_check():
    """ヘルスチェックエンドポイント"""
    return jsonify({
        'status': 'ok',
        'message': 'MT4 Inference Server is running',
        'timestamp': datetime.now().isoformat(),
        'requests_handled': request_count
    }), 200

@app.route('/predict', methods=['POST'])
def predict():
    """
    推論エンドポイント
    
    リクエスト形式:
    {
        "symbol": "USDJPY",
        "timeframe": "M15",
        "prices": [149.50, 149.55, 149.60, ...],
        "indicators": {
            "ema12": 149.45,
            "ema25": 149.40,
            "atr": 0.15
        }
    }
    
    レスポンス形式:
    {
        "signal": 1,  # 1: Buy, -1: Sell, 0: Neutral
        "confidence": 0.85,
        "reason": "Bullish trend detected",
        "timestamp": "2025-11-24T12:00:00"
    }
    """
    global request_count
    request_count += 1
    
    try:
        # リクエストデータ取得
        data = request.get_json()
        
        if not data:
            return jsonify({
                'error': 'No JSON data received'
            }), 400
        
        # 必須フィールドチェック
        symbol = data.get('symbol', 'UNKNOWN')
        timeframe = data.get('timeframe', 'UNKNOWN')
        prices = data.get('prices', [])
        indicators = data.get('indicators', {})
        
        logger.info(f"Prediction request #{request_count}: {symbol} {timeframe}, Prices: {len(prices)}, Indicators: {indicators}")
        
        # ダミー推論ロジック（実際にはここでAIモデルを使用）
        signal = 0
        confidence = 0.0
        reason = "No clear signal"
        
        # 簡単なトレンド判定（デモ用）
        if len(prices) >= 3:
            # 直近3本の価格から簡易判定
            if prices[-1] > prices[-2] > prices[-3]:
                signal = 1  # Buy
                confidence = 0.75
                reason = "Uptrend detected (3-bar rising)"
            elif prices[-1] < prices[-2] < prices[-3]:
                signal = -1  # Sell
                confidence = 0.75
                reason = "Downtrend detected (3-bar falling)"
            else:
                signal = 0
                confidence = 0.5
                reason = "No clear trend"
        
        # EMAベースの判定も追加（デモ用）
        if indicators:
            ema12 = indicators.get('ema12', 0)
            ema25 = indicators.get('ema25', 0)
            
            if ema12 > 0 and ema25 > 0:
                if ema12 > ema25 and signal >= 0:
                    signal = 1
                    confidence = min(confidence + 0.15, 1.0)
                    reason += " + EMA12 > EMA25 (bullish)"
                elif ema12 < ema25 and signal <= 0:
                    signal = -1
                    confidence = min(confidence + 0.15, 1.0)
                    reason += " + EMA12 < EMA25 (bearish)"
        
        response = {
            'signal': signal,
            'confidence': round(confidence, 2),
            'reason': reason,
            'timestamp': datetime.now().isoformat(),
            'request_id': request_count
        }
        
        logger.info(f"Response: Signal={signal}, Confidence={confidence:.2f}, Reason={reason}")
        
        # シグナルログを記録
        signal_name = {1: "BUY", -1: "SELL", 0: "NEUTRAL"}.get(signal, "UNKNOWN")
        logger.log_signal(symbol, signal_name, confidence, ['EMA', 'Price'], reason)
        
        return jsonify(response), 200
        
    except Exception as e:
        logger.error(f"Error processing prediction: {str(e)}")
        return jsonify({
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500

@app.route('/status', methods=['GET'])
def status():
    """サーバーステータス"""
    return jsonify({
        'status': 'running',
        'requests_handled': request_count,
        'timestamp': datetime.now().isoformat()
    }), 200

# =============================================================================
# オプション市場リスク監視エンドポイント
# 大きなドローダウン回避のための日次リスク分析
# =============================================================================

# モジュールのインスタンス（遅延初期化）
_options_risk_module = None
_open_interest_analyzer = None

def get_options_risk_module():
    """OptionsRiskModuleの遅延初期化"""
    global _options_risk_module
    if _options_risk_module is None:
        try:
            from modules.options_risk_module import OptionsRiskModule
            _options_risk_module = OptionsRiskModule()
            logger.info("OptionsRiskModule 初期化完了")
        except ImportError as e:
            logger.error(f"OptionsRiskModule インポート失敗: {e}")
            raise
    return _options_risk_module

def get_open_interest_analyzer():
    """OpenInterestAnalyzerの遅延初期化"""
    global _open_interest_analyzer
    if _open_interest_analyzer is None:
        try:
            from modules.open_interest_analyzer import OpenInterestAnalyzer
            _open_interest_analyzer = OpenInterestAnalyzer()
            logger.info("OpenInterestAnalyzer 初期化完了")
        except ImportError as e:
            logger.error(f"OpenInterestAnalyzer インポート失敗: {e}")
            raise
    return _open_interest_analyzer

@app.route('/options/risk', methods=['GET'])
def get_options_risk():
    """
    オプション市場リスクスコアエンドポイント
    
    VIX, SKEW, Put/Call Ratioから総合リスクを算出。
    1日1回更新（キャッシュ24時間）
    
    レスポンス形式:
    {
        "risk_level": "safe|caution|danger|extreme",
        "total_score": 0-9,
        "indicators": {...},
        "recommendation": "取引推奨事項",
        "timestamp": "2025-12-21T08:00:00"
    }
    """
    try:
        module = get_options_risk_module()
        force_refresh = request.args.get('refresh', 'false').lower() == 'true'
        
        if force_refresh:
            logger.info("オプションリスクデータ強制更新")
        
        risk_data = module.get_risk_score()
        
        # 取引可否判定も追加
        can_trade, trade_reason = module.should_trade()
        risk_data['can_trade'] = can_trade
        risk_data['trade_reason'] = trade_reason
        
        logger.info(f"Options Risk: {risk_data['risk_level']} (Score: {risk_data['total_score']})")
        
        return jsonify(risk_data), 200
        
    except Exception as e:
        logger.error(f"オプションリスク取得エラー: {e}")
        return jsonify({
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500

@app.route('/options/levels/<symbol>', methods=['GET'])
def get_options_levels(symbol: str):
    """
    指定銘柄の重要価格帯エンドポイント
    
    オプション建玉から特定したサポート/レジスタンスレベル。
    
    対応銘柄:
    - FX: USDJPY, EURUSD, AUDUSD, EURJPY, AUDJPY
    - 株価指数: JP225, US30, US500, NQ100
    
    レスポンス形式:
    {
        "symbol": "USDJPY",
        "key_levels": [...],
        "summary": {
            "put_wall": 148.50,
            "call_wall": 152.00,
            "max_pain": 150.00
        }
    }
    """
    try:
        analyzer = get_open_interest_analyzer()
        force_refresh = request.args.get('refresh', 'false').lower() == 'true'
        
        if force_refresh:
            logger.info(f"建玉データ強制更新: {symbol}")
        
        # シンボル正規化（大文字）
        symbol = symbol.upper()
        
        levels_data = analyzer.get_key_levels(symbol)
        
        if 'error' in levels_data:
            return jsonify(levels_data), 404
        
        logger.info(f"Options Levels: {symbol} - Put Wall: {levels_data['summary'].get('put_wall')}, Call Wall: {levels_data['summary'].get('call_wall')}")
        
        return jsonify(levels_data), 200
        
    except Exception as e:
        logger.error(f"建玉分析エラー ({symbol}): {e}")
        return jsonify({
            'error': str(e),
            'symbol': symbol,
            'timestamp': datetime.now().isoformat()
        }), 500

@app.route('/options/levels', methods=['GET'])
def get_all_options_levels():
    """
    全対応銘柄の重要価格帯を一括取得
    """
    try:
        analyzer = get_open_interest_analyzer()
        results = analyzer.analyze_all_symbols()
        
        return jsonify({
            'symbols': results,
            'count': len(results),
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"全銘柄建玉分析エラー: {e}")
        return jsonify({
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500

if __name__ == '__main__':
    logger.info("="*60)
    logger.info("MT4 Inference Server Starting...")
    logger.info("="*60)
    logger.info("Endpoints: GET /health, POST /predict, GET /status")
    logger.info("Server will run on: http://localhost:5000")
    logger.info("="*60)
    
    # サーバー起動
    app.run(
        host='0.0.0.0',  # 外部からもアクセス可能
        port=5000,
        debug=True,
        use_reloader=False  # リロード無効化（安定性向上）
    )
