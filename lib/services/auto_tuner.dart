/// Auto-connection-count tuner for aria2c downloads.
///
/// Dart port of [_maybe_adjust_task()] from [workers.py].
/// Uses an exponential moving average (EMA) of download speed to decide
/// whether to increase or decrease the per-server connection count for a
/// given aria2 GID.
library;

import 'package:flutter/foundation.dart';

/// Suggested connection-count change for a single aria2 GID.
class AdjustResult {
  const AdjustResult({required this.gid, required this.newConnections});

  /// The aria2 GID this adjustment applies to.
  final String gid;

  /// Recommended new value for `max-connection-per-server`.
  final int newConnections;

  @override
  String toString() =>
      'AdjustResult(gid: $gid, newConnections: $newConnections)';
}

/// Per-GID EMA state tracked internally by [AutoTuner].
class _GidState {
  _GidState({required this.emaSpeedBps, required this.lastAdjustMs});

  /// Smoothed speed in bytes/s.
  double emaSpeedBps;

  /// [DateTime.now().millisecondsSinceEpoch] of the last adjustment.
  int lastAdjustMs;
}

/// Heuristic auto-tuner that adjusts aria2 connection counts based on speed.
///
/// Mirrors the Python [_maybe_adjust_task()] logic inside [DownloadWorker]:
///
///   - Speed is smoothed with an EMA using [tuneEmaAlpha].
///   - If the smoothed speed falls below [tuneMinKib] KiB/s **and** the
///     current connection count is below [tuneMaxConn], increase by 1.
///   - If the smoothed speed exceeds `tuneMinKib * 10` KiB/s **and** the
///     current connection count is above [tuneMinConn], decrease by 1.
///   - Adjustments are rate-limited to at most once per [tuneIntervalSec].
///
/// The caller is responsible for applying the returned [AdjustResult] to aria2
/// via its RPC interface. [AutoTuner] only computes recommendations.
class AutoTuner {
  AutoTuner({
    this.enableAutoTune = false,
    this.tuneMinKib = 64,
    this.tuneMaxConn = 16,
    this.tuneMinConn = 1,
    this.tuneIntervalSec = 20,
    this.tuneEmaAlpha = 0.3,
  });

  /// Whether the auto-tuner should produce recommendations.
  final bool enableAutoTune;

  /// Minimum speed threshold in KiB/s before increasing connections.
  final int tuneMinKib;

  /// Maximum connection count the tuner may recommend.
  final int tuneMaxConn;

  /// Minimum connection count the tuner may recommend.
  final int tuneMinConn;

  /// Minimum seconds between adjustments for the same GID.
  final int tuneIntervalSec;

  /// EMA smoothing factor (0 < alpha <= 1).
  /// Higher values make the EMA more responsive; lower values smooth more.
  final double tuneEmaAlpha;

  /// Internal per-GID EMA state.
  final Map<String, _GidState> _state = {};

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Evaluate whether the connection count for [gid] should be changed.
  ///
  /// [currentSpeedBps] is the instantaneous download speed in bytes/s as
  /// reported by aria2.
  /// [currentConnections] is the current `max-connection-per-server` value.
  ///
  /// Returns an [AdjustResult] when a change is recommended, or `null` when
  /// no change is needed / the interval has not elapsed yet.
  AdjustResult? evaluate(
    String gid,
    int currentSpeedBps,
    int currentConnections,
  ) {
    if (!enableAutoTune) return null;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final intervalMs = tuneIntervalSec * 1000;
    // Minimum guard mirrors the Python `max(5, tune_interval)`.
    final minIntervalMs = (tuneIntervalSec > 5 ? tuneIntervalSec : 5) * 1000;

    final existing = _state[gid];
    if (existing != null) {
      if (nowMs - existing.lastAdjustMs < minIntervalMs) {
        // Update EMA even when not adjusting, so it stays fresh.
        existing.emaSpeedBps =
            tuneEmaAlpha * currentSpeedBps +
            (1 - tuneEmaAlpha) * existing.emaSpeedBps;
        return null;
      }
      // EMA update for the current tick.
      existing.emaSpeedBps =
          tuneEmaAlpha * currentSpeedBps +
          (1 - tuneEmaAlpha) * existing.emaSpeedBps;
    } else {
      // First observation – seed EMA with the current speed.
      _state[gid] = _GidState(
        emaSpeedBps: currentSpeedBps.toDouble(),
        lastAdjustMs: nowMs - intervalMs, // Allow first check immediately.
      );
      return null; // Need at least one EMA cycle before recommending.
    }

    final speedKib = existing.emaSpeedBps / 1024.0;
    final target = _computeTarget(speedKib, currentConnections);

    if (target == currentConnections) return null;

    existing.lastAdjustMs = nowMs;
    debugPrint(
      '[AutoTuner] gid=$gid speed=${speedKib.toStringAsFixed(1)} KiB/s '
      'conn: $currentConnections -> $target',
    );
    return AdjustResult(gid: gid, newConnections: target);
  }

  /// Reset all per-GID state (call when a new download session begins).
  void clear() => _state.clear();

  /// Remove state for a single [gid] (call when a download completes).
  void remove(String gid) => _state.remove(gid);

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  int _computeTarget(double speedKib, int currentConnections) {
    final thresholdKib = tuneMinKib.toDouble();

    if (speedKib < thresholdKib && currentConnections < tuneMaxConn) {
      return (currentConnections + 1).clamp(tuneMinConn, tuneMaxConn);
    }

    if (speedKib > thresholdKib * 10 && currentConnections > tuneMinConn) {
      return (currentConnections - 1).clamp(tuneMinConn, tuneMaxConn);
    }

    return currentConnections;
  }
}
