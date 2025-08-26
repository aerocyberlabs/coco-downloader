# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

ACL Downloader is a PyQt6-based desktop application that provides a GUI for downloading files from both Real-Debrid-supported hosters and direct HTTP/HTTPS URLs. The application unrestricts links via the Real-Debrid API when needed and downloads files using aria2c with JSON-RPC for progress tracking and pause/resume functionality.

## Architecture

The codebase is organized into several key modules:

- **app.py**: Main GUI application entry point and primary window (`MainWindow` class)
- **realdebrid_gui.py**: Alternative entry point (same as app.py)
- **config.py**: Configuration management with secure token storage
- **rd_client.py**: Real-Debrid API client with retry logic and error handling
- **aria2_client.py**: aria2c JSON-RPC client for download management
- **workers.py**: QThread-based workers for background operations (preview, download, torrent handling)
- **url_utils.py**: URL classification and direct download utilities

### Key Components

1. **MainWindow** (`app.py`): Primary GUI with preview table, settings, and download controls
2. **RealDebridClient** (`rd_client.py`): Handles API communication with retry/backoff logic
3. **Aria2Client** (`aria2_client.py`): Manages aria2c daemon lifecycle and RPC communication
4. **Worker Threads**:
   - `PreviewWorker`: Fetches file info for link previews
   - `DownloadWorker`: Manages the download process
   - `TorrentPreviewWorker`: Handles torrent file/magnet link processing

## Running the Application

```bash
python3 app.py
```

Alternative entry point:
```bash
python3 realdebrid_gui.py
```

## Dependencies

Install required packages:
```bash
pip install -r requirements.txt
```

System requirements (Fedora):
```bash
sudo dnf install -y python3-pip python3-virtualenv aria2
```

## Configuration

- Config stored at: `~/.config/realdebrid_gui/config.json` (0600 permissions)
- API token securely stored when "Remember token" is checked
- Settings persist: output directory, connections, splits, concurrency, dark mode

## Key Features

1. **Direct Downloads**: Support for HTTP/HTTPS URLs without requiring Real-Debrid
2. **Real-Debrid Integration**: Unrestrict supported hoster links via RD API
3. **Bulk Mode**: Process multiple links with file selection preview
4. **Progress Tracking**: Per-file and global progress with aria2c JSON-RPC
5. **Torrent Support**: Handle .torrent files and magnet links via Real-Debrid
6. **Resume/Pause**: Full download control with partial file resumption
7. **Dark Mode**: Theme switching with persistent settings

## Development Notes

- Uses PyQt6 for GUI framework
- Implements custom `SquareProgressBar` widget for visual feedback
- Thread-safe communication via Qt signals between workers and main thread
- URL classification system to route links appropriately
- Comprehensive error handling with user-friendly messages
- Secure configuration storage with proper file permissions
- Optional Real-Debrid token - not required for direct downloads

## File Structure

- GUI components and main logic in `app.py`
- API communication abstracted in `rd_client.py`
- Download management via `aria2_client.py`
- Background processing in `workers.py`
- URL classification and direct download utilities in `url_utils.py`
- Configuration utilities in `config.py`

## Important Implementation Details

- All API calls include retry logic with exponential backoff
- aria2c process lifecycle managed by `Aria2Client`
- URL classification determines download path (direct vs Real-Debrid)
- File existence checking to skip completed downloads
- Torrent files converted to magnet links as fallback when upload fails
- Progress updates use Qt signals to maintain thread safety
- Mixed batches supported (direct URLs + Real-Debrid links together)