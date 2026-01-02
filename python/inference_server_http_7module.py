"""HTTP Inference Server (7module/Antigravity) — CANONICAL

運用の正本（Docker/MT5 EA から呼ぶ想定）
- GET  /health
- POST /analyze  (MT5 EA: OHLCV配列)
- POST /predict  (フラット形式)

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
import threading
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
from flask import Flask, jsonify, request

SevenModuleInferenceServer = Any


def _calc_ema(values: np.ndarray, period: int) -> np.ndarray:
    if values.size == 0:
        return values
    alpha = 2.0 / (period + 1.0)
    out = np.empty_like(values, dtype=float)
    out[0] = float(values[0])
    for i in range(1, values.size):
        out[i] = alpha * float(values[i]) + (1.0 - alpha) * out[i - 1]
    return out


def _calc_atr(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14) -> float:
    if close.size < 2 or high.size != low.size or low.size != close.size:
        return 0.0
    prev_close = close[:-1]
    tr = np.maximum(
        high[1:] - low[1:],
        np.maximum(np.abs(high[1:] - prev_close), np.abs(low[1:] - prev_close)),
    )
    if tr.size < period:
        return float(np.mean(tr)) if tr.size else 0.0
    return float(np.mean(tr[-period:]))


def _prices_to_csv_latest_to_past(prices: List[float]) -> str:
    # SevenModuleAnalyzer は prices を "最新→過去" の CSV 文字列として扱う
    return ",".join(str(x) for x in reversed(prices))


def _normalize_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    symbol = (payload.get("symbol") or "UNKNOWN")
    timeframe = (payload.get("timeframe") or "M5")
    preset = (payload.get("preset") or "").strip()

    # A) MT5 EA互換: ohlcv配列
    ohlcv = payload.get("ohlcv")
    if isinstance(ohlcv, dict) and ohlcv:
        closes_list = ohlcv.get("close") or []
        opens_list = ohlcv.get("open") or []
        highs_list = ohlcv.get("high") or []
        lows_list = ohlcv.get("low") or []

        closes = np.array(closes_list, dtype=float)
        opens = np.array(opens_list, dtype=float)
        highs = np.array(highs_list, dtype=float)
        lows = np.array(lows_list, dtype=float)

        if closes.size:
            ema12 = float(_calc_ema(closes, 12)[-1])
            ema25 = float(_calc_ema(closes, 25)[-1])
            ema100 = float(_calc_ema(closes, 100)[-1]) if closes.size >= 2 else 0.0
        else:
            ema12 = 0.0
            ema25 = 0.0
            ema100 = 0.0

        atr = _calc_atr(highs, lows, closes, period=14) if closes.size else 0.0

        close_now = payload.get("current_price")
        if close_now is None and closes.size:
            close_now = float(closes[-1])

        return {
            "symbol": symbol,
            "timeframe": timeframe,
            "preset": preset,
            "ema12": ema12,
            "ema25": ema25,
            "ema100": ema100,
            "atr": float(atr) if atr else 0.001,
            "close": float(close_now) if close_now is not None else 0.0,
            "prices": _prices_to_csv_latest_to_past([float(x) for x in closes_list]),
        }

    # B) フラット形式（互換）
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
    # import を遅延させる（Docker最小依存でも落ちないように）
    from inference_server_7module import SevenModuleInferenceServer as _Server

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
    os.makedirs("./_http_dummy", exist_ok=True)
    return _Server(
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

_engine_lock = threading.Lock()
_engine: Optional[SevenModuleInferenceServer] = None
_engine_error: Optional[str] = None

_executor = ThreadPoolExecutor(max_workers=int(os.getenv("MAX_WORKERS", "4")))
_request_timeout_sec = float(os.getenv("REQUEST_TIMEOUT_SEC", "3.0"))

_request_count = 0


def _get_engine() -> Optional[SevenModuleInferenceServer]:
    global _engine, _engine_error
    if _engine is not None or _engine_error is not None:
        return _engine
    with _engine_lock:
        if _engine is not None or _engine_error is not None:
            return _engine
        try:
            _engine = _make_server()
        except Exception as e:
            _engine_error = str(e)
            _engine = None
        return _engine


def _safe_response(
    *,
    signal: int = 0,
    confidence: float = 0.0,
    entry_allowed: bool = False,
    reason: str = "",
    error: Optional[str] = None,
    engine_mode: str = "unknown",
    request_id: int,
) -> Tuple[Any, int]:
    payload: Dict[str, Any] = {
        "signal": int(signal),
        "confidence": float(round(confidence, 4)),
        "entry_allowed": bool(entry_allowed),
        "reason": str(reason),
        "timestamp": datetime.now().isoformat(),
        "request_id": int(request_id),
        "engine_mode": engine_mode,
    }
    if error:
        payload["error"] = str(error)
    return jsonify(payload), 200


@app.get("/health")
def health() -> Tuple[Any, int]:
    engine = _get_engine()
    engine_status = "ok" if engine is not None else "degraded"
    return (
        jsonify(
            {
                "status": "ok",
                "service": "MT5 HTTP Inference (7module)",
                "timestamp": datetime.now().isoformat(),
                "requests_handled": _request_count,
                "engine_status": engine_status,
                "engine_error": _engine_error,
            }
        ),
        200,
    )


def _run_engine(data: Dict[str, Any]) -> Tuple[int, float, str, str]:
    engine = _get_engine()
    if engine is None:
        return 0, 0.0, "engine unavailable (fallback)", "fallback"

    fut = _executor.submit(engine.process_request, "HTTP", data)
    try:
        signal, confidence, reason = fut.result(timeout=_request_timeout_sec)
        return int(signal), float(confidence), str(reason), "7module"
    except TimeoutError:
        return 0, 0.0, f"timeout ({_request_timeout_sec}s)", "fallback"
    except Exception as e:
        return 0, 0.0, f"engine error: {e}", "fallback"


@app.post("/predict")
def predict() -> Tuple[Any, int]:
    global _request_count
    _request_count += 1

    payload = request.get_json(silent=True) or {}
    try:
        if not isinstance(payload, dict) or not payload:
            return _safe_response(
                signal=0,
                confidence=0.0,
                entry_allowed=False,
                reason="No JSON data received",
                error="invalid_request",
                engine_mode="fallback",
                request_id=_request_count,
            )

        data = _normalize_request(payload)
        signal, confidence, reason, mode = _run_engine(data)
        return _safe_response(
            signal=signal,
            confidence=confidence,
            entry_allowed=(signal != 0),
            reason=reason,
            error=_engine_error,
            engine_mode=mode,
            request_id=_request_count,
        )
    except Exception as e:
        return _safe_response(
            signal=0,
            confidence=0.0,
            entry_allowed=False,
            reason="exception",
            error=str(e),
            engine_mode="fallback",
            request_id=_request_count,
        )


@app.post("/analyze")
def analyze() -> Tuple[Any, int]:
    """MT5 EA互換（OHLCV配列）エンドポイント。

    EAが `entry_allowed` を必須でパースするため、エラー時も常に同キーを返す。
    """

    global _request_count
    _request_count += 1

    payload = request.get_json(silent=True) or {}
    if not isinstance(payload, dict) or not payload:
        return _safe_response(
            signal=0,
            confidence=0.0,
            entry_allowed=False,
            reason="No JSON data received",
            error="invalid_request",
            engine_mode="fallback",
            request_id=_request_count,
        )

    try:
        data = _normalize_request(payload)

        # 最低限: pricesが空なら分析不可（安全側に倒す）
        if not str(data.get("prices") or ""):
            return _safe_response(
                signal=0,
                confidence=0.0,
                entry_allowed=False,
                reason="No prices/ohlcv provided",
                error="invalid_request",
                engine_mode="fallback",
                request_id=_request_count,
            )

        signal, confidence, reason, mode = _run_engine(data)
        return _safe_response(
            signal=signal,
            confidence=confidence,
            entry_allowed=(signal != 0),
            reason=reason,
            error=_engine_error,
            engine_mode=mode,
            request_id=_request_count,
        )
    except Exception as e:
        return _safe_response(
            signal=0,
            confidence=0.0,
            entry_allowed=False,
            reason="exception",
            error=str(e),
            engine_mode="fallback",
            request_id=_request_count,
        )


if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "5001"))
    app.run(host=host, port=port, debug=False)
