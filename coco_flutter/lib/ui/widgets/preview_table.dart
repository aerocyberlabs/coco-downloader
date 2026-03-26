/// PreviewTable — scrollable download-queue table using DataTable2.
///
/// Columns: Select (checkbox), Name, Size, Type, Source, %, Speed, ETA, Status
///
/// Features:
///   - Rows sourced from [previewProvider.filteredItems].
///   - Checkbox selection per row (delegates to [PreviewNotifier.toggleSelection]).
///   - Color-coded Status column.
///   - Right-click context menu: Pause, Resume, Cancel, Copy URL, Remove.
///   - Column header taps cycle sort order.
library;

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/download_item.dart';
import '../../providers/download_provider.dart';
import '../../providers/preview_provider.dart';
import '../../utils/format.dart';

// ---------------------------------------------------------------------------
// PreviewTable
// ---------------------------------------------------------------------------

class PreviewTable extends ConsumerStatefulWidget {
  const PreviewTable({super.key});

  @override
  ConsumerState<PreviewTable> createState() => _PreviewTableState();
}

class _PreviewTableState extends ConsumerState<PreviewTable> {
  int _sortColumnIndex = 1; // Name column
  bool _sortAscending = true;

  // -------------------------------------------------------------------------
  // Sorting helpers
  // -------------------------------------------------------------------------

  List<DownloadItem> _sorted(List<DownloadItem> items) {
    final list = List<DownloadItem>.from(items);
    list.sort((a, b) {
      int cmp;
      switch (_sortColumnIndex) {
        case 1:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 2:
          cmp = a.size.compareTo(b.size);
        case 3:
          cmp = a.category.compareTo(b.category);
        case 4:
          cmp = a.source.compareTo(b.source);
        case 5:
          cmp = a.percent.compareTo(b.percent);
        case 6:
          cmp = a.speed.compareTo(b.speed);
        case 7:
          cmp = a.eta.compareTo(b.eta);
        case 8:
          cmp = a.status.name.compareTo(b.status.name);
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return list;
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  // -------------------------------------------------------------------------
  // Status colour
  // -------------------------------------------------------------------------

  Color _statusColor(DownloadStatus status, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case DownloadStatus.active:
        return cs.tertiary;
      case DownloadStatus.completed:
        return cs.primary;
      case DownloadStatus.error:
        return cs.error;
      case DownloadStatus.paused:
        return cs.secondary;
      case DownloadStatus.queued:
        return cs.onSurfaceVariant;
      case DownloadStatus.removed:
        return cs.onSurfaceVariant.withAlpha(120);
      case DownloadStatus.excluded:
        return cs.onSurfaceVariant.withAlpha(120);
    }
  }

  // -------------------------------------------------------------------------
  // Context menu
  // -------------------------------------------------------------------------

  void _showContextMenu(
    BuildContext context,
    Offset position,
    DownloadItem item,
  ) {
    final downloadNotifier = ref.read(downloadProvider.notifier);
    final previewNotifier = ref.read(previewProvider.notifier);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        const PopupMenuItem(value: 'pause', child: Text('Pause')),
        const PopupMenuItem(value: 'resume', child: Text('Resume')),
        const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'copy', child: Text('Copy URL')),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'remove',
          child: Text('Remove from list'),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'pause':
          downloadNotifier.pauseItem(item.link);
        case 'resume':
          downloadNotifier.resumeItem(item.link);
        case 'cancel':
          downloadNotifier.cancelItem(item.link);
        case 'copy':
          Clipboard.setData(ClipboardData(text: item.downloadUrl ?? item.link));
        case 'remove':
          previewNotifier.removeItem(item.id);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final previewState = ref.watch(previewProvider);
    final items = _sorted(previewState.filteredItems);
    final cs = Theme.of(context).colorScheme;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              previewState.isLoading
                  ? 'Loading…'
                  : 'No files — paste a link above to get started.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (previewState.isLoading) ...[
              const SizedBox(height: 12),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      );
    }

    return DataTable2(
      columnSpacing: 8,
      horizontalMargin: 8,
      minWidth: 700,
      sortColumnIndex: _sortColumnIndex,
      sortAscending: _sortAscending,
      headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHighest),
      columns: [
        // 0 — Select (checkbox header = select all / deselect all)
        DataColumn2(
          label: Checkbox(
            tristate: true,
            value: _allCheckedState(items),
            onChanged: (_) => _toggleAll(items),
          ),
          fixedWidth: 48,
        ),
        // 1 — Name
        DataColumn2(
          label: const Text('Name', overflow: TextOverflow.ellipsis),
          size: ColumnSize.L,
          onSort: _onSort,
        ),
        // 2 — Size
        DataColumn2(
          label: const Text('Size'),
          fixedWidth: 90,
          numeric: true,
          onSort: _onSort,
        ),
        // 3 — Type
        DataColumn2(
          label: const Text('Type'),
          fixedWidth: 90,
          onSort: _onSort,
        ),
        // 4 — Source
        DataColumn2(
          label: const Text('Source'),
          fixedWidth: 110,
          onSort: _onSort,
        ),
        // 5 — %
        DataColumn2(
          label: const Text('%'),
          fixedWidth: 52,
          numeric: true,
          onSort: _onSort,
        ),
        // 6 — Speed
        DataColumn2(
          label: const Text('Speed'),
          fixedWidth: 90,
          numeric: true,
          onSort: _onSort,
        ),
        // 7 — ETA
        DataColumn2(
          label: const Text('ETA'),
          fixedWidth: 72,
          onSort: _onSort,
        ),
        // 8 — Status
        DataColumn2(
          label: const Text('Status'),
          fixedWidth: 88,
          onSort: _onSort,
        ),
      ],
      rows: items.map((item) => _buildRow(context, item)).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // Row builder
  // -------------------------------------------------------------------------

  DataRow2 _buildRow(BuildContext context, DownloadItem item) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(item.status, context);
    final isExcluded = item.excluded;

    Color? rowColor;
    if (isExcluded) {
      rowColor = cs.surfaceContainerHighest.withAlpha(60);
    }

    return DataRow2(
      color: rowColor != null ? WidgetStateProperty.all(rowColor) : null,
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition, item);
      },
      cells: [
        // 0 — Checkbox
        DataCell(
          Checkbox(
            value: item.selected,
            onChanged: isExcluded
                ? null
                : (_) => ref
                    .read(previewProvider.notifier)
                    .toggleSelection(item.id),
          ),
        ),

        // 1 — Name
        DataCell(
          Tooltip(
            message: item.name,
            child: Text(
              item.name,
              overflow: TextOverflow.ellipsis,
              style: isExcluded
                  ? TextStyle(
                      color: cs.onSurface.withAlpha(100),
                      decoration: TextDecoration.lineThrough,
                    )
                  : null,
            ),
          ),
        ),

        // 2 — Size
        DataCell(
          Text(
            item.size > 0 ? humanSize(item.size) : '—',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),

        // 3 — Type
        DataCell(Text(item.category, style: Theme.of(context).textTheme.bodySmall)),

        // 4 — Source
        DataCell(
          Text(
            item.source.isEmpty ? '—' : item.source,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),

        // 5 — %
        DataCell(
          Text(
            item.status == DownloadStatus.active ||
                    item.status == DownloadStatus.completed
                ? '${item.percent}%'
                : '—',
            style: TextStyle(
              fontSize: 12,
              color: item.percent > 0 ? Theme.of(context).colorScheme.tertiary : null,
              fontWeight:
                  item.percent > 0 ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),

        // 6 — Speed
        DataCell(
          Text(
            item.speed > 0 ? formatSpeed(item.speed) : '—',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),

        // 7 — ETA
        DataCell(
          Text(
            item.eta >= 0 ? formatEta(item.eta) : '—',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),

        // 8 — Status
        DataCell(
          Text(
            item.status.toJson(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Select-all header helpers
  // -------------------------------------------------------------------------

  bool? _allCheckedState(List<DownloadItem> items) {
    final selectable = items.where((i) => !i.excluded).toList();
    if (selectable.isEmpty) return false;
    final selectedCount = selectable.where((i) => i.selected).length;
    if (selectedCount == 0) return false;
    if (selectedCount == selectable.length) return true;
    return null; // indeterminate
  }

  void _toggleAll(List<DownloadItem> items) {
    final notifier = ref.read(previewProvider.notifier);
    final state = _allCheckedState(items);
    if (state == true) {
      notifier.clearSelection();
    } else {
      notifier.selectAll();
    }
  }
}
