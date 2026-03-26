/// LogPanel — expandable/collapsible scrollable log output.
///
/// Features:
///   - Reads log lines from [logProvider].
///   - Auto-scrolls to the bottom when new entries are appended.
///   - Clear button to wipe log state.
///   - Monospace font, constrained to a max height of 150 px.
///   - Header row with expand/collapse toggle.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/log_provider.dart';

// ---------------------------------------------------------------------------
// LogPanel
// ---------------------------------------------------------------------------

class LogPanel extends ConsumerStatefulWidget {
  const LogPanel({super.key});

  @override
  ConsumerState<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends ConsumerState<LogPanel> {
  bool _expanded = true;
  final _scrollController = ScrollController();

  // -------------------------------------------------------------------------
  // Auto-scroll
  // -------------------------------------------------------------------------

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(logProvider);
    final cs = Theme.of(context).colorScheme;

    // Scroll to bottom when new log entries arrive.
    if (_expanded && lines.isNotEmpty) {
      _scrollToBottom();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // -------------------------------------------------------------------
        // Header row
        // -------------------------------------------------------------------
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Log',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                if (lines.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    '(${lines.length})',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant.withAlpha(160),
                        ),
                  ),
                ],
                const Spacer(),
                if (_expanded)
                  TextButton(
                    onPressed: lines.isNotEmpty
                        ? ref.read(logProvider.notifier).clear
                        : null,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
        ),

        // -------------------------------------------------------------------
        // Log lines
        // -------------------------------------------------------------------
        if (_expanded)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: Container(
              color: cs.surfaceContainerHighest.withAlpha(80),
              child: lines.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'No log entries yet.',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: cs.onSurfaceVariant.withAlpha(140),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        return Text(
                          lines[index],
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: cs.onSurface,
                            height: 1.4,
                          ),
                        );
                      },
                    ),
            ),
          ),
      ],
    );
  }
}
