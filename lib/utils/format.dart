/// Human-readable formatting utilities for sizes, speeds, and durations.
///
/// Dart equivalents of the Python helpers in [utils/format.py].
library;

/// Converts [bytes] to a human-readable string using binary (IEC) units.
///
/// Examples:
/// ```dart
/// humanSize(0)           // '0 B'
/// humanSize(1024)        // '1.0 KiB'
/// humanSize(1536)        // '1.5 KiB'
/// humanSize(1073741824)  // '1.0 GiB'
/// ```
String humanSize(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  double n = (bytes < 0 ? 0 : bytes).toDouble();
  for (final unit in units) {
    if (n < 1024.0) {
      if (unit == 'B') {
        return '${n.toInt()} $unit';
      }
      return '${n.toStringAsFixed(1)} $unit';
    }
    n /= 1024.0;
  }
  // Overflow into PiB territory.
  return '${n.toStringAsFixed(1)} PiB';
}

/// Converts [seconds] into a human-readable duration string.
///
/// Returns `'--:--'` when [seconds] is negative or null-like (≤ 0 treated as
/// zero after clamping, but negative input returns the placeholder).
///
/// Format is `H:MM:SS` when there are hours, otherwise `M:SS`.
///
/// Examples:
/// ```dart
/// formatEta(0)     // '0:00'
/// formatEta(65)    // '1:05'
/// formatEta(3661)  // '1:01:01'
/// formatEta(-1)    // '--:--'
/// ```
String formatEta(int seconds) {
  if (seconds < 0) return '--:--';
  final s = seconds;
  final h = s ~/ 3600;
  final rem = s % 3600;
  final m = rem ~/ 60;
  final sec = rem % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
  return '$m:${sec.toString().padLeft(2, '0')}';
}

/// Converts [bytesPerSec] into a human-readable speed string with a `/s`
/// suffix using binary (IEC) units.
///
/// Examples:
/// ```dart
/// formatSpeed(0)       // '0 B/s'
/// formatSpeed(512)     // '512 B/s'
/// formatSpeed(1024)    // '1.0 KiB/s'
/// formatSpeed(1572864) // '1.5 MiB/s'
/// ```
String formatSpeed(int bytesPerSec) {
  const units = ['B/s', 'KiB/s', 'MiB/s', 'GiB/s'];
  double v = (bytesPerSec < 0 ? 0 : bytesPerSec).toDouble();
  int i = 0;
  while (v >= 1024.0 && i < units.length - 1) {
    v /= 1024.0;
    i++;
  }
  if (i == 0) {
    return '${v.toInt()} ${units[i]}';
  }
  return '${v.toStringAsFixed(1)} ${units[i]}';
}
