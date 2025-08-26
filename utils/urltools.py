from __future__ import annotations

from pathlib import Path
from urllib.parse import unquote, urlparse


def guess_name_from_link(link: str) -> str:
    try:
        p = urlparse(link or "")
        base = Path(p.path).name
        name = unquote(base) if base else ""
        return name or (link or "")
    except Exception:
        return link or ""
