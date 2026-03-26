/// Platform-specific utilities: opening files/folders/URLs and resolving
/// well-known directories.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

// ---------------------------------------------------------------------------
// Open helpers
// ---------------------------------------------------------------------------

/// Opens [path] in the platform file manager so the user can see the
/// containing folder.
///
/// - Linux: `xdg-open`
/// - macOS: `open`
/// - Windows: `explorer.exe /select,<path>` (selects the item)
Future<void> openFolder(String path) async {
  if (Platform.isLinux) {
    await Process.run('xdg-open', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else if (Platform.isWindows) {
    // /select highlights the item rather than just opening the parent folder.
    await Process.run('explorer.exe', ['/select,', path]);
  }
}

/// Opens [path] with the platform default application.
///
/// - Linux: `xdg-open`
/// - macOS: `open`
/// - Windows: uses the `start` shell command
Future<void> openFile(String path) async {
  if (Platform.isLinux) {
    await Process.run('xdg-open', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else if (Platform.isWindows) {
    // 'start' is a cmd built-in; run through cmd.exe.
    await Process.run(
      'cmd.exe',
      ['/c', 'start', '', path],
      runInShell: true,
    );
  }
}

/// Opens [url] in the system default browser using [url_launcher].
Future<void> openUrl(String url) async {
  final uri = Uri.parse(url);
  if (!await launcher.canLaunchUrl(uri)) return;
  await launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
}

// ---------------------------------------------------------------------------
// Directory helpers
// ---------------------------------------------------------------------------

/// Returns the platform configuration directory for this application.
///
/// - Linux/macOS: `~/.config/coco-downloader`
/// - Windows: `%APPDATA%\coco-downloader`
///
/// The directory is created if it does not already exist.
Future<String> getConfigDir() async {
  final base = await _configBase();
  final dir = Directory(p.join(base, 'coco-downloader'));
  await dir.create(recursive: true);
  return dir.path;
}

/// Returns the platform log directory for this application.
///
/// - Linux/macOS: `~/.local/share/coco-downloader/logs`
/// - Windows: `%APPDATA%\coco-downloader\logs`
///
/// The directory is created if it does not already exist.
Future<String> getLogDir() async {
  if (Platform.isWindows) {
    // On Windows keep logs alongside the config.
    final cfg = await getConfigDir();
    final dir = Directory(p.join(cfg, 'logs'));
    await dir.create(recursive: true);
    return dir.path;
  }
  // On Linux/macOS prefer XDG_DATA_HOME or ~/.local/share.
  final dataBase = await _dataBase();
  final dir = Directory(p.join(dataBase, 'coco-downloader', 'logs'));
  await dir.create(recursive: true);
  return dir.path;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

Future<String> _configBase() async {
  if (Platform.isWindows) {
    // APPDATA is the conventional config location on Windows.
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) return appData;
    final support = await getApplicationSupportDirectory();
    return support.path;
  }
  if (Platform.isMacOS) {
    final support = await getApplicationSupportDirectory();
    return support.parent.path; // ~/Library/Application Support -> use parent
  }
  // Linux: respect XDG_CONFIG_HOME, fall back to ~/.config.
  final xdg = Platform.environment['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty) return xdg;
  final home = Platform.environment['HOME'] ?? '';
  return p.join(home, '.config');
}

Future<String> _dataBase() async {
  // Linux: XDG_DATA_HOME, fall back to ~/.local/share.
  final xdg = Platform.environment['XDG_DATA_HOME'];
  if (xdg != null && xdg.isNotEmpty) return xdg;
  final home = Platform.environment['HOME'] ?? '';
  return p.join(home, '.local', 'share');
}
