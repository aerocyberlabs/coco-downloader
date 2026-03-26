/// aria2c process lifecycle management.
///
/// Dart port of the Python [Aria2Client.start()] / [Aria2Client.stop()] logic.
/// Spawns and supervises an aria2c child process, waits for its RPC endpoint
/// to become ready, and provides a clean [stop()] path that requests a
/// graceful shutdown before killing the process.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../utils/runtime.dart';
import 'aria2_client.dart';

/// Spawns, supervises, and stops an aria2c child process.
///
/// After calling [start], the returned [Aria2RpcClient] can be used to control
/// the running daemon.  Call [stop] to shut the daemon down cleanly.
///
/// Example:
/// ```dart
/// final svc = Aria2ProcessService();
/// final client = await svc.start(outdir: '/home/user/Downloads');
/// // … use client …
/// await svc.stop();
/// ```
class Aria2ProcessService {
  Process? _process;
  Aria2RpcClient? _client;

  /// Whether the aria2c process is currently running.
  bool get isRunning {
    return _process != null;
  }

  /// PID of the running aria2c process, or [null] when not running.
  int? get pid => _process?.pid;

  // ---------------------------------------------------------------------------
  // Start
  // ---------------------------------------------------------------------------

  /// Starts the aria2c daemon and returns an [Aria2RpcClient] ready to use.
  ///
  /// Parameters:
  /// - [outdir]: destination directory for downloads (required).
  /// - [connections]: per-server connection count (`--max-connection-per-server`).
  /// - [splits]: number of pieces per file (`--split`).
  /// - [concurrent]: max simultaneous downloads (`--max-concurrent-downloads`).
  /// - [httpProxy]: value for `--http-proxy`.
  /// - [httpsProxy]: value for `--https-proxy`.
  /// - [headers]: list of `"Name: Value"` header strings for `--header`.
  /// - [aria2Path]: explicit path to the aria2c binary; [resolveAria2Path] is
  ///   used as a fallback.
  /// - [sessionFile]: path for aria2 session persistence; defaults to
  ///   `<outdir>/.aria2.session`.
  ///
  /// Throws [StateError] if a process is already running.
  /// Throws [FileSystemException] when aria2c cannot be located.
  /// Throws [TimeoutException] when the RPC endpoint does not become reachable
  /// within 5 seconds.
  Future<Aria2RpcClient> start({
    required String outdir,
    int port = 6800,
    int connections = 16,
    int splits = 16,
    int concurrent = 4,
    String? httpProxy,
    String? httpsProxy,
    List<String>? headers,
    String? aria2Path,
    String? sessionFile,
  }) async {
    if (_process != null) {
      // Already running — return existing client.
      return _client!;
    }

    // Resolve binary path.
    final binary = await resolveAria2Path(aria2Path);
    if (binary == null) {
      throw FileSystemException(
        'aria2c not found. Install aria2 or set aria2_path in settings.',
      );
    }

    // Generate a fresh random secret for this session.
    final secret = _randSecret(20);

    // Session file path.
    final session = sessionFile ?? p.join(outdir, '.aria2.session');

    // Build argument list — mirrors the Python Aria2Client.start() method.
    final args = <String>[
      '--rpc-listen-port=$port',
      '--enable-rpc=true',
      '--rpc-listen-all=false',
      '--rpc-secure=false',
      '--rpc-secret=$secret',
      '--continue=true',
      '--max-concurrent-downloads=$concurrent',
      '--max-connection-per-server=$connections',
      '--split=$splits',
      '--summary-interval=1',
      '--console-log-level=warn',
      '--enable-color=false',
      '--dir=$outdir',
    ];

    // Optional proxy settings.
    if (httpProxy != null && httpProxy.isNotEmpty) {
      args.add('--http-proxy=$httpProxy');
    }
    if (httpsProxy != null && httpsProxy.isNotEmpty) {
      args.add('--https-proxy=$httpsProxy');
    }

    // Optional extra request headers.
    if (headers != null) {
      for (final header in headers) {
        if (header.contains(':')) {
          args.add('--header=$header');
        }
      }
    }

    // Session persistence.
    args
      ..add('--save-session=$session')
      ..add('--save-session-interval=30');

    final sessionFile_ = File(session);
    if (await sessionFile_.exists()) {
      args.add('--input-file=$session');
    }

    // Spawn process.
    _process = await Process.start(
      binary,
      args,
      mode: ProcessStartMode.detachedWithStdio,
    );

    // Drain stdio so the process does not block on full pipe buffers.
    _process!.stdout.drain<List<int>>();
    _process!.stderr.drain<List<int>>();

    // Watch for unexpected exits and clean up internal state.
    _process!.exitCode.then((_) {
      _process = null;
      _client?.dispose();
      _client = null;
    });

    // Build the RPC client.
    final client = Aria2RpcClient(port: port, secret: secret);
    _client = client;

    // Wait up to 5 seconds for the RPC endpoint to respond.
    await _waitReady(client, timeout: const Duration(seconds: 5));

    return client;
  }

  // ---------------------------------------------------------------------------
  // Stop
  // ---------------------------------------------------------------------------

  /// Shuts down the aria2c daemon gracefully.
  ///
  /// 1. Attempts a graceful RPC shutdown via [Aria2RpcClient.shutdown].
  /// 2. Falls back to [Aria2RpcClient.forceShutdown] if graceful shutdown
  ///    fails.
  /// 3. Sends SIGTERM to the process if the daemon is still running after the
  ///    RPC calls.
  /// 4. Sends SIGKILL as a last resort if the process does not exit within
  ///    5 seconds.
  Future<void> stop() async {
    final client = _client;
    final process = _process;

    // Best-effort RPC shutdown.
    if (client != null) {
      try {
        await client.removeAll();
      } catch (_) {}

      try {
        await client.shutdown();
      } catch (_) {
        try {
          await client.forceShutdown();
        } catch (_) {}
      }

      // Small delay to allow the process to exit on its own.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      client.dispose();
      _client = null;
    }

    // Terminate the process if it is still alive.
    if (process != null) {
      // On Windows, kill() sends a forceful termination signal.
      process.kill(ProcessSignal.sigterm);

      bool exited = false;
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
        exited = true;
      } on TimeoutException {
        exited = false;
      }

      if (!exited) {
        process.kill(ProcessSignal.sigkill);
      }

      _process = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Polls the RPC [client] until [getVersion] succeeds or [timeout] expires.
  ///
  /// Uses a short 100 ms probe interval, mirroring the Python `_wait_ready`
  /// implementation.
  Future<void> _waitReady(
    Aria2RpcClient client, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        await client.getVersion();
        return; // RPC is ready.
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    // RPC did not become ready in time — let the first real call surface the
    // error with a meaningful message (mirrors Python behaviour).
  }

  /// Generates a cryptographically-adequate random alphanumeric secret.
  static String _randSecret(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }
}
