import time
from typing import Optional, Dict, Any
import requests

OAUTH_BASE = "https://api.real-debrid.com/oauth/v2"
PUBLIC_CLIENT_ID = "X245A4XAIBGVM"  # per RD docs for opensource apps


def device_code(new_credentials: bool = True, session: Optional[requests.Session] = None) -> Dict[str, Any]:
    s = session or requests.Session()
    params = {"client_id": PUBLIC_CLIENT_ID}
    if new_credentials:
        params["new_credentials"] = "yes"
    r = s.get(f"{OAUTH_BASE}/device/code", params=params, timeout=20)
    r.raise_for_status()
    return r.json()


def poll_credentials(device_code: str, interval: int = 5, timeout_sec: int = 300, session: Optional[requests.Session] = None) -> Dict[str, Any]:
    s = session or requests.Session()
    params = {"client_id": PUBLIC_CLIENT_ID, "code": device_code}
    deadline = time.time() + max(5, timeout_sec)
    last_err = None
    while time.time() < deadline:
        r = s.get(f"{OAUTH_BASE}/device/credentials", params=params, timeout=20)
        if r.status_code == 200:
            return r.json()
        last_err = r.text
        time.sleep(max(2, interval))
    raise RuntimeError(f"Timeout waiting for credentials: {last_err}")


def exchange_token(client_id: str, client_secret: str, device_code: str, session: Optional[requests.Session] = None) -> Dict[str, Any]:
    s = session or requests.Session()
    data = {
        "client_id": client_id,
        "client_secret": client_secret,
        "code": device_code,
        "grant_type": "http://oauth.net/grant_type/device/1.0",
    }
    r = s.post(f"{OAUTH_BASE}/token", data=data, timeout=20)
    r.raise_for_status()
    return r.json()


def refresh_access_token(client_id: str, client_secret: str, refresh_token: str, session: Optional[requests.Session] = None) -> Dict[str, Any]:
    s = session or requests.Session()
    data = {
        "client_id": client_id,
        "client_secret": client_secret,
        "code": refresh_token,
        "grant_type": "http://oauth.net/grant_type/device/1.0",
    }
    r = s.post(f"{OAUTH_BASE}/token", data=data, timeout=20)
    r.raise_for_status()
    return r.json()

