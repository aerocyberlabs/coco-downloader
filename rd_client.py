import hashlib
import random
import time
from typing import Any, Dict, List, Optional, Tuple, cast
from urllib.parse import unquote, urlparse

import requests
from requests.exceptions import ConnectionError, RequestException, Timeout

API_BASE = "https://api.real-debrid.com/rest/1.0"

try:
    from config import load_config, save_config
except Exception:
    load_config = None  # type: ignore
    save_config = None  # type: ignore


class RealDebridClient:
    def __init__(self, token: str, timeout: float = 30.0, retries: int = 3, backoff: float = 0.8):
        self.token = token.strip()
        self.sess = requests.Session()
        self.timeout = timeout
        self.retries = max(0, retries)
        self.backoff = max(0.0, backoff)
        # Apply proxies and custom headers from config
        try:
            if load_config:
                cfg = load_config()
                # Prefer OAuth access token if present
                at = cast(str, cfg.get("rd_access_token") or "").strip()
                if at:
                    self.token = at
                http_proxy = cfg.get("http_proxy")
                https_proxy = cfg.get("https_proxy")
                if http_proxy or https_proxy:
                    proxies = {}
                    if http_proxy:
                        proxies["http"] = http_proxy
                    if https_proxy:
                        proxies["https"] = https_proxy
                    self.sess.proxies.update(proxies)
                headers_list = cfg.get("headers") or []
                if isinstance(headers_list, list):
                    for line in headers_list:
                        if isinstance(line, str) and ":" in line:
                            k, v = line.split(":", 1)
                            self.sess.headers[k.strip()] = v.strip()
        except Exception:
            pass

    def _headers(self) -> Dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}

    def _get(self, path: str, params: Optional[Dict[str, Any]] = None) -> requests.Response:
        url = f"{API_BASE}{path}"
        last_exc: Optional[Exception] = None
        for attempt in range(self.retries + 1):
            try:
                r = self.sess.get(
                    url, headers=self._headers(), params=params or {}, timeout=self.timeout
                )
                # Retry on rate limit and transient server errors
                if r.status_code == 429 or 500 <= r.status_code < 600:
                    if attempt < self.retries:
                        ra = r.headers.get("Retry-After")
                        delay = None
                        try:
                            if ra:
                                delay = float(ra)
                        except Exception:
                            delay = None
                        if delay is None:
                            delay = self.backoff * (2**attempt) + random.uniform(0, self.backoff)
                        time.sleep(delay)
                        continue
                return r
            except Exception as e:
                last_exc = e
                if attempt < self.retries:
                    time.sleep(self.backoff * (2**attempt) + random.uniform(0, self.backoff))
                else:
                    raise
        raise last_exc or RuntimeError("Unknown error")

    def _post(self, path: str, data: Dict[str, Any]) -> requests.Response:
        url = f"{API_BASE}{path}"
        last_exc: Optional[Exception] = None
        for attempt in range(self.retries + 1):
            try:
                r = self.sess.post(url, headers=self._headers(), data=data, timeout=self.timeout)
                if r.status_code == 429 or 500 <= r.status_code < 600:
                    if attempt < self.retries:
                        ra = r.headers.get("Retry-After")
                        delay = None
                        try:
                            if ra:
                                delay = float(ra)
                        except Exception:
                            delay = None
                        if delay is None:
                            delay = self.backoff * (2**attempt) + random.uniform(0, self.backoff)
                        time.sleep(delay)
                        continue
                return r
            except Exception as e:
                last_exc = e
                if attempt < self.retries:
                    time.sleep(self.backoff * (2**attempt) + random.uniform(0, self.backoff))
                else:
                    raise
        raise last_exc or RuntimeError("Unknown error")

    def check_link(self, link: str) -> Dict[str, Any]:
        info: Dict[str, Any] = {"ok": False, "link": link}
        try:
            r = self._post("/unrestrict/check", {"link": link})
        except (ConnectionError, Timeout):
            info["error"] = "Network error: unable to reach Real‑Debrid"
            return info
        except RequestException as e:
            info["error"] = f"Request error: {e}"[:200]
            return info
        if r.status_code == 200:
            try:
                j = r.json()
            except Exception:
                return {"ok": False, "link": link, "error": "Invalid JSON"}
            info.update({"ok": True, **j})
        else:
            info["error"] = self._friendly_error(r)
        return info

    def unrestrict_link(self, link: str) -> Dict[str, Any]:
        try:
            r = self._post("/unrestrict/link", {"link": link})
        except (ConnectionError, Timeout):
            return {"ok": False, "error": "Network error: unable to reach Real‑Debrid"}
        except RequestException as e:
            return {"ok": False, "error": f"Request error: {e}"[:200]}
        if r.status_code == 200:
            try:
                return {"ok": True, **r.json(), "via": "torrent"}
            except Exception:
                return {"ok": False, "error": "Invalid JSON"}
        return {"ok": False, "error": self._friendly_error(r)}

    def head_filename(self, url: str) -> Optional[str]:
        try:
            r = self.sess.head(url, allow_redirects=True, timeout=self.timeout)
        except Exception:
            return None
        # Try Content-Disposition first
        cd = None
        for k, v in r.headers.items():
            if k.lower() == "content-disposition":
                cd = v
                break
        name = None
        if cd:
            name = self._parse_cd_filename(cd)
        if not name:
            # Fallback to URL path
            try:
                path_name = unquote(urlparse(r.url or url).path.split("/")[-1])
                name = path_name or None
            except Exception:
                name = None
        return name

    @staticmethod
    def _parse_cd_filename(value: str) -> Optional[str]:
        try:
            # Split into parameters: disposition; key=value; key*=value
            parts = [p.strip() for p in value.split(";")]
            params = {}
            for p in parts[1:]:
                if "=" in p:
                    k, v = p.split("=", 1)
                    params[k.strip().lower()] = v.strip()

            # RFC 5987/6266: filename*=charset''percent-encoded
            vstar = params.get("filename*")
            if vstar:
                # trim optional quotes
                vstar = vstar.strip('"')
                if "''" in vstar:
                    _charset, enc = vstar.split("''", 1)
                else:
                    enc = vstar
                try:
                    return unquote(enc)
                except Exception:
                    return enc

            v = params.get("filename")
            if v:
                return v.strip('"')
        except Exception:
            pass
        return None

    @staticmethod
    def _friendly_error(r: requests.Response) -> str:
        try:
            j = r.json()
            if isinstance(j, dict) and "error" in j:
                code = j.get("error_code")
                if code is not None:
                    return f"HTTP {r.status_code}: {j['error']} (code {code})"
                return f"HTTP {r.status_code}: {j['error']}"
        except Exception:
            pass
        return f"HTTP {r.status_code}: {r.text.strip()[:200]}"

    # Torrent endpoints
    def add_torrent(self, file_path: str) -> Dict[str, Any]:
        # Per docs: PUT /torrents/addTorrent with multipart 'file'
        try:
            with open(file_path, "rb") as f:
                r = self.sess.put(
                    f"{API_BASE}/torrents/addTorrent",
                    headers=self._headers(),
                    files={"file": (file_path, f, "application/x-bittorrent")},
                    timeout=self.timeout,
                )
        except (ConnectionError, Timeout):
            return {"ok": False, "error": "Network error: unable to reach Real‑Debrid"}
        except RequestException as e:
            return {"ok": False, "error": f"Request error: {e}"[:200]}
        if r.status_code in (200, 201):
            try:
                j = r.json()
                return {"ok": True, "http_status": r.status_code, **j}
            except Exception:
                return {"ok": False, "http_status": r.status_code, "error": "Invalid JSON"}
        # If RD rejects the torrent file, attempt magnet fallback by deriving BTIH from the .torrent
        try:
            msg = self._friendly_error(r)
        except Exception:
            msg = f"HTTP {r.status_code}"
        if r.status_code == 400 and "torrent_file_invalid" in (msg or ""):
            magnet, v2_only = self._torrent_to_magnet(file_path)
            if v2_only:
                return {"ok": False, "error": "torrent_v2_only_unsupported"}
            if magnet:
                m = self.add_magnet(magnet)
                if m.get("ok"):
                    # augment to indicate fallback
                    m.update({"via": "magnet", "magnet": magnet})
                    return m
                else:
                    # include magnet so UI can offer copy/paste or retry
                    m.update({"magnet": magnet})
                    return m
        return {"ok": False, "http_status": r.status_code, "error": msg}

    # Utilities
    def _torrent_to_magnet(self, file_path: str) -> Tuple[Optional[str], bool]:
        try:
            with open(file_path, "rb") as f:
                data = f.read()
        except Exception:
            return None, False
        try:
            info_start, info_end = self._locate_info_dict_span(data)
            if info_start is None or info_end is None:
                return None, False
            info_blob = data[info_start:info_end]
            # Detect v2-only torrents: missing 'pieces' and has 'file tree' or meta version 2
            has_pieces = b"6:pieces" in info_blob
            has_file_tree = b"9:file tree" in info_blob or b"8:filetree" in info_blob
            has_meta_v2 = b"12:meta versioni2e" in info_blob
            if (not has_pieces) and (has_file_tree or has_meta_v2):
                return None, True
            btih = hashlib.sha1(info_blob).hexdigest()
            # Try to get a display name from torrent
            name = self._extract_name_from_info(data, info_start, info_end) or ""
            magnet = f"magnet:?xt=urn:btih:{btih}"
            if name:
                from urllib.parse import quote

                magnet += f"&dn={quote(name)}"
            return magnet, False
        except Exception:
            return None, False

    def _locate_info_dict_span(self, data: bytes) -> Tuple[Optional[int], Optional[int]]:
        # Minimal bencode parser that returns byte-span of the value of key 'info' in top-level dict
        # Bencode grammar: i<int>e | <len>:<bytes> | l<items>e | d<pairs>e
        info_span: Tuple[Optional[int], Optional[int]] = (None, None)

        def parse(i: int) -> Tuple[object, int]:
            lead = data[i : i + 1]
            if not lead:
                raise ValueError("unexpected eof")
            c = lead[:1]
            if c == b"i":
                j = data.index(b"e", i + 1)
                return int(data[i + 1 : j]), j + 1
            if c == b"l":
                i += 1
                lst = []
                while data[i : i + 1] != b"e":
                    v, i = parse(i)
                    lst.append(v)
                return lst, i + 1
            if c == b"d":
                i += 1
                d = {}
                while data[i : i + 1] != b"e":
                    k, i = parse(i)
                    if not isinstance(k, bytes):
                        raise ValueError("dict key not bytes")
                    v_start = i
                    v, i = parse(i)
                    d[k] = v
                    if k == b"info":
                        # value for 'info' started at v_start and goes to i
                        nonlocal info_span
                        info_span = (v_start, i)
                return d, i + 1
            # string
            # read length
            j = i
            while data[j : j + 1].isdigit():
                j += 1
            if data[j : j + 1] != b":":
                raise ValueError("invalid string")
            ln = int(data[i:j])
            s = data[j + 1 : j + 1 + ln]
            return s, j + 1 + ln

        try:
            parse(0)
        except Exception:
            pass
        return info_span

    def _extract_name_from_info(self, data: bytes, start: int, end: int) -> Optional[str]:
        # Naive parse inside info dict span to find name key (assumes well-formed bencode)
        try:
            i = start
            if data[i : i + 1] != b"d":
                return None
            i += 1
            while i < end and data[i : i + 1] != b"e":
                # key
                j = i
                while data[j : j + 1].isdigit():
                    j += 1
                if data[j : j + 1] != b":":
                    return None
                klen = int(data[i:j])
                k = data[j + 1 : j + 1 + klen]
                i = j + 1 + klen
                # value
                if k == b"name":
                    # value is a string; read length
                    j = i
                    while data[j : j + 1].isdigit():
                        j += 1
                    if data[j : j + 1] != b":":
                        return None
                    ln = int(data[i:j])
                    s = data[j + 1 : j + 1 + ln]
                    return s.decode("utf-8", errors="ignore")
                else:
                    # skip value generically via small parser
                    def skip(pos: int) -> int:
                        c = data[pos : pos + 1]
                        if c == b"i":
                            return data.index(b"e", pos + 1) + 1
                        if c == b"l" or c == b"d":
                            pos += 1
                            while data[pos : pos + 1] != b"e":
                                pos = skip(pos)
                            return pos + 1
                        # string
                        jj = pos
                        while data[jj : jj + 1].isdigit():
                            jj += 1
                        ln = int(data[pos:jj])
                        return jj + 1 + ln

                    i = skip(i)
        except Exception:
            return None
        return None

    def add_magnet(self, magnet: str) -> Dict[str, Any]:
        try:
            r = self.sess.post(
                f"{API_BASE}/torrents/addMagnet",
                headers=self._headers(),
                data={"magnet": magnet},
                timeout=self.timeout,
            )
        except (ConnectionError, Timeout):
            return {"ok": False, "error": "Network error: unable to reach Real‑Debrid"}
        except RequestException as e:
            return {"ok": False, "error": f"Request error: {e}"[:200]}
        if r.status_code in (200, 201):
            try:
                j = r.json()
                return {"ok": True, "http_status": r.status_code, **j}
            except Exception:
                return {"ok": False, "http_status": r.status_code, "error": "Invalid JSON"}
        return {"ok": False, "http_status": r.status_code, "error": self._friendly_error(r)}

    def torrent_info(self, tid: str) -> Dict[str, Any]:
        try:
            r = self._get(f"/torrents/info/{tid}")
        except (ConnectionError, Timeout):
            return {"ok": False, "error": "Network error: unable to reach Real‑Debrid"}
        except RequestException as e:
            return {"ok": False, "error": f"Request error: {e}"[:200]}
        if r.status_code == 200:
            try:
                j = r.json()
                return {"ok": True, "http_status": r.status_code, **j}
            except Exception:
                return {"ok": False, "http_status": r.status_code, "error": "Invalid JSON"}
        return {"ok": False, "http_status": r.status_code, "error": self._friendly_error(r)}

    def select_torrent_files(self, tid: str, file_ids: List[int | str]) -> Dict[str, Any]:
        # RD accepts either comma-separated indices or the literal 'all'
        files_param = (
            "all"
            if (not file_ids or (len(file_ids) == 1 and str(file_ids[0]).lower() == "all"))
            else ",".join(str(x) for x in file_ids)
        )
        try:
            r = self.sess.post(
                f"{API_BASE}/torrents/selectFiles/{tid}",
                headers=self._headers(),
                data={"files": files_param},
                timeout=self.timeout,
            )
        except (ConnectionError, Timeout):
            return {"ok": False, "error": "Network error: unable to reach Real‑Debrid"}
        except RequestException as e:
            return {"ok": False, "error": f"Request error: {e}"[:200]}
        if r.status_code in (200, 204):
            return {"ok": True, "http_status": r.status_code}
        return {"ok": False, "http_status": r.status_code, "error": self._friendly_error(r)}

    def delete_torrent(self, tid: str) -> Dict[str, Any]:
        try:
            r = self.sess.delete(
                f"{API_BASE}/torrents/delete/{tid}", headers=self._headers(), timeout=self.timeout
            )
        except (ConnectionError, Timeout):
            return {"ok": False, "error": "Network error: unable to reach Real‑Debrid"}
        except RequestException as e:
            return {"ok": False, "error": f"Request error: {e}"[:200]}
        if r.status_code in (200, 204):
            return {"ok": True, "http_status": r.status_code}
        return {"ok": False, "http_status": r.status_code, "error": self._friendly_error(r)}
