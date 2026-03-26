/// Download orchestration state management via Riverpod.
///
/// The [DownloadNotifier] manages the full download lifecycle:
///   - Starting / stopping the aria2c process via [Aria2ProcessService].
///   - Adding URIs to aria2 and maintaining a GID ↔ link mapping.
///   - A 500 ms polling timer that updates per-file progress via
///     [previewProvider] and computes aggregate statistics.
///   - Pause / resume / cancel at both the global and per-item level.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_item.dart';
import '../models/file_progress.dart';
import '../services/aria2/aria2_client.dart';
import '../services/aria2/aria2_process.dart';
import '../services/download_manager.dart';
import '../services/url_classifier.dart';
import 'log_provider.dart';
import 'preview_provider.dart';

// ---------------------------------------------------------------------------
// DownloadState
// ---------------------------------------------------------------------------

/// Immutable snapshot of the download-session status.
class DownloadState {
  const DownloadState({
    this.isRunning = false,
    this.isPaused = false,
    this.overallPercent = 0,
    this.globalEta = -1,
    this.activeCnt = 0,
    this.queuedCnt = 0,
    this.aria2Pid,
  });

  /// Whether a download session is currently active.
  final bool isRunning;

  /// Whether all downloads are paused.
  final bool isPaused;

  /// Aggregate completion percentage 0–100 across all queued/active items.
  final int overallPercent;

  /// Estimated seconds until all downloads complete; -1 when unknown.
  final int globalEta;

  /// Number of currently active (downloading) items.
  final int activeCnt;

  /// Number of queued (waiting) items.
  final int queuedCnt;

  /// PID of the managed aria2c process, or null when not running.
  final int? aria2Pid;

  DownloadState copyWith({
    bool? isRunning,
    bool? isPaused,
    int? overallPercent,
    int? globalEta,
    int? activeCnt,
    int? queuedCnt,
    int? aria2Pid,
    bool clearPid = false,
  }) {
    return DownloadState(
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      overallPercent: overallPercent ?? this.overallPercent,
      globalEta: globalEta ?? this.globalEta,
      activeCnt: activeCnt ?? this.activeCnt,
      queuedCnt: queuedCnt ?? this.queuedCnt,
      aria2Pid: clearPid ? null : (aria2Pid ?? this.aria2Pid),
    );
  }

  @override
  String toString() {
    return 'DownloadState('
        'isRunning: $isRunning, '
        'isPaused: $isPaused, '
        'overall: $overallPercent%, '
        'active: $activeCnt, '
        'queued: $queuedCnt'
        ')';
  }
}

// ---------------------------------------------------------------------------
// DownloadNotifier
// ---------------------------------------------------------------------------

/// Orchestrates aria2c-based downloads and surfaces aggregate progress to the
/// widget tree.
class DownloadNotifier extends StateNotifier<DownloadState> {
  DownloadNotifier(this._ref) : super(const DownloadState());

  final Ref _ref;

  // aria2 process and RPC client.
  final _aria2 = Aria2ProcessService();
  Aria2RpcClient? _client;

  // GID → original link mapping so progress updates can be routed back to the
  // correct [DownloadItem].
  final _gidToLink = <String, String>{};

  // Polling timer.
  Timer? _pollTimer;

  // Tracks items whose downloadUrl we already know (already unrestricted).
  // link → downloadUrl
  final _resolvedUrls = <String, String>{};

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _aria2.stop();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Start
  // -------------------------------------------------------------------------

  /// Start downloading [items] into [outdir].
  ///
  /// Launches aria2c, adds all selected non-excluded items as URIs, and begins
  /// the 500 ms progress-polling timer.
  ///
  /// Parameters mirror the aria2c launch options exposed in the Python GUI.
  Future<void> startDownload({
    required List<DownloadItem> items,
    required String outdir,
    int connections = 16,
    int splits = 16,
    int concurrent = 4,
    String? token,
    String? httpProxy,
    String? httpsProxy,
    List<String>? headers,
    String? aria2Path,
    bool autoCategorize = true,
    Map<String, List<String>>? categoryExts,
    Map<String, String>? categoryFolders,
  }) async {
    if (state.isRunning) return;

    final log = _ref.read(logProvider.notifier);
    log.log('Starting aria2c…');

    try {
      _client = await _aria2.start(
        outdir: outdir,
        connections: connections,
        splits: splits,
        concurrent: concurrent,
        httpProxy: httpProxy,
        httpsProxy: httpsProxy,
        headers: headers,
        aria2Path: aria2Path,
      );

      state = state.copyWith(
        isRunning: true,
        isPaused: false,
        overallPercent: 0,
        globalEta: -1,
        activeCnt: 0,
        queuedCnt: 0,
        aria2Pid: _aria2.pid,
      );

      log.log('aria2c started (pid: ${_aria2.pid})');

      // Build download manager for directory computation.
      final manager = DownloadManager(
        baseDir: outdir,
        classifier: URLClassifier(),
      );

      // Add all selected, non-excluded items.
      final toAdd = items.where((i) => i.selected && !i.excluded).toList();

      for (final item in toAdd) {
        try {
          await _addItem(
            item: item,
            manager: manager,
            outdir: outdir,
            connections: connections,
            splits: splits,
            autoCategorize: autoCategorize,
            categoryExts: categoryExts,
            categoryFolders: categoryFolders,
          );
        } catch (e) {
          log.log('Failed to add ${item.name}: $e');
          _ref.read(previewProvider.notifier).updateItemStatus(
                item.link,
                DownloadStatus.error,
              );
        }
      }

      // Start polling.
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _pollProgress(),
      );
    } catch (e) {
      log.log('Failed to start aria2c: $e');
      state = const DownloadState();
    }
  }

  // -------------------------------------------------------------------------
  // Pause / Resume / Cancel
  // -------------------------------------------------------------------------

  /// Pause all active downloads.
  Future<void> pause() async {
    if (!state.isRunning || state.isPaused) return;
    try {
      await _client?.pauseAll();
      state = state.copyWith(isPaused: true);
      _ref.read(logProvider.notifier).log('All downloads paused.');
    } catch (e) {
      _ref.read(logProvider.notifier).log('Pause failed: $e');
    }
  }

  /// Resume all paused downloads.
  Future<void> resume() async {
    if (!state.isRunning || !state.isPaused) return;
    try {
      await _client?.unpauseAll();
      state = state.copyWith(isPaused: false);
      _ref.read(logProvider.notifier).log('Downloads resumed.');
    } catch (e) {
      _ref.read(logProvider.notifier).log('Resume failed: $e');
    }
  }

  /// Cancel all downloads and shut down aria2c.
  Future<void> cancel() async {
    _pollTimer?.cancel();
    _pollTimer = null;

    try {
      await _aria2.stop();
    } catch (_) {}

    _client = null;
    _gidToLink.clear();
    _resolvedUrls.clear();

    state = const DownloadState();
    _ref.read(logProvider.notifier).log('Downloads cancelled.');
  }

  // -------------------------------------------------------------------------
  // Per-item controls
  // -------------------------------------------------------------------------

  /// Pause the download whose original link is [link].
  Future<void> pauseItem(String link) async {
    final gid = _gidForLink(link);
    if (gid == null) return;
    try {
      await _client?.pause(gid);
      _ref.read(previewProvider.notifier).updateItemStatus(
            link,
            DownloadStatus.paused,
          );
    } catch (e) {
      _ref.read(logProvider.notifier).log('Pause($link) failed: $e');
    }
  }

  /// Resume the download whose original link is [link].
  Future<void> resumeItem(String link) async {
    final gid = _gidForLink(link);
    if (gid == null) return;
    try {
      await _client?.unpause(gid);
      _ref.read(previewProvider.notifier).updateItemStatus(
            link,
            DownloadStatus.active,
          );
    } catch (e) {
      _ref.read(logProvider.notifier).log('Resume($link) failed: $e');
    }
  }

  /// Cancel and remove the download whose original link is [link].
  Future<void> cancelItem(String link) async {
    final gid = _gidForLink(link);
    if (gid == null) return;
    try {
      await _client?.forceRemove(gid);
      _gidToLink.remove(gid);
      _ref.read(previewProvider.notifier).updateItemStatus(
            link,
            DownloadStatus.removed,
          );
    } catch (e) {
      _ref.read(logProvider.notifier).log('Cancel($link) failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Private: add item to aria2
  // -------------------------------------------------------------------------

  Future<void> _addItem({
    required DownloadItem item,
    required DownloadManager manager,
    required String outdir,
    required int connections,
    required int splits,
    required bool autoCategorize,
    Map<String, List<String>>? categoryExts,
    Map<String, String>? categoryFolders,
  }) async {
    final client = _client;
    if (client == null) return;

    // Resolve download URL: prefer already-unrestricted URL, fall back to link.
    final downloadUrl = _resolvedUrls[item.link] ?? item.downloadUrl ?? item.link;

    final opts = manager.aria2OptionsForEntry(
      name: item.name,
      baseDir: outdir,
      autoCategorize: autoCategorize,
      customExts: categoryExts,
      customFolders: categoryFolders,
    );

    final aria2Opts = <String, String>{
      'out': opts['out'] ?? item.name,
      'dir': opts['dir'] ?? outdir,
      'max-connection-per-server': connections.toString(),
      'split': splits.toString(),
    };

    final gid = await client.addUri([downloadUrl], options: aria2Opts);
    _gidToLink[gid] = item.link;

    _ref.read(previewProvider.notifier)
      ..assignGid(item.link, gid)
      ..updateItemStatus(item.link, DownloadStatus.active);
  }

  // -------------------------------------------------------------------------
  // Private: progress polling
  // -------------------------------------------------------------------------

  Future<void> _pollProgress() async {
    final client = _client;
    if (client == null) return;

    try {
      final active = await client.tellActive();
      final waiting = await client.tellWaiting(0, 200);
      final stopped = await client.tellStopped(0, 200);

      final previewNotifier = _ref.read(previewProvider.notifier);

      int totalLength = 0;
      int completedLength = 0;
      int totalSpeed = 0;

      // Process active tasks.
      for (final task in active) {
        final link = _gidToLink[task.gid];
        if (link == null) continue;

        final len = task.totalLength;
        final done = task.completedLength;
        final spd = task.downloadSpeed;

        totalLength += len;
        completedLength += done;
        totalSpeed += spd;

        final pct = len > 0 ? ((done / len) * 100).clamp(0, 100).toInt() : 0;
        final eta = spd > 0 && len > done
            ? ((len - done) / spd).round()
            : -1;

        previewNotifier.updateItemProgress(FileProgress(
          link: link,
          percent: pct,
          speed: spd,
          eta: eta,
          status: 'active',
        ));
      }

      // Process waiting tasks.
      for (final task in waiting) {
        final link = _gidToLink[task.gid];
        if (link == null) continue;

        totalLength += task.totalLength;
        completedLength += task.completedLength;

        previewNotifier.updateItemProgress(FileProgress(
          link: link,
          percent: 0,
          speed: 0,
          eta: -1,
          status: 'waiting',
        ));
      }

      // Process stopped (completed / error) tasks.
      for (final task in stopped) {
        final link = _gidToLink[task.gid];
        if (link == null) continue;

        final isError = task.status == 'error';
        previewNotifier.updateItemProgress(FileProgress(
          link: link,
          percent: isError ? 0 : 100,
          speed: 0,
          eta: 0,
          status: isError ? 'error' : 'complete',
        ));
      }

      // Compute aggregate stats.
      final overallPct = totalLength > 0
          ? ((completedLength / totalLength) * 100).clamp(0, 100).toInt()
          : 0;
      final globalEta = totalSpeed > 0 && totalLength > completedLength
          ? ((totalLength - completedLength) / totalSpeed).round()
          : -1;

      // Check whether all tasks are done.
      final allDone = active.isEmpty && waiting.isEmpty;
      final wasRunning = state.isRunning;

      state = state.copyWith(
        activeCnt: active.length,
        queuedCnt: waiting.length,
        overallPercent: overallPct,
        globalEta: globalEta,
      );

      if (allDone && wasRunning) {
        _ref.read(logProvider.notifier).log('All downloads complete.');
        _pollTimer?.cancel();
        _pollTimer = null;
        state = state.copyWith(isRunning: false, overallPercent: 100, globalEta: 0);
      }
    } catch (_) {
      // Transient RPC errors during polling are non-fatal; the timer will
      // retry on the next tick.
    }
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  String? _gidForLink(String link) {
    for (final entry in _gidToLink.entries) {
      if (entry.value == link) return entry.key;
    }
    return null;
  }

  /// Register a pre-resolved download URL for [link].
  ///
  /// Call this before [startDownload] when the caller has already obtained
  /// the direct download URL via Real-Debrid unrestriction.
  void registerResolvedUrl(String link, String downloadUrl) {
    _resolvedUrls[link] = downloadUrl;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global download-session provider.
final downloadProvider =
    StateNotifierProvider<DownloadNotifier, DownloadState>((ref) {
  return DownloadNotifier(ref);
});
