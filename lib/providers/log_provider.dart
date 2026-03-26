/// Log state management via Riverpod.
///
/// Provides an append-only log list with automatic trimming to a maximum of
/// 1000 lines.  All messages are prefixed with an ISO-8601 timestamp,
/// mirroring the Python GUI's log_box behaviour.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// LogNotifier
// ---------------------------------------------------------------------------

/// Maximum number of log lines retained before the oldest entries are dropped.
const _kMaxLogLines = 1000;

/// Manages an ordered list of timestamped log messages.
///
/// Example:
/// ```dart
/// ref.read(logProvider.notifier).log('Download started');
/// final lines = ref.watch(logProvider);
/// ```
class LogNotifier extends StateNotifier<List<String>> {
  LogNotifier() : super(const []);

  // -------------------------------------------------------------------------
  // Append
  // -------------------------------------------------------------------------

  /// Append [message] with a leading UTC timestamp.
  ///
  /// Messages are formatted as: `[HH:MM:SS] message`
  /// When the list exceeds [_kMaxLogLines] the oldest entries are trimmed.
  void log(String message) {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final entry = '[$h:$m:$s] $message';

    final updated = [...state, entry];
    if (updated.length > _kMaxLogLines) {
      state = updated.sublist(updated.length - _kMaxLogLines);
    } else {
      state = updated;
    }
  }

  // -------------------------------------------------------------------------
  // Clear
  // -------------------------------------------------------------------------

  /// Remove all log entries.
  void clear() {
    state = const [];
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global log provider.
///
/// Widgets reading this provider will rebuild whenever a new log entry is
/// appended or the log is cleared.  For high-frequency updates prefer
/// listening to a scroll controller rather than rebuilding the full list on
/// every append.
final logProvider = StateNotifierProvider<LogNotifier, List<String>>((ref) {
  return LogNotifier();
});
