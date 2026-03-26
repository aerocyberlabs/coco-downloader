/// Theme-mode provider for Coco Downloader.
///
/// Derives the [ThemeMode] from [configProvider.darkMode] so widgets only
/// need to watch this single provider for theme changes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config_provider.dart';

// ---------------------------------------------------------------------------
// themeProvider
// ---------------------------------------------------------------------------

/// Derived provider that maps [AppConfig.darkMode] to a [ThemeMode].
///
/// - `darkMode == true`  → [ThemeMode.dark]
/// - `darkMode == false` → [ThemeMode.light]
///
/// Example:
/// ```dart
/// final theme = ref.watch(themeProvider);
/// MaterialApp(themeMode: theme, ...);
/// ```
final themeProvider = Provider<ThemeMode>((ref) {
  final isDark = ref.watch(configProvider.select((cfg) => cfg.darkMode));
  return isDark ? ThemeMode.dark : ThemeMode.light;
});
