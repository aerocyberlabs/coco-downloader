/// PreviewTable — scrollable download-queue table.
///
/// Columns: Select (checkbox), Name, Size, Type, Source, %, Speed, ETA, Status
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/download_item.dart';
import '../../providers/download_provider.dart';
import '../../providers/preview_provider.dart';
import '../../utils/format.dart';

class PreviewTable extends ConsumerStatefulWidget {
  const PreviewTable({super.key});

  @override
  ConsumerState<PreviewTable> createState() => _PreviewTableState();
}

class _PreviewTableState extends ConsumerState<PreviewTable> {
  int _sortColumnIndex = 1;
  bool _sortAscending = true;

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
          cmp = a.status.index.compareTo(b.status.index);
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
        return cs.onSurfaceVariant;
      case DownloadStatus.excluded:
        return cs.onSurfaceVariant.withAlpha(120);
    }
  }

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
        position.dx, position.dy, position.dx + 1, position.dy + 1,
      ),
      items: [
        const PopupMenuItem(value: 'pause', child: Text('Pause')),
        const PopupMenuItem(value: 'resume', child: Text('Resume')),
        const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'copy', child: Text('Copy URL')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'remove', child: Text('Remove from list')),
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

  @override
  Widget build(BuildContext context) {
    final previewState = ref.watch(previewProvider);
    final items = _sorted(previewState.filteredItems);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              previewState.isLoading
                  ? 'Loading...'
                  : 'No files \u2014 paste a link above to get started.',
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: SingleChildScrollView(
              child: DataTable(
                columnSpacing: 12,
                horizontalMargin: 8,
                sortColumnIndex: _sortColumnIndex,
                sortAscending: _sortAscending,
                headingRowColor: WidgetStateProperty.all(
                  cs.surfaceContainerHighest,
                ),
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 44,
                columns: [
                  DataColumn(
                    label: Checkbox(
                      tristate: true,
                      value: _allCheckedState(items),
                      onChanged: (_) => _toggleAll(items),
                    ),
                  ),
                  DataColumn(
                    label: const Text('Name'),
                    onSort: _onSort,
                  ),
                  DataColumn(
                    label: const Text('Size'),
                    numeric: true,
                    onSort: _onSort,
                  ),
                  DataColumn(
                    label: const Text('Type'),
                    onSort: _onSort,
                  ),
                  DataColumn(
                    label: const Text('Source'),
                    onSort: _onSort,
                  ),
                  DataColumn(
                    label: const Text('%'),
                    numeric: true,
                    onSort: _onSort,
                  ),
                  DataColumn(
                    label: const Text('Speed'),
                    numeric: true,
                    onSort: _onSort,
                  ),
                  DataColumn(
                    label: const Text('ETA'),
                    onSort: _onSort,
                  ),
                  DataColumn(
                    label: const Text('Status'),
                    onSort: _onSort,
                  ),
                ],
                rows: items.map((item) => _buildRow(context, item)).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  DataRow _buildRow(BuildContext context, DownloadItem item) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(item.status, context);
    final isExcluded = item.excluded;
    final bodySmall = Theme.of(context).textTheme.bodySmall;

    return DataRow(
      color: isExcluded
          ? WidgetStateProperty.all(cs.surfaceContainerHighest.withAlpha(60))
          : null,
      cells: [
        // 0 - Checkbox
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
        // 1 - Name
        DataCell(
          GestureDetector(
            onSecondaryTapDown: (details) =>
                _showContextMenu(context, details.globalPosition, item),
            child: Tooltip(
              message: item.name,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
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
          ),
        ),
        // 2 - Size
        DataCell(Text(
          item.size > 0 ? humanSize(item.size) : '\u2014',
          style: bodySmall,
        )),
        // 3 - Type
        DataCell(Text(item.category, style: bodySmall)),
        // 4 - Source
        DataCell(ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Text(
            item.source.isEmpty ? '\u2014' : item.source,
            overflow: TextOverflow.ellipsis,
            style: bodySmall,
          ),
        )),
        // 5 - %
        DataCell(Text(
          item.status == DownloadStatus.active ||
                  item.status == DownloadStatus.completed
              ? '${item.percent}%'
              : '\u2014',
          style: TextStyle(
            fontSize: 12,
            color: item.percent > 0 ? cs.tertiary : null,
            fontWeight: item.percent > 0 ? FontWeight.w600 : FontWeight.normal,
          ),
        )),
        // 6 - Speed
        DataCell(Text(
          item.speed > 0 ? formatSpeed(item.speed) : '\u2014',
          style: bodySmall,
        )),
        // 7 - ETA
        DataCell(Text(
          item.eta >= 0 ? formatEta(item.eta) : '\u2014',
          style: bodySmall,
        )),
        // 8 - Status
        DataCell(Text(
          item.status.toJson(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: statusColor,
          ),
        )),
      ],
    );
  }

  bool? _allCheckedState(List<DownloadItem> items) {
    final selectable = items.where((i) => !i.excluded).toList();
    if (selectable.isEmpty) return false;
    final selectedCount = selectable.where((i) => i.selected).length;
    if (selectedCount == 0) return false;
    if (selectedCount == selectable.length) return true;
    return null;
  }

  void _toggleAll(List<DownloadItem> items) {
    final notifier = ref.read(previewProvider.notifier);
    final selectable = items.where((i) => !i.excluded);
    final allSelected = selectable.every((i) => i.selected);
    if (allSelected) {
      notifier.clearSelection();
    } else {
      notifier.selectAll();
    }
  }
}
