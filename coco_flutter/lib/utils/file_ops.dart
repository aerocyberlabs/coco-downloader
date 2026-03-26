/// File-system operation utilities.
///
/// Dart equivalents of the Python helpers in [utils/fileops.py].
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns a filename that does not already exist inside [dir].
///
/// If `[dir]/[name]` is free the original [name] is returned unchanged.
/// Otherwise numbers are appended before the extension until a free slot is
/// found: `base (1).ext`, `base (2).ext`, …
///
/// Mirrors `unique_name(folder, name)` from [utils/fileops.py].
///
/// Example:
/// ```dart
/// uniqueName('/downloads', 'movie.mkv');
/// // -> 'movie.mkv'        when the file does not exist, or
/// // -> 'movie (1).mkv'    when 'movie.mkv' already exists.
/// ```
String uniqueName(String dir, String name) {
  final ext = p.extension(name);
  final base = p.basenameWithoutExtension(name);
  int attempt = 1;
  while (true) {
    final candidate = '$base ($attempt)$ext';
    final full = p.join(dir, candidate);
    if (!File(full).existsSync()) {
      return candidate;
    }
    attempt++;
  }
}

/// Returns `true` when the file at [path] exists and its size equals
/// [expectedSize] bytes.
///
/// Returns `false` on any error (file absent, permission denied, etc.).
///
/// Mirrors `size_matches(path, size)` from [utils/fileops.py].
bool sizeMatches(String path, int expectedSize) {
  try {
    final stat = File(path).statSync();
    if (stat.type == FileSystemEntityType.notFound) return false;
    return stat.size == expectedSize;
  } catch (_) {
    return false;
  }
}
