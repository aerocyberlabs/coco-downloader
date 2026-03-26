import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const String _apiBase = 'https://api.real-debrid.com/rest/1.0';

/// Cache TTL for host regex patterns: 6 hours.
const Duration _ttl = Duration(hours: 6);

/// Cached Real-Debrid host and folder regex patterns.
///
/// Dart port of `fetch_rd_host_patterns()` and the `URLClassifier` pattern
/// storage from `url_utils.py`.
///
/// Usage:
/// ```dart
/// final patterns = RdHostPatterns();
/// await patterns.refresh(token);
/// final supported = patterns.isSupported('https://mega.nz/...');
/// ```
class RdHostPatterns {
  RdHostPatterns();

  /// Compiled host patterns (from `/hosts/regex`).
  List<RegExp> _hostPatterns = [];

  /// Compiled folder patterns (from `/hosts/regexFolder`).
  List<RegExp> _folderPatterns = [];

  /// When the cache was last successfully populated.
  DateTime? _fetchedAt;

  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  // ---------------------------------------------------------------------------
  // Public interface
  // ---------------------------------------------------------------------------

  /// Fetch `/hosts/regex` and `/hosts/regexFolder` from the RD API, compile
  /// the results into [RegExp] objects, and cache them for [_ttl].
  ///
  /// Safe to call repeatedly; re-fetches only when the cache has expired.
  /// On network failure the existing cached patterns (if any) are preserved.
  Future<void> refresh(String token) async {
    final now = DateTime.now();
    if (_fetchedAt != null && now.difference(_fetchedAt!) < _ttl) {
      // Cache still valid.
      return;
    }

    final headers = {'Authorization': 'Bearer $token'};

    List<RegExp> hostPatterns;
    List<RegExp> folderPatterns;

    try {
      hostPatterns = await _fetchPatterns('$_apiBase/hosts/regex', headers);
    } catch (e) {
      debugPrint('[RdHostPatterns] hosts/regex fetch failed: $e');
      // Keep previous patterns if available.
      hostPatterns = _hostPatterns;
    }

    try {
      folderPatterns =
          await _fetchPatterns('$_apiBase/hosts/regexFolder', headers);
    } catch (e) {
      debugPrint('[RdHostPatterns] hosts/regexFolder fetch failed: $e');
      folderPatterns = _folderPatterns;
    }

    _hostPatterns = hostPatterns;
    _folderPatterns = folderPatterns;
    _fetchedAt = now;
  }

  /// Returns `true` when [url] matches at least one host or folder pattern.
  ///
  /// Automatically re-fetches patterns if the cache has expired; requires a
  /// prior call to [refresh] for the first population.  If no patterns are
  /// loaded, returns `false`.
  bool isSupported(String url) {
    for (final pattern in _hostPatterns) {
      if (pattern.hasMatch(url)) return true;
    }
    for (final pattern in _folderPatterns) {
      if (pattern.hasMatch(url)) return true;
    }
    return false;
  }

  /// Whether the pattern cache has been populated and is still within TTL.
  bool get isCacheValid =>
      _fetchedAt != null && DateTime.now().difference(_fetchedAt!) < _ttl;

  /// Number of loaded host patterns.
  int get hostPatternCount => _hostPatterns.length;

  /// Number of loaded folder patterns.
  int get folderPatternCount => _folderPatterns.length;

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<List<RegExp>> _fetchPatterns(
    String url,
    Map<String, String> headers,
  ) async {
    final resp = await _dio.get<dynamic>(
      url,
      options: Options(
        headers: headers,
        validateStatus: (s) => true,
      ),
    );
    if (resp.statusCode != 200) {
      throw Exception('Pattern fetch failed: HTTP ${resp.statusCode} for $url');
    }
    final body = resp.data;
    if (body is! List) return [];
    final patterns = <RegExp>[];
    for (final item in body) {
      if (item is String && item.isNotEmpty) {
        try {
          patterns.add(RegExp(item, caseSensitive: false));
        } catch (e) {
          debugPrint('[RdHostPatterns] Skipping invalid regex "$item": $e');
        }
      }
    }
    return patterns;
  }
}
