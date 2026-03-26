/// aria2c JSON-RPC 2.0 client implemented over HTTP using Dio.
///
/// Dart port of the Python [Aria2Client._rpc] layer and all public RPC methods.
/// This class handles only the network communication; process lifecycle is
/// managed separately by [Aria2ProcessService] in [aria2_process.dart].
library;

import 'dart:async';

import 'package:dio/dio.dart';

import 'aria2_models.dart';

/// Low-level JSON-RPC 2.0 client for an already-running aria2c daemon.
///
/// Construct with the [port] the daemon is listening on and the [secret] token
/// used to authenticate RPC calls.  Both values must match what was used when
/// the daemon was started.
///
/// Example:
/// ```dart
/// final client = Aria2RpcClient(port: 6800, secret: 'mySecret');
/// final version = await client.getVersion();
/// ```
class Aria2RpcClient {
  final int port;
  final String secret;

  late final Dio _dio;
  late final String _url;

  /// Number of times a transient server error (502/503/504) is retried before
  /// propagating the exception – mirrors the Python implementation.
  static const int _maxRetries = 3;

  /// Base delay in milliseconds for exponential back-off; doubles each attempt.
  static const int _backoffBaseMs = 200;

  Aria2RpcClient({this.port = 6800, required this.secret}) {
    _url = 'http://127.0.0.1:$port/jsonrpc';
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
        sendTimeout: const Duration(seconds: 3),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Core RPC transport
  // ---------------------------------------------------------------------------

  /// Send a JSON-RPC 2.0 request to aria2c and return the [result] value.
  ///
  /// Prepends the authentication token to [params] automatically.
  /// Retries up to [_maxRetries] times on HTTP 502/503/504 or connection
  /// errors, applying exponential back-off between attempts.
  Future<dynamic> _rpc(String method, [List<dynamic>? params]) async {
    final payload = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'aria2.$method',
      'params': <dynamic>['token:$secret', ...(params ?? [])],
    };

    Object? lastError;

    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          _url,
          data: payload,
        );

        final statusCode = response.statusCode ?? 0;
        if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
          lastError = DioException(
            requestOptions: response.requestOptions,
            response: response,
            message: 'HTTP $statusCode',
          );
          await _backoff(attempt);
          continue;
        }

        final body = response.data;
        if (body == null) {
          throw StateError('aria2 RPC returned empty response for $method');
        }

        if (body.containsKey('error')) {
          final err = body['error'];
          throw StateError('aria2 RPC error [$method]: $err');
        }

        return body['result'];
      } on DioException catch (e) {
        lastError = e;
        // Only retry on connection/server errors; surface client errors fast.
        final code = e.response?.statusCode;
        if (code != null && code < 500 && code != 502 && code != 503 && code != 504) {
          rethrow;
        }
        await _backoff(attempt);
      }
    }

    throw lastError ?? StateError('aria2 RPC failed after $_maxRetries attempts [$method]');
  }

  Future<void> _backoff(int attempt) async {
    final ms = _backoffBaseMs * (1 << attempt); // 200, 400, 800 …
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  // ---------------------------------------------------------------------------
  // Version / info
  // ---------------------------------------------------------------------------

  /// Returns version information for the running aria2c daemon.
  Future<Map<String, dynamic>> getVersion() async {
    final result = await _rpc('getVersion');
    return (result as Map?)?.cast<String, dynamic>() ?? {};
  }

  // ---------------------------------------------------------------------------
  // Adding downloads
  // ---------------------------------------------------------------------------

  /// Add a download by URI(s).
  ///
  /// [uris] is a list of HTTP/FTP/BitTorrent URIs for the same resource.
  /// [options] is an optional map of aria2 per-download options.
  ///
  /// Returns the GID of the newly created task.
  Future<String> addUri(
    List<String> uris, {
    Map<String, String>? options,
  }) async {
    final result = await _rpc('addUri', [uris, options ?? <String, String>{}]);
    return result as String;
  }

  // ---------------------------------------------------------------------------
  // Querying downloads
  // ---------------------------------------------------------------------------

  /// Returns the list of currently active downloads.
  Future<List<Aria2Task>> tellActive({List<String>? keys}) async {
    final params = keys != null ? [keys] : <dynamic>[];
    final result = await _rpc('tellActive', params);
    return _parseTaskList(result);
  }

  /// Returns [num] waiting (queued) downloads starting at [offset].
  Future<List<Aria2Task>> tellWaiting(
    int offset,
    int num, {
    List<String>? keys,
  }) async {
    final params = <dynamic>[offset, num];
    if (keys != null) params.add(keys);
    final result = await _rpc('tellWaiting', params);
    return _parseTaskList(result);
  }

  /// Returns [num] stopped (completed or removed) downloads starting at [offset].
  Future<List<Aria2Task>> tellStopped(
    int offset,
    int num, {
    List<String>? keys,
  }) async {
    final params = <dynamic>[offset, num];
    if (keys != null) params.add(keys);
    final result = await _rpc('tellStopped', params);
    return _parseTaskList(result);
  }

  /// Returns the status of the download identified by [gid].
  Future<Aria2Task> tellStatus(String gid, {List<String>? keys}) async {
    final params = <dynamic>[gid];
    if (keys != null) params.add(keys);
    final result = await _rpc('tellStatus', params);
    if (result is Map<String, dynamic>) {
      return Aria2Task.fromJson(result);
    }
    throw StateError('Unexpected tellStatus response: $result');
  }

  /// Returns aggregate global statistics.
  Future<Aria2GlobalStat> getGlobalStat() async {
    final result = await _rpc('getGlobalStat');
    if (result is Map<String, dynamic>) {
      return Aria2GlobalStat.fromJson(result);
    }
    throw StateError('Unexpected getGlobalStat response: $result');
  }

  // ---------------------------------------------------------------------------
  // Options
  // ---------------------------------------------------------------------------

  /// Returns the options for the download identified by [gid].
  Future<Map<String, dynamic>> getOption(String gid) async {
    final result = await _rpc('getOption', [gid]);
    return (result as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// Changes per-download options for [gid].
  Future<void> changeOption(String gid, Map<String, String> options) async {
    await _rpc('changeOption', [gid, options]);
  }

  /// Changes global options for the running aria2c session.
  Future<void> changeGlobalOption(Map<String, String> options) async {
    await _rpc('changeGlobalOption', [options]);
  }

  // ---------------------------------------------------------------------------
  // Pause / Resume
  // ---------------------------------------------------------------------------

  /// Pauses the download identified by [gid].
  ///
  /// Returns the GID of the paused task.
  Future<String> pause(String gid) async {
    final result = await _rpc('pause', [gid]);
    return result as String;
  }

  /// Resumes the download identified by [gid].
  ///
  /// Returns the GID of the resumed task.
  Future<String> unpause(String gid) async {
    final result = await _rpc('unpause', [gid]);
    return result as String;
  }

  /// Pauses all active downloads.
  Future<void> pauseAll() async {
    await _rpc('pauseAll');
  }

  /// Resumes all paused downloads.
  Future<void> unpauseAll() async {
    await _rpc('unpauseAll');
  }

  // ---------------------------------------------------------------------------
  // Remove / Clean-up
  // ---------------------------------------------------------------------------

  /// Removes the download identified by [gid].
  ///
  /// Returns the GID of the removed task.
  Future<String> remove(String gid) async {
    final result = await _rpc('remove', [gid]);
    return result as String;
  }

  /// Forcefully removes the download identified by [gid] without waiting for
  /// any pending operations to complete.
  ///
  /// Returns the GID of the removed task.
  Future<String> forceRemove(String gid) async {
    final result = await _rpc('forceRemove', [gid]);
    return result as String;
  }

  /// Removes all completed/error/removed downloads from aria2's in-memory
  /// result list.
  Future<void> purgeDownloadResult() async {
    try {
      await _rpc('purgeDownloadResult');
    } catch (_) {
      // Non-fatal – mirrors the Python implementation that silently ignores
      // errors from this call.
    }
  }

  // ---------------------------------------------------------------------------
  // Shutdown
  // ---------------------------------------------------------------------------

  /// Requests a graceful shutdown of the aria2c daemon.
  Future<void> shutdown() async {
    await _rpc('shutdown');
  }

  /// Requests an immediate (forced) shutdown of the aria2c daemon.
  Future<void> forceShutdown() async {
    await _rpc('forceShutdown');
  }

  // ---------------------------------------------------------------------------
  // Composite helpers
  // ---------------------------------------------------------------------------

  /// Forcefully removes all active and waiting downloads, then purges results.
  ///
  /// Mirrors [Aria2Client.remove_all] from the Python implementation.
  Future<void> removeAll() async {
    List<Aria2Task> active = [];
    List<Aria2Task> waiting = [];

    try {
      active = await tellActive();
    } catch (_) {}
    try {
      waiting = await tellWaiting(0, 1000);
    } catch (_) {}

    for (final task in [...active, ...waiting]) {
      if (task.gid.isNotEmpty) {
        try {
          await forceRemove(task.gid);
        } catch (_) {}
      }
    }

    await purgeDownloadResult();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  List<Aria2Task> _parseTaskList(dynamic result) {
    if (result is! List) return [];
    return result
        .whereType<Map<String, dynamic>>()
        .map(Aria2Task.fromJson)
        .toList();
  }

  /// Closes the underlying Dio client.  Call this when the [Aria2RpcClient]
  /// will no longer be used (e.g. after the daemon has been shut down).
  void dispose() {
    _dio.close();
  }
}
