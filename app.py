import logging
import os
import subprocess
import sys
import time
import webbrowser
from logging.handlers import RotatingFileHandler
from pathlib import Path
from urllib.parse import urlparse

from PyQt6.QtCore import QByteArray, QPoint, Qt
from PyQt6.QtGui import QAction, QBrush, QColor, QPainter, QPen
from PyQt6.QtWidgets import (
    QApplication,
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMenu,
    QMenuBar,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QSpinBox,
    QStyle,
    QSystemTrayIcon,
    QTableWidget,
    QTableWidgetItem,
    QTabWidget,
    QTextBrowser,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from app_meta import SUPPORT_URL
from config import APP_NAME, load_config, save_config
from rd_client import RealDebridClient
from ui.dialogs import HelpDialog
from utils import categories as cat
from utils import format as fmt
from utils import urltools as utools
from workers import (
    DownloadWorker,
    PreviewWorker,
    RDTorrentStartWorker,
    TorrentPreviewWorker,
)


class SquareProgressBar(QWidget):
    def __init__(self, squares: int = 20, parent=None):
        super().__init__(parent)
        self._value = 0  # 0..100
        self._squares = max(5, squares)
        self.setMinimumHeight(28)

    def setValue(self, v: int):
        v = max(0, min(100, int(v)))
        if v != self._value:
            self._value = v
            self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        w = self.width()
        h = self.height()
        gap = 4
        box_w = (w - gap * (self._squares - 1)) / self._squares
        box_h = h
        filled = int(round(self._value / 100 * self._squares))

        on_brush = QBrush(QColor(56, 142, 60))
        off_brush = QBrush(QColor(220, 220, 220))
        pen = QPen(QColor(200, 200, 200))
        painter.setPen(pen)

        x = 0
        for i in range(self._squares):
            rect = (int(x), 0, int(box_w), int(box_h))
            painter.setBrush(on_brush if i < filled else off_brush)
            painter.drawRect(*rect)
            x += box_w + gap
        # No overlay text; percent shown in a label alongside


class MainWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(APP_NAME)
        self.resize(720, 520)

        # Hidden token controls (managed via menu dialog)
        self.token_edit = QLineEdit()
        self.token_edit.setEchoMode(QLineEdit.EchoMode.Password)
        self.show_token_cb = QCheckBox("Show token")
        self.save_token_cb = QCheckBox("Remember token")
        self.link_edit = QLineEdit()
        self.link_label = QLabel("Link:")
        self.bulk_mode_cb = QCheckBox("Bulk mode")
        self.bulk_label = QLabel("Links (one per line):")
        self.bulk_edit = QTextEdit()
        self.bulk_edit.setPlaceholderText("Paste one link per line…")
        self.outdir_edit = QLineEdit(str(Path.home() / "Downloads"))
        self.log_box = QPlainTextEdit()
        self.log_box.setReadOnly(True)

        self.preview_btn = QPushButton("Preview Files")
        self.select_all_btn = QPushButton("Select All")
        self.clear_sel_btn = QPushButton("Clear Selection")
        self.remove_sel_btn = QPushButton("Remove Selected")
        self.clear_all_btn = QPushButton("Clear All")
        self.total_label = QLabel("Selected: 0 B")
        self.filter_label = QLabel("Filter:")
        from PyQt6.QtWidgets import QComboBox

        self.filter_combo = QComboBox()
        self.filter_combo.addItems(
            [
                "All",
                "Video",
                "Audio",
                "Image",
                "Document",
                "Compressed",
                "Program",
                "Other",
                "Excluded",
            ]
        )
        self.filter_combo.currentIndexChanged.connect(lambda *_: self.apply_filter())
        # Columns: Select, Name, Size, Type, Source, %, Speed, ETA, Status
        self.preview_table = QTableWidget(0, 9)
        self.preview_table.setHorizontalHeaderLabels(
            ["Select", "Name", "Size", "Type", "Source", "%", "Speed", "ETA", "Status"]
        )
        self.preview_table.setColumnWidth(0, 70)
        self.preview_table.setColumnWidth(1, 280)
        self.preview_table.setColumnWidth(2, 110)
        self.preview_table.setColumnWidth(3, 80)
        self.preview_table.setColumnWidth(4, 120)
        self.preview_table.setColumnWidth(5, 60)
        self.preview_table.setColumnWidth(6, 100)
        self.preview_table.setColumnWidth(7, 100)
        self.preview_table.setColumnWidth(8, 100)
        self.preview_table.setVisible(False)
        self.preview_table.setSortingEnabled(True)
        # Context menu for per-row actions
        self.preview_table.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.preview_table.customContextMenuRequested.connect(self.on_table_context_menu)

        self.concurrent_spin = QSpinBox()
        self.concurrent_spin.setRange(1, 8)
        self.concurrent_spin.setValue(1)
        self.concurrent_label = QLabel("Concurrent downloads (-j):")

        self.btn_browse = QPushButton("Browse…")
        self.btn_download = QPushButton("Download")
        self.btn_quit = QPushButton("Quit")

        self.conn_edit = QLineEdit("16")
        self.splt_edit = QLineEdit("16")
        self.conn_edit.setMaximumWidth(60)
        self.splt_edit.setMaximumWidth(60)

        self.help_label = QLabel(
            (
                'Get API token: <a href="https://real-debrid.com/apitoken">Real-Debrid</a>. '
                "Supports RD hosters and direct downloads. "
                "Paste links, choose folder, then click Download."
            )
        )
        self.help_label.setTextFormat(Qt.TextFormat.RichText)
        self.help_label.setOpenExternalLinks(True)

        self.progress = SquareProgressBar(squares=24)
        self.eta_global_label = QLabel("")
        self.queue_counts_label = QLabel("")
        self.percent_global_label = QLabel("")

        self.btn_pause = QPushButton("Pause")
        self.btn_cancel = QPushButton("Cancel")
        self.btn_help = QPushButton("Help")
        self.dark_mode_cb = QCheckBox("Dark mode")
        self.open_on_done_cb = QCheckBox("Open folder when done")

        self.btn_pause.clicked.connect(self.on_pause_resume)
        self.btn_cancel.clicked.connect(self.on_cancel)
        self.btn_help.clicked.connect(self.on_help)

        cfg = load_config()
        if cfg.get("token"):
            self.token_edit.setText(cfg["token"])
            self.save_token_cb.setChecked(True)
        else:
            try:
                if cfg.get("use_keyring"):
                    from config import get_token_from_keyring

                    tok = get_token_from_keyring()
                    if tok:
                        self.token_edit.setText(tok)
                        self.save_token_cb.setChecked(True)
            except Exception:
                pass
        # restore settings
        if cfg.get("outdir"):
            self.outdir_edit.setText(cfg.get("outdir"))
        if cfg.get("connections"):
            self.conn_edit.setText(str(cfg.get("connections")))
        if cfg.get("splits"):
            self.splt_edit.setText(str(cfg.get("splits")))
        if cfg.get("concurrency"):
            self.concurrent_spin.setValue(int(cfg.get("concurrency")))
        if cfg.get("dark_mode"):
            self.dark_mode_cb.setChecked(bool(cfg.get("dark_mode")))
            self.apply_theme()
        if cfg.get("open_on_done"):
            self.open_on_done_cb.setChecked(bool(cfg.get("open_on_done")))

        self.show_token_cb.stateChanged.connect(self.toggle_token_visibility)
        self.btn_browse.clicked.connect(self.choose_dir)
        self.btn_download.clicked.connect(self.start_download)
        self.btn_quit.clicked.connect(self.close)
        self.bulk_mode_cb.stateChanged.connect(self.on_bulk_mode_changed)
        self.preview_btn.clicked.connect(self.on_preview)
        self.select_all_btn.clicked.connect(self.on_select_all)
        self.clear_sel_btn.clicked.connect(self.on_clear_selection)
        self.dark_mode_cb.stateChanged.connect(self.on_dark_mode_changed)

        # Auto-preview timer
        from PyQt6.QtCore import QTimer

        self._preview_timer = QTimer(self)
        self._preview_timer.setSingleShot(True)
        self._preview_timer.timeout.connect(self.on_preview)
        self.link_edit.textChanged.connect(lambda *_: self._schedule_preview())
        self.bulk_edit.textChanged.connect(lambda *_: self._schedule_preview())

        layout = QVBoxLayout()
        # Menu bar
        self.menu_bar = QMenuBar(self)
        layout.setMenuBar(self.menu_bar)
        self._build_menus()

        row2 = QHBoxLayout()
        row2.addWidget(self.link_label)
        row2.addWidget(self.link_edit)
        row2.addWidget(self.bulk_mode_cb)
        layout.addLayout(row2)

        layout.addWidget(self.bulk_label)
        layout.addWidget(self.bulk_edit)

        rowp = QHBoxLayout()
        rowp.addWidget(self.preview_btn)
        rowp.addWidget(self.select_all_btn)
        rowp.addWidget(self.clear_sel_btn)
        rowp.addWidget(self.remove_sel_btn)
        rowp.addWidget(self.clear_all_btn)
        rowp.addStretch(1)
        rowp.addWidget(self.filter_label)
        rowp.addWidget(self.filter_combo)
        rowp.addWidget(self.concurrent_label)
        rowp.addWidget(self.concurrent_spin)
        rowp.addWidget(self.total_label)
        layout.addLayout(rowp)
        layout.addWidget(self.preview_table)

        row3 = QHBoxLayout()
        row3.addWidget(QLabel("Save to:"))
        row3.addWidget(self.outdir_edit)
        row3.addWidget(self.btn_browse)
        layout.addLayout(row3)

        row4 = QHBoxLayout()
        row4.addWidget(QLabel("Connections (-x):"))
        row4.addWidget(self.conn_edit)
        row4.addSpacing(12)
        row4.addWidget(QLabel("Splits (-s):"))
        row4.addWidget(self.splt_edit)
        layout.addLayout(row4)

        layout.insertWidget(0, self.help_label)
        layout.addWidget(self.progress)
        pr = QHBoxLayout()
        pr.addWidget(self.eta_global_label)
        pr.addSpacing(12)
        pr.addWidget(self.queue_counts_label)
        pr.addStretch(1)
        pr.addWidget(self.percent_global_label)
        layout.addLayout(pr)

        # Log header with Clear button
        log_row = QHBoxLayout()
        log_row.addWidget(QLabel("Log:"))
        self.btn_clear_log = QPushButton("Clear Log")
        self.btn_clear_log.setToolTip("Clear the log view")
        self.btn_clear_log.clicked.connect(self.on_clear_log)
        log_row.addStretch(1)
        log_row.addWidget(self.btn_clear_log)
        layout.addLayout(log_row)
        layout.addWidget(self.log_box)

        row5 = QHBoxLayout()
        row5.addStretch(1)
        row5.addWidget(self.btn_pause)
        row5.addWidget(self.btn_cancel)
        row5.addWidget(self.btn_help)
        row5.addWidget(self.dark_mode_cb)
        row5.addWidget(self.open_on_done_cb)
        row5.addWidget(self.btn_download)
        row5.addWidget(self.btn_quit)
        layout.addLayout(row5)

        self.btn_pause.setEnabled(False)
        self.btn_cancel.setEnabled(False)
        self.setLayout(layout)
        self.on_bulk_mode_changed(0)
        # Hook checkbox changes for selected size update
        self.preview_table.itemChanged.connect(lambda *_: self.update_selected_total())
        self.remove_sel_btn.clicked.connect(self.on_remove_selected)
        self.clear_all_btn.clicked.connect(self.on_clear_all_preview)
        # Restore table layout and sort
        self.restore_table_layout()
        # Drag & drop support
        self.setAcceptDrops(True)
        # Scheduler + clipboard timers
        from PyQt6.QtCore import QTimer

        self._sched_timer = QTimer(self)
        self._sched_timer.setInterval(60_000)
        self._sched_timer.timeout.connect(self._apply_scheduler)
        self._sched_timer.start()
        self._clip_timer = QTimer(self)
        self._clip_timer.setInterval(1500)
        self._clip_timer.timeout.connect(self._check_clipboard)
        self._clip_timer.start()
        self._clip_last = ""
        self._scheduler_paused = False

    def _build_menus(self):
        file_menu = self.menu_bar.addMenu("File")
        open_folder_act = QAction("Open Download Folder", self)
        open_folder_act.triggered.connect(lambda: self.open_folder(self.outdir_edit.text().strip()))
        history_act = QAction("History…", self)
        history_act.triggered.connect(self.open_history)
        import_act = QAction("Import Links…", self)
        export_act = QAction("Export Links…", self)
        import_act.triggered.connect(self.on_import_links)
        export_act.triggered.connect(self.on_export_links)
        add_torrent_act = QAction("Add Torrent…", self)
        add_torrent_act.triggered.connect(self.on_add_torrent)
        add_magnet_act = QAction("Add Magnet…", self)
        add_magnet_act.triggered.connect(self.on_add_magnet)
        yt_act = QAction("Add via yt-dlp…", self)
        yt_act.triggered.connect(self.on_add_ytdlp)
        exit_act = QAction("Exit", self)
        exit_act.triggered.connect(self.close)
        file_menu.addAction(open_folder_act)
        file_menu.addAction(history_act)
        file_menu.addAction(import_act)
        file_menu.addAction(export_act)
        file_menu.addAction(add_torrent_act)
        file_menu.addAction(add_magnet_act)
        file_menu.addAction(yt_act)
        page_act = QAction("Add Page…", self)
        page_act.triggered.connect(self.on_add_page)
        file_menu.addAction(page_act)
        file_menu.addSeparator()
        file_menu.addAction(exit_act)

        settings_menu = self.menu_bar.addMenu("Settings")
        token_act = QAction("Set API Token…", self)
        token_act.triggered.connect(self.open_token_dialog)
        oauth_act = QAction("Sign in to Real‑Debrid…", self)
        oauth_act.triggered.connect(self.open_rd_oauth)
        net_act = QAction("Network Settings…", self)
        net_act.triggered.connect(self.open_network_settings)
        sched_act = QAction("Scheduler…", self)
        sched_act.triggered.connect(self.open_scheduler)
        set_folder_act = QAction("Set Download Folder…", self)
        set_folder_act.triggered.connect(self.on_set_download_folder)
        types_act = QAction("File Types & Rules…", self)
        types_act.triggered.connect(self.open_filetypes_settings)
        privacy_act = QAction("Privacy & Power…", self)
        privacy_act.triggered.connect(self.open_privacy_power)
        self.dark_act = QAction("Dark Mode", self)
        self.dark_act.setCheckable(True)
        self.dark_act.setChecked(self.dark_mode_cb.isChecked())
        self.dark_act.toggled.connect(self.dark_mode_cb.setChecked)
        self.autostart_act = QAction("Auto-start RD after add", self)
        self.autostart_act.setCheckable(True)
        try:
            self.autostart_act.setChecked(bool(load_config().get("auto_start_rd_on_add", True)))
        except Exception:
            self.autostart_act.setChecked(True)
        self.autostart_act.toggled.connect(self.on_toggle_autostart)
        settings_menu.addAction(token_act)
        settings_menu.addAction(oauth_act)
        settings_menu.addAction(net_act)
        settings_menu.addAction(sched_act)
        settings_menu.addAction(set_folder_act)
        settings_menu.addAction(types_act)
        settings_menu.addAction(self.dark_act)
        settings_menu.addAction(privacy_act)
        settings_menu.addAction(self.autostart_act)

        help_menu = self.menu_bar.addMenu("Help")
        help_act = QAction("Help", self)
        help_act.triggered.connect(self.on_help)
        support_act = QAction("Support / Donate…", self)
        support_act.triggered.connect(self.on_support)
        about_act = QAction("About", self)
        about_act.triggered.connect(
            lambda: QMessageBox.information(
                self, "About", f"{APP_NAME}\nPyQt6 + Real‑Debrid + aria2"
            )
        )
        help_menu.addAction(help_act)
        help_menu.addAction(support_act)
        help_menu.addAction(about_act)
        # Top-right Support button on menubar
        try:
            btn = QPushButton("Support")
            btn.setCursor(Qt.CursorShape.PointingHandCursor)
            btn.setFlat(True)
            btn.clicked.connect(self.on_support)
            self.menu_bar.setCornerWidget(btn, Qt.Corner.TopRightCorner)
        except Exception:
            pass

    def on_support(self):
        url = SUPPORT_URL
        if url:
            try:
                import webbrowser

                webbrowser.open(url)
                return
            except Exception:
                pass
        QMessageBox.information(
            self, "Support", "Thank you for your support!\nSupport link will be available soon."
        )

    def open_token_dialog(self):
        dlg = QDialog(self)
        dlg.setWindowTitle("API Token")
        v = QVBoxLayout(dlg)
        v.addWidget(QLabel("Enter your Real‑Debrid API token:"))
        token_edit = QLineEdit(self.token_edit.text())
        token_edit.setEchoMode(QLineEdit.EchoMode.Password)
        show_cb = QCheckBox("Show token")
        show_cb.stateChanged.connect(
            lambda _: token_edit.setEchoMode(
                QLineEdit.EchoMode.Normal if show_cb.isChecked() else QLineEdit.EchoMode.Password
            )
        )
        remember_cb = QCheckBox("Remember token (config file)")
        remember_cb.setChecked(self.save_token_cb.isChecked())
        keyring_cb = QCheckBox("Use system keyring (recommended)")
        try:
            from config import keyring_available

            keyring_ok = keyring_available()
        except Exception:
            keyring_ok = False
        cfg = load_config()
        keyring_cb.setChecked(bool(cfg.get("use_keyring") and keyring_ok))
        keyring_cb.setEnabled(keyring_ok)
        v.addWidget(token_edit)
        v.addWidget(show_cb)
        v.addWidget(remember_cb)
        v.addWidget(keyring_cb)
        btns = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        v.addWidget(btns)
        btns.accepted.connect(dlg.accept)
        btns.rejected.connect(dlg.reject)
        if dlg.exec() == QDialog.DialogCode.Accepted:
            self.token_edit.setText(token_edit.text().strip())
            self.save_token_cb.setChecked(remember_cb.isChecked())
            # Persist choice
            cfg = load_config()
            cfg["use_keyring"] = bool(keyring_cb.isChecked())
            save_config(cfg)
            # Save token per preference
            if keyring_cb.isChecked():
                try:
                    from config import set_token_in_keyring

                    set_token_in_keyring(token_edit.text().strip())
                    cfg = load_config()
                    if "token" in cfg:
                        del cfg["token"]
                    save_config(cfg)
                except Exception:
                    pass
            elif remember_cb.isChecked():
                self.save_settings(token=token_edit.text().strip())

    def open_rd_oauth(self):
        from PyQt6.QtCore import QThread, pyqtSignal

        try:
            import rd_oauth

            step1 = rd_oauth.device_code(new_credentials=True)
            user_code = step1.get("user_code")
            verify_url = step1.get("verification_url")
            interval = int(step1.get("interval") or 5)
            device_code = step1.get("device_code")
        except Exception as e:
            QMessageBox.warning(self, "Real‑Debrid", f"Failed to initiate device flow: {e}")
            return

        # Worker to poll credentials and exchange token without blocking UI
        class RDOAuthWorker(QThread):
            progress = pyqtSignal(str)
            success = pyqtSignal(dict)
            error = pyqtSignal(str)

            def __init__(self, device_code: str, interval: int):
                super().__init__()
                self.device_code = device_code
                self.interval = interval
                self._stop = False

            def stop(self):
                self._stop = True

            def run(self):
                try:
                    self.progress.emit("Waiting for authorization…")
                    creds = rd_oauth.poll_credentials(
                        self.device_code, interval=self.interval, timeout_sec=600
                    )
                    if self._stop:
                        return
                    cid = creds.get("client_id")
                    csec = creds.get("client_secret")
                    toks = rd_oauth.exchange_token(cid, csec, self.device_code)
                    self.success.emit(
                        {
                            "client_id": cid,
                            "client_secret": csec,
                            "access_token": toks.get("access_token"),
                            "refresh_token": toks.get("refresh_token"),
                        }
                    )
                except Exception as e:
                    self.error.emit(str(e))

        dlg = QDialog(self)
        dlg.setWindowTitle("Sign in to Real‑Debrid")
        v = QVBoxLayout(dlg)
        v.addWidget(QLabel("1) Click the button to open Real‑Debrid device page."))
        open_btn = QPushButton("Open Device Page")
        v.addWidget(open_btn)
        v.addWidget(QLabel("2) Enter this code (auto-copied to clipboard):"))
        code_row = QHBoxLayout()
        code_edit = QLineEdit(user_code or "")
        code_edit.setReadOnly(True)
        copy_btn = QPushButton("Copy Code")

        def copy_code():
            try:
                QApplication.clipboard().setText(user_code or "")
                code_edit.selectAll()
            except Exception:
                pass

        copy_btn.clicked.connect(copy_code)
        code_row.addWidget(code_edit)
        code_row.addWidget(copy_btn)
        v.addLayout(code_row)
        # Copy once immediately so user can paste on the page
        try:
            QApplication.clipboard().setText(user_code or "")
            code_edit.selectAll()
        except Exception:
            pass

        def open_dev():
            try:
                QApplication.clipboard().setText(user_code or "")
            except Exception:
                pass
            webbrowser.open(verify_url)

        open_btn.clicked.connect(open_dev)
        status = QLabel("Waiting for authorization…")
        v.addWidget(status)
        btns = QDialogButtonBox(QDialogButtonBox.StandardButton.Cancel)
        v.addWidget(btns)
        btns.rejected.connect(dlg.reject)

        worker = RDOAuthWorker(device_code, max(2, interval))
        worker.progress.connect(lambda s: status.setText(s))

        def on_success(payload: dict):
            cfg = load_config()
            cfg["rd_oauth_client_id"] = payload.get("client_id")
            cfg["rd_oauth_client_secret"] = payload.get("client_secret")
            cfg["rd_access_token"] = payload.get("access_token")
            cfg["rd_refresh_token"] = payload.get("refresh_token")
            save_config(cfg)
            status.setText("Authorized. You can close this dialog.")
            QMessageBox.information(self, "Real‑Debrid", "Authorization successful.")
            dlg.accept()

        worker.success.connect(on_success)
        worker.error.connect(lambda e: status.setText(f"Waiting… ({e})"))
        worker.start()
        dlg.exec()
        try:
            if worker.isRunning():
                worker.stop()
                worker.wait(1000)
        except Exception:
            pass

    def open_scheduler(self):
        cfg = load_config()
        dlg = QDialog(self)
        dlg.setWindowTitle("Scheduler")
        v = QVBoxLayout(dlg)
        v.addWidget(
            QLabel("Quiet hours (pause downloads during this window). Use 24h format HH:MM.")
        )
        row = QHBoxLayout()
        start_edit = QLineEdit(cfg.get("quiet_start", ""))
        end_edit = QLineEdit(cfg.get("quiet_end", ""))
        row.addWidget(QLabel("Start:"))
        row.addWidget(start_edit)
        row.addSpacing(12)
        row.addWidget(QLabel("End:"))
        row.addWidget(end_edit)
        v.addLayout(row)
        auto_zip_cb = QCheckBox("Auto-extract .zip files after completion")
        auto_zip_cb.setChecked(bool(cfg.get("auto_extract_zip")))
        v.addWidget(auto_zip_cb)
        btns = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        v.addWidget(btns)
        btns.accepted.connect(dlg.accept)
        btns.rejected.connect(dlg.reject)
        if dlg.exec() == QDialog.DialogCode.Accepted:
            cfg["quiet_start"] = start_edit.text().strip()
            cfg["quiet_end"] = end_edit.text().strip()
            cfg["auto_extract_zip"] = bool(auto_zip_cb.isChecked())
            save_config(cfg)
            self.append_log("Scheduler settings saved.")

    def _parse_hhmm(self, s: str) -> tuple[int, int] | None:
        try:
            parts = s.split(":", 1)
            if len(parts) != 2:
                return None
            h = int(parts[0])
            m = int(parts[1])
            if 0 <= h < 24 and 0 <= m < 60:
                return h, m
        except Exception:
            return None
        return None

    def _apply_scheduler(self):
        try:
            cfg = load_config()
            qs = cfg.get("quiet_start")
            qe = cfg.get("quiet_end")
            if not qs or not qe:
                return
            s = self._parse_hhmm(qs)
            e = self._parse_hhmm(qe)
            if not s or not e:
                return
            from datetime import datetime

            now = datetime.now()
            cur = now.hour * 60 + now.minute
            sm = s[0] * 60 + s[1]
            em = e[0] * 60 + e[1]
            in_quiet = False
            if sm <= em:
                in_quiet = sm <= cur < em
            else:
                in_quiet = cur >= sm or cur < em
            if in_quiet and hasattr(self, "worker") and self.worker.isRunning():
                if not self._scheduler_paused:
                    try:
                        self.worker.pause()
                        self._scheduler_paused = True
                        self.append_log("Scheduler: paused during quiet hours.")
                    except Exception:
                        pass
            elif (not in_quiet) and self._scheduler_paused and hasattr(self, "worker"):
                try:
                    self.worker.resume()
                    self._scheduler_paused = False
                    self.append_log("Scheduler: resumed after quiet hours.")
                except Exception:
                    pass
        except Exception:
            pass

    def _check_clipboard(self):
        try:
            cb = QApplication.clipboard().text() or ""
            cb = cb.strip()
            if (
                cb
                and cb != self._clip_last
                and (
                    cb.startswith("http://")
                    or cb.startswith("https://")
                    or cb.startswith("magnet:")
                )
            ):
                self._clip_last = cb
                reply = QMessageBox.question(
                    self,
                    "Add Link",
                    f"Add copied link to inputs?\n{cb}",
                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                )
                if reply == QMessageBox.StandardButton.Yes:
                    if self.bulk_mode_cb.isChecked():
                        cur = self.bulk_edit.toPlainText().strip()
                        self.bulk_edit.setPlainText((cur + "\n" if cur else "") + cb)
                    else:
                        self.link_edit.setText(cb)
        except Exception:
            pass

    def _post_process_completed(self):
        cfg = load_config()
        if not cfg.get("auto_extract_zip"):
            pass
        import hashlib
        import zipfile

        outdir = self.outdir_edit.text().strip()
        # dedup index
        hash_index = cfg.get("hash_index") or {}
        changed = False
        for row in range(self.preview_table.rowCount()):
            status_item = self.preview_table.item(row, 8)
            name_item = self.preview_table.item(row, 1)
            if not status_item or not name_item:
                continue
            if status_item.text().lower() != "completed":
                continue
            name = name_item.text()
            fpath = os.path.join(outdir, name)
            # extract zip
            if cfg.get("auto_extract_zip") and name.lower().endswith(".zip"):
                try:
                    with zipfile.ZipFile(fpath, "r") as zf:
                        zf.extractall(outdir)
                    self.append_log(f"Extracted: {name}")
                except Exception as e:
                    self.append_log(f"Extract failed for {name}: {e}")
            # compute hash for dedup and optional encryption/rename
            try:
                h = hashlib.sha256()
                with open(fpath, "rb") as f:
                    for chunk in iter(lambda: f.read(1024 * 1024), b""):
                        h.update(chunk)
                digest = h.hexdigest()
            except Exception as e:
                self.append_log(f"Hash failed for {name}: {e}")
                digest = None
            # dedup
            if cfg.get("dedup_on_complete") and digest:
                if digest in hash_index and os.path.exists(hash_index[digest]):
                    dup_dir = os.path.join(outdir, "Duplicates")
                    try:
                        os.makedirs(dup_dir, exist_ok=True)
                        newp = os.path.join(dup_dir, name)
                        os.replace(fpath, newp)
                        self.append_log(f"Duplicate moved: {name}")
                    except Exception as e:
                        self.append_log(f"Move duplicate failed: {e}")
                else:
                    hash_index[digest] = fpath
                    changed = True
            # audio metadata rename
            if cfg.get("auto_rename_media"):
                try:
                    from mutagen import File as MFile

                    mf = MFile(fpath, easy=True)
                    if mf and mf.tags:
                        artist = "; ".join(mf.tags.get("artist", []) or [])
                        title = "; ".join(mf.tags.get("title", []) or [])
                        if title:
                            base, ext = os.path.splitext(name)
                            newname = f"{artist + ' - ' if artist else ''}{title}{ext}".strip()
                            newname = newname.replace("/", "_")
                            if newname and newname != name:
                                newpath = os.path.join(outdir, newname)
                                if not os.path.exists(newpath):
                                    os.rename(fpath, newpath)
                                    self.append_log(f"Renamed: {name} -> {newname}")
                                    fpath = newpath
                except Exception:
                    pass
            # encryption
            if cfg.get("encrypt_completed") and cfg.get("vault_password"):
                try:
                    import base64
                    import hashlib

                    from cryptography.fernet import Fernet

                    key = hashlib.sha256(cfg.get("vault_password").encode("utf-8")).digest()
                    fkey = base64.urlsafe_b64encode(key)
                    fernet = Fernet(fkey)
                    with open(fpath, "rb") as f:
                        data = f.read()
                    enc = fernet.encrypt(data)
                    enc_path = fpath + ".enc"
                    with open(enc_path, "wb") as f:
                        f.write(enc)
                    os.remove(fpath)
                    self.append_log(f"Encrypted: {os.path.basename(enc_path)}")
                except Exception as e:
                    self.append_log(f"Encrypt failed for {name}: {e}")
        if changed:
            cfg["hash_index"] = hash_index
            save_config(cfg)

    def human_size(self, num: int) -> str:
        step = 1024.0
        units = ["B", "KiB", "MiB", "GiB", "TiB"]
        n = float(num)
        for u in units:
            if n < step:
                return f"{n:.1f} {u}" if u != "B" else f"{int(n)} {u}"
            n /= step
        return f"{n:.1f} PiB"

    def guess_name_from_link(self, link: str) -> str:
        return utools.guess_name_from_link(link)

    def toggle_token_visibility(self, state):
        self.token_edit.setEchoMode(
            QLineEdit.EchoMode.Normal
            if self.show_token_cb.isChecked()
            else QLineEdit.EchoMode.Password
        )

    def choose_dir(self):
        d = QFileDialog.getExistingDirectory(
            self, "Choose download directory", self.outdir_edit.text()
        )
        if d:
            self.outdir_edit.setText(d)

    def append_log(self, msg: str):
        self.log_box.appendPlainText(msg)
        try:
            logging.getLogger("acl").info(msg)
        except Exception:
            pass

    def on_clear_log(self):
        try:
            self.log_box.clear()
            # Also truncate the file log to keep things tidy
            from config import CONF_DIR

            log_dir = CONF_DIR / "logs"
            log_file = log_dir / "app.log"
            if log_file.exists():
                with open(log_file, "w"):
                    pass
            self.append_log("Log cleared.")
        except Exception:
            # If anything goes wrong, at least clear the view
            try:
                self.log_box.clear()
            except Exception:
                pass

    def on_bulk_mode_changed(self, state):
        is_bulk = self.bulk_mode_cb.isChecked()
        self.link_label.setVisible(not is_bulk)
        self.link_edit.setVisible(not is_bulk)
        self.bulk_label.setVisible(is_bulk)
        self.bulk_edit.setVisible(is_bulk)
        self.preview_btn.setVisible(True)
        # Preview table visibility is driven by whether it has rows, not bulk mode
        self.concurrent_label.setVisible(is_bulk)
        self.concurrent_spin.setVisible(is_bulk)
        self.select_all_btn.setVisible(is_bulk)
        self.clear_sel_btn.setVisible(is_bulk)
        self.total_label.setVisible(is_bulk)

    def _schedule_preview(self):
        # Auto-preview if there are links (direct downloads don't need token)
        has_links = bool(self._collect_links())
        if has_links:
            self._preview_timer.start(600)

    def on_help(self):
        dlg = HelpDialog(self)
        dlg.exec()

    def on_set_download_folder(self):
        d = QFileDialog.getExistingDirectory(
            self, "Choose default download directory", self.outdir_edit.text()
        )
        if d:
            self.outdir_edit.setText(d)
            self.save_settings()

    # Drag & drop
    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls() or event.mimeData().hasText():
            event.acceptProposedAction()
        else:
            super().dragEnterEvent(event)

    def dropEvent(self, event):
        urls = []
        if event.mimeData().hasUrls():
            for u in event.mimeData().urls():
                try:
                    urls.append(u.toString())
                except Exception:
                    pass
        elif event.mimeData().hasText():
            raw = event.mimeData().text()
            urls.extend([ln.strip() for ln in raw.splitlines() if ln.strip()])
        if urls:
            if self.bulk_mode_cb.isChecked():
                cur = self.bulk_edit.toPlainText().strip()
                joined = (cur + "\n" if cur else "") + "\n".join(urls)
                self.bulk_edit.setPlainText(joined)
            else:
                self.link_edit.setText(urls[0])
        event.acceptProposedAction()

    def open_network_settings(self):
        dlg = QDialog(self)
        dlg.setWindowTitle("Network Settings")
        v = QVBoxLayout(dlg)
        cfg = load_config()
        v.addWidget(QLabel("HTTP proxy (e.g., http://user:pass@host:port)"))
        http_edit = QLineEdit(cfg.get("http_proxy", ""))
        v.addWidget(http_edit)
        v.addWidget(QLabel("HTTPS proxy (e.g., http://user:pass@host:port)"))
        https_edit = QLineEdit(cfg.get("https_proxy", ""))
        v.addWidget(https_edit)
        v.addWidget(QLabel("Extra HTTP headers (one per line: Key: Value)"))
        headers_edit = QPlainTextEdit()
        hdrs = cfg.get("headers") or []
        if isinstance(hdrs, list):
            headers_edit.setPlainText("\n".join(hdrs))
        v.addWidget(headers_edit)
        btns = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        v.addWidget(btns)
        btns.accepted.connect(dlg.accept)
        btns.rejected.connect(dlg.reject)
        if dlg.exec() == QDialog.DialogCode.Accepted:
            cfg = load_config()
            cfg["http_proxy"] = http_edit.text().strip()
            cfg["https_proxy"] = https_edit.text().strip()
            lines = [ln.strip() for ln in headers_edit.toPlainText().splitlines() if ln.strip()]
            cfg["headers"] = lines
            save_config(cfg)
            self.append_log("Network settings saved. Restart downloads to apply.")

    def open_privacy_power(self):
        cfg = load_config()
        dlg = QDialog(self)
        dlg.setWindowTitle("Privacy & Power")
        v = QVBoxLayout(dlg)
        # Power-aware
        power_cb = QCheckBox("Enable power-aware throttling (battery mode)")
        power_cb.setChecked(bool(cfg.get("enable_power_aware")))
        v.addWidget(power_cb)
        rowp = QHBoxLayout()
        rowp.addWidget(QLabel("Battery limit (KiB/s):"))
        bat_limit = QLineEdit(str(cfg.get("battery_limit_kib", 5120)))
        bat_limit.setMaximumWidth(100)
        rowp.addWidget(bat_limit)
        rowp.addSpacing(8)
        rowp.addWidget(QLabel("Battery concurrent:"))
        bat_conc = QLineEdit(str(cfg.get("battery_concurrent", 2)))
        bat_conc.setMaximumWidth(60)
        rowp.addWidget(bat_conc)
        rowp.addSpacing(12)
        rowp.addWidget(QLabel("AC concurrent:"))
        ac_conc = QLineEdit(str(cfg.get("ac_concurrent", max(1, self.concurrent_spin.value()))))
        ac_conc.setMaximumWidth(60)
        rowp.addWidget(ac_conc)
        v.addLayout(rowp)
        # Privacy
        ua_cb = QCheckBox("Rotate User-Agent for direct downloads")
        ua_cb.setChecked(bool(cfg.get("rotate_user_agent")))
        v.addWidget(ua_cb)
        v.addWidget(QLabel("User-Agents (one per line):"))
        ua_edit = QPlainTextEdit()
        uas = cfg.get("user_agents") or []
        if isinstance(uas, list):
            ua_edit.setPlainText("\n".join(uas))
        v.addWidget(ua_edit)
        # Auto-tuning
        tune_cb = QCheckBox("Enable smart auto-tuning (per-task connections)")
        tune_cb.setChecked(bool(cfg.get("enable_auto_tune")))
        v.addWidget(tune_cb)
        rowt = QHBoxLayout()
        rowt.addWidget(QLabel("Min speed to scale up (KiB/s):"))
        t_min = QLineEdit(str(cfg.get("tune_min_kib", 64)))
        t_min.setMaximumWidth(80)
        rowt.addWidget(t_min)
        rowt.addSpacing(8)
        rowt.addWidget(QLabel("Max conn/server:"))
        t_max = QLineEdit(str(cfg.get("tune_max_conn", 16)))
        t_max.setMaximumWidth(60)
        rowt.addWidget(t_max)
        rowt.addSpacing(8)
        rowt.addWidget(QLabel("Interval (sec):"))
        t_int = QLineEdit(str(cfg.get("tune_interval_sec", 20)))
        t_int.setMaximumWidth(60)
        rowt.addWidget(t_int)
        v.addLayout(rowt)
        btns = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel, dlg
        )
        v.addWidget(btns)
        btns.accepted.connect(dlg.accept)
        btns.rejected.connect(dlg.reject)
        if dlg.exec() == QDialog.DialogCode.Accepted:
            cfg["enable_power_aware"] = bool(power_cb.isChecked())
            try:
                cfg["battery_limit_kib"] = int(bat_limit.text().strip() or "0")
                cfg["battery_concurrent"] = int(bat_conc.text().strip() or "2")
                cfg["ac_concurrent"] = int(
                    ac_conc.text().strip() or str(self.concurrent_spin.value())
                )
            except Exception:
                pass
            cfg["rotate_user_agent"] = bool(ua_cb.isChecked())
            lines = [ln.strip() for ln in ua_edit.toPlainText().splitlines() if ln.strip()]
            cfg["user_agents"] = lines
            cfg["enable_auto_tune"] = bool(tune_cb.isChecked())
            try:
                cfg["tune_min_kib"] = int(t_min.text().strip() or "64")
                cfg["tune_max_conn"] = int(t_max.text().strip() or "16")
                cfg["tune_interval_sec"] = int(t_int.text().strip() or "20")
            except Exception:
                pass
            save_config(cfg)
            self.append_log("Privacy & Power settings saved.")

    def on_preview(self):
        token = self.token_edit.text().strip()
        links = self._collect_links()
        if not links:
            QMessageBox.warning(self, "No links", "Provide at least one link to preview.")
            return

        # Check if we need a token for any RD links
        needs_token = any(
            link
            for link in links
            if not (link.startswith("http://") or link.startswith("https://"))
        )
        if needs_token and not token:
            self.open_token_dialog()
            token = self.token_edit.text().strip()
            if not token:
                QMessageBox.warning(self, "Token", "API token required for Real-Debrid links.")
                return

        self.preview_btn.setEnabled(False)
        self.append_log("Fetching file info…")
        self.preview_worker = PreviewWorker(token, links)
        self.preview_worker.log.connect(self.append_log)
        self.preview_worker.result.connect(self.populate_preview)
        self.preview_worker.start()

    def on_add_torrent(self):
        token = self.token_edit.text().strip()
        if not token:
            self.open_token_dialog()
            token = self.token_edit.text().strip()
            if not token:
                QMessageBox.warning(self, "Token", "Real-Debrid API token required for torrents.")
                return
        path, _ = QFileDialog.getOpenFileName(
            self, "Select .torrent file", str(Path.home()), "Torrent Files (*.torrent)"
        )
        if not path:
            return
        self.append_log(f"Adding torrent: {path}")
        self.preview_btn.setEnabled(False)
        self.torrent_worker = TorrentPreviewWorker(token, torrent_path=path)
        self.torrent_worker.log.connect(self.append_log)
        self.torrent_worker.result.connect(self.populate_preview)
        self.torrent_worker.start()

    def on_add_magnet(self):
        token = self.token_edit.text().strip()
        if not token:
            self.open_token_dialog()
            token = self.token_edit.text().strip()
            if not token:
                QMessageBox.warning(self, "Token", "Real-Debrid API token required for magnets.")
                return
        magnet, ok = QInputDialog.getText(self, "Add Magnet", "Paste magnet URI:")
        if not ok or not magnet.strip():
            return
        self.append_log("Adding magnet…")
        self.preview_btn.setEnabled(False)
        self.torrent_worker = TorrentPreviewWorker(token, magnet=magnet.strip())
        self.torrent_worker.log.connect(self.append_log)
        self.torrent_worker.result.connect(self.populate_preview)
        self.torrent_worker.start()

    def on_add_page(self):
        from bs4 import BeautifulSoup

        url, ok = QInputDialog.getText(self, "Add Page", "Enter page URL:")
        if not ok or not url.strip():
            return
        try:
            import requests

            resp = requests.get(url.strip(), timeout=15)
            resp.raise_for_status()
            soup = BeautifulSoup(resp.text, "html.parser")
            links = []
            exts = {
                ".jpg",
                ".jpeg",
                ".png",
                ".gif",
                ".webp",
                ".mp4",
                ".webm",
                ".mp3",
                ".flac",
                ".zip",
                ".pdf",
            }
            for a in soup.find_all("a", href=True):
                href = a["href"]
                if any(href.lower().endswith(e) for e in exts):
                    links.append(href)
            if not links:
                QMessageBox.information(self, "Add Page", "No asset links found.")
                return
            self.bulk_mode_cb.setChecked(True)
            cur = self.bulk_edit.toPlainText().strip()
            self.bulk_edit.setPlainText((cur + "\n" if cur else "") + "\n".join(links))
            self.append_log(f"Added {len(links)} link(s) from page.")
        except Exception as e:
            QMessageBox.warning(self, "Add Page", f"Failed: {e}")

    def on_import_links(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "Import Links", str(Path.home()), "Text Files (*.txt);;All Files (*.*)"
        )
        if not path:
            return
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                lines = [ln.strip() for ln in f.readlines() if ln.strip()]
            self.bulk_mode_cb.setChecked(True)
            self.bulk_edit.setPlainText("\n".join(lines))
            self.append_log(f"Imported {len(lines)} link(s).")
        except Exception as e:
            QMessageBox.warning(self, "Import", f"Failed to import: {e}")

    def on_export_links(self):
        links = self._collect_links()
        if self.preview_table.isVisible() and self.preview_table.rowCount() > 0:
            # Prefer selected in preview
            sel = []
            for row in range(self.preview_table.rowCount()):
                cb = self.preview_table.cellWidget(row, 0)
                if isinstance(cb, QCheckBox) and cb.isChecked():
                    item = self.preview_table.item(row, 1)
                    link = item.data(int(Qt.ItemDataRole.UserRole)) if item else None
                    if link:
                        sel.append(link)
            if sel:
                links = sel
        if not links:
            QMessageBox.information(self, "Export", "No links to export.")
            return
        path, _ = QFileDialog.getSaveFileName(
            self, "Export Links", str(Path.home() / "links.txt"), "Text Files (*.txt)"
        )
        if not path:
            return
        try:
            with open(path, "w", encoding="utf-8") as f:
                for ln in links:
                    f.write(ln + "\n")
            self.append_log(f"Exported {len(links)} link(s) to {path}.")
        except Exception as e:
            QMessageBox.warning(self, "Export", f"Failed to export: {e}")

    def on_add_ytdlp(self):
        # Optional helper that requires yt_dlp; best-effort prompt
        try:
            import yt_dlp  # type: ignore
        except Exception:
            QMessageBox.information(
                self, "yt-dlp", "yt-dlp is not installed. Install it to enable this feature."
            )
            return
        url, ok = QInputDialog.getText(self, "Add via yt-dlp", "Paste page URL:")
        if not ok or not url.strip():
            return
        self.append_log("Resolving media URL via yt-dlp…")
        try:
            ydl_opts = {"quiet": True, "skip_download": True, "no_warnings": True}
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url.strip(), download=False)
                direct = info.get("url") or info.get("entries", [{}])[0].get("url")
                if direct:
                    if self.bulk_mode_cb.isChecked():
                        cur = self.bulk_edit.toPlainText().strip()
                        self.bulk_edit.setPlainText((cur + "\n" if cur else "") + direct)
                    else:
                        self.link_edit.setText(direct)
                    self.append_log("yt-dlp: added direct media URL to links.")
                else:
                    QMessageBox.warning(self, "yt-dlp", "Failed to resolve a direct media URL.")
        except Exception as e:
            QMessageBox.warning(self, "yt-dlp", f"yt-dlp error: {e}")

    def populate_preview(self, items: list):
        self.preview_btn.setEnabled(True)
        if not items:
            QMessageBox.warning(self, "Preview", "No info available for the provided links.")
            return
        self.preview_table.setRowCount(0)
        self.preview_table.setVisible(True)
        cfg = load_config()
        exclude_ext = set(
            [e.lower().lstrip(".") for e in (cfg.get("exclude_ext") or []) if isinstance(e, str)]
        )
        for it in items:
            row = self.preview_table.rowCount()
            self.preview_table.insertRow(row)
            cb = QCheckBox()
            cb.setChecked(bool(it.get("ok")))
            cb.stateChanged.connect(lambda *_: self.update_selected_total())
            self.preview_table.setCellWidget(row, 0, cb)
            # Name
            link = it.get("link") or it.get("url") or it.get("final_url") or ""
            name = it.get("filename") or it.get("name") or self.guess_name_from_link(link)
            name_item = QTableWidgetItem(name)
            name_item.setData(int(Qt.ItemDataRole.UserRole), link)
            # Size
            try:
                size_val = int(it.get("filesize") or it.get("size") or 0)
            except Exception:
                size_val = 0
            # Store raw size on the name item for totals
            name_item.setData(int(Qt.ItemDataRole.UserRole) + 1, size_val)
            self.preview_table.setItem(row, 1, name_item)
            self.preview_table.setItem(row, 2, QTableWidgetItem(fmt.human_size(size_val)))
            # Type
            ext_l = cat.ext_from_name(name)
            type_item = QTableWidgetItem(ext_l)
            # Store category and excluded flags in data roles
            category = cat.categorize_extension(ext_l, load_config())
            type_item.setData(int(Qt.ItemDataRole.UserRole), category)
            excluded = ext_l in exclude_ext
            type_item.setData(int(Qt.ItemDataRole.UserRole) + 1, bool(excluded))
            self.preview_table.setItem(row, 3, type_item)
            # Source/Host
            source = it.get("host") or ""
            if not source:
                url_type = it.get("type", "unknown")
                if url_type == "direct":
                    try:
                        from urllib.parse import urlparse as _u

                        source = _u(it.get("final_url") or it.get("url") or "").netloc or "Direct"
                    except Exception:
                        source = "Direct"
                elif url_type == "realdebrid":
                    try:
                        source = urlparse(it.get("link") or "").netloc
                    except Exception:
                        source = "Real-Debrid"
                else:
                    try:
                        source = urlparse(link or "").netloc
                    except Exception:
                        source = "Unknown"
            self.preview_table.setItem(row, 4, QTableWidgetItem(source or "Unknown"))
            # Progress, Speed and ETA placeholders
            prog_item = QTableWidgetItem("0%")
            prog_item.setData(int(Qt.ItemDataRole.UserRole), 0)
            spd_item = QTableWidgetItem("0 B/s")
            spd_item.setData(int(Qt.ItemDataRole.UserRole), 0)
            eta_item = QTableWidgetItem("-")
            eta_item.setData(int(Qt.ItemDataRole.UserRole), 0)
            self.preview_table.setItem(row, 5, prog_item)
            self.preview_table.setItem(row, 6, spd_item)
            self.preview_table.setItem(row, 7, eta_item)
            status_item = QTableWidgetItem("Queued")
            status_item.setData(int(Qt.ItemDataRole.UserRole), 0)
            if excluded:
                cb.setChecked(False)
                status_item.setText("Excluded")
            self.preview_table.setItem(row, 8, status_item)
        self.update_selected_total()
        self.apply_filter()
        # Auto-start RD caching after add (optional setting)
        try:
            cfg = load_config()
            if cfg.get("auto_start_rd_on_add", True):
                self._maybe_autostart_rd(items)
        except Exception:
            pass

    def _maybe_autostart_rd(self, items: list):
        # Build specs from checked rd-torrent rows
        specs: list[str] = []
        for row in range(self.preview_table.rowCount()):
            cb = self.preview_table.cellWidget(row, 0)
            if isinstance(cb, QCheckBox) and cb.isChecked():
                item = self.preview_table.item(row, 1)
                link = item.data(int(Qt.ItemDataRole.UserRole)) if item else None
                if isinstance(link, str) and link.startswith("rd-torrent:"):
                    specs.append(link)
        if not specs:
            return
        token = self.token_edit.text().strip()
        if not token:
            return
        self.append_log("Auto-start: requesting RD to prepare selected torrent files…")
        self.rd_start_worker = RDTorrentStartWorker(token, specs)
        self.rd_start_worker.log.connect(self.append_log)
        self.rd_start_worker.open_url.connect(self._open_url)
        self.rd_start_worker.result.connect(self._on_rd_autostart_links)
        self.rd_start_worker.start()

    def _on_rd_autostart_links(self, links: list[str]):
        if not links:
            self.append_log(
                "Auto-start: RD hasn't produced direct links yet. Will not start downloads."
            )
            return
        # Start download automatically if no active worker
        if (
            hasattr(self, "worker")
            and isinstance(self.worker, DownloadWorker)
            and self.worker.isRunning()
        ):
            self.append_log("A download is already running; skipping auto-start downloads.")
            return
        # Use current UI settings
        outdir = self.outdir_edit.text().strip()
        try:
            conns = int(self.conn_edit.text())
            splits = int(self.splt_edit.text())
        except Exception:
            conns = 16
            splits = 16
        concurrent = int(self.concurrent_spin.value()) if self.bulk_mode_cb.isChecked() else 1
        token = self.token_edit.text().strip()
        self.append_log(f"Auto-start: starting download for {len(links)} file(s).")
        self.worker = DownloadWorker(token, links, outdir, conns, splits, concurrent)
        self.worker.log.connect(self.append_log)
        self.worker.done.connect(self.finish_download)
        self.progress.setValue(0)
        self.btn_pause.setEnabled(True)
        self.btn_cancel.setEnabled(True)
        self.btn_download.setEnabled(False)
        self.worker.progress.connect(self.on_overall_progress)
        self.worker.state.connect(self.on_worker_state)
        self.worker.pid_ready.connect(lambda pid: self.append_log(f"aria2c PID: {pid}"))
        self.worker.file_update.connect(self.on_file_update)
        self.worker.eta_update.connect(self.on_eta_update)
        self.worker.counts_update.connect(self.on_counts_update)
        self.worker.start()

    def _open_url(self, url: str):
        try:
            webbrowser.open(url)
            self.append_log("Opened Real‑Debrid in browser for confirmation…")
        except Exception:
            pass

    def _find_row_by_link(self, link: str) -> int:
        for row in range(self.preview_table.rowCount()):
            item = self.preview_table.item(row, 1)
            if item and item.data(int(Qt.ItemDataRole.UserRole)) == link:
                return row
        return -1

    def _format_eta(self, secs: int) -> str:
        try:
            s = max(0, int(secs))
        except Exception:
            s = 0
        h, rem = divmod(s, 3600)
        m, s = divmod(rem, 60)
        if h:
            return f"{h:d}:{m:02d}:{s:02d}"
        return f"{m:d}:{s:02d}"

    def update_selected_total(self):
        # Recompute using hidden raw sizes
        total = 0
        for row in range(self.preview_table.rowCount()):
            cb = self.preview_table.cellWidget(row, 0)
            if isinstance(cb, QCheckBox) and cb.isChecked():
                item = self.preview_table.item(row, 1)
                raw_size = item.data(int(Qt.ItemDataRole.UserRole) + 1) if item else 0
                try:
                    total += int(raw_size or 0)
                except Exception:
                    pass
        self.total_label.setText(f"Selected: {self.human_size(total)}")

    def on_select_all(self):
        for row in range(self.preview_table.rowCount()):
            cb = self.preview_table.cellWidget(row, 0)
            if isinstance(cb, QCheckBox):
                cb.setChecked(True)
        self.update_selected_total()

    def on_clear_selection(self):
        for row in range(self.preview_table.rowCount()):
            cb = self.preview_table.cellWidget(row, 0)
            if isinstance(cb, QCheckBox):
                cb.setChecked(False)
        self.update_selected_total()

    def on_remove_selected(self):
        if self.preview_table.rowCount() == 0:
            return
        # Determine rows to remove: prefer actively selected rows; if none, use checked checkboxes
        rows = (
            sorted(
                {idx.row() for idx in self.preview_table.selectionModel().selectedRows()},
                reverse=True,
            )
            if self.preview_table.selectionModel()
            else []
        )
        if not rows:
            rows = []
            for r in range(self.preview_table.rowCount()):
                cb = self.preview_table.cellWidget(r, 0)
                if isinstance(cb, QCheckBox) and cb.isChecked():
                    rows.append(r)
            rows.sort(reverse=True)
        if not rows:
            QMessageBox.information(self, "Remove", "No rows selected to remove.")
            return
        sorting = self.preview_table.isSortingEnabled()
        if sorting:
            self.preview_table.setSortingEnabled(False)
        for r in rows:
            if 0 <= r < self.preview_table.rowCount():
                self.preview_table.removeRow(r)
        if sorting:
            self.preview_table.setSortingEnabled(True)
        self.update_selected_total()
        if self.preview_table.rowCount() == 0:
            self.preview_table.setVisible(False)

    def on_clear_all_preview(self):
        if self.preview_table.rowCount() == 0:
            return
        reply = QMessageBox.question(
            self,
            "Clear All",
            "Remove all rows from preview?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        self.preview_table.setRowCount(0)
        self.preview_table.setVisible(False)
        self.total_label.setText("Selected: 0 B")

    def on_pause_resume(self):
        if not hasattr(self, "worker") or not self.worker.isRunning():
            return
        if self.btn_pause.text() == "Pause":
            reply = QMessageBox.question(
                self,
                "Pause",
                "Pause all downloads?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            if reply == QMessageBox.StandardButton.Yes:
                self.worker.pause()
                self.btn_pause.setText("Resume")
        else:
            reply = QMessageBox.question(
                self,
                "Resume",
                "Resume all downloads?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            if reply == QMessageBox.StandardButton.Yes:
                self.worker.resume()
                self.btn_pause.setText("Pause")

    def on_cancel(self):
        if hasattr(self, "worker"):
            reply = QMessageBox.warning(
                self,
                "Cancel",
                "Cancel all downloads? Partial files remain and can resume later.",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            if reply == QMessageBox.StandardButton.Yes:
                # Immediately reflect cancel intent in UI
                self.append_log("Canceled, cleaning up…")
                self.btn_cancel.setEnabled(False)
                self.worker.cancel()

    def _collect_links(self):
        if self.bulk_mode_cb.isChecked():
            raw = self.bulk_edit.toPlainText()
            links = [ln.strip() for ln in raw.splitlines() if ln.strip()]
        else:
            s = self.link_edit.text().strip()
            links = [s] if s else []
        # dedupe preserve order
        seen = set()
        out = []
        for link in links:
            if link not in seen:
                out.append(link)
                seen.add(link)
        return out

    def start_download(self):
        token = self.token_edit.text().strip()
        links = self._collect_links()
        outdir = self.outdir_edit.text().strip()

        # Check if we need a token for any RD links
        needs_token = any(
            link
            for link in links
            if not (link.startswith("http://") or link.startswith("https://"))
        )
        if needs_token and not token:
            self.open_token_dialog()
            token = self.token_edit.text().strip()
            if not token:
                QMessageBox.warning(self, "Token", "API token required for Real-Debrid links.")
                return
        if self.save_token_cb.isChecked():
            self.save_settings(token=token)
        try:
            conns = int(self.conn_edit.text())
            splits = int(self.splt_edit.text())
        except ValueError:
            QMessageBox.warning(self, "Invalid input", "Connections and Splits must be integers.")
            return
        if not links:
            QMessageBox.warning(self, "Invalid input", "Please provide at least one link.")
            return

        # Respect preview selection if visible
        if self.preview_table.isVisible() and self.preview_table.rowCount() > 0:
            selected = []
            torrent_specs = []  # entries like rd-torrent:<tid>:<fid>
            for row in range(self.preview_table.rowCount()):
                cb = self.preview_table.cellWidget(row, 0)
                if isinstance(cb, QCheckBox) and cb.isChecked():
                    item = self.preview_table.item(row, 1)
                    link = item.data(int(Qt.ItemDataRole.UserRole)) if item else None
                    if link:
                        if isinstance(link, str) and link.startswith("rd-torrent:"):
                            torrent_specs.append(link)
                        else:
                            selected.append(link)
            if selected:
                links = selected

            # If torrents selected, prepare their direct links
            if torrent_specs:
                self.append_log("Preparing torrent links…")
                prep_links = self.prepare_torrent_links(torrent_specs)
                if not prep_links:
                    QMessageBox.warning(
                        self, "Torrent", "No ready links for selected torrent files yet."
                    )
                    return
                links = prep_links + links

        # Confirm start
        reply = QMessageBox.question(
            self,
            "Start Download",
            f"Start downloading {len(links)} file(s) to:\n{outdir}?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return

        concurrent = int(self.concurrent_spin.value()) if self.bulk_mode_cb.isChecked() else 1
        self.worker = DownloadWorker(token, links, outdir, conns, splits, concurrent)
        self.worker.log.connect(self.append_log)
        self.worker.done.connect(self.finish_download)
        self.progress.setValue(0)
        self.btn_pause.setEnabled(True)
        self.btn_cancel.setEnabled(True)
        self.btn_download.setEnabled(False)
        self.worker.progress.connect(self.on_overall_progress)
        self.worker.state.connect(self.on_worker_state)
        self.worker.pid_ready.connect(lambda pid: self.append_log(f"aria2c PID: {pid}"))
        self.worker.file_update.connect(self.on_file_update)
        self.worker.eta_update.connect(self.on_eta_update)
        self.worker.counts_update.connect(self.on_counts_update)
        self.worker.start()

    def prepare_torrent_links(self, specs: list[str]) -> list[str]:
        # specs: ['rd-torrent:<tid>:<fid>', ...]
        token = self.token_edit.text().strip()
        client = RealDebridClient(token)
        # group by torrent id
        by_tid: dict[str, list[str]] = {}
        for s in specs:
            parts = s.split(":", 2)
            if len(parts) == 3:
                _, tid, fid = parts
                by_tid.setdefault(tid, []).append(fid)
        out_links: list[str] = []
        for tid, fids in by_tid.items():
            # select files
            r = client.select_torrent_files(tid, fids)
            if not r.get("ok"):
                self.append_log(f"selectFiles failed for {tid}: {r.get('error')}")
                continue
            else:
                self.append_log(f"RD accepted selection for {tid}. Preparing cached links…")
            # poll info for links (extend wait to accommodate uncached torrents)
            ready_links: list[str] = []
            last_status = None
            last_progress = None
            attempts = 450  # up to ~15 minutes at 2s interval
            while attempts > 0:
                info = client.torrent_info(tid)
                if not info.get("ok"):
                    time.sleep(2)
                    attempts -= 1
                    continue
                links = info.get("links") or []
                if links:
                    ready_links.extend(
                        [ln for ln in links if isinstance(ln, str) and ln.startswith("http")]
                    )
                    break
                # log status/progress changes
                try:
                    status = info.get("status")
                    progress = info.get("progress")
                    if status and status != last_status:
                        self.append_log(f"Torrent {tid} status: {status}")
                        last_status = status
                    if isinstance(progress, (int, float)) and progress != last_progress:
                        self.append_log(f"Torrent {tid} progress: {int(progress)}%")
                        last_progress = progress
                except Exception:
                    pass
                time.sleep(2)
                attempts -= 1
            if not ready_links:
                self.append_log(
                    f"Torrent {tid}: no ready links yet. RD may still be preparing the files."
                )
                self.append_log("Tip: You can also start it from RD's Torrents tab.")
                self.append_log("Then retry once links are ready.")
            else:
                out_links.extend(ready_links)
        return out_links

    def finish_download(self, ok: bool, msg: str):
        self.append_log(msg)
        self.btn_download.setEnabled(True)
        self.btn_pause.setEnabled(False)
        self.btn_cancel.setEnabled(False)
        self.btn_pause.setText("Pause")
        if ok:
            QMessageBox.information(self, "Done", msg)
            # System notification (best-effort)
            try:
                if hasattr(self, "tray") and self.tray:
                    self.tray.showMessage(
                        "Downloads",
                        "All downloads complete.",
                        QSystemTrayIcon.MessageIcon.Information,
                        3000,
                    )
            except Exception:
                pass
            if self.open_on_done_cb.isChecked():
                self.open_folder(self.outdir_edit.text().strip())
            # Append to history from completed rows
            try:
                self._append_history_from_table()
            except Exception:
                pass
        else:
            QMessageBox.warning(self, "Failed", msg)
            try:
                if hasattr(self, "tray") and self.tray:
                    self.tray.showMessage(
                        "Downloads",
                        "One or more downloads failed.",
                        QSystemTrayIcon.MessageIcon.Warning,
                        3000,
                    )
            except Exception:
                pass

    def on_worker_state(self, s: str):
        if s == "paused":
            self.btn_pause.setText("Resume")
        elif s in ("resumed", "running"):
            self.btn_pause.setText("Pause")
        elif s == "canceled":
            self.btn_pause.setEnabled(False)
            self.btn_cancel.setEnabled(False)
            # Keep Download disabled until worker finishes and calls finish_download
            self.append_log("Cleanup complete or in progress after cancel.")

    def on_file_update(self, link: str, percent: int, speed: int, eta_sec: int, status: str):
        row = self._find_row_by_link(link)
        if row < 0:
            return
        prog_item = self.preview_table.item(row, 5)
        spd_item = self.preview_table.item(row, 6)
        eta_item = self.preview_table.item(row, 7)
        status_item = self.preview_table.item(row, 8)
        if not prog_item:
            prog_item = QTableWidgetItem()
            self.preview_table.setItem(row, 5, prog_item)
        if not spd_item:
            spd_item = QTableWidgetItem()
            self.preview_table.setItem(row, 6, spd_item)
        if not eta_item:
            eta_item = QTableWidgetItem()
            self.preview_table.setItem(row, 7, eta_item)
        if not status_item:
            status_item = QTableWidgetItem()
            self.preview_table.setItem(row, 8, status_item)
        # Temporarily disable sorting to avoid flicker while updating cells
        sorting = self.preview_table.isSortingEnabled()
        if sorting:
            self.preview_table.setSortingEnabled(False)
        prog_item.setText(f"{percent}%")
        prog_item.setData(int(Qt.ItemDataRole.UserRole), int(percent))
        spd_item.setText(self._format_speed(speed))
        spd_item.setData(int(Qt.ItemDataRole.UserRole), int(speed))
        if int(eta_sec) < 0:
            eta_item.setText("–")
        else:
            eta_item.setText(fmt.format_eta(eta_sec) if percent < 100 else "Done")
        eta_item.setData(int(Qt.ItemDataRole.UserRole), int(eta_sec))
        # Status text, humanized
        status_map = {
            "active": "Active",
            "waiting": "Queued",
            "paused": "Paused",
            "complete": "Completed",
            "error": "Error",
            "removed": "Removed",
            "stopped": "Stopped",
        }
        status_item.setText(status_map.get(status, status.title()))
        # Per-file updates only; global percent driven by overall progress
        if sorting:
            self.preview_table.setSortingEnabled(True)
        # Avoid changing background colors to prevent flicker

    def on_eta_update(self, eta_sec: int):
        self.eta_global_label.setText(f"Time remaining: {fmt.format_eta(eta_sec)}")

    def on_overall_progress(self, v: int):
        # Drive the global progress bar and label using overall percent
        v = max(0, min(100, int(v)))
        self.progress.setValue(v)
        self.percent_global_label.setText(f"{v}%")

    def on_counts_update(self, active: int, queued: int):
        try:
            a = max(0, int(active))
        except Exception:
            a = 0
        try:
            q = max(0, int(queued))
        except Exception:
            q = 0
        self.queue_counts_label.setText(f"Active {a} | Queued {q}")

    def _format_speed(self, bps: int) -> str:
        return fmt.format_speed(bps)

    def _ext_from_name(self, name: str) -> str:
        # kept for backward-compat; delegate to utils
        return cat.ext_from_name(name)

    def _default_category_exts(self) -> dict:
        return cat.default_category_exts()

    def _category_exts(self) -> dict:
        return cat.category_exts(load_config())

    def categorize_extension(self, ext: str) -> str:
        return cat.categorize_extension(ext, load_config())

    def apply_filter(self):
        want = self.filter_combo.currentText()
        for row in range(self.preview_table.rowCount()):
            type_item = self.preview_table.item(row, 3)
            cat = type_item.data(int(Qt.ItemDataRole.UserRole)) if type_item else None
            excluded = (
                bool(type_item.data(int(Qt.ItemDataRole.UserRole) + 1)) if type_item else False
            )
            show = True
            if want == "Excluded":
                show = excluded
            elif want != "All":
                show = cat == want
            self.preview_table.setRowHidden(row, not show)

    def open_filetypes_settings(self):
        cfg = load_config()
        dlg = QDialog(self)
        dlg.setWindowTitle("File Types & Rules")
        v = QVBoxLayout(dlg)
        tabs = QTabWidget(dlg)
        v.addWidget(tabs)

        # Tab: Rules (excluded + category extension lists)
        rules = QWidget()
        vr = QVBoxLayout(rules)
        auto_cb = QCheckBox("Automatically categorize into subfolders (Video, Audio, etc.)")
        auto_cb.setChecked(bool(cfg.get("auto_categorize", True)))
        vr.addWidget(auto_cb)
        vr.addWidget(QLabel("Excluded extensions (one per line, without dot):"))
        ex_edit = QPlainTextEdit()
        ex = cfg.get("exclude_ext") or []
        if isinstance(ex, list):
            ex_edit.setPlainText("\n".join(sorted([str(x) for x in ex])))
        vr.addWidget(ex_edit)
        vr.addWidget(QLabel("Category extensions (comma-separated per line):"))
        # Build editors per category
        cat_map = self._category_exts()
        cat_edits = {}
        for cat_name in [
            "Video",
            "Audio",
            "Image",
            "Document",
            "Compressed",
            "Program",
            "Other",
        ]:
            hl = QHBoxLayout()
            hl.addWidget(QLabel(f"{cat_name}:"))
            le = QLineEdit(", ".join(cat_map.get(cat_name, [])))
            hl.addWidget(le)
            cat_edits[cat_name] = le
            vr.addLayout(hl)
        # Reset button
        reset_btn = QPushButton("Reset to defaults")
        vr.addWidget(reset_btn)

        def on_reset():
            defaults = self._default_category_exts()
            for cat_key, le in cat_edits.items():
                le.setText(", ".join(defaults.get(cat_key, [])))
            ex_edit.clear()

        reset_btn.clicked.connect(on_reset)
        tabs.addTab(rules, "Rules")

        # Tab: Folders (custom subfolder names per category)
        folders = QWidget()
        vf = QVBoxLayout(folders)
        vf.addWidget(QLabel("Subfolder name per category:"))
        folder_map = cfg.get("category_folders") or {}
        folder_edits = {}
        defaults_folders = {
            "Video": "Video",
            "Audio": "Audio",
            "Image": "Images",
            "Document": "Documents",
            "Compressed": "Compressed",
            "Program": "Programs",
            "Other": "Other",
        }
        for cat_name in [
            "Video",
            "Audio",
            "Image",
            "Document",
            "Compressed",
            "Program",
            "Other",
        ]:
            hl = QHBoxLayout()
            hl.addWidget(QLabel(f"{cat_name}:"))
            le = QLineEdit(str(folder_map.get(cat_name, defaults_folders.get(cat_name, cat_name))))
            hl.addWidget(le)
            folder_edits[cat_name] = le
            vf.addLayout(hl)
        tabs.addTab(folders, "Folders")

        btns = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel, dlg
        )
        v.addWidget(btns)
        btns.accepted.connect(dlg.accept)
        btns.rejected.connect(dlg.reject)
        if dlg.exec() == QDialog.DialogCode.Accepted:
            cfg = load_config()
            cfg["auto_categorize"] = bool(auto_cb.isChecked())
            # Save excluded
            lines = [
                ln.strip().lstrip(".").lower()
                for ln in ex_edit.toPlainText().splitlines()
                if ln.strip()
            ]
            seen = set()
            ex_list = []
            for ln in lines:
                if ln not in seen:
                    ex_list.append(ln)
                    seen.add(ln)
            cfg["exclude_ext"] = ex_list
            # Save category maps
            new_map = {}
            for cat_key, le in cat_edits.items():
                exts = [p.strip().lstrip(".").lower() for p in le.text().split(",") if p.strip()]
                new_map[cat_key] = sorted(set(exts))
            cfg["category_exts"] = new_map
            # Save folder names
            new_folders = {}
            for cat_key, le in folder_edits.items():
                new_folders[cat_key] = le.text().strip() or defaults_folders.get(cat_key, cat_key)
            cfg["category_folders"] = new_folders
            save_config(cfg)
            self.append_log("File type rules updated.")

    def closeEvent(self, event):
        token = self.token_edit.text().strip() if self.save_token_cb.isChecked() else None
        self.save_settings(token=token)
        super().closeEvent(event)

    def save_settings(self, token: str | None = None):
        cfg = load_config()
        if token is not None:
            cfg["token"] = token
        cfg["outdir"] = self.outdir_edit.text().strip()
        cfg["connections"] = int(self.conn_edit.text() or 16)
        cfg["splits"] = int(self.splt_edit.text() or 16)
        cfg["concurrency"] = int(self.concurrent_spin.value())
        cfg["dark_mode"] = bool(self.dark_mode_cb.isChecked())
        cfg["open_on_done"] = bool(self.open_on_done_cb.isChecked())
        try:
            cfg["auto_start_rd_on_add"] = bool(self.autostart_act.isChecked())
        except Exception:
            pass
        # Persist table layout and sort
        try:
            header = self.preview_table.horizontalHeader()
            state: QByteArray = header.saveState()
            cfg["table_header_state"] = bytes(state.toBase64()).decode("ascii")
            cfg["table_sort_col"] = int(header.sortIndicatorSection())
            cfg["table_sort_order"] = int(header.sortIndicatorOrder())
        except Exception:
            pass
        save_config(cfg)

    def on_dark_mode_changed(self):
        self.apply_theme()
        self.save_settings()
        if hasattr(self, "dark_act"):
            self.dark_act.setChecked(self.dark_mode_cb.isChecked())

    def on_toggle_autostart(self, checked: bool):
        try:
            cfg = load_config()
            cfg["auto_start_rd_on_add"] = bool(checked)
            save_config(cfg)
            self.append_log(f"Auto-start RD after add: {'On' if checked else 'Off'}")
        except Exception:
            pass

    def apply_theme(self):
        from PyQt6.QtGui import QPalette

        app = QApplication.instance()
        if not app:
            return
        # Reset style and palette each toggle to ensure live refresh
        app.setStyle("Fusion")
        if self.dark_mode_cb.isChecked():
            palette = QPalette()
            palette.setColor(QPalette.ColorRole.Window, QColor(53, 53, 53))
            palette.setColor(QPalette.ColorRole.WindowText, Qt.GlobalColor.white)
            palette.setColor(QPalette.ColorRole.Base, QColor(35, 35, 35))
            palette.setColor(QPalette.ColorRole.AlternateBase, QColor(53, 53, 53))
            palette.setColor(QPalette.ColorRole.ToolTipBase, Qt.GlobalColor.white)
            palette.setColor(QPalette.ColorRole.ToolTipText, Qt.GlobalColor.white)
            palette.setColor(QPalette.ColorRole.Text, Qt.GlobalColor.white)
            palette.setColor(QPalette.ColorRole.Button, QColor(53, 53, 53))
            palette.setColor(QPalette.ColorRole.ButtonText, Qt.GlobalColor.white)
            palette.setColor(QPalette.ColorRole.BrightText, Qt.GlobalColor.red)
            palette.setColor(QPalette.ColorRole.Highlight, QColor(142, 45, 197).lighter())
            palette.setColor(QPalette.ColorRole.HighlightedText, Qt.GlobalColor.black)
            app.setPalette(palette)
        else:
            app.setPalette(app.style().standardPalette())
        try:
            # Repolish widgets to apply changes immediately
            for w in app.allWidgets():
                s = w.style()
                s.unpolish(w)
                s.polish(w)
                w.update()
        except Exception:
            pass

    def open_folder(self, path: str):
        if not path:
            return
        try:
            if sys.platform.startswith("win"):
                os.startfile(path)  # type: ignore[attr-defined]
            elif sys.platform == "darwin":
                subprocess.Popen(["open", path])
            else:
                subprocess.Popen(["xdg-open", path])
        except Exception as e:
            self.append_log(f"Failed to open folder: {e}")

    def _append_history_from_table(self):
        # Store entries for rows with Status = Completed
        from datetime import datetime

        done = []
        for row in range(self.preview_table.rowCount()):
            status_item = self.preview_table.item(row, 8)
            if status_item and status_item.text().lower() == "completed":
                name_item = self.preview_table.item(row, 1)
                link = name_item.data(int(Qt.ItemDataRole.UserRole)) if name_item else ""
                name = name_item.text() if name_item else ""
                done.append(
                    {
                        "when": datetime.now().isoformat(timespec="seconds"),
                        "file": name,
                        "outdir": self.outdir_edit.text().strip(),
                        "link": link,
                    }
                )
        if not done:
            return
        cfg = load_config()
        hist = cfg.get("history") or []
        if not isinstance(hist, list):
            hist = []
        hist.extend(done)
        # keep last 500 entries
        hist = hist[-500:]
        cfg["history"] = hist
        save_config(cfg)

    def open_history(self):
        cfg = load_config()
        hist = cfg.get("history") or []
        dlg = QDialog(self)
        dlg.setWindowTitle("History")
        v = QVBoxLayout(dlg)
        box = QTextBrowser(dlg)
        box.setOpenExternalLinks(False)
        lines = []
        for it in hist:
            when = it.get("when")
            outdir = it.get("outdir")
            name = it.get("file")
            link = it.get("link")
            lines.append(f"{when}  —  {name}  —  {outdir}\n{link}")
        box.setPlainText("\n\n".join(lines))
        v.addWidget(box)
        btns = QDialogButtonBox(QDialogButtonBox.StandardButton.Close, dlg)
        btns.rejected.connect(dlg.reject)
        btns.accepted.connect(dlg.accept)
        v.addWidget(btns)

    def restore_table_layout(self):
        try:
            cfg = load_config()
            state_b64 = cfg.get("table_header_state")
            if state_b64:
                ba = QByteArray.fromBase64(state_b64.encode("ascii"))
                self.preview_table.horizontalHeader().restoreState(ba)
            col = int(cfg.get("table_sort_col", -1))
            if col >= 0:
                try:
                    order_val = int(cfg.get("table_sort_order", int(Qt.SortOrder.AscendingOrder)))
                    order = Qt.SortOrder(order_val)
                except Exception:
                    order = Qt.SortOrder.AscendingOrder
                self.preview_table.sortItems(col, order)
        except Exception:
            pass

    def on_table_context_menu(self, pos: QPoint):
        idx = self.preview_table.indexAt(pos)
        if not idx.isValid():
            return
        row = idx.row()
        link_item = self.preview_table.item(row, 1)
        link = link_item.data(int(Qt.ItemDataRole.UserRole)) if link_item else None
        if not link:
            return
        menu = QMenu(self)
        status_item = self.preview_table.item(row, 8)
        status_txt = (status_item.text() if status_item else "").lower()
        act_pause = menu.addAction("Pause")
        act_resume = menu.addAction("Resume")
        act_cancel = menu.addAction("Cancel")
        menu.addSeparator()
        act_open_file = menu.addAction("Open File")
        act_open_folder = menu.addAction("Open Containing Folder")
        menu.addSeparator()
        act_copy_url = menu.addAction("Copy URL")
        menu.addSeparator()
        act_remove_row = menu.addAction("Remove From Preview")
        act_pause.setEnabled("active" in status_txt)
        act_resume.setEnabled(
            "paused" in status_txt or "waiting" in status_txt or "queued" in status_txt
        )
        act_cancel.setEnabled(True)
        chosen = menu.exec(self.preview_table.viewport().mapToGlobal(pos))
        if not chosen:
            return
        if chosen == act_pause and hasattr(self, "worker"):
            try:
                self.worker.pause_item(link)
            except Exception as e:
                self.append_log(f"Pause failed: {e}")
        elif chosen == act_resume and hasattr(self, "worker"):
            try:
                self.worker.resume_item(link)
            except Exception as e:
                self.append_log(f"Resume failed: {e}")
        elif chosen == act_cancel and hasattr(self, "worker"):
            try:
                self.worker.cancel_item(link)
            except Exception as e:
                self.append_log(f"Cancel failed: {e}")
        elif chosen == act_open_file:
            name_item = self.preview_table.item(row, 1)
            fname = name_item.text() if name_item else None
            path = os.path.join(self.outdir_edit.text().strip(), fname or "")
            self.open_folder(path)
        elif chosen == act_open_folder:
            d = self.outdir_edit.text().strip()
            self.open_folder(d)
        elif chosen == act_copy_url:
            try:
                QApplication.clipboard().setText(str(link))
            except Exception:
                pass
        elif chosen == act_remove_row:
            self.preview_table.removeRow(row)
            self.update_selected_total()
            if self.preview_table.rowCount() == 0:
                self.preview_table.setVisible(False)


def main():
    app = QApplication(sys.argv)
    # Logger setup (rotating file in config dir)
    try:
        from config import CONF_DIR

        log_dir = CONF_DIR / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        fh = RotatingFileHandler(str(log_dir / "app.log"), maxBytes=512 * 1024, backupCount=3)
        fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
        fh.setFormatter(fmt)
        lg = logging.getLogger("acl")
        lg.setLevel(logging.INFO)
        lg.addHandler(fh)
    except Exception:
        pass
    # Resolve bundled aria2 if available and not configured
    try:
        cfg = load_config()
        aria_cfg = cfg.get("aria2_path")
        if not aria_cfg or not os.path.exists(aria_cfg):
            from utils.runtime import resolve_bundled_aria2

            found = resolve_bundled_aria2()
            if found:
                cfg["aria2_path"] = found
                save_config(cfg)
    except Exception:
        pass
    w = MainWindow()
    # System tray for notifications (only if available)
    try:
        if QSystemTrayIcon.isSystemTrayAvailable():
            icon = app.style().standardIcon(QStyle.StandardPixmap.SP_ComputerIcon)
            w.tray = QSystemTrayIcon(icon, w)
            w.tray.setToolTip(APP_NAME)
            w.tray.setVisible(True)
        else:
            w.tray = None
    except Exception:
        w.tray = None
    w.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
