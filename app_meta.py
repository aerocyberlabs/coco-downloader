import os
from pathlib import Path


def _read_file(fname: str) -> str | None:
    try:
        p = Path(__file__).parent / fname
        if p.exists():
            return p.read_text(encoding="utf-8").strip()
    except Exception:
        pass
    return None


# Human-readable app name
APP_NAME: str = os.environ.get("APP_NAME") or _read_file("APP_NAME") or "Coco Downloader"

# Machine-friendly slug used for binary and folder names
APP_SLUG: str = os.environ.get("APP_SLUG") or _read_file("APP_SLUG") or "coco-downloader"

# Bundle identifier (macOS)
BUNDLE_ID: str = os.environ.get("BUNDLE_ID") or _read_file("BUNDLE_ID") or "com.acl.downloader"

# Version string
VERSION: str = os.environ.get("APP_VERSION") or _read_file("VERSION") or "0.1.0"

# Optional support/donate URL
SUPPORT_URL: str | None = os.environ.get("SUPPORT_URL") or _read_file("SUPPORT_URL")
