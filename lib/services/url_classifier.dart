/// URL classifier service for Coco Downloader.
///
/// Dart port of [url_utils.py] from the Python backend.
/// Classifies URLs into types and fetches direct file metadata via HTTP HEAD.
library;

import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../models/preview_item.dart';
import '../utils/url_tools.dart';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// All possible URL classifications, mirroring the Python strings.
enum UrlType {
  direct,
  realDebrid,
  magnet,
  rdTorrent,
  invalid,
  unknown;

  /// Convert to the string representation used by the Python backend.
  String toTypeString() {
    switch (this) {
      case UrlType.direct:
        return 'direct';
      case UrlType.realDebrid:
        return 'realdebrid';
      case UrlType.magnet:
        return 'magnet';
      case UrlType.rdTorrent:
        return 'rd-torrent';
      case UrlType.invalid:
        return 'invalid';
      case UrlType.unknown:
        return 'unknown';
    }
  }
}

/// Callback typedef so [URLClassifier] does not directly depend on the
/// RD client module.  Receives a URL and returns true when Real-Debrid
/// supports it.
typedef RdSupportCheck = bool Function(String url);

// ---------------------------------------------------------------------------
// URLClassifier
// ---------------------------------------------------------------------------

/// Classifies URLs and fetches metadata for direct HTTP/HTTPS links.
///
/// Mirrors [URLClassifier] in [url_utils.py].
class URLClassifier {
  URLClassifier({
    Map<String, String>? proxies,
    Map<String, String>? headers,
    List<String>? userAgents,
    bool rotateUserAgent = false,
    RdSupportCheck? rdSupportCheck,
  })  : _userAgents = userAgents ?? const [],
        _rotateUserAgent = rotateUserAgent,
        _rdSupportCheck = rdSupportCheck {
    // Build base options for Dio.
    final baseHeaders = <String, dynamic>{};
    if (rotateUserAgent && (userAgents?.isNotEmpty ?? false)) {
      final idx = math.Random().nextInt(userAgents!.length);
      baseHeaders['User-Agent'] = userAgents[idx];
    }
    if (headers != null) {
      baseHeaders.addAll(headers);
    }

    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: baseHeaders,
        followRedirects: true,
        maxRedirects: 10,
      ),
    );
  }

  final List<String> _userAgents;
  final bool _rotateUserAgent;
  final RdSupportCheck? _rdSupportCheck;

  late final Dio _dio;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Classify [url] into a [UrlType].
  ///
  /// Check order:
  ///   1. Empty / blank -> [UrlType.invalid]
  ///   2. `magnet:` prefix -> [UrlType.magnet]
  ///   3. `rd-torrent:` prefix -> [UrlType.rdTorrent]
  ///   4. RD host pattern match -> [UrlType.realDebrid]
  ///   5. HTTP/HTTPS (not RD) -> [UrlType.direct]
  ///   6. Anything else -> [UrlType.unknown]
  UrlType classifyUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return UrlType.invalid;

    if (trimmed.startsWith('magnet:')) return UrlType.magnet;
    if (trimmed.startsWith('rd-torrent:')) return UrlType.rdTorrent;

    if (isRdSupported(trimmed)) return UrlType.realDebrid;
    if (_isDirectDownloadable(trimmed)) return UrlType.direct;
    return UrlType.unknown;
  }

  /// Returns true when [url] matches any of the Real-Debrid host or folder
  /// regex patterns registered via the [rdSupportCheck] callback.
  bool isRdSupported(String url) {
    if (_rdSupportCheck == null) return false;
    return _rdSupportCheck(url);
  }

  /// Perform a HEAD (and optionally a range GET) request to obtain filename
  /// and size for a direct HTTP/HTTPS [url].
  ///
  /// Returns a [PreviewItem] with [PreviewItem.ok] set accordingly.
  Future<PreviewItem> getDirectFileInfo(String url) async {
    try {
      final response = await _dio.head<dynamic>(
        url,
        options: _requestOptions(),
      );

      final headers = response.headers;
      final finalUrl = response.realUri.toString();

      int size = _parseSizeFromHeaders(headers);

      // If HEAD gave no Content-Length, try a Range GET for Content-Range.
      if (size == 0) {
        size = await _sizeViaRangeGet(finalUrl);
      }

      final filename = _extractFilename(headers) ?? guessNameFromLink(finalUrl);

      final contentType = (headers.value('content-type') ?? '')
          .split(';')
          .first
          .trim();

      final host = Uri.tryParse(finalUrl)?.host ?? '';

      return PreviewItem(
        ok: true,
        link: url,
        filename: filename,
        filesize: size,
        type: contentType,
        host: host.isNotEmpty ? host : 'Direct',
      );
    } on DioException catch (e) {
      return PreviewItem(
        ok: false,
        link: url,
        error: _dioErrorMessage(e),
      );
    } catch (e) {
      return PreviewItem(
        ok: false,
        link: url,
        error: 'Unexpected error: ${e.toString().substring(0, e.toString().length.clamp(0, 200))}',
      );
    }
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  bool _isDirectDownloadable(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' && uri.scheme != 'https') return false;
      if (isRdSupported(url)) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Build [Options] for a Dio request, rotating User-Agent if configured.
  Options _requestOptions({Map<String, dynamic>? extraHeaders}) {
    final h = <String, dynamic>{};
    if (_rotateUserAgent && _userAgents.isNotEmpty) {
      final idx = math.Random().nextInt(_userAgents.length);
      h['User-Agent'] = _userAgents[idx];
    }
    if (extraHeaders != null) h.addAll(extraHeaders);
    return Options(headers: h.isEmpty ? null : h);
  }

  int _parseSizeFromHeaders(Headers headers) {
    final cl = headers.value('content-length');
    if (cl != null) {
      return int.tryParse(cl.trim()) ?? 0;
    }
    return 0;
  }

  /// Try a `Range: bytes=0-0` GET and parse `Content-Range: bytes 0-0/TOTAL`.
  Future<int> _sizeViaRangeGet(String url) async {
    try {
      final resp = await _dio.get<dynamic>(
        url,
        options: _requestOptions(
          extraHeaders: {'Range': 'bytes=0-0'},
        ),
      );
      final cr =
          resp.headers.value('content-range') ?? resp.headers.value('Content-Range');
      if (cr != null && cr.contains('/')) {
        final total = cr.split('/').last.trim();
        return int.tryParse(total) ?? 0;
      }
    } catch (_) {
      // Ignore — size remains 0.
    }
    return 0;
  }

  /// Extract filename from `Content-Disposition` header using [parseContentDisposition].
  String? _extractFilename(Headers headers) {
    final cd = headers.value('content-disposition');
    if (cd == null || cd.isEmpty) return null;
    return parseContentDisposition(cd);
  }

  String _dioErrorMessage(DioException e) {
    final msg = e.message ?? e.type.name;
    return msg.length > 200 ? msg.substring(0, 200) : msg;
  }
}
