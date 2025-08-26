# Coco Downloader

Cross-platform GUI download manager built with PyQt6, aria2, and optional Real‑Debrid integration. It supports direct HTTP(S) links, Real‑Debrid hosters, torrents/magnets via Real‑Debrid, bulk import, per-file progress, pause/resume/cancel, power-aware throttling, simple privacy settings, and packaging for Windows and macOS.

Note: This repository is maintained privately; releases will be published on a separate website. Issues/PRs are not expected from external contributors.

## Highlights
- Direct HTTP/HTTPS downloads (no token required)
- Real‑Debrid integration: hosters, torrents, magnets
- Auto-start RD flow: attempts to select files and start caching; detects when web confirmation is needed and opens RD
- Concurrent downloads, per-file progress, overall progress, ETA
- Power-aware throttling (battery/AC), optional UA rotation
- Optional encrypted vault, deduplication, and media auto-rename
- Drag-and-drop, history export/import, Help dialog
- Auto-detected bundled aria2 from `bin/` (if present)
- Windows installer (Inno Setup), macOS .pkg (Apple Silicon)

## Quick Start (Dev)
### Linux/macOS
```
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
python app.py
```

### Windows
```
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
python app.py
```

## Real‑Debrid Authentication
- Token mode: Settings → Set API Token… (stores in config or system keyring if enabled)
- OAuth mode (recommended): Settings → Sign in to Real‑Debrid…
  - Opens device flow; code is auto-copied and the device page can be launched directly.
  - The app saves `rd_access_token` and uses it automatically for all RD API calls.

## Torrent/Magnet Flow with Real‑Debrid
1) Add Torrent… or Add Magnet…
2) Preview loads file list. If “Auto-start RD after add” is enabled (default), the app:
   - Selects files (currently selects all) via RD API to start caching
   - Polls status/progress and waits for links to appear
   - Starts download automatically when links are ready
3) If RD requires manual confirmation (status remains `waiting_files_selection`), the app opens RD’s Torrents page to confirm. After confirmation, it retries selection and continues polling.

Known limitation: Some torrents may require manual confirmation in RD’s web UI. The app detects this and opens RD automatically, but cannot bypass that requirement.

## Packaging
The project includes PyInstaller spec and CI for Windows/macOS/Linux builds. We publish releases from CI artifacts.

### Windows (local)
- Prereqs: Python 3.11 x64, Inno Setup
- Optional: Put `aria2c.exe` under `bin\` to bundle.
```
pyinstaller -y downloader.spec
choco install innosetup -y
"$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe" .\installer.iss
```
Outputs:
- Portable: `dist\coco-downloader\coco-downloader.exe`
- Installer: `installer-output\coco-downloader-Setup-x64.exe`

### macOS (Apple Silicon, local)
- Prereqs: macOS 14+, Xcode CLT
- Optional: Put `aria2c` under `bin/` to bundle.
```
python -m pip install --upgrade pip
pip install -r requirements.txt pyinstaller
pyinstaller -y downloader.spec
APP_NAME="$(cat APP_NAME 2>/dev/null || echo 'Coco Downloader')"
APP_SLUG="$(cat APP_SLUG 2>/dev/null || echo 'coco-downloader')"
APP_PATH="dist/${APP_SLUG}/${APP_NAME}.app"
mkdir -p pkgroot/Applications && cp -R "$APP_PATH" pkgroot/Applications/
IDENTIFIER="$(cat BUNDLE_ID 2>/dev/null || echo com.acl.downloader)"
VERSION="$(cat VERSION 2>/dev/null || echo 0.1.0)"
pkgbuild --root pkgroot --identifier "$IDENTIFIER" --version "$VERSION" --install-location "/" component.pkg
productbuild --package component.pkg "${APP_SLUG}-mac-arm64.pkg"
```
Outputs:
- PKG: `coco-downloader-mac-arm64.pkg`

Codesigning/notarization steps are documented in `docs/packaging.md` and are handled in CI if secrets are provided.

## GitHub Actions
The workflow `.github/workflows/release.yml` builds artifacts on `windows-latest`, `macos-14` (arm64), and `ubuntu-latest`:
- Windows: portable zip + signed installer (if cert secrets provided)
- macOS: signed + notarized `.pkg` (if cert secrets provided)
- Linux: portable tar.gz
Artifacts are attached to the run and to tagged releases (`v*`).

### Required CI Secrets (optional but recommended)
- Windows code signing: `WINDOWS_CERT_PFX_BASE64`, `WINDOWS_CERT_PASSWORD`, `WINDOWS_TIMESTAMP_URL` (optional)
- macOS codesigning + notarization: `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `MACOS_SIGN_IDENTITY`, `MACOS_INSTALLER_IDENTITY`, `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`

## Configuration & Data
- Config is stored under `~/.config/coco-downloader` (migrated automatically from the old path on first run).
- Logs: `~/.config/coco-downloader/logs/app.log` (rotating)
- Optional: system keyring for API token (if available)

## Known Issues
- Real‑Debrid manual confirmation: Certain torrents require web confirmation and cannot be started purely via API; the app detects this and opens RD.
- Wayland/X11 warnings on Linux are harmless fallbacks and do not affect functionality.

## License
All rights reserved. Releases will be distributed separately; external contributions are not expected.

---

This README is intentionally detailed to support local builds and packaging without needing external documentation.

