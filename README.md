# Coco Downloader

A cross-platform desktop download manager built with Flutter. Supports direct HTTP/HTTPS downloads and Real-Debrid integration for premium hoster links, torrents, and magnet URIs.

## Features

- **Direct Downloads** -- paste any HTTP/HTTPS URL, no account needed
- **Real-Debrid Integration** -- unrestrict links from 100+ supported hosters
- **Torrent & Magnet Support** -- add `.torrent` files or magnet links via Real-Debrid
- **Bulk Downloads** -- paste multiple links, preview files, select what to download
- **Progress Tracking** -- per-file and global progress with speed and ETA
- **Pause / Resume / Cancel** -- full download control with aria2c session persistence
- **File Categorization** -- auto-organize downloads into Video, Audio, Image, etc.
- **Dark Mode** -- Material 3 theming with light and dark variants
- **Drag & Drop** -- drop URLs or `.torrent` files directly into the app
- **Clipboard Monitor** -- detects copied URLs and offers to add them
- **Download History** -- browse last 500 completed downloads
- **Quiet Hours** -- schedule download pauses during specified time windows
- **Power-Aware** -- throttle downloads on battery to save power
- **Post-Processing** -- auto-extract ZIP, SHA-256 deduplication, file encryption

## Screenshots

*Coming soon*

## Requirements

- **Flutter SDK** 3.x (tested with 3.32.1)
- **aria2c** -- the download engine (must be installed separately)

### Install aria2c

```bash
# Fedora / RHEL
sudo dnf install -y aria2

# Ubuntu / Debian
sudo apt install -y aria2

# macOS
brew install aria2

# Windows (via Chocolatey)
choco install aria2
```

## Getting Started

```bash
# Clone the repository
git clone https://github.com/aerocyberlabs/coco-downloader.git
cd coco-downloader

# Install Flutter dependencies
flutter pub get

# Run on your platform
flutter run -d linux
flutter run -d macos
flutter run -d windows
```

## Build for Release

```bash
flutter build linux
flutter build macos
flutter build windows
```

Release binaries are placed in `build/<platform>/`.

## Project Structure

```
lib/
  main.dart                     # Entry point, window setup
  app.dart                      # MaterialApp, theming, routing
  constants.dart                # App metadata

  models/                       # Data models (immutable, with JSON serialization)
  services/                     # Backend logic (aria2, Real-Debrid, config, etc.)
  providers/                    # Riverpod state management
  ui/
    screens/                    # Full-screen pages (home, settings, history)
    widgets/                    # Reusable UI components
    dialogs/                    # Modal dialogs (token, OAuth, network, etc.)
  utils/                        # Pure utility functions
```

## Configuration

Settings are stored at:
- **Linux**: `~/.config/coco-downloader/config.json`
- **macOS**: `~/Library/Application Support/coco-downloader/config.json`
- **Windows**: `%APPDATA%\coco-downloader\config.json`

API tokens can be stored securely in the system keyring.

## Tech Stack

- **Flutter** -- cross-platform UI framework
- **Riverpod** -- state management (StateNotifier pattern)
- **Dio** -- HTTP client
- **aria2c** -- download engine (JSON-RPC control)
- **Material 3** -- design system

## License

MIT
