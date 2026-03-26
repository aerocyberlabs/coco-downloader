/// Root application widget for Coco Downloader.
///
/// Wraps the widget tree with [ProviderScope] (Riverpod) and configures a
/// Material 3 theme using the brand green seed colour (#388E3C).  The active
/// [ThemeMode] is derived from [themeProvider] so dark-mode preference toggles
/// are reflected immediately.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'constants.dart';
import 'providers/providers.dart';
import 'ui/screens/home_screen.dart';

// ---------------------------------------------------------------------------
// Seed colour
// ---------------------------------------------------------------------------

/// Brand green that seeds both light and dark Material 3 colour schemes.
const _kSeedColor = Color(0xFF388E3C);

// ---------------------------------------------------------------------------
// CocoApp
// ---------------------------------------------------------------------------

/// Top-level application widget.
///
/// Must be a descendant of [ProviderScope], which is inserted in [main.dart].
class CocoApp extends ConsumerWidget {
  const CocoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,

      // --- Light theme ---
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _kSeedColor,
          brightness: Brightness.light,
        ),
      ),

      // --- Dark theme ---
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _kSeedColor,
          brightness: Brightness.dark,
        ),
      ),

      home: const HomeScreen(),
    );
  }
}
