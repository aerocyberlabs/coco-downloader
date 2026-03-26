/// Battery / AC power state monitor.
///
/// Dart port of [_power_aware_loop()] from [workers.py].
/// Detects whether the machine is running on battery or AC power using
/// platform-specific mechanisms and translates that into download throttle
/// recommendations.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_config.dart';

// ---------------------------------------------------------------------------
// Power state enum
// ---------------------------------------------------------------------------

/// Coarse power state reported by [PowerMonitor].
enum PowerState {
  /// Connected to mains / AC power.
  ac,

  /// Running on battery.
  battery,

  /// Could not determine the power state.
  unknown,
}

// ---------------------------------------------------------------------------
// PowerMonitor
// ---------------------------------------------------------------------------

/// Detects power state and recommends download throttle settings.
///
/// Platform detection mirrors the Python [_power_aware_loop()] which uses
/// [psutil.sensors_battery()].  The Dart implementation reads the same
/// underlying system interfaces directly:
///
///   - **Linux**: `/sys/class/power_supply/` sysfs entries.
///   - **macOS**: `pmset -g batt` output.
///   - **Windows**: `WMIC Path Win32_Battery Get BatteryStatus`.
///
/// On unsupported platforms (Android, iOS) [currentState] always returns
/// [PowerState.unknown].
class PowerMonitor {
  PowerMonitor();

  PowerState _currentState = PowerState.unknown;

  /// Last-known power state.  Updated by [refresh].
  PowerState get currentState => _currentState;

  // ---------------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------------

  /// Probe the OS and return `true` when the machine is running on battery.
  ///
  /// Returns `false` on AC power or when the state cannot be determined.
  Future<bool> isOnBattery() async {
    try {
      if (Platform.isLinux) {
        return await _isOnBatteryLinux();
      } else if (Platform.isMacOS) {
        return await _isOnBatteryMacOS();
      } else if (Platform.isWindows) {
        return await _isOnBatteryWindows();
      }
    } catch (e) {
      debugPrint('[PowerMonitor] isOnBattery error: $e');
    }
    return false;
  }

  /// Refresh [currentState] by calling [isOnBattery].
  Future<PowerState> refresh() async {
    try {
      final onBattery = await isOnBattery();
      _currentState = onBattery ? PowerState.battery : PowerState.ac;
    } catch (_) {
      _currentState = PowerState.unknown;
    }
    return _currentState;
  }

  // ---------------------------------------------------------------------------
  // Throttle recommendations
  // ---------------------------------------------------------------------------

  /// Recommended maximum concurrent downloads based on [currentState].
  ///
  /// Returns [AppConfig.batteryConcurrent] when on battery,
  /// [AppConfig.acConcurrent] when on AC, or [AppConfig.concurrency] when
  /// the state is unknown.
  int recommendedConcurrent(AppConfig config) {
    switch (_currentState) {
      case PowerState.battery:
        return config.batteryConcurrent;
      case PowerState.ac:
        return config.acConcurrent;
      case PowerState.unknown:
        return config.concurrency;
    }
  }

  /// Recommended download speed limit in KiB/s, or `null` for unlimited.
  ///
  /// Returns [AppConfig.batteryLimitKib] when on battery (0 means unlimited),
  /// or `null` (unlimited) when on AC or state is unknown.
  int? recommendedSpeedLimitKib(AppConfig config) {
    if (_currentState == PowerState.battery) {
      final limit = config.batteryLimitKib;
      return limit > 0 ? limit : null;
    }
    return null; // unlimited on AC or unknown
  }

  // ---------------------------------------------------------------------------
  // Linux detection
  // ---------------------------------------------------------------------------

  /// Read `/sys/class/power_supply/` to determine battery/AC state.
  ///
  /// We look for any supply whose `type` file contains "Battery" and whose
  /// `status` file does NOT contain "Charging" or "Full" (i.e. discharging).
  /// If no battery supply is found we fall back to looking for an AC adapter
  /// whose `online` file is "1".
  Future<bool> _isOnBatteryLinux() async {
    final supplyDir = Directory('/sys/class/power_supply');
    if (!supplyDir.existsSync()) return false;

    bool hasBattery = false;
    bool batteryDischarging = false;
    bool acOnline = false;

    await for (final entity in supplyDir.list(followLinks: true)) {
      if (entity is! Directory && entity is! Link) continue;

      final name = entity.path.split('/').last;
      final typePath = '${entity.path}/type';
      final statusPath = '${entity.path}/status';
      final onlinePath = '${entity.path}/online';

      try {
        final type =
            (await File(typePath).readAsString()).trim().toLowerCase();

        if (type == 'battery') {
          hasBattery = true;
          try {
            final status =
                (await File(statusPath).readAsString()).trim().toLowerCase();
            // "Discharging" means on battery; "Charging" or "Full" means AC.
            if (status == 'discharging') {
              batteryDischarging = true;
            }
          } catch (_) {
            // status file may not exist for all batteries.
          }
        } else if (type == 'mains' || type == 'usb' || name.startsWith('AC')) {
          try {
            final online =
                (await File(onlinePath).readAsString()).trim();
            if (online == '1') acOnline = true;
          } catch (_) {}
        }
      } catch (_) {
        // Unreadable supply entry; skip.
      }
    }

    if (hasBattery) return batteryDischarging;
    // Desktop with no battery; if an AC adapter is online we are on AC.
    if (acOnline) return false;
    return false; // unknown → assume AC
  }

  // ---------------------------------------------------------------------------
  // macOS detection
  // ---------------------------------------------------------------------------

  /// Parse `pmset -g batt` output.
  ///
  /// Example lines:
  ///   `Now drawing from 'Battery Power'`
  ///   `Now drawing from 'AC Power'`
  Future<bool> _isOnBatteryMacOS() async {
    final result = await Process.run('pmset', ['-g', 'batt']);
    if (result.exitCode != 0) return false;
    final output = (result.stdout as String).toLowerCase();
    // "battery power" indicates battery; "ac power" indicates mains.
    return output.contains("'battery power'") ||
        output.contains('"battery power"') ||
        output.contains('battery power');
  }

  // ---------------------------------------------------------------------------
  // Windows detection
  // ---------------------------------------------------------------------------

  /// Query WMI for battery status via WMIC.
  ///
  /// BatteryStatus values:
  ///   1 = Discharging (battery), 2 = On AC, 6 = Charging
  /// Absence of a battery row means desktop (AC).
  Future<bool> _isOnBatteryWindows() async {
    try {
      final result = await Process.run('WMIC', [
        'Path',
        'Win32_Battery',
        'Get',
        'BatteryStatus',
        '/format:value',
      ]);
      if (result.exitCode != 0) return false;
      final output = result.stdout as String;
      // Parse lines like "BatteryStatus=1"
      for (final line in output.split(RegExp(r'[\r\n]+'))) {
        final trimmed = line.trim();
        if (trimmed.toLowerCase().startsWith('batterystatus=')) {
          final valueStr = trimmed.split('=').last.trim();
          final value = int.tryParse(valueStr);
          if (value == null) continue;
          // 1 = Discharging, 4 = Low, 5 = Critical (all on battery)
          return value == 1 || value == 4 || value == 5;
        }
      }
      // No battery found (desktop) → AC.
      return false;
    } catch (e) {
      // WMIC may be absent on very old or stripped Windows installs.
      debugPrint('[PowerMonitor] WMIC query failed: $e');
      return false;
    }
  }
}
