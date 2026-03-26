/// GlobalStatusBar — compact status indicator row read from [downloadProvider].
///
/// Displays:
///   - Time remaining (formatted with [formatEta]).
///   - Active and queued download counts.
///   - Overall percentage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/download_provider.dart';
import '../../utils/format.dart';

// ---------------------------------------------------------------------------
// GlobalStatusBar
// ---------------------------------------------------------------------------

class GlobalStatusBar extends ConsumerWidget {
  const GlobalStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dl = ref.watch(downloadProvider);
    final cs = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
        );

    final etaText = dl.globalEta >= 0 ? formatEta(dl.globalEta) : '--:--';
    final countText = 'Active: ${dl.activeCnt} | Queued: ${dl.queuedCnt}';
    final pctText = '${dl.overallPercent}%';

    return Row(
      children: [
        // Time remaining
        if (dl.isRunning) ...[
          Icon(Icons.timer_outlined, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(etaText, style: labelStyle),
          const SizedBox(width: 16),
        ],

        // Active / queued counts
        Text(countText, style: labelStyle),

        const Spacer(),

        // Percentage
        Text(
          pctText,
          style: labelStyle?.copyWith(
            fontWeight: FontWeight.w600,
            color: dl.overallPercent > 0 ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
