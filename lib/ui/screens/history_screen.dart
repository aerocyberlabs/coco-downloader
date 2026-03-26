/// History screen — shows completed download history with sort and clear.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/history_entry.dart';
import '../../providers/config_provider.dart';

enum _SortColumn { timestamp, filename, directory, link }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _SortColumn _sortCol = _SortColumn.timestamp;
  bool _sortAsc = false;

  List<HistoryEntry> _sorted(List<HistoryEntry> entries) {
    final list = List<HistoryEntry>.from(entries);
    list.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case _SortColumn.timestamp:
          cmp = a.when.compareTo(b.when);
        case _SortColumn.filename:
          cmp = a.file.compareTo(b.file);
        case _SortColumn.directory:
          cmp = a.outdir.compareTo(b.outdir);
        case _SortColumn.link:
          cmp = a.link.compareTo(b.link);
      }
      return _sortAsc ? cmp : -cmp;
    });
    return list;
  }

  void _setSort(_SortColumn col) {
    setState(() {
      if (_sortCol == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortCol = col;
        _sortAsc = true;
      }
    });
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Remove all download history entries?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(configProvider.notifier).updateConfig(
            (c) => c.copyWith(history: []),
          );
    }
  }

  DataColumn _col(String label, _SortColumn col) {
    return DataColumn(
      label: Text(label),
      onSort: (_, __) => _setSort(col),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(configProvider).history;
    final sorted = _sorted(history);

    return Scaffold(
      appBar: AppBar(
        title: Text('History (${history.length})'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear history',
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: history.isEmpty
          ? const Center(child: Text('No download history yet.'))
          : SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  sortColumnIndex: _SortColumn.values.indexOf(_sortCol),
                  sortAscending: _sortAsc,
                  columns: [
                    _col('Timestamp', _SortColumn.timestamp),
                    _col('Filename', _SortColumn.filename),
                    _col('Directory', _SortColumn.directory),
                    _col('Link', _SortColumn.link),
                  ],
                  rows: sorted.map((entry) {
                    return DataRow(cells: [
                      DataCell(Text(entry.when)),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: Text(
                            entry.file,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: Text(
                            entry.outdir,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            entry.link,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
            ),
    );
  }
}
