from __future__ import annotations
import os


def unique_name(folder: str, name: str) -> str:
    base, ext = os.path.splitext(name)
    attempt = 1
    while True:
        cand = f"{base} ({attempt}){ext}" if attempt > 0 else name
        path = os.path.join(folder, cand)
        if not os.path.exists(path):
            return cand
        attempt += 1


def size_matches(path: str, size: int) -> bool:
    try:
        st = os.stat(path)
        return int(st.st_size) == int(size)
    except Exception:
        return False

