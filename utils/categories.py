from __future__ import annotations
import os
from typing import Dict, List


def ext_from_name(name: str) -> str:
    n = (name or '').lower()
    for comp in ('.tar.gz', '.tar.bz2', '.tar.xz'):
        if n.endswith(comp):
            return comp.lstrip('.')
    return os.path.splitext(n)[1].lstrip('.')


def default_category_exts() -> Dict[str, List[str]]:
    return {
        'Video': ["mp4","mkv","mov","avi","wmv","webm","mpg","mpeg","ts","m2ts","flv","m4v"],
        'Audio': ["mp3","flac","wav","m4a","aac","ogg","opus","aiff","alac"],
        'Image': ["jpg","jpeg","png","gif","bmp","webp","tiff","tif"],
        'Document': ["pdf","doc","docx","xls","xlsx","ppt","pptx","txt","md","csv","rtf","epub"],
        'Compressed': ["zip","rar","7z","tar","gz","bz2","xz","tar.gz","tar.bz2","tar.xz"],
        'Program': ["exe","msi","dmg","apk","appimage","deb","rpm","pkg","sh","bat","ps1"],
    }


def category_exts(cfg: dict | None) -> Dict[str, List[str]]:
    mapping = {k: [e.lower().lstrip('.') for e in v] for k, v in default_category_exts().items()}
    if not cfg:
        return mapping
    user_map = cfg.get('category_exts') or {}
    if isinstance(user_map, dict):
        for k, v in user_map.items():
            if isinstance(v, list):
                mapping[k] = [str(e).lower().lstrip('.') for e in v]
    return mapping


def categorize_extension(ext: str, cfg: dict | None = None) -> str:
    e = (ext or '').lower()
    mapping = category_exts(cfg)
    for cat, exts in mapping.items():
        if e in exts:
            return cat
    return 'Other'


def subfolder_for_category(cat: str, cfg: dict | None = None) -> str:
    defaults = {
        "Video": "Video",
        "Audio": "Audio",
        "Image": "Images",
        "Document": "Documents",
        "Compressed": "Compressed",
        "Program": "Programs",
        "Other": "Other",
    }
    if not cfg:
        return defaults.get(cat, 'Other')
    mapping = cfg.get('category_folders') or {}
    if not isinstance(mapping, dict):
        mapping = {}
    return str(mapping.get(cat, defaults.get(cat, 'Other')))

