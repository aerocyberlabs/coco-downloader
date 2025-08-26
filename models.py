from dataclasses import dataclass
from typing import Optional


@dataclass
class DownloadItem:
    id: str
    link: str
    name: str
    size: int = 0
    category: str = "Other"
    source: str = ""
    status: str = "Queued"  # Queued, Active, Paused, Completed, Error, Removed
    gid: Optional[str] = None


@dataclass
class FileProgress:
    link: str
    percent: int
    speed: int
    eta: int
    status: str
