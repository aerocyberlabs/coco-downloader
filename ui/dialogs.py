from PyQt6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QTabWidget,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)


class HelpDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Help")
        self.resize(680, 560)
        v = QVBoxLayout(self)
        tabs = QTabWidget(self)
        v.addWidget(tabs)

        def add_tab(title: str, html: str):
            w = QWidget()
            layout = QVBoxLayout(w)
            tb = QTextBrowser(w)
            tb.setOpenExternalLinks(True)
            tb.setHtml(html)
            layout.addWidget(tb)
            tabs.addTab(w, title)

        add_tab(
            "Overview",
            """
            <h3>ACL Downloader</h3>
            <p>
              Cross-platform GUI downloader powered by aria2 and optional Real‑Debrid
              integration.
            </p>
            <ul>
              <li>Direct HTTP/HTTPS downloads (no token needed)</li>
              <li>Real‑Debrid hosters, torrents, and magnets (API token required)</li>
              <li>Pause/Resume/Cancel, concurrent downloads, per-file progress</li>
            </ul>
        """,
        )

        add_tab(
            "Getting Started",
            """
            <h4>Direct Downloads</h4>
            <ol>
              <li>Paste direct HTTP/HTTPS URLs</li>
              <li>Click Preview, select items, choose a folder</li>
              <li>Click Download</li>
            </ol>
            <h4>Real‑Debrid</h4>
            <ol>
              <li>Get your API token: <a href='https://real-debrid.com/apitoken'>real-debrid.com/apitoken</a></li>
              <li>Set token in Settings → Set API Token</li>
              <li>Paste supported hoster links (or add torrent/magnet)</li>
              <li>Preview, then Download</li>
            </ol>
        """,
        )

        add_tab(
            "Controls",
            """
            <ul>
              <li><b>Pause/Resume</b> all downloads</li>
              <li><b>Cancel</b> stops and cleans up running tasks</li>
              <li><b>Right-click</b> a row for per-item Pause/Resume/Cancel/Open/Copy URL</li>
              <li><b>Active | Queued</b> counters show current queue status</li>
            </ul>
        """,
        )

        add_tab(
            "Settings",
            """
            <ul>
              <li><b>Connections (-x)</b>: max connections per download</li>
              <li><b>Splits (-s)</b>: segments per file</li>
              <li><b>Concurrency (-j)</b>: concurrent downloads</li>
              <li><b>Dark mode</b> and <b>Open folder when done</b></li>
              <li>Optional <b>aria2 path</b>: set in config if aria2 is not in PATH</li>
            </ul>
        """,
        )

        add_tab(
            "Troubleshooting",
            """
            <ul>
              <li>
                If aria2 is missing, install it or configure its path. The app checks
                availability on start.
              </li>
              <li>Some servers do not expose size immediately; ETA shows a dash until known.</li>
              <li>For Real‑Debrid errors, verify your token and host status on RD.</li>
            </ul>
        """,
        )

        btns = QDialogButtonBox(QDialogButtonBox.StandardButton.Close, self)
        btns.rejected.connect(self.reject)
        btns.accepted.connect(self.accept)
        v.addWidget(btns)
