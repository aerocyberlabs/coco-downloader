/// Clipboard monitoring state management via Riverpod.
///
/// Polls the system clipboard every 1500 ms and surfaces any newly-detected
/// HTTP/HTTPS URL as [ClipboardState.pendingUrl] so the UI can prompt the
/// user to add it to the download queue.
///
/// Mirrors the `_check_clipboard` / `_clip_timer` logic from [app.py].
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// ClipboardState
// ---------------------------------------------------------------------------

/// Immutable snapshot of the clipboard monitor.
class ClipboardState {
  const ClipboardState({
    this.pendingUrl,
    this.isMonitoring = false,
  });

  /// A newly-detected URL from the clipboard waiting for user action, or null.
  final String? pendingUrl;

  /// Whether the background clipboard polling timer is active.
  final bool isMonitoring;

  ClipboardState copyWith({
    String? pendingUrl,
    bool? isMonitoring,
    bool clearPending = false,
  }) {
    return ClipboardState(
      pendingUrl: clearPending ? null : (pendingUrl ?? this.pendingUrl),
      isMonitoring: isMonitoring ?? this.isMonitoring,
    );
  }

  @override
  String toString() {
    return 'ClipboardState(isMonitoring: $isMonitoring, pendingUrl: $pendingUrl)';
  }
}

// ---------------------------------------------------------------------------
// ClipboardNotifier
// ---------------------------------------------------------------------------

/// Monitors the system clipboard for HTTP/HTTPS URLs.
class ClipboardNotifier extends StateNotifier<ClipboardState> {
  ClipboardNotifier() : super(const ClipboardState());

  Timer? _timer;

  /// The last clipboard text we acted on, so we don't re-prompt for the same URL.
  String _lastSeen = '';

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
  // Monitoring
  // -------------------------------------------------------------------------

  /// Begin polling the clipboard every 1500 ms.
  ///
  /// Safe to call multiple times – subsequent calls are no-ops while already
  /// monitoring.
  void startMonitoring() {
    if (state.isMonitoring) return;
    state = state.copyWith(isMonitoring: true);
    _timer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _checkClipboard(),
    );
  }

  /// Stop clipboard polling.
  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(isMonitoring: false, clearPending: true);
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  /// Dismiss the pending URL without acting on it.
  void dismissPending() {
    if (state.pendingUrl != null) {
      _lastSeen = state.pendingUrl!;
    }
    state = state.copyWith(clearPending: true);
  }

  /// Accept the pending URL: returns it (for the caller to enqueue) and clears
  /// [pendingUrl].
  ///
  /// Returns null when there is no pending URL.
  String? acceptPending() {
    final url = state.pendingUrl;
    if (url == null) return null;
    _lastSeen = url;
    state = state.copyWith(clearPending: true);
    return url;
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';

      if (text.isEmpty) return;
      if (text == _lastSeen) return;
      if (text == state.pendingUrl) return;

      // Only surface HTTP/HTTPS or magnet URLs.
      if (!_isInterestingUrl(text)) {
        _lastSeen = text; // Suppress future noise from the same text.
        return;
      }

      state = state.copyWith(pendingUrl: text);
    } catch (_) {
      // Clipboard access may fail on some platforms – silently ignore.
    }
  }

  /// Returns true for URLs the app is interested in downloading.
  bool _isInterestingUrl(String text) {
    // Single-line only.
    if (text.contains('\n')) return false;
    if (text.length > 2048) return false;

    if (text.startsWith('http://') || text.startsWith('https://')) {
      return true;
    }
    if (text.startsWith('magnet:?')) return true;

    return false;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global clipboard monitor provider.
final clipboardProvider =
    StateNotifierProvider<ClipboardNotifier, ClipboardState>((ref) {
  final notifier = ClipboardNotifier();
  // StateNotifier.dispose() is called automatically by Riverpod; no ref.onDispose needed.
  return notifier;
});
