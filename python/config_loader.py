from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = dict(base)
    for key, override_value in override.items():
        base_value = result.get(key)
        if isinstance(base_value, dict) and isinstance(override_value, dict):
            result[key] = _deep_merge(base_value, override_value)
        else:
            result[key] = override_value
    return result


def load_config(config_path: str | Path, *, local_filename: str = "config.local.yaml") -> dict[str, Any]:
    """Load YAML config and optionally merge a local override.

    - Reads `config_path` if it exists.
    - If `<config_dir>/<local_filename>` exists, deep-merges it over the base config.

    This is intended to keep machine-specific settings (e.g., DB path on matsuPC D: drive)
    out of git.
    """

    config_file = Path(config_path)
    config: dict[str, Any] = {}

    if config_file.exists():
        with open(config_file, "r", encoding="utf-8") as f:
            loaded = yaml.safe_load(f) or {}
            if isinstance(loaded, dict):
                config = loaded

    local_file = config_file.parent / local_filename
    if local_file.exists():
        with open(local_file, "r", encoding="utf-8") as f:
            loaded_local = yaml.safe_load(f) or {}
            if isinstance(loaded_local, dict):
                config = _deep_merge(config, loaded_local)

    return config
