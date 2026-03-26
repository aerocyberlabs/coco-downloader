/// Download scheduler (quiet-hours) state management via Riverpod.
///
/// Polls once per minute to determine whether the current wall-clock time
/// falls inside the configured quiet window.  When it does, the download
/// notifier should be paused; when it exits the window, downloads resume.
///
/// Mirrors [MainWindow._apply_scheduler] from [app.py].
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// SchedulerState
// ---------------------------------------------------------------------------

/// Immutable snapshot of the quiet-hours scheduler.
class SchedulerState {
  const SchedulerState({
    this.isInQuietHours = false,
    this.quietStart,
    this.quietEnd,
    this.isRunning = false,
  });

  /// Whether the current time is inside the configured quiet window.
  final bool isInQuietHours;

  /// Start of the quiet window in "HH:MM" 24-hour format, or null when unset.
  final String? quietStart;

  /// End of the quiet window in "HH:MM" 24-hour format, or null when unset.
  final String? quietEnd;

  /// Whether the 60-second background check timer is active.
  final bool isRunning;

  SchedulerState copyWith({
    bool? isInQuietHours,
    String? quietStart,
    String? quietEnd,
    bool? isRunning,
    bool clearQuietStart = false,
    bool clearQuietEnd = false,
  }) {
    return SchedulerState(
      isInQuietHours: isInQuietHours ?? this.isInQuietHours,
      quietStart: clearQuietStart ? null : (quietStart ?? this.quietStart),
      quietEnd: clearQuietEnd ? null : (quietEnd ?? this.quietEnd),
      isRunning: isRunning ?? this.isRunning,
    );
  }

  @override
  String toString() {
    return 'SchedulerState('
        'isInQuietHours: $isInQuietHours, '
        'quietStart: $quietStart, '
        'quietEnd: $quietEnd, '
        'isRunning: $isRunning'
        ')';
  }
}

// ---------------------------------------------------------------------------
// SchedulerNotifier
// ---------------------------------------------------------------------------

/// Checks the quiet-hours window at 60-second intervals.
class SchedulerNotifier extends StateNotifier<SchedulerState> {
  SchedulerNotifier() : super(const SchedulerState());

  Timer? _timer;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Start / stop
  // -------------------------------------------------------------------------

  /// Start the 60-second polling loop with the given [quietStart] and
  /// [quietEnd] window strings ("HH:MM").
  ///
  /// An immediate check is performed before the first timer tick.
  void start(String quietStart, String quietEnd) {
    stop();
    state = state.copyWith(
      quietStart: quietStart,
      quietEnd: quietEnd,
      isRunning: true,
    );
    _checkQuietHours();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _checkQuietHours());
  }

  /// Stop the polling loop and clear the quiet-hours window.
  void stop() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(
      isRunning: false,
      isInQuietHours: false,
      clearQuietStart: true,
      clearQuietEnd: true,
    );
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  /// Compare the current wall-clock time against the configured window and
  /// update [SchedulerState.isInQuietHours].
  ///
  /// Handles wrap-around midnight (e.g. 23:00–06:00) correctly.
  void _checkQuietHours() {
    final start = state.quietStart;
    final end = state.quietEnd;

    if (start == null || start.isEmpty || end == null || end.isEmpty) {
      state = state.copyWith(isInQuietHours: false);
      return;
    }

    final startMinutes = _parseHhmm(start);
    final endMinutes = _parseHhmm(end);

    if (startMinutes == null || endMinutes == null) {
      state = state.copyWith(isInQuietHours: false);
      return;
    }

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final inWindow = _isInWindow(currentMinutes, startMinutes, endMinutes);
    if (inWindow != state.isInQuietHours) {
      state = state.copyWith(isInQuietHours: inWindow);
    }
  }

  /// Parse an "HH:MM" string into minutes-since-midnight.
  ///
  /// Returns null on parse failure.
  static int? _parseHhmm(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  /// Return true when [currentMinutes] is inside the window defined by
  /// [startMin]–[endMin], handling wrap-around midnight.
  static bool _isInWindow(int currentMinutes, int startMin, int endMin) {
    if (startMin == endMin) return false; // No-op window.

    if (startMin < endMin) {
      // Simple case: window does not cross midnight.
      // e.g. 02:00 – 06:00
      return currentMinutes >= startMin && currentMinutes < endMin;
    } else {
      // Window crosses midnight.
      // e.g. 23:00 – 06:00
      return currentMinutes >= startMin || currentMinutes < endMin;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global scheduler (quiet-hours) provider.
final schedulerProvider =
    StateNotifierProvider<SchedulerNotifier, SchedulerState>((ref) {
  final notifier = SchedulerNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});
