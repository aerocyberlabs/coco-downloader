from pathlib import Path
import json
import os
from typing import Optional
from app_meta import APP_NAME, APP_SLUG

try:
    import keyring  # type: ignore
except Exception:
    keyring = None  # type: ignore

_OLD_CONF_DIR = Path.home() / ".config" / "realdebrid_gui"
CONF_DIR = Path.home() / ".config" / APP_SLUG

# Migrate old config directory if present
try:
    if _OLD_CONF_DIR.exists() and not CONF_DIR.exists():
        # Prefer rename to preserve perms; fallback to copy
        try:
            _OLD_CONF_DIR.rename(CONF_DIR)
        except Exception:
            # Fallback: create and copy files
            CONF_DIR.mkdir(parents=True, exist_ok=True)
            for p in _OLD_CONF_DIR.iterdir():
                try:
                    target = CONF_DIR / p.name
                    if p.is_file():
                        data = p.read_bytes()
                        target.write_bytes(data)
                    elif p.is_dir():
                        import shutil
                        shutil.copytree(p, target, dirs_exist_ok=True)
                except Exception:
                    pass
except Exception:
    pass
CONF_FILE = CONF_DIR / "config.json"

def load_config() -> dict:
    try:
        with open(CONF_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return {}

def save_config(cfg: dict):
    CONF_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(CONF_DIR, 0o700)
    except Exception:
        pass
    with open(CONF_FILE, "w") as f:
        json.dump(cfg, f, indent=2)
    try:
        os.chmod(CONF_FILE, 0o600)
    except Exception:
        pass

# Keyring helpers
def keyring_available() -> bool:
    return keyring is not None

def get_token_from_keyring() -> Optional[str]:
    try:
        if not keyring:
            return None
        return keyring.get_password(APP_NAME, "token")
    except Exception:
        return None

def set_token_in_keyring(token: Optional[str]) -> bool:
    try:
        if not keyring:
            return False
        if token:
            keyring.set_password(APP_NAME, "token", token)
        else:
            try:
                keyring.delete_password(APP_NAME, "token")
            except Exception:
                pass
        return True
    except Exception:
        return False
