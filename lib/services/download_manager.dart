/// Download orchestration service for Coco Downloader.
///
/// Dart port of [core/download_manager.py] from the Python backend.
/// Routes links through the URL classifier, builds preview items, and
/// computes aria2 options with optional auto-categorisation.
library;

import 'package:path/path.dart' as p;

import '../models/preview_item.dart';
import '../utils/url_tools.dart';
import 'categories_service.dart';
import 'url_classifier.dart';

// ---------------------------------------------------------------------------
// Dependency typedefs (avoids circular imports with the RD client module)
// ---------------------------------------------------------------------------

/// Called when a link needs to be unrestricted via Real-Debrid.
///
/// Returns a map that mirrors the Python `unrestrict_link()` return value:
///   { 'ok': bool, 'download': String?, 'filename': String?, 'filesize': int? }
typedef UnrestrictLink = Future<Map<String, dynamic>> Function(String link);

/// Called to check / enrich a link via Real-Debrid without unrestricting it.
///
/// Returns a map that mirrors the Python `check_link()` return value:
///   { 'ok': bool, 'filename': String?, 'filesize': int?, 'host': String? }
typedef CheckLink = Future<Map<String, dynamic>> Function(String link);

// ---------------------------------------------------------------------------
// DownloadManager
// ---------------------------------------------------------------------------

/// Orchestrates building preview items and aria2 download options for links
/// from different sources (direct HTTP/HTTPS, Real-Debrid, magnets, torrents).
///
/// Mirrors [DownloadManager] in [core/download_manager.py].
class DownloadManager {
  DownloadManager({
    required this.baseDir,
    required URLClassifier classifier,
    UnrestrictLink? unrestrictLink,
    CheckLink? checkLink,
  })  : _classifier = classifier,
        _unrestrictLink = unrestrictLink,
        _checkLink = checkLink;

  /// Base output directory for downloads.
  final String baseDir;

  final URLClassifier _classifier;
  final UnrestrictLink? _unrestrictLink;
  final CheckLink? _checkLink;

  // -------------------------------------------------------------------------
  // Preview building
  // -------------------------------------------------------------------------

  /// Route [link] through the classifier and return a [PreviewItem] with
  /// metadata suitable for display in the preview table.
  ///
  /// Mirrors [build_preview_item] in [core/download_manager.py].
  Future<PreviewItem> buildPreviewItem(String link) async {
    UrlType urlType;
    try {
      urlType = _classifier.classifyUrl(link);
    } catch (_) {
      urlType = UrlType.unknown;
    }

    // ------------------------------------------------------------------
    // Direct download path
    // ------------------------------------------------------------------
    if (urlType == UrlType.direct || _unrestrictLink == null) {
      final info = await _classifier.getDirectFileInfo(link);
      if (!info.ok) {
        return PreviewItem(
          ok: false,
          link: link,
          error: info.error,
          type: 'direct',
        );
      }

      final fname = info.filename ?? guessNameFromLink(link);
      final fsize = info.filesize;
      final ext = extFromName(fname);

      String host = 'Direct';
      try {
        final h = Uri.parse(info.host ?? link).host;
        if (h.isNotEmpty) host = h;
      } catch (_) {}

      return PreviewItem(
        ok: true,
        link: link,
        filename: fname,
        filesize: fsize,
        type: ext,
        host: host,
      );
    }

    // ------------------------------------------------------------------
    // Real-Debrid / unknown path
    // ------------------------------------------------------------------
    if (urlType == UrlType.realDebrid || urlType == UrlType.unknown) {
      if (_checkLink != null) {
        final info = await _checkLink(link);
        String? fname = (info['filename'] as String?) ?? (info['name'] as String?);
        int fsize = (info['filesize'] as num?)?.toInt() ?? 0;

        // If check_link did not return a filename, try unrestrict_link.
        if (fname == null || fname.isEmpty) {
          final u = await _unrestrictLink(link);
          if (u['ok'] == true) {
            fname = (u['filename'] as String?) ?? fname;
            if (fsize == 0) {
              fsize = (u['filesize'] as num?)?.toInt() ?? 0;
            }
          }
        }

        fname ??= guessNameFromLink(link);
        final ext = extFromName(fname);

        String? host = info['host'] as String?;
        if (host == null || host.isEmpty) {
          try {
            host = Uri.parse(link).host;
          } catch (_) {
            host = 'Real-Debrid';
          }
        }

        final ok = info['ok'] == true;
        return PreviewItem(
          ok: ok,
          link: link,
          filename: fname,
          filesize: fsize,
          type: ext,
          host: host,
        );
      }
    }

    // ------------------------------------------------------------------
    // Unsupported / fallback
    // ------------------------------------------------------------------
    return PreviewItem(
      ok: false,
      link: link,
      error: 'Unsupported link type',
    );
  }

  // -------------------------------------------------------------------------
  // Policy helpers
  // -------------------------------------------------------------------------

  /// Returns true when [name]'s extension appears in [excludeExts].
  ///
  /// [excludeExts] entries may optionally carry a leading dot; comparison is
  /// case-insensitive.  Mirrors [is_excluded] in [core/download_manager.py].
  bool isExcluded(String name, {List<String>? excludeExts}) {
    if (excludeExts == null || excludeExts.isEmpty) return false;
    final ext = extFromName(name);
    if (ext.isEmpty) return false;
    final normalised = excludeExts
        .map((e) => e.toLowerCase().replaceFirst(RegExp(r'^\.'), ''))
        .toSet();
    return normalised.contains(ext.toLowerCase());
  }

  /// Return the category name for the file identified by [name].
  ///
  /// Optionally override the default extension map with [customExts].
  /// Mirrors [category_for_name] in [core/download_manager.py].
  String categoryForName(
    String name, {
    Map<String, List<String>>? customExts,
  }) {
    final ext = extFromName(name);
    return categorizeExtension(ext, customExts: customExts);
  }

  /// Build the target directory path for [name] under [baseDir].
  ///
  /// When [autoCategorize] is true (the default), a category subfolder is
  /// appended.  [customExts] and [customFolders] override the defaults.
  ///
  /// Mirrors [target_dir_for_name] in [core/download_manager.py].
  String targetDirForName(
    String name,
    String baseDir, {
    bool autoCategorize = true,
    Map<String, List<String>>? customExts,
    Map<String, String>? customFolders,
  }) {
    if (!autoCategorize) return baseDir;
    final category = categoryForName(name, customExts: customExts);
    final sub = subfolderForCategory(category, customFolders: customFolders);
    if (sub == null || sub.isEmpty) return baseDir;
    return p.join(baseDir, sub);
  }

  /// Build the aria2 options map for a single download entry.
  ///
  /// Returns `{'out': name, 'dir': targetDir}`.
  ///
  /// Mirrors [aria2_options_for_entry] in [core/download_manager.py].
  Map<String, String> aria2OptionsForEntry({
    required String name,
    required String baseDir,
    bool autoCategorize = true,
    Map<String, List<String>>? customExts,
    Map<String, String>? customFolders,
  }) {
    final targetDir = targetDirForName(
      name,
      baseDir,
      autoCategorize: autoCategorize,
      customExts: customExts,
      customFolders: customFolders,
    );
    return {
      'out': name,
      'dir': targetDir,
    };
  }
}
