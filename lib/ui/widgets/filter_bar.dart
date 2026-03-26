/// FilterBar — category filter dropdown, selection controls, concurrency, and
/// selected-total-size label.
///
/// Sits between [InputZone] and [PreviewTable] in the layout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/config_provider.dart';
import '../../providers/preview_provider.dart';
import '../../utils/format.dart';

// ---------------------------------------------------------------------------
// Filter categories
// ---------------------------------------------------------------------------

const _kCategories = [
  'All',
  'Video',
  'Audio',
  'Image',
  'Document',
  'Compressed',
  'Program',
  'Other',
  'Excluded',
];

// ---------------------------------------------------------------------------
// FilterBar
// ---------------------------------------------------------------------------

class FilterBar extends ConsumerWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewState = ref.watch(previewProvider);
    final previewNotifier = ref.read(previewProvider.notifier);
    final concurrency = ref.watch(
      configProvider.select((cfg) => cfg.concurrency),
    );

    final selectedSize = previewState.selectedTotalSize;
    final selectedCount = previewState.selectedCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // -----------------------------------------------------------------
          // Category filter dropdown
          // -----------------------------------------------------------------
          const Text('Filter:'),
          const SizedBox(width: 6),
          DropdownButton<String>(
            value: previewState.filter,
            isDense: true,
            onChanged: (v) {
              if (v != null) previewNotifier.setFilter(v);
            },
            items: _kCategories
                .map(
                  (cat) => DropdownMenuItem(
                    value: cat,
                    child: Text(cat),
                  ),
                )
                .toList(),
          ),

          const SizedBox(width: 12),

          // -----------------------------------------------------------------
          // Selection controls
          // -----------------------------------------------------------------
          TextButton(
            onPressed: previewState.items.isNotEmpty
                ? previewNotifier.selectAll
                : null,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Select All'),
          ),
          TextButton(
            onPressed: previewState.items.isNotEmpty
                ? previewNotifier.clearSelection
                : null,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Clear Selection'),
          ),
          TextButton(
            onPressed: selectedCount > 0 ? previewNotifier.removeSelected : null,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove Selected'),
          ),
          TextButton(
            onPressed: previewState.items.isNotEmpty
                ? previewNotifier.clearAll
                : null,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Clear All'),
          ),

          const SizedBox(width: 16),

          // -----------------------------------------------------------------
          // Concurrent downloads spin-box
          // -----------------------------------------------------------------
          const Text('Concurrent:'),
          const SizedBox(width: 4),
          _ConcurrencySpinner(value: concurrency),

          const Spacer(),

          // -----------------------------------------------------------------
          // Selected total size (right-aligned)
          // -----------------------------------------------------------------
          if (selectedCount > 0)
            Text(
              'Selected: $selectedCount file${selectedCount == 1 ? '' : 's'}'
              '  (${humanSize(selectedSize)})',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ConcurrencySpinner
// ---------------------------------------------------------------------------

/// A simple +/- spin box for the concurrent download count (1–8).
class _ConcurrencySpinner extends ConsumerWidget {
  const _ConcurrencySpinner({required this.value});

  final int value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove, size: 16),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          onPressed: value > 1
              ? () => ref.read(configProvider.notifier).updateConfig(
                    (c) => c.copyWith(concurrency: value - 1),
                  )
              : null,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 16),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          onPressed: value < 8
              ? () => ref.read(configProvider.notifier).updateConfig(
                    (c) => c.copyWith(concurrency: value + 1),
                  )
              : null,
        ),
      ],
    );
  }
}
