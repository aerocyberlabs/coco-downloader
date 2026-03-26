/// Config state management via Riverpod.
///
/// Provides a [StateNotifier] that wraps [AppConfig] and delegates
/// persistence to [ConfigService].  All mutations go through [updateConfig]
/// so the config is always saved to disk after every change.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_config.dart';
import '../services/config_service.dart';

// ---------------------------------------------------------------------------
// ConfigNotifier
// ---------------------------------------------------------------------------

/// Manages the mutable [AppConfig] state and persists changes to disk.
///
/// Example:
/// ```dart
/// // Read
/// final cfg = ref.watch(configProvider);
///
/// // Update a single field
/// ref.read(configProvider.notifier).updateConfig((c) => c.copyWith(darkMode: true));
/// ```
class ConfigNotifier extends StateNotifier<AppConfig> {
  ConfigNotifier() : super(AppConfig.defaults());

  // -------------------------------------------------------------------------
  // Load
  // -------------------------------------------------------------------------

  /// Load configuration from disk and update state.
  ///
  /// Falls back to [AppConfig.defaults] when the file is missing or invalid.
  Future<void> loadConfig() async {
    try {
      final raw = await configService.loadConfig();
      state = raw.isEmpty ? AppConfig.defaults() : AppConfig.fromJson(raw);
    } catch (e) {
      // Keep existing (default) state on failure.
    }
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  /// Persist the current state to disk.
  Future<void> saveConfig() async {
    try {
      await configService.saveConfig(state.toJson());
    } catch (_) {
      // Non-fatal – caller can retry.
    }
  }

  // -------------------------------------------------------------------------
  // Update
  // -------------------------------------------------------------------------

  /// Apply [updater] to the current [AppConfig], update state, and persist.
  ///
  /// Example:
  /// ```dart
  /// notifier.updateConfig((c) => c.copyWith(connections: 8));
  /// ```
  Future<void> updateConfig(AppConfig Function(AppConfig current) updater) async {
    state = updater(state);
    await saveConfig();
  }

  // -------------------------------------------------------------------------
  // Reset
  // -------------------------------------------------------------------------

  /// Restore factory defaults and persist to disk.
  Future<void> resetToDefaults() async {
    state = AppConfig.defaults();
    await saveConfig();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global [AppConfig] provider.
///
/// Exposes the current configuration to the widget tree. Changes trigger
/// widget rebuilds only for widgets that read the specific part of the config
/// they care about (use `.select` for fine-grained reactivity).
final configProvider = StateNotifierProvider<ConfigNotifier, AppConfig>((ref) {
  return ConfigNotifier();
});
