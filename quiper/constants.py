# Application Configuration
from pathlib import Path

APP_NAME = "Quiper"
DEFAULT_SERVICE = "Grok"

# User Interface
LOGO_PATH = "logo/logo.png"
WINDOW_FRAME_AUTOSAVE_NAME = "QuiperWindowFrame"
WINDOW_CORNER_RADIUS = 15.0
DRAGGABLE_AREA_HEIGHT = 30
UI_PADDING = 5

# System Integration
STATUS_ITEM_OBSERVER_CONTEXT = 1
DEFAULT_HOTKEY = {"flags": 0x80000, "key": 49}  # Option + Space


LOG_DIR = Path.home() / "Library" / "Logs" / "quiper"
LOG_DIR.mkdir(parents=True, exist_ok=True)
