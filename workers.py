import os
import threading
import time

import psutil
from PyQt6.QtCore import QThread, pyqtSignal

from aria2_client import Aria2Client
from config import load_config
from models import FileProgress
from rd_client import RealDebridClient
from url_utils import URLClassifier, fetch_rd_host_patterns
from utils import categories as cat
from utils import fileops as fops


class PreviewWorker(QThread):
    result = pyqtSignal(list)
    log = pyqtSignal(str)

    def __init__(self, token: str, links):
        super().__init__()
        if isinstance(links, str):
            links = [links]
        self.links = [link.strip() for link in (links or []) if link and link.strip()]
        self.client = RealDebridClient(token) if token else None
        self.classifier = URLClassifier()
        if token:
            try:
                hosts_regex, folder_regex = fetch_rd_host_patterns(token)
                self.classifier.set_rd_patterns(hosts_regex, folder_regex)
            except Exception:
                pass

    def run(self):
        items = []
        if not self.links:
            self.result.emit(items)
            return
        from core.download_manager import DownloadManager

        manager = DownloadManager(
            outdir="", cfg={}, rd_client=self.client, classifier=self.classifier
        )
        for link in self.links:
            try:
                url_type = self.classifier.classify_url(link)
                if url_type == "rd-torrent":
                    info = {
                        "ok": True,
                        "link": link,
                        "type": "rd-torrent",
                        "filename": "Torrent file",
                        "filesize": 0,
                    }
                elif url_type == "magnet":
                    info = {
                        "ok": True,
                        "link": link,
                        "type": "magnet",
                        "filename": "Magnet",
                        "filesize": 0,
                    }
                else:
                    info = manager.build_preview_item(link)
            except Exception as e:
                info = {"ok": False, "link": link, "error": str(e), "type": "unknown"}
            items.append(info)
        self.result.emit(items)

    # legacy helpers removed; now delegated to DownloadManager


class DownloadWorker(QThread):
    log = pyqtSignal(str)
    done = pyqtSignal(bool, str)
    progress = pyqtSignal(int)  # 0..100 overall
    state = pyqtSignal(str)  # running|paused|resumed|canceled
    pid_ready = pyqtSignal(int)  # aria2c PID
    file_update = pyqtSignal(str, int, int, int, str)  # link, percent, speed(B/s), eta(s), status
    eta_update = pyqtSignal(int)  # global eta seconds
    counts_update = pyqtSignal(int, int)  # active, queued(waiting)
    file_update_typed = pyqtSignal(object)  # FileProgress

    def __init__(
        self,
        token: str,
        links,
        outdir: str,
        connections: int = 16,
        splits: int = 16,
        concurrent: int = 1,
    ):
        super().__init__()
        if isinstance(links, str):
            links = [links]
        self.links = [link.strip() for link in (links or []) if link and link.strip()]
        self.outdir = outdir
        self.connections = max(1, int(connections))
        self.splits = max(1, int(splits))
        self.concurrent = max(1, int(concurrent))
        self.client = RealDebridClient(token) if token else None
        self.classifier = URLClassifier()
        self.aria = Aria2Client(self.outdir)
        self._canceled = False
        self._paused = False
        self._gid_to_link = {}
        self._link_to_gid: dict[str, str] = {}
        self._cfg = load_config()
        # Auto-tune settings
        self._tune_enabled = bool(self._cfg.get("enable_auto_tune", False))
        self._tune_min_kib = int(self._cfg.get("tune_min_kib", 64))
        self._tune_max_conn = int(self._cfg.get("tune_max_conn", 16))
        self._tune_min_conn = int(self._cfg.get("tune_min_conn", 1))
        self._tune_interval = int(self._cfg.get("tune_interval_sec", 20))
        self._tune_alpha = float(self._cfg.get("tune_ema_alpha", 0.3))
        self._gid_last_adjust: dict[str, float] = {}
        self._gid_conn_hint: dict[str, int] = {}
        if token:
            try:
                hosts_regex, folder_regex = fetch_rd_host_patterns(token)
                self.classifier.set_rd_patterns(hosts_regex, folder_regex)
            except Exception:
                pass

    def run(self):
        try:
            if not self.links:
                self.done.emit(False, "Missing link(s).")
                return
            os.makedirs(self.outdir, exist_ok=True)
            extra = [f"-x{self.connections}", f"-s{self.splits}", f"-j{self.concurrent}"]
            self.aria.start(extra_args=extra)
            if self.aria.proc:
                self.pid_ready.emit(self.aria.proc.pid)
            self.state.emit("running")
            # Start power-aware limiter thread if enabled
            power_cfg = self._cfg
            self._power_thread_stop = False
            if power_cfg.get("enable_power_aware"):
                t = threading.Thread(target=self._power_aware_loop, daemon=True)
                t.start()

            dl_entries = []  # list of dicts with url, name, size
            failed = 0
            from core.download_manager import DownloadManager

            manager = DownloadManager(self.outdir, self._cfg, self.client, self.classifier)
            for idx, link in enumerate(self.links):
                if self._canceled:
                    break

                try:
                    entry = manager.process_link(link)
                    if entry:
                        dl_entries.append(entry)
                    else:
                        failed += 1
                        self.log.emit(f"Unsupported or failed link: {link}")
                except Exception as e:
                    failed += 1
                    self.log.emit(f"Link processing error: {e}")

            if self._canceled:
                self.done.emit(False, "Download canceled.")
                return
            if not dl_entries:
                self.done.emit(False, "No valid links to download.")
                return

            for ent in dl_entries:
                try:
                    name_for_ext = ent.get("name") or ""
                    # Skip excluded extensions
                    if manager.is_excluded(name_for_ext):
                        self.log.emit(f"Excluded by file type: {name_for_ext}")
                        continue
                    # Ensure per-file directory exists
                    target_dir = manager.target_dir_for_name(name_for_ext)
                    try:
                        os.makedirs(target_dir, exist_ok=True)
                    except Exception:
                        pass
                    # Options for aria2
                    opts = manager.aria2_options_for_entry(ent)
                    gid = self.aria.addUri([ent["url"]], options=opts)
                    # Map gid back to original link for progress tracking
                    orig_link = ent.get("orig_link") or ent.get("url")
                    self._gid_to_link[str(gid)] = orig_link
                    self._link_to_gid[orig_link] = str(gid)
                    # Also map the download URL to original link for direct downloads
                    if ent["url"] != orig_link:
                        self._gid_to_link[ent["url"]] = orig_link
                except Exception as e:
                    failed += 1
                    self.log.emit(f"Failed to queue download: {e}")

            # Poll progress
            total_done = False
            last_overall = 0
            while not total_done and not self._canceled:
                try:
                    active = self.aria.tellActive() or []
                    waiting = self.aria.tellWaiting() or []
                    stopped = self.aria.tellStopped() or []
                    gstat = self.aria.getGlobalStat() or {}
                except Exception as e:
                    self.log.emit(f"RPC error: {e}")
                    time.sleep(0.5)
                    continue

                total_len = 0
                completed = 0
                # Map any new URIs to original links to keep correlation stable
                for it in active + waiting + stopped:
                    try:
                        gid = str(it.get("gid"))
                        orig = self._gid_to_link.get(gid)
                        if not orig:
                            continue
                        files = it.get("files") or []
                        for f in files:
                            for u in f.get("uris") or []:
                                uri = u.get("uri")
                                if uri:
                                    self._gid_to_link[uri] = orig
                    except Exception:
                        pass
                for it in active + waiting + stopped:
                    try:
                        total_len += int(it.get("totalLength") or 0)
                        completed += int(it.get("completedLength") or 0)
                    except Exception:
                        pass
                # per-file updates for active and recently stopped
                for it in active:
                    gid = str(it.get("gid"))
                    link = self._gid_to_link.get(gid)
                    if not link:
                        # Try to find link by checking files info for direct downloads
                        files = it.get("files") or []
                        if files and len(files) > 0:
                            uris = files[0].get("uris") or []
                            if uris:
                                uri = uris[0].get("uri", "")
                                link = self._gid_to_link.get(uri)
                        if not link:
                            continue
                    try:
                        tl = int(it.get("totalLength") or 0)
                        cl = int(it.get("completedLength") or 0)
                        spd = int(it.get("downloadSpeed") or 0)
                        pct = int((cl * 100) / tl) if tl > 0 else 0
                        eta = int((tl - cl) / spd) if (spd > 0 and tl > 0) else -1
                    except Exception:
                        pct = 0
                        spd = 0
                        eta = -1
                    st = it.get("status") or "active"
                    self.file_update.emit(link, pct, spd, eta, str(st))
                    try:
                        self.file_update_typed.emit(
                            FileProgress(link=link, percent=pct, speed=spd, eta=eta, status=str(st))
                        )
                    except Exception:
                        pass
                    # Heuristic auto-tuning per task
                    if self._tune_enabled:
                        try:
                            self._maybe_adjust_task(gid, it, spd)
                        except Exception:
                            pass
                for it in waiting:
                    gid = str(it.get("gid"))
                    link = self._gid_to_link.get(gid)
                    if not link:
                        # Try to find link by checking files info
                        files = it.get("files") or []
                        if files and len(files) > 0:
                            uris = files[0].get("uris") or []
                            if uris:
                                uri = uris[0].get("uri", "")
                                link = self._gid_to_link.get(uri)
                        if not link:
                            continue
                    st = it.get("status") or "waiting"
                    self.file_update.emit(link, 0, 0, 0, str(st))
                    try:
                        self.file_update_typed.emit(
                            FileProgress(link=link, percent=0, speed=0, eta=0, status=str(st))
                        )
                    except Exception:
                        pass
                for it in stopped:
                    gid = str(it.get("gid"))
                    link = self._gid_to_link.get(gid)
                    if not link:
                        # Try to find link by checking files info
                        files = it.get("files") or []
                        if files and len(files) > 0:
                            uris = files[0].get("uris") or []
                            if uris:
                                uri = uris[0].get("uri", "")
                                link = self._gid_to_link.get(uri)
                        if not link:
                            continue
                    st = it.get("status") or "stopped"
                    pct = 100 if st in ("complete", "removed") else 0
                    self.file_update.emit(link, pct, 0, 0, str(st))
                    try:
                        self.file_update_typed.emit(
                            FileProgress(link=link, percent=pct, speed=0, eta=0, status=str(st))
                        )
                    except Exception:
                        pass
                overall = int((completed * 100) / total_len) if total_len > 0 else last_overall
                if overall != last_overall:
                    last_overall = overall
                    self.progress.emit(overall)
                # global ETA
                try:
                    spd_g = int(gstat.get("downloadSpeed") or 0)
                    eta_g = int((total_len - completed) / spd_g) if spd_g > 0 else 0
                except Exception:
                    eta_g = 0
                self.eta_update.emit(eta_g)
                # counts for UI
                try:
                    self.counts_update.emit(len(active), len(waiting))
                except Exception:
                    pass

                # Done when no active/waiting tasks
                total_done = len(active) == 0 and len(waiting) == 0
                time.sleep(0.5)

            if self._canceled:
                self.done.emit(False, "Download canceled.")
                return
            self.progress.emit(100)
            self.done.emit(
                True,
                "All downloads complete." if failed == 0 else f"Complete with {failed} failure(s).",
            )
        except Exception as e:
            self.done.emit(False, f"Error: {e}")
        finally:
            try:
                self.aria.stop()
            except Exception:
                pass
            self._power_thread_stop = True

    # Per-item controls
    def pause_item(self, link: str):
        gid = self._link_to_gid.get(str(link))
        if gid:
            try:
                self.aria.pause(gid)
            except Exception as e:
                self.log.emit(f"Pause failed: {e}")

    def resume_item(self, link: str):
        gid = self._link_to_gid.get(str(link))
        if gid:
            try:
                self.aria.unpause(gid)
            except Exception as e:
                self.log.emit(f"Resume failed: {e}")

    def cancel_item(self, link: str):
        gid = self._link_to_gid.get(str(link))
        if gid:
            try:
                self.aria.remove(gid)
            except Exception as e:
                self.log.emit(f"Cancel failed: {e}")

    def _process_direct_link(self, link: str):
        try:
            info = self.classifier.get_direct_file_info(link)
            if not info.get("ok"):
                self.log.emit(f"Direct download check failed: {info.get('error')}")
                return None

            name = info.get("filename") or "download"
            try:
                size_int = int(info.get("filesize") or 0)
            except Exception:
                size_int = 0

            # Skip if file already complete
            if name:
                target = os.path.join(self.outdir, name)
                if os.path.exists(target):
                    try:
                        st = os.stat(target)
                        if size_int > 0 and int(st.st_size) == size_int:
                            self.log.emit(f"Skipping existing complete file: {name}")
                            return None
                        # Auto-rename to avoid overwrite
                        name = fops.unique_name(self.outdir, name)
                    except Exception:
                        name = fops.unique_name(self.outdir, name)

            # For direct downloads, use final_url if available (after redirects)
            download_url = info.get("final_url") or link
            return {"url": download_url, "name": name, "size": size_int, "orig_link": link}
        except Exception as e:
            self.log.emit(f"Error processing direct link: {e}")
            return None

    def _process_rd_link(self, link: str):
        try:
            res = self.client.unrestrict_link(link)
            if not res.get("ok"):
                self.log.emit(f"Unrestrict failed: {res.get('error')}")
                return None

            url = res.get("download")
            name = res.get("filename") or ""
            try:
                size_int = int(res.get("filesize") or 0)
            except Exception:
                size_int = 0

            if not url:
                self.log.emit("Missing download URL in response")
                return None

            # If RD didn't return filename, try to infer from URL headers
            if not name:
                try:
                    inferred = self.client.head_filename(url)
                    if inferred:
                        name = inferred
                except Exception:
                    pass

            # Skip if file already complete
            if name:
                target = os.path.join(self.outdir, name)
                if os.path.exists(target):
                    try:
                        st = os.stat(target)
                        if size_int > 0 and int(st.st_size) == size_int:
                            self.log.emit(f"Skipping existing complete file: {name}")
                            return None
                        name = fops.unique_name(self.outdir, name)
                    except Exception:
                        name = fops.unique_name(self.outdir, name)

            return {"url": url, "name": name, "size": size_int, "orig_link": link}
        except Exception as e:
            self.log.emit(f"Error processing RD link: {e}")
            return None

    # _unique_name moved to utils.fileops.unique_name

    def _category_for_name(self, name: str) -> str:
        ext = cat.ext_from_name(name)
        if not ext:
            return "Other"
        return cat.categorize_extension(ext, self._cfg)

    def _subfolder_for_category(self, cat: str) -> str:
        return cat.subfolder_for_category(cat, self._cfg)

    def _ext_from_name(self, name: str) -> str:
        return cat.ext_from_name(name)

    def pause(self):
        try:
            self.aria.pauseAll()
            self._paused = True
            self.state.emit("paused")
            self.log.emit("Paused.")
        except Exception as e:
            self.log.emit(f"Pause failed: {e}")

    def resume(self):
        try:
            self.aria.unpauseAll()
            self._paused = False
            self.state.emit("resumed")
            self.log.emit("Resumed.")
        except Exception as e:
            self.log.emit(f"Resume failed: {e}")

    def cancel(self):
        self._canceled = True
        # Proactively remove active/waiting tasks and force-shutdown aria2 RPC
        try:
            self.aria.remove_all()
        except Exception:
            pass
        try:
            self.aria.shutdown(force=True)
        except Exception:
            pass
        self.state.emit("canceled")

    def _maybe_adjust_task(self, gid: str, task: dict, speed_bps: int):
        import time as _t

        now = _t.time()
        last = self._gid_last_adjust.get(gid, 0.0)
        if now - last < max(5, self._tune_interval):
            return
        # Derive current conn per server
        try:
            opts = self.aria.getOption(gid) or {}
            cur_conn = int(opts.get("max-connection-per-server") or self.connections)
        except Exception:
            cur_conn = self.connections
        spd_kib = int((speed_bps or 0) / 1024)
        target = cur_conn
        if spd_kib < self._tune_min_kib and cur_conn < self._tune_max_conn:
            target = min(self._tune_max_conn, cur_conn + 1)
        elif spd_kib > (self._tune_min_kib * 10) and cur_conn > self._tune_min_conn:
            target = max(self._tune_min_conn, cur_conn - 1)
        if target != cur_conn:
            try:
                self.aria.changeOption(gid, {"max-connection-per-server": str(target)})
                self._gid_last_adjust[gid] = now
                self._gid_conn_hint[gid] = target
                self.log.emit(f"Auto-tune: adjusted connections for task to {target}")
            except Exception:
                pass

    def _power_aware_loop(self):
        # Adjust global download limit and concurrency based on power state
        # Uses psutil.sensors_battery when available
        # limit_ac implicit (0 = unlimited). Use battery limit when on battery.
        limit_bat = int(self._cfg.get("battery_limit_kib", 5120))  # default 5 MiB/s
        conc_ac = int(self._cfg.get("ac_concurrent", max(1, self.concurrent)))
        conc_bat = int(self._cfg.get("battery_concurrent", max(1, min(2, self.concurrent))))
        last_state = None
        while not getattr(self, "_power_thread_stop", False):
            try:
                bat = psutil.sensors_battery() if hasattr(psutil, "sensors_battery") else None
                on_battery = bool(bat and bat.power_plugged is False)
                if on_battery != last_state:
                    opts = {}
                    if on_battery:
                        if limit_bat > 0:
                            opts["max-overall-download-limit"] = f"{limit_bat}K"
                        opts["max-concurrent-downloads"] = str(max(1, conc_bat))
                        self.log.emit("Power-aware: on battery, limiting speed and concurrency.")
                    else:
                        opts["max-overall-download-limit"] = "0"
                        opts["max-concurrent-downloads"] = str(max(1, conc_ac))
                        self.log.emit("Power-aware: on AC, restoring speed and concurrency.")
                    try:
                        self.aria.changeGlobalOption(opts)
                    except Exception:
                        pass
                    last_state = on_battery
            except Exception:
                pass
            time.sleep(30)


class TorrentPreviewWorker(QThread):
    result = pyqtSignal(list)
    log = pyqtSignal(str)

    def __init__(self, token: str, torrent_path: str | None = None, magnet: str | None = None):
        super().__init__()
        self.client = RealDebridClient(token) if token else None
        self.torrent_path = torrent_path
        self.magnet = magnet

    def run(self):
        items = []
        try:
            if self.torrent_path:
                self.log.emit(f"Uploading torrent: {self.torrent_path}")
                r = self.client.add_torrent(self.torrent_path)
                try:
                    tid = r.get("id") or r.get("hash") or r.get("torrent_id")
                    http = r.get("http_status")
                    self.log.emit(f"RD add_torrent http={http} id={tid}")
                except Exception:
                    pass
            else:
                self.log.emit("Adding magnet…")
                r = self.client.add_magnet(self.magnet or "")
                try:
                    tid = r.get("id") or r.get("hash") or r.get("torrent_id")
                    http = r.get("http_status")
                    self.log.emit(f"RD add_magnet http={http} id={tid}")
                except Exception:
                    pass
            if not r.get("ok"):
                if str(r.get("error")) == "torrent_v2_only_unsupported":
                    self.log.emit("Torrent is BitTorrent v2-only (no v1 infohash). RD requires v1.")
                # If magnet fallback info is present, hint to the user
                if r.get("magnet"):
                    self.log.emit("Torrent file invalid. Attempted magnet fallback but it failed.")
                    self.log.emit(f"Magnet candidate: {r.get('magnet')}")
                err = str(r.get("error"))
                self.log.emit(err)
                self.result.emit(items)
                return
            tid = r.get("id") or r.get("torrent_hash") or r.get("hash") or r.get("torrent_id")
            if not tid:
                self.log.emit("Failed to retrieve torrent id")
                self.result.emit(items)
                return
            if r.get("via") == "magnet":
                self.log.emit("Added via magnet fallback. Waiting for RD to prepare files…")
                info = self.client.torrent_info(str(tid))
                try:
                    http = info.get("http_status")
                    status = info.get("status")
                    prog = info.get("progress")
                    files_count = len(info.get("files") or [])
                    self.log.emit(
                        f"RD info http={http} status={status} progress={prog} files={files_count}"
                    )
                except Exception:
                    pass
            files = info.get("files") if info.get("ok") else []
            # Poll briefly if info not immediately available
            wait_logged = False
            last_status = None
            last_progress = None
            attempts = 30  # ~60s at 2s interval
            while (not info.get("ok") or not files) and attempts > 0:
                if not wait_logged:
                    self.log.emit("Waiting for torrent info from Real‑Debrid…")
                    wait_logged = True
                time.sleep(2)
                info = self.client.torrent_info(str(tid))
                # Log status/progress if available
                try:
                    status = info.get("status")
                    progress = info.get("progress")
                    http_st = info.get("http_status")
                    if status and status != last_status:
                        self.log.emit(f"Torrent status: {status} (http={http_st})")
                        last_status = status
                    if isinstance(progress, (int, float)) and progress != last_progress:
                        self.log.emit(f"Torrent progress: {int(progress)}%")
                        last_progress = progress
                except Exception:
                    pass
                files = info.get("files") if info.get("ok") else []
                attempts -= 1
            if not info.get("ok"):
                self.log.emit(str(info.get("error")))
                self.result.emit(items)
                return
            files = files or []
            for f in files:
                try:
                    name = f.get("path") or f.get("filename") or ""
                    size = int(f.get("bytes") or f.get("size") or 0)
                    fid = f.get("id") or f.get("file_id") or f.get("index")
                except Exception:
                    name = f.get("path") or ""
                    size = 0
                    fid = f.get("id")
                link_marker = f"rd-torrent:{tid}:{fid}"
                items.append(
                    {
                        "ok": True,
                        "filename": name,
                        "filesize": size,
                        "type": (name.rsplit(".", 1)[-1] if "." in name else ""),
                        "host": "Real‑Debrid",
                        "link": link_marker,
                    }
                )
        except Exception as e:
            self.log.emit(f"Torrent add error: {e}")
        self.result.emit(items)

    # No pause/resume/cancel here; handled by DownloadWorker after links are queued


class RDTorrentStartWorker(QThread):
    """
    Background worker: selects files for given RD torrent specs and waits for links to be ready.
    Emits result as a list of direct HTTP links when ready.
    """

    result = pyqtSignal(list)
    log = pyqtSignal(str)
    open_url = pyqtSignal(str)

    def __init__(self, token: str, specs: list[str]):
        super().__init__()
        self.client = RealDebridClient(token) if token else None
        if isinstance(specs, str):
            specs = [specs]
        self.specs = [s for s in (specs or []) if s and isinstance(s, str)]

    def run(self):
        links_out: list[str] = []
        try:
            if not self.client or not self.specs:
                self.result.emit(links_out)
                return
            # Group by torrent id
            by_tid: dict[str, list[str]] = {}
            for s in self.specs:
                parts = s.split(":", 2)
                if len(parts) == 3:
                    _, tid, fid = parts
                    by_tid.setdefault(tid, []).append(fid)
            for tid, fids in by_tid.items():
                try:
                    self.log.emit(f"Auto-start: tid={tid} fids={','.join(fids) if fids else 'all'}")
                except Exception:
                    pass
                # Ensure RD has parsed files before selecting
                parsed = False
                for _ in range(30):  # up to ~60s
                    info0 = self.client.torrent_info(tid)
                    try:
                        http = info0.get("http_status")
                        status = info0.get("status")
                        prog = info0.get("progress")
                        files_count = len(info0.get("files") or [])
                        msg = (
                            f"RD info0 http={http} status={status} "
                            f"progress={prog} files={files_count}"
                        )
                        self.log.emit(msg)
                    except Exception:
                        pass
                    files0 = info0.get("files") if info0.get("ok") else []
                    if files0:
                        parsed = True
                        break
                    time.sleep(2)
                if not parsed:
                    self.log.emit(f"Torrent {tid}: files not parsed yet; continuing anyway.")
                # Select all files to guarantee RD starts caching
                r = self.client.select_torrent_files(
                    tid, ["all"]
                )  # use 'all' to avoid id mismatches
                try:
                    self.log.emit(
                        f"RD selectFiles http={r.get('http_status')} ok={bool(r.get('ok'))}"
                    )
                except Exception:
                    pass
                if not r.get("ok"):
                    self.log.emit(f"selectFiles failed for {tid}: {r.get('error')}")
                    continue
                else:
                    self.log.emit(f"RD accepted selection for {tid}. Preparing cached links…")
                # Poll for links, with progress logging
                ready_links: list[str] = []
                last_status = None
                last_progress = None
                attempts = 450  # ~15 minutes at 2s interval
                prompted = False
                while attempts > 0:
                    info = self.client.torrent_info(tid)
                    try:
                        http = info.get("http_status")
                        status = info.get("status")
                        prog = info.get("progress")
                        links_count = len(info.get("links") or [])
                        msg = (
                            f"RD info http={http} status={status} "
                            f"progress={prog} links={links_count}"
                        )
                        self.log.emit(msg)
                    except Exception:
                        pass
                    if not info.get("ok"):
                        time.sleep(2)
                        attempts -= 1
                        continue
                    api_links = info.get("links") or []
                    if api_links:
                        ready_links.extend(
                            [
                                ln
                                for ln in api_links
                                if isinstance(ln, str) and ln.startswith("http")
                            ]
                        )
                        break
                    # Detect manual confirmation requirement
                    st = (info.get("status") or "").lower()
                    if "waiting_files_selection" in st and not prompted:
                        self.log.emit(
                            "RD waiting_files_selection; opening RD Torrents for confirmation…"
                        )
                        try:
                            self.open_url.emit("https://real-debrid.com/torrents")
                        except Exception:
                            pass
                        prompted = True
                        # Try to re-send selection once after prompting
                        try:
                            r2 = self.client.select_torrent_files(tid, ["all"])  # re-assert
                            http = r2.get("http_status")
                            ok = bool(r2.get("ok"))
                            self.log.emit(f"RD re-selectFiles http={http} ok={ok}")
                        except Exception:
                            pass
                    try:
                        status = info.get("status")
                        progress = info.get("progress")
                        if status and status != last_status:
                            self.log.emit(f"Torrent {tid} status: {status}")
                            last_status = status
                        if isinstance(progress, (int, float)) and progress != last_progress:
                            self.log.emit(f"Torrent {tid} progress: {int(progress)}%")
                            last_progress = progress
                    except Exception:
                        pass
                    time.sleep(2)
                    attempts -= 1
                if ready_links:
                    links_out.extend(ready_links)
                else:
                    self.log.emit(
                        f"Torrent {tid}: no ready links yet. RD may still be preparing the files."
                    )
        except Exception as e:
            self.log.emit(f"RD auto-start error: {e}")
        self.result.emit(links_out)
