import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
import site

# Fix for Qt plugins in virtual environments (like uv)
try:
    site_packages = site.getsitepackages()[0]
    qt_plugin_path = os.path.join(site_packages, "PyQt5", "Qt5", "plugins")
    os.environ["QT_PLUGIN_PATH"] = qt_plugin_path
except Exception:
    pass

from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import (
    QApplication,
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)
from controls_config import BUTTON_ORDER, DEFAULT_CONTROL_NAMES, load_control_names, save_control_names


APP_TITLE = "NES Launcher"
PROJECT_DIR = Path(__file__).resolve().parent
RECENT_FILE = PROJECT_DIR / ".cython_nes_recent_games.json"
MAX_RECENT = 15

KEY_NAME_LABELS = {
    "up": "Arrows Up",
    "down": "Arrows Down",
    "left": "Arrows Left",
    "right": "Arrows Right",
    "return": "Enter",
    "space": "Space",
    "tab": "Tab",
    "right shift": "Right Shift",
    "left shift": "Left Shift",
    "right ctrl": "Right Ctrl",
    "left ctrl": "Left Ctrl",
    "right alt": "Right Alt",
    "left alt": "Left Alt",
}
class ControlsDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Controls Settings")
        self.resize(620, 360)

        self._controls = load_control_names()
        self._buttons = {"P1": {}, "P2": {}}
        self._capture_target = None
        self.setFocusPolicy(Qt.StrongFocus)

        root = QVBoxLayout()
        hint = QLabel("Click action, then press a key. Settings will be used by main.py on next launch.")
        root.addWidget(hint)

        self.capture_hint = QLabel("")
        root.addWidget(self.capture_hint)

        grid = QGridLayout()
        grid.addWidget(QLabel("Button"), 0, 0)
        grid.addWidget(QLabel("Player 1"), 0, 1)
        grid.addWidget(QLabel("Player 2"), 0, 2)

        for row, btn in enumerate(BUTTON_ORDER, start=1):
            grid.addWidget(QLabel(btn), row, 0)

            btn_p1 = QPushButton(self._display_key_name(self._controls["P1"][btn]))
            btn_p2 = QPushButton(self._display_key_name(self._controls["P2"][btn]))

            btn_p1.clicked.connect(lambda _checked=False, p="P1", b=btn: self._start_capture(p, b))
            btn_p2.clicked.connect(lambda _checked=False, p="P2", b=btn: self._start_capture(p, b))

            self._buttons["P1"][btn] = btn_p1
            self._buttons["P2"][btn] = btn_p2

            grid.addWidget(btn_p1, row, 1)
            grid.addWidget(btn_p2, row, 2)

        root.addLayout(grid)

        buttons = QDialogButtonBox(QDialogButtonBox.Save | QDialogButtonBox.Cancel)
        reset_button = buttons.addButton("Reset to Defaults", QDialogButtonBox.ResetRole)
        reset_button.clicked.connect(self._on_reset_defaults)
        buttons.accepted.connect(self._on_save)
        buttons.rejected.connect(self.reject)
        root.addWidget(buttons)

        self.setLayout(root)

    def _display_key_name(self, key_name):
        if key_name in KEY_NAME_LABELS:
            return KEY_NAME_LABELS[key_name]
        if len(key_name) == 1:
            return key_name.upper()
        return key_name.title()

    def _start_capture(self, player, button):
        self._capture_target = (player, button)
        self.capture_hint.setText(f"Press key for {player} {button}...")
        self._buttons[player][button].setText("Press key...")
        self.setFocus()

    def _event_to_key_name(self, event):
        key = event.key()

        if Qt.Key_A <= key <= Qt.Key_Z:
            return chr(key).lower()
        if Qt.Key_0 <= key <= Qt.Key_9:
            return chr(key)

        special = {
            Qt.Key_Up: "up",
            Qt.Key_Down: "down",
            Qt.Key_Left: "left",
            Qt.Key_Right: "right",
            Qt.Key_Return: "return",
            Qt.Key_Enter: "return",
            Qt.Key_Space: "space",
            Qt.Key_Tab: "tab",
            Qt.Key_Shift: "right shift",
            Qt.Key_Control: "right ctrl",
            Qt.Key_Alt: "right alt",
        }
        mapped = special.get(key)
        if mapped is not None:
            return mapped

        text = event.text().strip().lower()
        if len(text) == 1:
            return text
        return None

    def keyPressEvent(self, event):
        if self._capture_target is None:
            super().keyPressEvent(event)
            return

        player, button = self._capture_target
        if event.key() == Qt.Key_Escape:
            self._buttons[player][button].setText(self._display_key_name(self._controls[player][button]))
            self.capture_hint.setText("Capture cancelled")
            self._capture_target = None
            return

        key_name = self._event_to_key_name(event)
        if key_name is None:
            return

        self._controls[player][button] = key_name
        self._buttons[player][button].setText(self._display_key_name(key_name))
        self.capture_hint.setText(f"Set {player} {button} = {self._display_key_name(key_name)}")
        self._capture_target = None

    def _on_save(self):
        save_control_names(self._controls)
        self.accept()

    def _on_reset_defaults(self):
        self._capture_target = None
        self.capture_hint.setText("Defaults restored in form. Click Save to apply.")
        for player in ("P1", "P2"):
            for btn in BUTTON_ORDER:
                key_name = DEFAULT_CONTROL_NAMES[player][btn]
                self._controls[player][btn] = key_name
                self._buttons[player][btn].setText(self._display_key_name(key_name))


class NESLauncher(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(APP_TITLE)
        self.resize(560, 420)

        self.recent_games = self._load_recent_games()

        self.path_input = QLineEdit()
        self.path_input.setPlaceholderText("Path to .nes ROM")

        self.browse_button = QPushButton("Browse")
        self.browse_button.clicked.connect(self.browse_rom)

        self.controls_button = QPushButton("Controls Settings")
        self.controls_button.clicked.connect(self.open_controls_settings)

        self.launch_button = QPushButton("Launch")
        self.launch_button.clicked.connect(self.launch_selected_game)

        self.close_on_launch = QCheckBox("Close launcher on start")
        self.close_on_launch.setChecked(True)

        self.status_label = QLabel("Choose ROM file to start")

        self.recents_list = QListWidget()
        self.recents_list.itemDoubleClicked.connect(self.launch_recent_item)
        self.recents_list.currentItemChanged.connect(self.preview_recent_item)

        top_row = QHBoxLayout()
        top_row.addWidget(self.path_input, 1)
        top_row.addWidget(self.browse_button)
        top_row.addWidget(self.controls_button)
        top_row.addWidget(self.launch_button)

        root = QVBoxLayout()
        root.addLayout(top_row)
        root.addWidget(self.close_on_launch)
        root.addWidget(QLabel("Recent games (double click to launch):"))
        root.addWidget(self.recents_list, 1)
        root.addWidget(self.status_label)
        self.setLayout(root)

        self._refresh_recents_list()

    def browse_rom(self):
        file_path, _ = QFileDialog.getOpenFileName(self, "Select NES ROM", "", "NES ROM (*.nes)")
        if not file_path:
            return
        self.path_input.setText(file_path)
        self.status_label.setText("ROM selected")

    def launch_selected_game(self):
        rom_path = self.path_input.text().strip()
        if not rom_path:
            QMessageBox.warning(self, APP_TITLE, "Select ROM first")
            return

        if not os.path.isfile(rom_path):
            QMessageBox.warning(self, APP_TITLE, "ROM file does not exist")
            return

        emulator_entry = Path(__file__).parent / "main.py"
        if not emulator_entry.exists():
            QMessageBox.critical(self, APP_TITLE, "main.py not found")
            return

        title = self._title_candidates(rom_path)[0]
        self._remember_game(rom_path, title)

        subprocess.Popen(
            [sys.executable, str(emulator_entry), rom_path],
            cwd=str(Path(__file__).parent),
        )

        self.status_label.setText("Game launched")
        if self.close_on_launch.isChecked():
            self.close()

    def open_controls_settings(self):
        dialog = ControlsDialog(self)
        if dialog.exec_():
            self.status_label.setText("Controls saved")

    def launch_recent_item(self, item):
        data = item.data(Qt.UserRole)
        if not data:
            return
        self.path_input.setText(data["path"])
        self.launch_selected_game()

    def preview_recent_item(self, current, _previous):
        if current is None:
            return
        data = current.data(Qt.UserRole)
        if not data:
            return

        self.path_input.setText(data.get("path", ""))
        self.status_label.setText(f"Ready: {data.get('title', 'Unknown')}")

    def _title_candidates(self, rom_path):
        stem = Path(rom_path).stem
        cleaned = re.sub(r"[\(\[].*?[\)\]]", " ", stem)
        cleaned = cleaned.replace("_", " ").replace(".", " ")
        cleaned = re.sub(r"\s+", " ", cleaned).strip()

        candidates = []
        if cleaned:
            candidates.append(cleaned)
        if stem != cleaned and stem:
            candidates.append(stem)
        return candidates or ["nes"]

    def _load_recent_games(self):
        if not RECENT_FILE.exists():
            return []
        try:
            payload = json.loads(RECENT_FILE.read_text(encoding="utf-8"))
            if isinstance(payload, list):
                return payload
        except Exception:
            pass
        return []

    def _save_recent_games(self):
        try:
            RECENT_FILE.write_text(json.dumps(self.recent_games, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception:
            pass

    def _refresh_recents_list(self):
        self.recents_list.clear()
        for entry in self.recent_games:
            title = entry.get("title") or Path(entry.get("path", "")).stem
            timestamp = entry.get("last_played", "")
            label = f"{title}  [{timestamp}]"
            item = QListWidgetItem(label)
            item.setData(Qt.UserRole, entry)
            self.recents_list.addItem(item)

    def _remember_game(self, path, title):
        now = datetime.now().strftime("%Y-%m-%d %H:%M")
        new_entry = {
            "path": path,
            "title": title,
            "last_played": now,
        }

        existing = [x for x in self.recent_games if x.get("path") != path]
        self.recent_games = [new_entry] + existing
        self.recent_games = self.recent_games[:MAX_RECENT]
        self._save_recent_games()
        self._refresh_recents_list()


def main():
    app = QApplication(sys.argv)
    widget = NESLauncher()
    widget.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
