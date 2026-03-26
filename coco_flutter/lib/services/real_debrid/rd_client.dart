import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

const String _apiBase = 'https://api.real-debrid.com/rest/1.0';

// ---------------------------------------------------------------------------
// Bencode parser
// ---------------------------------------------------------------------------

/// Result of a bencode parse: the parsed value and the index after the value.
typedef _ParseResult = ({Object? value, int end});

/// Recursive-descent bencode parser.
///
/// Returns the parsed Dart value.  Supported types:
///   - `int`  (bencode integer)
///   - `Uint8List` (bencode string / byte string)
///   - `List<Object?>` (bencode list)
///   - `Map<Uint8List, Object?>` (bencode dict, keys kept as bytes to allow
///     binary keys and to preserve ordering)
_ParseResult _bparse(Uint8List data, int i) {
  if (i >= data.length) throw const FormatException('Unexpected end of data');
  final lead = data[i];
  final leadChar = String.fromCharCode(lead);

  // Integer: i<digits>e
  if (leadChar == 'i') {
    final eIdx = _indexOf(data, 0x65 /* 'e' */, i + 1);
    if (eIdx == -1) throw const FormatException('Unterminated integer');
    final n = int.parse(utf8.decode(data.sublist(i + 1, eIdx)));
    return (value: n, end: eIdx + 1);
  }

  // List: l<items>e
  if (leadChar == 'l') {
    final list = <Object?>[];
    int pos = i + 1;
    while (pos < data.length && data[pos] != 0x65 /* 'e' */) {
      final r = _bparse(data, pos);
      list.add(r.value);
      pos = r.end;
    }
    if (pos >= data.length) throw const FormatException('Unterminated list');
    return (value: list, end: pos + 1);
  }

  // Dict: d<pairs>e
  if (leadChar == 'd') {
    final dict = <String, Object?>{};
    int pos = i + 1;
    while (pos < data.length && data[pos] != 0x65 /* 'e' */) {
      final kr = _bparse(data, pos);
      final rawKey = kr.value;
      if (rawKey is! Uint8List) {
        throw const FormatException('Dict key is not a byte string');
      }
      pos = kr.end;
      final vr = _bparse(data, pos);
      final key = utf8.decode(rawKey, allowMalformed: true);
      dict[key] = vr.value;
      pos = vr.end;
    }
    if (pos >= data.length) throw const FormatException('Unterminated dict');
    return (value: dict, end: pos + 1);
  }

  // Byte string: <len>:<bytes>
  if (lead >= 0x30 && lead <= 0x39 /* '0'..'9' */) {
    int j = i;
    while (j < data.length && data[j] >= 0x30 && data[j] <= 0x39) {
      j++;
    }
    if (j >= data.length || data[j] != 0x3A /* ':' */) {
      throw const FormatException('Invalid byte string length');
    }
    final len = int.parse(utf8.decode(data.sublist(i, j)));
    final start = j + 1;
    final end = start + len;
    if (end > data.length) throw const FormatException('Byte string too long');
    return (value: Uint8List.sublistView(data, start, end), end: end);
  }

  throw FormatException('Unknown bencode token at $i: $leadChar');
}

/// Find the first occurrence of [byte] in [data] starting at [from].
int _indexOf(Uint8List data, int byte, int from) {
  for (int i = from; i < data.length; i++) {
    if (data[i] == byte) return i;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Locate the raw bytes of the "info" dict value so we can SHA-1 hash them.
// ---------------------------------------------------------------------------

/// Returns the `[start, end)` byte range of the bencode value for the `info`
/// key inside the top-level torrent dict.
///
/// Returns `null` if the info key is not found.
({int start, int end})? _locateInfoDictSpan(Uint8List data) {
  // Walk the top-level dict manually so we track byte offsets.
  if (data.isEmpty || String.fromCharCode(data[0]) != 'd') return null;
  int pos = 1;
  while (pos < data.length && data[pos] != 0x65 /* 'e' */) {
    // Key
    final kr = _bparse(data, pos);
    final rawKey = kr.value;
    if (rawKey is! Uint8List) return null;
    final key = utf8.decode(rawKey, allowMalformed: true);
    pos = kr.end;

    // Value start (byte offset used for SHA-1 span)
    final vStart = pos;
    final vr = _bparse(data, pos);
    pos = vr.end;

    if (key == 'info') {
      return (start: vStart, end: pos);
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Public bencode helpers
// ---------------------------------------------------------------------------

/// Parse a bencode-encoded byte array and return the top-level value.
///
/// The return type mirrors the Python `bdecode` specification:
/// a `Map<String, dynamic>` for the typical torrent top-level dict.
Map<String, dynamic> bdecode(List<int> data) {
  final bytes = Uint8List.fromList(data);
  final result = _bparse(bytes, 0);
  final value = result.value;
  if (value is Map<String, dynamic>) return value;
  // Wrap non-dict result so the return type is always Map.
  return {'_value': value};
}

/// Parse a `.torrent` file and generate a `magnet:` URI containing the BTIH.
///
/// Returns `null` when the torrent is v2-only (no `pieces` key) – RD cannot
/// handle v2 torrents without a v1 compatibility layer.
///
/// Throws on I/O errors or malformed bencode.
String? torrentToMagnet(String filePath) {
  final bytes = File(filePath).readAsBytesSync();
  final data = Uint8List.fromList(bytes);
  final span = _locateInfoDictSpan(data);
  if (span == null) return null;

  final infoBlob = Uint8List.sublistView(data, span.start, span.end);

  // v2-only detection (no pieces + has file tree or meta_version >= 2).
  bool containsBytes(Uint8List haystack, String needle) {
    final needleBytes = utf8.encode(needle);
    outer:
    for (int i = 0; i <= haystack.length - needleBytes.length; i++) {
      for (int j = 0; j < needleBytes.length; j++) {
        if (haystack[i + j] != needleBytes[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  final hasPieces = containsBytes(infoBlob, '6:pieces');
  final hasFileTree =
      containsBytes(infoBlob, '9:file tree') || containsBytes(infoBlob, '8:filetree');
  final hasMetaV2 = containsBytes(infoBlob, '12:meta versioni2e');

  if (!hasPieces && (hasFileTree || hasMetaV2)) return null; // v2-only

  final btih = sha1.convert(infoBlob).toString();

  // Extract name from the info dict for the dn= parameter.
  String? name;
  try {
    final infoResult = _bparse(infoBlob, 0);
    final infoDict = infoResult.value;
    if (infoDict is Map<String, dynamic>) {
      final rawName = infoDict['name'];
      if (rawName is Uint8List) {
        name = utf8.decode(rawName, allowMalformed: true);
      } else if (rawName is String) {
        name = rawName;
      }
    }
  } catch (_) {
    // Non-fatal – proceed without dn=.
  }

  final buffer = StringBuffer('magnet:?xt=urn:btih:$btih');
  if (name != null && name.isNotEmpty) {
    buffer.write('&dn=${Uri.encodeComponent(name)}');
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// RealDebridClient
// ---------------------------------------------------------------------------

/// Dart port of the Python `RealDebridClient`.
///
/// Uses [Dio] for HTTP with automatic retry on 429 and 5xx responses.
class RealDebridClient {
  RealDebridClient({
    required String token,
    String? httpProxy,
    String? httpsProxy,
    List<String>? headers,
    String? oauthAccessToken,
    String? oauthRefreshToken,
    String? oauthClientId,
    String? oauthClientSecret,
    int retries = 3,
    double backoff = 0.8,
  })  : _retries = retries < 0 ? 0 : retries,
        _backoff = backoff < 0 ? 0 : backoff,
        _oauthRefreshToken = oauthRefreshToken,
        _oauthClientId = oauthClientId,
        _oauthClientSecret = oauthClientSecret,
        // Prefer OAuth access token when available.
        _token =
            (oauthAccessToken?.trim().isNotEmpty == true
                    ? oauthAccessToken!
                    : token)
                .trim() {
    final options = BaseOptions(
      baseUrl: _apiBase,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      followRedirects: true,
      maxRedirects: 10,
    );

    _dio = Dio(options);

    // Proxy configuration.
    if (httpProxy != null || httpsProxy != null) {
      _dio.httpClientAdapter = _buildProxiedAdapter(
        httpProxy: httpProxy,
        httpsProxy: httpsProxy,
      );
    }

    // Custom headers.
    if (headers != null) {
      for (final line in headers) {
        final colonIdx = line.indexOf(':');
        if (colonIdx > 0) {
          final k = line.substring(0, colonIdx).trim();
          final v = line.substring(colonIdx + 1).trim();
          _dio.options.headers[k] = v;
        }
      }
    }
  }

  late final Dio _dio;
  // Non-final: may be updated when an OAuth access token is refreshed.
  // ignore: prefer_final_fields
  String _token;
  // Stored for future token-refresh support.
  // ignore: unused_field
  final String? _oauthRefreshToken;
  // ignore: unused_field
  final String? _oauthClientId;
  // ignore: unused_field
  final String? _oauthClientSecret;
  final int _retries;
  final double _backoff;

  final _rng = Random();

  Options get _authOptions =>
      Options(headers: {'Authorization': 'Bearer $_token'});

  // -------------------------------------------------------------------------
  // Proxy adapter
  // -------------------------------------------------------------------------

  HttpClientAdapter _buildProxiedAdapter({
    String? httpProxy,
    String? httpsProxy,
  }) {
    final adapter = IOHttpClientAdapter()
      ..createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) {
          if (uri.scheme == 'https' && httpsProxy != null) {
            final p = Uri.parse(httpsProxy);
            return 'PROXY ${p.host}:${p.port}';
          }
          if (uri.scheme == 'http' && httpProxy != null) {
            final p = Uri.parse(httpProxy);
            return 'PROXY ${p.host}:${p.port}';
          }
          return 'DIRECT';
        };
        return client;
      };
    return adapter;
  }

  // -------------------------------------------------------------------------
  // Retry helpers
  // -------------------------------------------------------------------------

  double _retryDelay(int attempt, String? retryAfterHeader) {
    if (retryAfterHeader != null) {
      final parsed = double.tryParse(retryAfterHeader);
      if (parsed != null) return parsed;
    }
    return _backoff * pow(2, attempt).toDouble() + _rng.nextDouble() * _backoff;
  }

  bool _shouldRetry(int statusCode) =>
      statusCode == 429 || (statusCode >= 500 && statusCode < 600);

  Future<Response<T>> _getWithRetry<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    DioException? lastError;
    for (int attempt = 0; attempt <= _retries; attempt++) {
      try {
        final resp = await _dio.get<T>(
          path,
          queryParameters: queryParameters,
          options: options ?? _authOptions,
        );
        if (_shouldRetry(resp.statusCode ?? 0) && attempt < _retries) {
          final delay = _retryDelay(
            attempt,
            resp.headers.value('Retry-After'),
          );
          await Future<void>.delayed(
            Duration(milliseconds: (delay * 1000).round()),
          );
          continue;
        }
        return resp;
      } on DioException catch (e) {
        lastError = e;
        final statusCode = e.response?.statusCode;
        if (statusCode != null &&
            _shouldRetry(statusCode) &&
            attempt < _retries) {
          final delay = _retryDelay(
            attempt,
            e.response?.headers.value('Retry-After'),
          );
          await Future<void>.delayed(
            Duration(milliseconds: (delay * 1000).round()),
          );
          continue;
        }
        if (attempt >= _retries) rethrow;
      }
    }
    throw lastError ?? DioException(requestOptions: RequestOptions(path: path));
  }

  Future<Response<T>> _postWithRetry<T>(
    String path, {
    Object? data,
    Options? options,
  }) async {
    DioException? lastError;
    for (int attempt = 0; attempt <= _retries; attempt++) {
      try {
        final resp = await _dio.post<T>(
          path,
          data: data,
          options: options ?? _authOptions,
        );
        if (_shouldRetry(resp.statusCode ?? 0) && attempt < _retries) {
          final delay = _retryDelay(
            attempt,
            resp.headers.value('Retry-After'),
          );
          await Future<void>.delayed(
            Duration(milliseconds: (delay * 1000).round()),
          );
          continue;
        }
        return resp;
      } on DioException catch (e) {
        lastError = e;
        final statusCode = e.response?.statusCode;
        if (statusCode != null &&
            _shouldRetry(statusCode) &&
            attempt < _retries) {
          final delay = _retryDelay(
            attempt,
            e.response?.headers.value('Retry-After'),
          );
          await Future<void>.delayed(
            Duration(milliseconds: (delay * 1000).round()),
          );
          continue;
        }
        if (attempt >= _retries) rethrow;
      }
    }
    throw lastError ?? DioException(requestOptions: RequestOptions(path: path));
  }

  // -------------------------------------------------------------------------
  // Error formatting
  // -------------------------------------------------------------------------

  String _friendlyError(Response<dynamic> r) {
    try {
      final body = r.data;
      if (body is Map<String, dynamic> && body.containsKey('error')) {
        final msg = body['error'];
        final code = body['error_code'];
        if (code != null) {
          return 'HTTP ${r.statusCode}: $msg (code $code)';
        }
        return 'HTTP ${r.statusCode}: $msg';
      }
    } catch (_) {}
    final text = r.data?.toString() ?? '';
    final snippet = text.length > 200 ? text.substring(0, 200) : text;
    return 'HTTP ${r.statusCode}: $snippet';
  }

  String _friendlyDioError(DioException e) {
    final r = e.response;
    if (r != null) return _friendlyError(r);
    return 'Network error: ${e.message ?? e.type.name}';
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// POST /unrestrict/check – check whether a link is supported by RD.
  Future<Map<String, dynamic>> checkLink(String link) async {
    try {
      final resp = await _postWithRetry<dynamic>(
        '/unrestrict/check',
        data: FormData.fromMap({'link': link}),
      );
      if (resp.statusCode == 200) {
        final body = resp.data;
        if (body is Map<String, dynamic>) {
          return {'ok': true, 'link': link, ...body};
        }
        return {'ok': false, 'link': link, 'error': 'Invalid JSON'};
      }
      return {
        'ok': false,
        'link': link,
        'error': _friendlyError(resp),
      };
    } on DioException catch (e) {
      return {
        'ok': false,
        'link': link,
        'error': _friendlyDioError(e),
      };
    } catch (e) {
      return {'ok': false, 'link': link, 'error': e.toString()};
    }
  }

  /// POST /unrestrict/link – unrestrict a hoster link and return download info.
  ///
  /// Returns a map containing at minimum `download`, `filename`, and `filesize`
  /// on success, plus `ok: true`.
  Future<Map<String, dynamic>> unrestrictLink(String link) async {
    try {
      final resp = await _postWithRetry<dynamic>(
        '/unrestrict/link',
        data: FormData.fromMap({'link': link}),
      );
      if (resp.statusCode == 200) {
        final body = resp.data;
        if (body is Map<String, dynamic>) {
          return {'ok': true, ...body};
        }
        return {'ok': false, 'error': 'Invalid JSON'};
      }
      return {'ok': false, 'error': _friendlyError(resp)};
    } on DioException catch (e) {
      return {'ok': false, 'error': _friendlyDioError(e)};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// HEAD [url] following redirects; extract filename from Content-Disposition
  /// (RFC 5987 `filename*=` takes priority) or fall back to the URL path.
  Future<String?> headFilename(String url) async {
    try {
      final resp = await _dio.head<dynamic>(
        url,
        options: Options(
          followRedirects: true,
          receiveDataWhenStatusError: false,
          validateStatus: (_) => true,
        ),
      );
      final cd = resp.headers.value('content-disposition');
      if (cd != null) {
        final name = _parseCdFilename(cd);
        if (name != null && name.isNotEmpty) return name;
      }
      // Fallback to URL path segment.
      final resolvedUrl = resp.realUri.toString();
      final pathSegments = Uri.tryParse(resolvedUrl)?.pathSegments ?? [];
      if (pathSegments.isNotEmpty) {
        final last = Uri.decodeComponent(pathSegments.last);
        if (last.isNotEmpty) return last;
      }
      // Try original URL.
      final origSegments = Uri.tryParse(url)?.pathSegments ?? [];
      if (origSegments.isNotEmpty) {
        final last = Uri.decodeComponent(origSegments.last);
        if (last.isNotEmpty) return last;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Parse the `filename` or `filename*` parameter from a Content-Disposition
  /// header value.  RFC 5987 (`filename*=charset''percent-encoded`) takes
  /// priority.
  static String? _parseCdFilename(String value) {
    try {
      final parts = value.split(';').map((p) => p.trim()).toList();
      final params = <String, String>{};
      for (final p in parts.skip(1)) {
        final eq = p.indexOf('=');
        if (eq > 0) {
          final k = p.substring(0, eq).trim().toLowerCase();
          final v = p.substring(eq + 1).trim();
          params[k] = v;
        }
      }
      // RFC 5987: filename*=charset''encoded
      final star = params['filename*'];
      if (star != null) {
        var s = star.replaceAll('"', '');
        if (s.contains("''")) {
          final sep = s.indexOf("''");
          s = s.substring(sep + 2);
        }
        return Uri.decodeComponent(s);
      }
      final plain = params['filename'];
      if (plain != null) return plain.replaceAll('"', '');
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------------------
  // Torrent endpoints
  // -------------------------------------------------------------------------

  /// PUT /torrents/addTorrent – upload a `.torrent` file.
  ///
  /// On `400 torrent_file_invalid`, automatically falls back to computing the
  /// BTIH from the info dict and calling [addMagnet].
  ///
  /// Returns a map with `ok: true` and the RD torrent ID in `id` on success.
  Future<Map<String, dynamic>> addTorrent(String filePath) async {
    try {
      final fileBytes = await File(filePath).readAsBytes();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: File(filePath).uri.pathSegments.last,
          contentType: DioMediaType('application', 'x-bittorrent'),
        ),
      });

      final authOptions = Options(
        headers: {'Authorization': 'Bearer $_token'},
        validateStatus: (s) => true,
      );

      final resp = await _dio.put<dynamic>(
        '/torrents/addTorrent',
        data: formData,
        options: authOptions,
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final body = resp.data;
        if (body is Map<String, dynamic>) {
          return {'ok': true, 'http_status': resp.statusCode, ...body};
        }
        return {
          'ok': false,
          'http_status': resp.statusCode,
          'error': 'Invalid JSON',
        };
      }

      // Attempt magnet fallback on invalid torrent error.
      final errMsg = _friendlyError(resp);
      if (resp.statusCode == 400 && errMsg.contains('torrent_file_invalid')) {
        return await _magnetFallback(filePath, errMsg);
      }

      return {
        'ok': false,
        'http_status': resp.statusCode,
        'error': errMsg,
      };
    } on DioException catch (e) {
      final resp = e.response;
      if (resp != null) {
        final errMsg = _friendlyError(resp);
        if (resp.statusCode == 400 && errMsg.contains('torrent_file_invalid')) {
          return await _magnetFallback(filePath, errMsg);
        }
        return {
          'ok': false,
          'http_status': resp.statusCode,
          'error': errMsg,
        };
      }
      return {'ok': false, 'error': _friendlyDioError(e)};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _magnetFallback(
    String filePath,
    String originalError,
  ) async {
    try {
      final magnet = torrentToMagnet(filePath);
      if (magnet == null) {
        // null means v2-only torrent.
        return {'ok': false, 'error': 'torrent_v2_only_unsupported'};
      }
      final m = await addMagnet(magnet);
      if (m['ok'] == true) {
        return {...m, 'via': 'magnet', 'magnet': magnet};
      }
      return {...m, 'magnet': magnet};
    } catch (e) {
      return {'ok': false, 'error': 'Magnet fallback failed: $e'};
    }
  }

  /// POST /torrents/addMagnet – add a torrent via magnet URI.
  Future<Map<String, dynamic>> addMagnet(String magnet) async {
    try {
      final authOptions = Options(
        headers: {'Authorization': 'Bearer $_token'},
        validateStatus: (s) => true,
      );
      final resp = await _dio.post<dynamic>(
        '/torrents/addMagnet',
        data: FormData.fromMap({'magnet': magnet}),
        options: authOptions,
      );
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final body = resp.data;
        if (body is Map<String, dynamic>) {
          return {'ok': true, 'http_status': resp.statusCode, ...body};
        }
        return {
          'ok': false,
          'http_status': resp.statusCode,
          'error': 'Invalid JSON',
        };
      }
      return {
        'ok': false,
        'http_status': resp.statusCode,
        'error': _friendlyError(resp),
      };
    } on DioException catch (e) {
      return {'ok': false, 'error': _friendlyDioError(e)};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// GET /torrents/info/{id} – get torrent metadata and status.
  Future<Map<String, dynamic>> torrentInfo(String torrentId) async {
    try {
      final resp = await _getWithRetry<dynamic>('/torrents/info/$torrentId');
      if (resp.statusCode == 200) {
        final body = resp.data;
        if (body is Map<String, dynamic>) {
          return {'ok': true, 'http_status': resp.statusCode, ...body};
        }
        return {
          'ok': false,
          'http_status': resp.statusCode,
          'error': 'Invalid JSON',
        };
      }
      return {
        'ok': false,
        'http_status': resp.statusCode,
        'error': _friendlyError(resp),
      };
    } on DioException catch (e) {
      return {'ok': false, 'error': _friendlyDioError(e)};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// POST /torrents/selectFiles/{id} – select which files to download.
  ///
  /// [fileIds] can contain integer IDs; an empty list or a list with the single
  /// string `'all'` selects all files.
  Future<void> selectTorrentFiles(String torrentId, List<int> fileIds) async {
    final filesParam = fileIds.isEmpty ? 'all' : fileIds.join(',');
    final authOptions = Options(
      headers: {'Authorization': 'Bearer $_token'},
      validateStatus: (s) => true,
    );
    final resp = await _dio.post<dynamic>(
      '/torrents/selectFiles/$torrentId',
      data: FormData.fromMap({'files': filesParam}),
      options: authOptions,
    );
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception(_friendlyError(resp));
    }
  }

  /// DELETE /torrents/delete/{id} – remove a torrent from the RD account.
  Future<void> deleteTorrent(String torrentId) async {
    final authOptions = Options(
      headers: {'Authorization': 'Bearer $_token'},
      validateStatus: (s) => true,
    );
    final resp = await _dio.delete<dynamic>(
      '/torrents/delete/$torrentId',
      options: authOptions,
    );
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception(_friendlyError(resp));
    }
  }
}
