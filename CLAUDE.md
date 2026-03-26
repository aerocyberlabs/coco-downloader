# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Coco Downloader is a Flutter desktop application (Windows/macOS/Linux) that provides a GUI for downloading files from both Real-Debrid-supported hosters and direct HTTP/HTTPS URLs. The application unrestricts links via the Real-Debrid API when needed and downloads files using aria2c with JSON-RPC for progress tracking and pause/resume functionality.

## Architecture

The codebase is organized into layered modules:

### Models (`lib/models/`)
- **download_item.dart**: DownloadItem model with DownloadStatus enum
- **file_progress.dart**: Per-file progress updates from aria2
- **app_config.dart**: Full application configuration with JSON serialization
- **preview_item.dart**: Link preview metadata
- **history_entry.dart**: Download history records
- **torrent_file_info.dart**: RD torrent file listing

### Services (`lib/services/`)
- **aria2/aria2_client.dart**: aria2c JSON-RPC 2.0 client over HTTP (Dio)
- **aria2/aria2_process.dart**: aria2c process lifecycle (spawn, stop, dynamic port)
- **aria2/aria2_models.dart**: Typed wrappers for aria2 RPC responses
- **real_debrid/rd_client.dart**: Real-Debrid REST API client with retry logic, bencode parser
- **real_debrid/rd_oauth.dart**: OAuth device flow for RD authentication
- **real_debrid/rd_host_patterns.dart**: Cached RD host/folder regex patterns
- **url_classifier.dart**: URL classification (direct, RD, magnet, torrent)
- **download_manager.dart**: Download orchestration and categorization
- **config_service.dart**: JSON config persistence with keyring integration
- **categories_service.dart**: File extension categorization
- **post_processor.dart**: ZIP extraction, SHA-256 dedup, AES encryption
- **auto_tuner.dart**: Per-task connection auto-adjustment
- **power_monitor.dart**: Battery/AC detection for throttling

### Providers (`lib/providers/`) - Riverpod State Management
- **config_provider.dart**: AppConfig state (root of state tree)
- **theme_provider.dart**: Dark/light mode derived from config
- **auth_provider.dart**: Token and OAuth state
- **preview_provider.dart**: Preview items, selection, filtering, progress updates
- **download_provider.dart**: Download session, aria2 lifecycle, polling loop
- **log_provider.dart**: Log message accumulation
- **clipboard_provider.dart**: Clipboard URL monitoring
- **scheduler_provider.dart**: Quiet hours scheduling

### UI (`lib/ui/`)
- **screens/home_screen.dart**: Main 3-zone layout (Input, Preview Table, Action Bar)
- **screens/settings_screen.dart**: Tabbed settings (General, Account, Network, File Rules, Scheduler, Advanced)
- **screens/history_screen.dart**: Download history viewer
- **widgets/**: input_zone, preview_table, filter_bar, action_bar, progress_bar, global_status_bar, log_panel
- **dialogs/**: token, oauth, network, scheduler, file_types, privacy_power, add_torrent, add_magnet, add_page, ytdlp, help, about

### Utils (`lib/utils/`)
- **format.dart**: humanSize, formatEta, formatSpeed
- **file_ops.dart**: uniqueName, sizeMatches
- **url_tools.dart**: guessNameFromLink, parseContentDisposition
- **platform_utils.dart**: openFolder, openFile, openUrl, configDir
- **runtime.dart**: resolveAria2Path (bundled/system)

## Running the Application

```bash
flutter run -d linux    # or macos, windows
```

## Dependencies

Install system requirements:
```bash
# Fedora
sudo dnf install -y aria2

# Ubuntu/Debian
sudo apt install -y aria2

# macOS
brew install aria2
```

Flutter dependencies:
```bash
flutter pub get
```

## Key Technical Details

- Uses Riverpod StateNotifier pattern (not code generation)
- aria2c spawned with dynamic port (OS-assigned) to avoid conflicts
- aria2c `--async-dns=false` required on Linux to avoid sandbox EPERM
- Dio JSON responses may return `Map<dynamic, dynamic>` — all fromJson methods accept untyped `Map`
- Material 3 theming with green seed color (#388E3C)
- Config stored at `~/.config/coco-downloader/config.json`
- Secure token storage via `flutter_secure_storage`

## Build Commands

```bash
flutter build linux     # Release build
flutter build macos
flutter build windows
```
