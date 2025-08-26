import os
import random
import shutil
import string
import subprocess
import time
from typing import Any, Dict, List, Optional

import requests

try:
    # Optional: read configured aria2 path
    from config import load_config
except Exception:
    load_config = None  # type: ignore


def _rand_secret(n: int = 16) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(random.choice(alphabet) for _ in range(n))


class Aria2Client:
    def __init__(
        self,
        outdir: str,
        port: int = 6800,
        secret: Optional[str] = None,
        program: Optional[str] = None,
    ):
        self.port = port
        self.secret = secret or _rand_secret(20)
        self.outdir = outdir
        self.proc: Optional[subprocess.Popen] = None
        self._url = f"http://127.0.0.1:{self.port}/jsonrpc"
        self._sess = requests.Session()
        self._timeout = 3.0
        # Session persistence in download directory
        self.session_path = os.path.join(self.outdir, ".aria2.session")
        # Program path resolution: use provided program, then config 'aria2_path', then PATH
        cfg_prog = None
        try:
            if load_config:
                cfg = load_config()
                cfg_prog = cfg.get("aria2_path")
        except Exception:
            cfg_prog = None
        self.aria2_prog = program or cfg_prog or "aria2c"

    def start(self, extra_args: Optional[List[str]] = None) -> None:
        if self.proc and self.proc.poll() is None:
            return
        # Check aria2c availability
        prog_ok = os.path.isabs(self.aria2_prog) and os.path.exists(self.aria2_prog)
        if not prog_ok and not shutil.which(self.aria2_prog):
            raise FileNotFoundError(
                "aria2c not found. Install aria2 or set 'aria2_path' in settings."
            )
        args = [
            self.aria2_prog,
            f"--rpc-listen-port={self.port}",
            "--enable-rpc=true",
            "--rpc-listen-all=false",
            "--rpc-secure=false",
            f"--rpc-secret={self.secret}",
            "--continue=true",
            "--max-concurrent-downloads=4",
            "--summary-interval=1",
            "--console-log-level=warn",
            "--enable-color=false",
            f"--dir={self.outdir}",
        ]
        # Inject proxies and headers from config
        try:
            if load_config:
                cfg = load_config()
                http_proxy = cfg.get("http_proxy")
                https_proxy = cfg.get("https_proxy")
                headers_list = cfg.get("headers") or []
                if http_proxy:
                    args.append(f"--http-proxy={http_proxy}")
                if https_proxy:
                    args.append(f"--https-proxy={https_proxy}")
                if isinstance(headers_list, list):
                    for line in headers_list:
                        if isinstance(line, str) and ":" in line:
                            args.append(f"--header={line}")
        except Exception:
            pass
        # Enable session persistence
        try:
            args.append(f"--save-session={self.session_path}")
            args.append("--save-session-interval=30")
            if os.path.exists(self.session_path):
                args.append(f"--input-file={self.session_path}")
        except Exception:
            pass
        if extra_args:
            args.extend(extra_args)
        # Start detached-ish; GUI handles lifecycle
        self.proc = subprocess.Popen(
            args,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        # Wait a moment for RPC server to be ready
        self._wait_ready()

    def stop(self):
        # Attempt to remove queued/active tasks and shutdown RPC server
        try:
            self.remove_all()
        except Exception:
            pass
        try:
            self.shutdown()
        except Exception:
            pass
        if self.proc and self.proc.poll() is None:
            try:
                self.proc.terminate()
                self.proc.wait(timeout=5)
            except Exception:
                try:
                    self.proc.kill()
                except Exception:
                    pass

    def _rpc(self, method: str, params: Optional[List[Any]] = None) -> Any:
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": f"aria2.{method}",
            "params": [f"token:{self.secret}"] + (params or []),
        }
        last_exc = None
        for attempt in range(3):
            try:
                r = self._sess.post(self._url, json=payload, timeout=self._timeout)
                # Retry on transient HTTP errors
                if r.status_code in (502, 503, 504):
                    time.sleep(0.2 * (2**attempt))
                    continue
                r.raise_for_status()
                j = r.json()
                break
            except Exception as e:
                last_exc = e
                time.sleep(0.2 * (2**attempt))
        else:
            raise last_exc or RuntimeError("RPC failed")
        if "error" in j:
            raise RuntimeError(j["error"])  # type: ignore
        return j.get("result")

    def _wait_ready(self, timeout: float = 5.0):
        start = time.time()
        while time.time() - start < timeout:
            try:
                # Use a short-timeout quick probe to avoid blocking long
                payload = {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "aria2.getVersion",
                    "params": [f"token:{self.secret}"],
                }
                r = self._sess.post(self._url, json=payload, timeout=0.5)
                r.raise_for_status()
                _ = r.json()
                return
            except Exception:
                time.sleep(0.1)
        # Let it fail later; better message from first call

    # Basic RPCs
    def getVersion(self):
        return self._rpc("getVersion")

    def addUri(self, uris: List[str], options: Optional[Dict[str, Any]] = None) -> str:
        return self._rpc("addUri", [uris, options or {}])

    def tellActive(self):
        keys = [
            "gid",
            "status",
            "totalLength",
            "completedLength",
            "downloadSpeed",
            "files",
            "bittorrent",
        ]
        return self._rpc("tellActive", [keys])

    def tellStopped(self, offset: int = 0, num: int = 1000):
        keys = ["gid", "status", "totalLength", "completedLength", "downloadSpeed", "files"]
        return self._rpc("tellStopped", [offset, num, keys])

    def tellWaiting(self, offset: int = 0, num: int = 1000):
        keys = ["gid", "status", "totalLength", "completedLength", "downloadSpeed", "files"]
        return self._rpc("tellWaiting", [offset, num, keys])

    def getGlobalStat(self):
        return self._rpc("getGlobalStat")

    def getOption(self, gid: str):
        return self._rpc("getOption", [gid])

    def pauseAll(self):
        return self._rpc("pauseAll")

    def unpauseAll(self):
        return self._rpc("unpauseAll")

    def changeGlobalOption(self, opts: Dict[str, Any]):
        return self._rpc("changeGlobalOption", [opts])

    def changeOption(self, gid: str, opts: Dict[str, Any]):
        return self._rpc("changeOption", [gid, opts])

    def pause(self, gid: str):
        return self._rpc("pause", [gid])

    def unpause(self, gid: str):
        return self._rpc("unpause", [gid])

    def remove(self, gid: str):
        return self._rpc("remove", [gid])

    def forceRemove(self, gid: str):
        return self._rpc("forceRemove", [gid])

    def purgeDownloadResult(self):
        try:
            return self._rpc("purgeDownloadResult")
        except Exception:
            return None

    def remove_all(self):
        try:
            active = self.tellActive() or []
        except Exception:
            active = []
        try:
            waiting = self.tellWaiting() or []
        except Exception:
            waiting = []
        gids = []
        for it in active + waiting:
            gid = it.get("gid")
            if gid:
                gids.append(str(gid))
        for gid in gids:
            try:
                self.forceRemove(gid)
            except Exception:
                pass
        self.purgeDownloadResult()

    def shutdown(self, force: bool = False):
        try:
            if force:
                r = self._rpc("forceShutdown")
                # Small delay to allow process to exit cleanly
                time.sleep(0.2)
                return r
            return self._rpc("shutdown")
        except Exception:
            # Fall back to force-shutdown if graceful failed
            if not force:
                try:
                    r = self._rpc("forceShutdown")
                    time.sleep(0.2)
                    return r
                except Exception:
                    pass
