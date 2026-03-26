/// Runtime utilities for locating bundled or system binaries.
///
/// Dart equivalent of [utils/runtime.py].
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Attempts to find the `aria2c` binary to use.
///
/// Search order:
/// 1. [configPath] — a user-supplied explicit path (e.g. from settings).
/// 2. Bundled binary relative to the running executable:
///    - `<exe_dir>/bin/aria2c[.exe]`
///    - `<exe_dir>/bin/<platform>/aria2c[.exe]`  (linux / macos / windows)
/// 3. System `PATH` — runs `which aria2c` on Unix or `where aria2c` on
///    Windows.
///
/// Returns the absolute path to the binary, or `null` when none is found.
///
/// On Unix the bundled binary is made executable automatically if needed.
///
/// Mirrors `resolve_bundled_aria2()` from [utils/runtime.py].
Future<String?> resolveAria2Path([String? configPath]) async {
  // 1. Explicit user-provided path.
  if (configPath != null && configPath.isNotEmpty) {
    final f = File(configPath);
    if (await f.exists()) {
      if (!Platform.isWindows) await _ensureExecutable(configPath);
      return configPath;
    }
  }

  // 2. Bundled binary next to the running executable.
  final bundled = await _findBundled();
  if (bundled != null) return bundled;

  // 3. System PATH.
  return _findOnPath();
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

Future<String?> _findBundled() async {
  final String binaryName = Platform.isWindows ? 'aria2c.exe' : 'aria2c';

  // Candidate base directories relative to the running executable.
  final List<String> bases = [
    p.dirname(Platform.resolvedExecutable),
  ];

  // Platform-specific sub-directory names to probe under each base.
  final String platformSubdir;
  if (Platform.isWindows) {
    platformSubdir = 'windows';
  } else if (Platform.isMacOS) {
    platformSubdir = 'macos';
  } else {
    platformSubdir = 'linux';
  }

  final List<String> subdirs = [
    'bin',
    p.join('bin', platformSubdir),
  ];

  for (final base in bases) {
    for (final sd in subdirs) {
      final candidate = p.join(base, sd, binaryName);
      final f = File(candidate);
      if (await f.exists()) {
        if (!Platform.isWindows) await _ensureExecutable(candidate);
        return candidate;
      }
    }
  }
  return null;
}

Future<String?> _findOnPath() async {
  try {
    final ProcessResult result;
    if (Platform.isWindows) {
      result = await Process.run('where', ['aria2c']);
    } else {
      result = await Process.run('which', ['aria2c']);
    }
    if (result.exitCode == 0) {
      final out = (result.stdout as String).trim();
      // `where` can return multiple lines; take the first.
      final first = out.split(RegExp(r'[\r\n]+')).first.trim();
      if (first.isNotEmpty) return first;
    }
  } catch (_) {
    // `which`/`where` not available or aria2c not found.
  }
  return null;
}

/// Ensures the file at [path] has the user-executable bit set on Unix.
Future<void> _ensureExecutable(String path) async {
  try {
    final stat = await File(path).stat();
    // mode bits: owner-execute is 0x40 (octal 0100).
    if (stat.mode & 0x40 == 0) {
      await Process.run('chmod', ['u+x', path]);
    }
  } catch (_) {
    // Non-fatal — the binary may still be executable.
  }
}
