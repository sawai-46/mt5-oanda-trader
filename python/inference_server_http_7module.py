"""HTTP Inference Server (7module/Antigravity)

MT5 から WebRequest(HTTP/HTTPS) で推論を呼び出す用途。
- POST /predict : 推論
- GET  /health  : ヘルスチェック

入力は MT4/CSV と互換な「フラット形式」を推奨:
{
  "symbol": "USDJPY",
  "timeframe": "M5",
  "preset": "antigravity_pullback",
  "ema12": 150.12,
  "ema25": 150.05,
  "ema100": 149.90,
  "atr": 0.15,
  "close": 150.10,
  "prices": "150.10,150.09,150.08,..."  # 最新→過去
}

互換のため、以下も受理:
- prices: [150.10, 150.09, ...] (配列)
- indicators: {"ema12":..., "ema25":..., "ema100":..., "atr":...}
"""

from __future__ import annotations

import os
from datetime import datetime
from typing import Any, Dict, Tuple

from flask import Flask, jsonify, request

from inference_server_7module import SevenModuleInferenceServer


def _normalize_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    symbol = (payload.get("symbol") or "UNKNOWN")
    timeframe = (payload.get("timeframe") or "M5")

    indicators = payload.get("indicators") or {}
    ema12 = payload.get("ema12", indicators.get("ema12", 0))
    ema25 = payload.get("ema25", indicators.get("ema25", 0))
    ema100 = payload.get("ema100", indicators.get("ema100", 0))
    atr = payload.get("atr", indicators.get("atr", 0.001))
    close = payload.get("close", 0)

    prices = payload.get("prices", "")
    if isinstance(prices, list):
        prices_str = ",".join(str(x) for x in prices)
    else:
        prices_str = str(prices or "")

    preset = (payload.get("preset") or "").strip()

    # SevenModuleAnalyzer は prices を "最新→過去" の CSV 文字列として扱う
    return {
        "symbol": symbol,
        "timeframe": timeframe,
        "preset": preset,
        "ema12": ema12,
        "ema25": ema25,
        "ema100": ema100,
        "atr": atr,
        "close": close,
        "prices": prices_str,
    }


def _make_server() -> SevenModuleInferenceServer:
    # 環境変数で制御（まずは最小限）
    lm_studio_url = os.getenv("LM_STUDIO_URL", "http://localhost:1234")
    strategy = os.getenv("STRATEGY", "full")
    preset = os.getenv("PRESET", "antigravity_pullback")

    atr_fx = float(os.getenv("ATR_THRESHOLD_FX", "7.0"))
    atr_index = float(os.getenv("ATR_THRESHOLD_INDEX", "70.0"))

    use_antigravity = os.getenv("USE_ANTIGRAVITY", "0").lower() in ("1", "true", "yes")
    model_type = os.getenv("MODEL_TYPE", "ensemble")

    transformer_model_path = os.getenv("TRANSFORMER_MODEL_PATH") or ""
    kan_model_path = os.getenv("KAN_MODEL_PATH") or ""
    daily_data_path = os.getenv("DAILY_DATA_PATH") or ""

    max_position = int(os.getenv("MAX_POSITION", "2"))

    # file-based の data_dirs が必須なので、HTTP用途ではダミーを1つ用意
    return SevenModuleInferenceServer(
        data_dirs=[{"id": "HTTP", "data_dir": "./_http_dummy"}],
        lm_studio_url=lm_studio_url,
        strategy=strategy,
        preset_name=preset,
        atr_threshold_fx=atr_fx,
        atr_threshold_index=atr_index,
        use_antigravity=use_antigravity,
        model_type=model_type,
        transformer_model_path=transformer_model_path,
        kan_model_path=kan_model_path,
        daily_data_path=daily_data_path,
        max_position=max_position,
    )


app = Flask(__name__)
_engine = _make_server()
_request_count = 0


@app.get("/health")
def health() -> Tuple[Any, int]:
    return (
        jsonify(
            {
                "status": "ok",
                "service": "MT5 HTTP Inference (7module)",
                "timestamp": datetime.now().isoformat(),
                "requests_handled": _request_count,
            }
        ),
        200,
    )


@app.post("/predict")
def predict() -> Tuple[Any, int]:
    global _request_count
    _request_count += 1

    payload = request.get_json(silent=True) or {}
    if not isinstance(payload, dict) or not payload:
        return jsonify({"error": "No JSON data received"}), 400

    try:
        data = _normalize_request(payload)
        # MT5は terminal_id 相当を持たないので固定
        signal, confidence, reason = _engine.process_request("HTTP", data)
        return (
            jsonify(
                {
                    "signal": int(signal),
                    "confidence": float(round(confidence, 4)),
                    "reason": str(reason),
                    "timestamp": datetime.now().isoformat(),
                    "request_id": _request_count,
                }
            ),
            200,
        )
    except Exception as e:
        return (
            jsonify({"error": str(e), "timestamp": datetime.now().isoformat()}),
            500,
        )


if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "5001"))
    app.run(host=host, port=port, debug=False)
