from __future__ import annotations
import os
import sys
import stat


def _is_executable(path: str) -> bool:
    try:
        st = os.stat(path)
        return bool(st.st_mode & stat.S_IXUSR)
    except Exception:
        return False


def resolve_bundled_aria2() -> str | None:
    """
    Attempt to locate a bundled aria2 binary relative to the executable or PyInstaller temp dir.
    Returns an absolute path if found and (on Unix) marks it executable.
    """
    bases: list[str] = []
    try:
        meipass = getattr(sys, '_MEIPASS', None)
        if meipass:
            bases.append(str(meipass))
    except Exception:
        pass
    try:
        bases.append(os.path.abspath(os.path.dirname(sys.argv[0])))
    except Exception:
        pass
    bases.append(os.getcwd())

    is_win = sys.platform.startswith('win')
    is_mac = sys.platform == 'darwin'
    name = 'aria2c.exe' if is_win else 'aria2c'
    subdirs = ['bin']
    if is_win:
        subdirs += ['bin\\windows']
    elif is_mac:
        subdirs += ['bin/macos']
    else:
        subdirs += ['bin/linux']

    for base in bases:
        for sd in subdirs:
            cand = os.path.join(base, sd, name)
            if os.path.isfile(cand):
                if not is_win:
                    try:
                        # ensure executable bit
                        os.chmod(cand, os.stat(cand).st_mode | stat.S_IXUSR)
                    except Exception:
                        pass
                return cand
    return None

