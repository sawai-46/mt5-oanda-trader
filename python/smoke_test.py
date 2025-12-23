from pathlib import Path

from inference_server_7module import SevenModuleInferenceServer


def build_request(data_dir: Path) -> Path:
    data_dir.mkdir(parents=True, exist_ok=True)
    req_path = data_dir / "request_SMOKE.csv"
    lines = [
        "symbol,USDJPY",
        "timeframe,M5",
        "ema12,150.12",
        "ema25,150.05",
        "ema100,149.90",
        "atr,0.15",
        "close,150.10",
        "volume,100",
        "technical_strength,0.7",
        "trend_direction,1",
    ]
    req_path.write_text("\n".join(lines), encoding="utf-8")
    return req_path


def main() -> None:
    data_dir = Path("python_smoke")
    req_file = build_request(data_dir)

    server = SevenModuleInferenceServer(
        data_dirs=[{"id": "SMOKE", "data_dir": str(data_dir)}],
        lm_studio_url="http://localhost:1234",
        strategy="full",
        atr_threshold_fx=7.0,
        atr_threshold_index=70.0,
        use_antigravity=False,
        model_type="ensemble",
        transformer_model_path="",
        kan_model_path="",
        daily_data_path="",
        max_position=2,
    )

    parsed = server.parse_request(req_file)
    if not parsed:
        raise SystemExit("Failed to parse request file")

    signal, confidence, reason = server.process_request("SMOKE", parsed)
    server.write_response("SMOKE", signal, confidence, reason, data_path=data_dir)

    resp_path = data_dir / "response_SMOKE.csv"
    print("--- Response file contents ---")
    print(resp_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
