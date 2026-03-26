/// Application entry point for Coco Downloader.
///
/// Initialises Flutter bindings, configures the desktop window via
/// [window_manager], loads persisted configuration, then hands off to
/// [CocoApp] which is wrapped in a Riverpod [ProviderScope].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'constants.dart';
import 'providers/config_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // Desktop window setup
  // -------------------------------------------------------------------------

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    title: appName,
    size: Size(1100, 700),
    minimumSize: Size(720, 520),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // -------------------------------------------------------------------------
  // Bootstrap Riverpod and load config
  // -------------------------------------------------------------------------

  // Create the container so we can eagerly load configuration before the
  // first frame is painted. This avoids a flash of default settings.
  final container = ProviderContainer();
  await container.read(configProvider.notifier).loadConfig();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CocoApp(),
    ),
  );
}
