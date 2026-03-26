/// File categorisation service for Coco Downloader.
///
/// Dart equivalent of [utils/categories.py] in the Python backend.
/// Provides extension extraction, default category maps, and categorisation
/// logic identical to the Python implementation so that the Flutter UI groups
/// files into the same buckets as the downloader.
library;

// ---------------------------------------------------------------------------
// Extension extraction
// ---------------------------------------------------------------------------

/// Extract the file extension from [name], lower-cased and without a leading
/// dot.
///
/// Handles compound extensions (.tar.gz, .tar.bz2, .tar.xz) before falling
/// back to the last path component, mirroring [ext_from_name] in categories.py.
///
/// Examples:
///   extFromName('archive.tar.gz')  // 'tar.gz'
///   extFromName('video.MKV')       // 'mkv'
///   extFromName('README')          // ''
String extFromName(String name) {
  final n = name.toLowerCase();
  for (final compound in ['.tar.gz', '.tar.bz2', '.tar.xz']) {
    if (n.endsWith(compound)) {
      return compound.substring(1); // strip the leading dot
    }
  }
  final dotIndex = n.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == n.length - 1) return '';
  return n.substring(dotIndex + 1);
}

// ---------------------------------------------------------------------------
// Default maps
// ---------------------------------------------------------------------------

/// Returns the default mapping from category name to the list of extensions
/// that belong to that category.
///
/// The lists are identical to those returned by [default_category_exts()] in
/// categories.py (with the additions requested in the feature spec for the
/// Flutter layer: vob, 3gp, ogv, wma, alac, aiff, svg, tiff, ico, raw, heic,
/// heif, odt, ods, odp, epub, mobi, iso, dmg, cab, lz, zst, cmd, ps1).
///
/// Each extension is already lower-cased and has no leading dot.
Map<String, List<String>> defaultCategoryExts() {
  return {
    'Video': [
      'mp4',
      'mkv',
      'avi',
      'mov',
      'wmv',
      'flv',
      'webm',
      'm4v',
      'mpg',
      'mpeg',
      'ts',
      'm2ts',
      'vob',
      '3gp',
      'ogv',
    ],
    'Audio': [
      'mp3',
      'flac',
      'aac',
      'ogg',
      'wma',
      'wav',
      'm4a',
      'opus',
      'alac',
      'aiff',
    ],
    'Image': [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'bmp',
      'svg',
      'webp',
      'tiff',
      'tif',
      'ico',
      'raw',
      'heic',
      'heif',
    ],
    'Document': [
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'rtf',
      'odt',
      'ods',
      'odp',
      'epub',
      'mobi',
      'csv',
      'md',
    ],
    'Compressed': [
      'zip',
      'rar',
      '7z',
      'tar',
      'gz',
      'bz2',
      'xz',
      'iso',
      'cab',
      'lz',
      'zst',
      'tar.gz',
      'tar.bz2',
      'tar.xz',
    ],
    'Program': [
      'exe',
      'msi',
      'deb',
      'rpm',
      'appimage',
      'apk',
      'dmg',
      'pkg',
      'sh',
      'bat',
      'cmd',
      'ps1',
    ],
  };
}

/// Returns the default mapping from category name to the subfolder name that
/// should be used when organising downloads by category.
///
/// Mirrors [subfolder_for_category] defaults in categories.py.
Map<String, String> defaultCategoryFolders() {
  return {
    'Video': 'Video',
    'Audio': 'Audio',
    'Image': 'Images',
    'Document': 'Documents',
    'Compressed': 'Compressed',
    'Program': 'Programs',
    'Other': 'Other',
  };
}

// ---------------------------------------------------------------------------
// Categorisation
// ---------------------------------------------------------------------------

/// Categorise [ext] (lower-cased, no leading dot) and return the category
/// name.
///
/// When [customExts] is provided it takes priority over the defaults, exactly
/// as [category_exts(cfg)] works in categories.py.  The lookup falls back to
/// `'Other'` for any extension not found in any category.
///
/// Example:
///   categorizeExtension('mkv')            // 'Video'
///   categorizeExtension('tar.gz')         // 'Compressed'
///   categorizeExtension('xyz')            // 'Other'
String categorizeExtension(
  String ext, {
  Map<String, List<String>>? customExts,
}) {
  final e = ext.toLowerCase();
  final mapping = _mergeExts(customExts);
  for (final entry in mapping.entries) {
    if (entry.value.contains(e)) return entry.key;
  }
  return 'Other';
}

/// Returns the subfolder name for [category], optionally overridden by
/// [customFolders].
///
/// Returns `null` only when [category] is not present in either map (callers
/// can then choose to omit the subfolder entirely).  For 'Other' and all
/// default categories a non-null value is always returned.
String? subfolderForCategory(
  String category, {
  Map<String, String>? customFolders,
}) {
  final defaults = defaultCategoryFolders();
  if (customFolders != null) {
    return customFolders[category] ?? defaults[category];
  }
  return defaults[category];
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Merge [customExts] on top of the defaults (custom wins per category).
///
/// Extensions within each list are lower-cased and stripped of leading dots,
/// matching the normalisation in [category_exts(cfg)] in categories.py.
Map<String, List<String>> _mergeExts(Map<String, List<String>>? customExts) {
  final base = {
    for (final e in defaultCategoryExts().entries)
      e.key: e.value.map((x) => x.toLowerCase().replaceFirst(RegExp(r'^\.'), '')).toList(),
  };
  if (customExts == null) return base;
  for (final entry in customExts.entries) {
    base[entry.key] =
        entry.value.map((x) => x.toLowerCase().replaceFirst(RegExp(r'^\.'), '')).toList();
  }
  return base;
}
