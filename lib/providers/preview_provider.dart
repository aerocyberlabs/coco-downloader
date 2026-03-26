/// Preview / download-queue state management via Riverpod.
///
/// The [PreviewNotifier] is the central store for the list of [DownloadItem]s
/// shown in the preview table.  It handles link resolution, selection,
/// filtering, and live progress updates.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/download_item.dart';
import '../models/file_progress.dart';
import '../services/categories_service.dart';
import '../services/download_manager.dart';
import '../services/url_classifier.dart';
import 'config_provider.dart';
import 'log_provider.dart';

// ---------------------------------------------------------------------------
// PreviewState
// ---------------------------------------------------------------------------

/// Immutable snapshot of the preview table state.
class PreviewState {
  const PreviewState({
    this.items = const [],
    this.isLoading = false,
    this.filter = 'All',
    this.error,
  });

  /// All items currently in the preview list (unfiltered).
  final List<DownloadItem> items;

  /// True while a preview fetch is in progress.
  final bool isLoading;

  /// Active category filter: 'All', 'Video', 'Audio', 'Image', 'Document',
  /// 'Compressed', 'Program', 'Other', or 'Excluded'.
  final String filter;

  /// Error message from the last failed [fetchPreview] call, or null.
  final String? error;

  PreviewState copyWith({
    List<DownloadItem>? items,
    bool? isLoading,
    String? filter,
    String? error,
    bool clearError = false,
  }) {
    return PreviewState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      filter: filter ?? this.filter,
      error: clearError ? null : (error ?? this.error),
    );
  }

  // -------------------------------------------------------------------------
  // Derived / computed
  // -------------------------------------------------------------------------

  /// Items that pass the current [filter].
  List<DownloadItem> get filteredItems {
    if (filter == 'All') return items;
    if (filter == 'Excluded') {
      return items.where((i) => i.excluded).toList();
    }
    return items.where((i) => !i.excluded && i.category == filter).toList();
  }

  /// Number of items that are currently selected.
  int get selectedCount => items.where((i) => i.selected && !i.excluded).length;

  /// Sum of sizes for all selected (non-excluded) items in bytes.
  int get selectedTotalSize {
    return items
        .where((i) => i.selected && !i.excluded)
        .fold(0, (acc, i) => acc + i.size);
  }
}

// ---------------------------------------------------------------------------
// _uuid helper
// ---------------------------------------------------------------------------

const _uuid = Uuid();

// ---------------------------------------------------------------------------
// PreviewNotifier
// ---------------------------------------------------------------------------

/// Manages the preview list: fetching link metadata, selection, filtering, and
/// progress updates during downloads.
class PreviewNotifier extends StateNotifier<PreviewState> {
  PreviewNotifier(this._ref) : super(const PreviewState());

  final Ref _ref;

  // -------------------------------------------------------------------------
  // Fetch
  // -------------------------------------------------------------------------

  /// Resolve each link in [links] into a [DownloadItem] and populate the list.
  ///
  /// Already-existing items (matched by link) are preserved so that an
  /// in-progress download is not reset. New links are appended.
  Future<void> fetchPreview(List<String> links) async {
    if (links.isEmpty) {
      state = state.copyWith(items: const [], clearError: true);
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    final cfg = _ref.read(configProvider);

    // Build a DownloadManager backed by a URL classifier with no RD client.
    // The provider layer intentionally avoids importing rd_client to keep
    // this file testable without network access; callers that need Real-Debrid
    // unrestriction should call [updateItemStatus] after the fact or supply a
    // resolved downloadUrl.
    final classifier = URLClassifier();
    final manager = DownloadManager(
      baseDir: cfg.outdir.isEmpty ? '.' : cfg.outdir,
      classifier: classifier,
    );

    final existingByLink = {for (final i in state.items) i.link: i};
    final newItems = <DownloadItem>[];
    final errors = <String>[];

    for (final rawLink in links) {
      final link = rawLink.trim();
      if (link.isEmpty) continue;

      // Preserve existing item state (progress, gid, etc.).
      if (existingByLink.containsKey(link)) {
        newItems.add(existingByLink[link]!);
        continue;
      }

      try {
        final preview = await manager.buildPreviewItem(link);

        final name = preview.filename ?? _guessName(link);
        final ext = extFromName(name);
        final category = categorizeExtension(ext,
            customExts: cfg.categoryExts.isEmpty ? null : cfg.categoryExts);
        final excluded = cfg.excludeExt.contains(ext);

        newItems.add(DownloadItem(
          id: _uuid.v4(),
          link: link,
          name: name,
          size: preview.filesize,
          category: category,
          source: preview.host ?? 'Direct',
          status: excluded ? DownloadStatus.excluded : DownloadStatus.queued,
          selected: !excluded,
          excluded: excluded,
          extension: ext,
        ));
      } catch (e) {
        errors.add('$link: $e');
        newItems.add(DownloadItem(
          id: _uuid.v4(),
          link: link,
          name: _guessName(link),
          status: DownloadStatus.error,
          selected: false,
        ));
      }
    }

    final logNotifier = _ref.read(logProvider.notifier);
    for (final err in errors) {
      logNotifier.log('Preview error: $err');
    }

    state = state.copyWith(
      items: newItems,
      isLoading: false,
      error: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  // -------------------------------------------------------------------------
  // Selection
  // -------------------------------------------------------------------------

  /// Toggle the [DownloadItem.selected] flag for the item with [id].
  void toggleSelection(String id) {
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.id == id && !item.excluded) {
          return item.copyWith(selected: !item.selected);
        }
        return item;
      }).toList(),
    );
  }

  /// Select all non-excluded items.
  void selectAll() {
    state = state.copyWith(
      items: state.items.map((i) {
        return i.excluded ? i : i.copyWith(selected: true);
      }).toList(),
    );
  }

  /// Deselect all items.
  void clearSelection() {
    state = state.copyWith(
      items: state.items.map((i) => i.copyWith(selected: false)).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // Remove
  // -------------------------------------------------------------------------

  /// Remove all currently-selected items from the list.
  void removeSelected() {
    state = state.copyWith(
      items: state.items.where((i) => !i.selected).toList(),
    );
  }

  /// Remove the item identified by [id].
  void removeItem(String id) {
    state = state.copyWith(
      items: state.items.where((i) => i.id != id).toList(),
    );
  }

  /// Remove all items.
  void clearAll() {
    state = state.copyWith(items: const [], clearError: true);
  }

  // -------------------------------------------------------------------------
  // Filter
  // -------------------------------------------------------------------------

  /// Set the active category [filter].
  ///
  /// Valid values: 'All', 'Video', 'Audio', 'Image', 'Document', 'Compressed',
  /// 'Program', 'Other', 'Excluded'.
  void setFilter(String category) {
    state = state.copyWith(filter: category);
  }

  // -------------------------------------------------------------------------
  // Progress updates (called by DownloadNotifier during polling)
  // -------------------------------------------------------------------------

  /// Update the progress fields of the item matching [progress.link].
  void updateItemProgress(FileProgress progress) {
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.link != progress.link) return item;
        return item.copyWith(
          percent: progress.percent,
          speed: progress.speed,
          eta: progress.eta,
          status: DownloadStatus.fromString(progress.status),
        );
      }).toList(),
    );
  }

  /// Update the status of the item whose [DownloadItem.link] equals [link].
  void updateItemStatus(String link, DownloadStatus status) {
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.link != link) return item;
        return item.copyWith(status: status);
      }).toList(),
    );
  }

  /// Update the [DownloadItem.gid] for the item matching [link].
  void assignGid(String link, String gid) {
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.link != link) return item;
        return item.copyWith(gid: gid);
      }).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  String _guessName(String link) {
    try {
      final uri = Uri.parse(link);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty && segments.last.isNotEmpty) {
        return Uri.decodeComponent(segments.last);
      }
    } catch (_) {}
    return link;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global preview / download-queue provider.
final previewProvider = StateNotifierProvider<PreviewNotifier, PreviewState>((ref) {
  return PreviewNotifier(ref);
});
