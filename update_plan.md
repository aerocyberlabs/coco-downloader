# Project Update Plan

This plan lists prioritized, actionable steps to improve the downloader. We will mark items as completed as we finish them.

Legend: [ ] pending, [x] completed, [>] in progress

## Phase 1 — High-Impact Immediate
1. [x] Drive global progress via overall percent
2. [x] Add Active/Queued counters in UI
3. [x] Persist column layout and sort
4. [x] Row context menu (Pause/Resume/Cancel/Open)
5. [x] Enable aria2 session persistence

## Phase 2 — Aria2 Integration
6. [x] Detect missing aria2c and show install hint
7. [x] RPC resilience with backoff/retry
8. [x] Map all task URIs for correlation
9. [x] Small wait after forceShutdown

## Phase 3 — Direct Downloads Polish
10. [x] Handle unknown size (ETA dash)
11. [x] GET range probe when HEAD lacks size
12. [x] Smart naming and conflict policy

## Phase 4 — Real‑Debrid & Torrents
13. [x] RD rate limit/backoff handling
14. [x] Cache hosts regex with TTL
15. [x] Detect v2-only torrents and message
16. [x] RD torrent info progress/status

## Phase 5 — Config & Security
17. [x] Keyring storage for token
18. [x] Proxy and headers UI support

## Phase 6 — Errors & Logging
19. [x] Normalize error messages (friendlier RD + RPC logs)
20. [x] Log to file with rotation

## Phase 7 — UI/UX Extras
21. [x] System notifications (done/error)
22. [x] Drag & drop (URLs/torrents/text)
23. [x] Completed downloads history

## Phase 8 — Architecture & Quality
24. [ ] Modularize into ui/core/utils (in progress: ui/dialogs, utils/*, core/download_manager)
25. [x] DownloadItem dataclass + typed signals (added models.py; typed file updates)
26. [x] Type hints and mypy checks (config added)

## Phase 9 — Testing & Tooling
27. [x] Unit tests for URL/RD utils (expanded: categories/format/urltools/manager + edge cases)
28. [x] Lint/format (ruff/black) + pre-commit config
29. [x] CI (GitHub Actions) for lint/tests

## Phase 10 — Packaging
30. [x] PyInstaller spec added; includes optional bin/ tree for aria2 binaries
31. [x] Runtime selection of bundled aria2 per OS (auto-detect and save aria2_path)

## Phase 11 — Help & Docs
32. [x] Help dialog with tabs (Overview, Getting Started, Controls, Settings, Troubleshooting)

## Phase 12 — Potential Features
33. [x] Scheduler and timed limits
34. [x] Clipboard watcher (auto-add prompt)
35. [x] Queue import/export
36. [x] Post-processing (zip extract)
37. [x] Provider plugins (yt-dlp) (optional helper)
## Phase 13 — Innovative Features (Cross‑Platform)
36. [x] Power‑aware bandwidth and concurrency (detect battery/AC, adapt)
37. [x] Encrypted download vault (optional on‑the‑fly encryption of completed files)
38. [x] Duplicate detection and deduplication (hashing, smart rename/move)
39. [>] Smart segment auto‑tuning per host (adjust splits based on throughput)
40. [x] Metadata‑based auto‑rename (audio/video tags → tidy filenames)
41. [x] Page URL expansion (parse a webpage and enqueue assets with filters)
42. [x] Privacy mode: per‑host header rules + user‑agent rotation
