import re
from typing import Dict, Any, Optional, Tuple
from urllib.parse import urlparse, unquote
import requests
import time

_RD_REGEX_CACHE: dict[str, tuple[float, list, list]] = {}
_RD_REGEX_TTL = 6 * 60 * 60  # 6 hours


class URLClassifier:
    def __init__(self):
        self.rd_hosts_patterns = None
        self.rd_folder_patterns = None
        self._session = requests.Session()
        self._timeout = 10.0
        # Apply proxies and custom headers from config
        try:
            from config import load_config
            cfg = load_config()
            # Rotate user-agent for privacy if configured
            uas = cfg.get('user_agents') or []
            if cfg.get('rotate_user_agent') and isinstance(uas, list) and uas:
                import random
                self._session.headers['User-Agent'] = random.choice(uas)
            http_proxy = cfg.get("http_proxy")
            https_proxy = cfg.get("https_proxy")
            if http_proxy or https_proxy:
                proxies = {}
                if http_proxy:
                    proxies["http"] = http_proxy
                if https_proxy:
                    proxies["https"] = https_proxy
                self._session.proxies.update(proxies)
            headers_list = cfg.get("headers") or []
            if isinstance(headers_list, list):
                for line in headers_list:
                    if isinstance(line, str) and ":" in line:
                        k, v = line.split(":", 1)
                        self._session.headers[k.strip()] = v.strip()
        except Exception:
            pass
    
    def set_rd_patterns(self, hosts_regex: list, folder_regex: list):
        self.rd_hosts_patterns = [re.compile(p) for p in hosts_regex if p]
        self.rd_folder_patterns = [re.compile(p) for p in folder_regex if p]
    
    def is_rd_supported(self, url: str) -> bool:
        if not self.rd_hosts_patterns:
            return False
        for pattern in self.rd_hosts_patterns:
            if pattern.search(url):
                return True
        for pattern in (self.rd_folder_patterns or []):
            if pattern.search(url):
                return True
        return False
    
    def is_direct_downloadable(self, url: str) -> bool:
        try:
            parsed = urlparse(url)
            if parsed.scheme not in ('http', 'https'):
                return False
            if self.is_rd_supported(url):
                return False
            return True
        except Exception:
            return False
    
    def classify_url(self, url: str) -> str:
        if not url or not url.strip():
            return "invalid"
        url = url.strip()
        
        if url.startswith("magnet:"):
            return "magnet"
        if url.startswith("rd-torrent:"):
            return "rd-torrent"
        
        if self.is_rd_supported(url):
            return "realdebrid"
        elif self.is_direct_downloadable(url):
            return "direct"
        else:
            return "unknown"
    
    def get_direct_file_info(self, url: str) -> Dict[str, Any]:
        info = {"ok": False, "url": url, "type": "direct"}
        try:
            resp = self._session.head(url, allow_redirects=True, timeout=self._timeout)
            resp.raise_for_status()
            
            size = 0
            if 'content-length' in resp.headers:
                try:
                    size = int(resp.headers['content-length'])
                except ValueError:
                    pass
            else:
                # Try a range request to infer size from Content-Range
                try:
                    r2 = self._session.get(resp.url, headers={'Range': 'bytes=0-0'}, timeout=self._timeout, allow_redirects=True)
                    cr = r2.headers.get('Content-Range') or r2.headers.get('content-range')
                    # Expected format: bytes 0-0/12345
                    if cr and '/' in cr:
                        total = cr.split('/')[-1].strip()
                        size = int(total)
                except Exception:
                    pass
            
            filename = self._extract_filename(resp)
            if not filename:
                parsed = urlparse(resp.url)
                filename = unquote(parsed.path.split('/')[-1]) or "download"
            
            content_type = resp.headers.get('content-type', '').split(';')[0].strip()
            
            info.update({
                "ok": True,
                "filename": filename,
                "filesize": size,
                "content_type": content_type,
                "final_url": resp.url
            })
        except requests.exceptions.RequestException as e:
            info["error"] = str(e)[:200]
        except Exception as e:
            info["error"] = f"Unexpected error: {str(e)[:200]}"
        
        return info
    
    def _extract_filename(self, response) -> Optional[str]:
        cd = response.headers.get('content-disposition')
        if not cd:
            return None
        
        try:
            parts = [p.strip() for p in cd.split(';')]
            params = {}
            for p in parts[1:]:
                if '=' in p:
                    k, v = p.split('=', 1)
                    params[k.strip().lower()] = v.strip()
            
            vstar = params.get('filename*')
            if vstar:
                vstar = vstar.strip('"')
                if "''" in vstar:
                    _charset, enc = vstar.split("''", 1)
                else:
                    enc = vstar
                try:
                    return unquote(enc)
                except Exception:
                    return enc
            
            v = params.get('filename')
            if v:
                return v.strip('"')
        except Exception:
            pass
        return None


def fetch_rd_host_patterns(token: str) -> Tuple[list, list]:
    # Return cached patterns if within TTL
    now = time.time()
    try:
        if token in _RD_REGEX_CACHE:
            ts, hosts_regex, folder_regex = _RD_REGEX_CACHE[token]
            if now - ts < _RD_REGEX_TTL:
                return hosts_regex, folder_regex
    except Exception:
        pass
    try:
        headers = {"Authorization": f"Bearer {token}"}
        resp = requests.get(
            "https://api.real-debrid.com/rest/1.0/hosts/regex",
            headers=headers,
            timeout=10
        )
        hosts_regex = resp.json() if resp.status_code == 200 else []
        resp = requests.get(
            "https://api.real-debrid.com/rest/1.0/hosts/regexFolder",
            headers=headers,
            timeout=10
        )
        folder_regex = resp.json() if resp.status_code == 200 else []
        _RD_REGEX_CACHE[token] = (now, hosts_regex, folder_regex)
        return hosts_regex, folder_regex
    except Exception:
        # On failure, return cached values if present
        try:
            if token in _RD_REGEX_CACHE:
                _, hosts_regex, folder_regex = _RD_REGEX_CACHE[token]
                return hosts_regex, folder_regex
        except Exception:
            pass
        return [], []
