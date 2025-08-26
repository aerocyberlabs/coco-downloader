from __future__ import annotations
import os
from typing import Optional, Dict, Any

from utils import categories as cat
from utils import urltools as utools
from urllib.parse import urlparse


class DownloadManager:
    """
    Encapsulates building download entries and aria2 options for links from different sources.
    Keeps policy decisions (exclude, categorization) centralized.
    """

    def __init__(self, outdir: str, cfg: dict, rd_client=None, classifier=None):
        self.outdir = outdir
        self.cfg = cfg or {}
        self.rd = rd_client
        self.classifier = classifier

    # Policy helpers
    def is_excluded(self, name: str) -> bool:
        ext = cat.ext_from_name(name)
        excluded = set(
            [e.lower().lstrip(".") for e in (self.cfg.get("exclude_ext") or []) if isinstance(e, str)]
        )
        return bool(ext and ext in excluded)

    def category_for_name(self, name: str) -> str:
        return cat.categorize_extension(cat.ext_from_name(name), self.cfg)

    def target_dir_for_name(self, name: str) -> str:
        base = self.outdir
        if not self.cfg.get("auto_categorize", True):
            return base
        category = self.category_for_name(name)
        sub = cat.subfolder_for_category(category, self.cfg)
        return os.path.join(base, sub)

    def aria2_options_for_entry(self, entry: Dict[str, Any]) -> Dict[str, Any]:
        opts: Dict[str, Any] = {}
        name = entry.get("name") or ""
        if name:
            opts["out"] = name
            td = self.target_dir_for_name(name)
            if td:
                opts["dir"] = td
        return opts

    # Entry builders
    def process_link(self, link: str) -> Optional[Dict[str, Any]]:
        if not link:
            return None
        url_type = None
        try:
            if self.classifier:
                url_type = self.classifier.classify_url(link)
        except Exception:
            url_type = None

        if url_type == "direct" or not self.rd:
            return self._build_direct_entry(link)
        elif url_type in ("realdebrid", "unknown") and self.rd:
            return self._build_rd_entry(link)
        else:
            # unsupported types handled upstream (e.g., rd-torrent specs)
            return None

    def build_preview_item(self, link: str) -> Dict[str, Any]:
        """
        Build a preview dict for the UI table with keys:
        { ok, link, filename, filesize, type, host }
        """
        try:
            url_type = self.classifier.classify_url(link) if self.classifier else "unknown"
        except Exception:
            url_type = "unknown"

        if url_type == "direct" or not self.rd:
            # Direct: use HEAD info
            info = self.classifier.get_direct_file_info(link) if self.classifier else {"ok": False}
            if not info.get("ok"):
                return {"ok": False, "link": link, "error": info.get("error"), "type": "direct"}
            fname = info.get("filename") or utools.guess_name_from_link(link)
            fsize = int(info.get("filesize") or 0)
            host = "Direct"
            try:
                host = urlparse(info.get("final_url") or link).netloc or host
            except Exception:
                pass
            ext = cat.ext_from_name(fname)
            return {"ok": True, "link": link, "filename": fname, "filesize": fsize, "type": ext, "host": host}

        if url_type in ("realdebrid", "unknown") and self.rd:
            # RD: check and enrich
            info = self.rd.check_link(link)
            fname = info.get("filename") or info.get("name")
            if not fname:
                u = self.rd.unrestrict_link(link)
                if u.get("ok"):
                    fname = u.get("filename") or fname
                    durl = u.get("download")
                    if (not fname) and durl:
                        fn2 = self.rd.head_filename(durl)
                        if fn2:
                            fname = fn2
                if u.get("ok") and (not info.get("filesize")):
                    info["filesize"] = u.get("filesize")
            if fname:
                info["filename"] = fname
            host = info.get("host")
            if not host:
                try:
                    host = urlparse(link).netloc
                except Exception:
                    host = "Real‑Debrid"
            fsize = int(info.get("filesize") or 0) if info.get("filesize") else 0
            ext = cat.ext_from_name(fname or "")
            ok = bool(info.get("ok"))
            return {"ok": ok, "link": link, "filename": fname or utools.guess_name_from_link(link), "filesize": fsize, "type": ext, "host": host}

        # Fallback unknown
        return {"ok": False, "link": link, "error": "Unsupported link type"}

    def _build_direct_entry(self, link: str) -> Optional[Dict[str, Any]]:
        if not self.classifier:
            return None
        info = self.classifier.get_direct_file_info(link)
        if not info.get("ok"):
            return None
        name = info.get("filename") or "download"
        try:
            size_int = int(info.get("filesize") or 0)
        except Exception:
            size_int = 0
        url = info.get("final_url") or link
        return {"url": url, "name": name, "size": size_int, "orig_link": link}

    def _build_rd_entry(self, link: str) -> Optional[Dict[str, Any]]:
        if not self.rd:
            return None
        res = self.rd.unrestrict_link(link)
        if not res.get("ok"):
            return None
        url = res.get("download")
        name = res.get("filename") or ""
        try:
            size_int = int(res.get("filesize") or 0)
        except Exception:
            size_int = 0
        if not url:
            return None
        if not name:
            try:
                inferred = self.rd.head_filename(url)
                if inferred:
                    name = inferred
            except Exception:
                pass
        return {"url": url, "name": name, "size": size_int, "orig_link": link}
