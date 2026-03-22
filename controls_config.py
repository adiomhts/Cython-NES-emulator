import json
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent
CONTROLS_FILE = PROJECT_DIR / ".cython_nes_controls.json"

DEFAULT_CONTROL_NAMES = {
    "P1": {
        "A": "z",
        "B": "x",
        "SELECT": "right shift",
        "START": "return",
        "UP": "up",
        "DOWN": "down",
        "LEFT": "left",
        "RIGHT": "right",
    },
    "P2": {
        "A": "u",
        "B": "o",
        "SELECT": "right ctrl",
        "START": "right alt",
        "UP": "i",
        "DOWN": "k",
        "LEFT": "j",
        "RIGHT": "l",
    },
}

BUTTON_ORDER = ["A", "B", "SELECT", "START", "UP", "DOWN", "LEFT", "RIGHT"]


def _deep_copy_default_controls():
    return json.loads(json.dumps(DEFAULT_CONTROL_NAMES))


def load_control_names():
    if not CONTROLS_FILE.exists():
        return _deep_copy_default_controls()

    try:
        data = json.loads(CONTROLS_FILE.read_text(encoding="utf-8"))
    except Exception:
        return _deep_copy_default_controls()

    merged = _deep_copy_default_controls()
    if isinstance(data, dict):
        for player in ("P1", "P2"):
            p_data = data.get(player, {})
            if isinstance(p_data, dict):
                for btn in BUTTON_ORDER:
                    value = p_data.get(btn)
                    if isinstance(value, str) and value.strip():
                        merged[player][btn] = value.strip().lower()
    return merged


def save_control_names(config):
    try:
        CONTROLS_FILE.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        pass
