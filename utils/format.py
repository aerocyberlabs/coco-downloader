from __future__ import annotations


def human_size(num: int) -> str:
    step = 1024.0
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    n = float(num or 0)
    for u in units:
        if n < step:
            return f"{n:.1f} {u}" if u != "B" else f"{int(n)} {u}"
        n /= step
    return f"{n:.1f} PiB"


def format_eta(secs: int) -> str:
    try:
        s = max(0, int(secs))
    except Exception:
        s = 0
    h, rem = divmod(s, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h:d}:{m:02d}:{s:02d}"
    return f"{m:d}:{s:02d}"


def format_speed(bps: int) -> str:
    try:
        v = float(bps or 0)
    except Exception:
        v = 0.0
    units = ["B/s", "KiB/s", "MiB/s", "GiB/s"]
    i = 0
    while v >= 1024.0 and i < len(units) - 1:
        v /= 1024.0
        i += 1
    if i == 0:
        return f"{int(v)} {units[i]}"
    return f"{v:.1f} {units[i]}"
