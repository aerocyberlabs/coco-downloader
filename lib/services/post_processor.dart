/// Post-download processing pipeline.
///
/// Dart port of [_post_process_completed()] from [app.py].
/// Handles ZIP extraction, SHA-256 deduplication, and AES encryption of
/// completed download files.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/app_config.dart';

/// Result reported back to the caller for each processed file.
class PostProcessResult {
  const PostProcessResult({
    required this.originalPath,
    this.finalPath,
    this.extracted = false,
    this.duplicate = false,
    this.encrypted = false,
    this.sha256,
    this.error,
  });

  /// Absolute path of the file passed into the pipeline.
  final String originalPath;

  /// Absolute path of the file after any move/rename (may differ from
  /// [originalPath] when the file was deduped or encrypted).
  final String? finalPath;

  /// True when a ZIP archive was extracted successfully.
  final bool extracted;

  /// True when the file was identified as a duplicate and moved to
  /// `Duplicates/`.
  final bool duplicate;

  /// True when the file was encrypted to a `.enc` file.
  final bool encrypted;

  /// Hex SHA-256 digest computed during the pipeline, if available.
  final String? sha256;

  /// Non-null when an unrecoverable error occurred.
  final String? error;

  @override
  String toString() =>
      'PostProcessResult(originalPath: $originalPath, '
      'finalPath: $finalPath, extracted: $extracted, '
      'duplicate: $duplicate, encrypted: $encrypted, '
      'sha256: ${sha256?.substring(0, 8)}…, error: $error)';
}

/// Post-download processing pipeline.
///
/// Call [processCompletedFile] once per file that has finished downloading.
/// The pipeline runs in the following order:
///   1. Auto-extract ZIP (if [AppConfig.autoExtractZip] and file is .zip).
///   2. SHA-256 deduplication (if [AppConfig.dedupOnComplete]).
///   3. AES encryption (if [AppConfig.encryptCompleted] and password set).
///
/// [PostProcessor] is stateless with respect to individual files; all
/// persistent state (the hash index) is passed in via [AppConfig] and the
/// updated index is returned inside [PostProcessResult] so the caller can
/// persist it.
class PostProcessor {
  const PostProcessor();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Run the full post-processing pipeline on [filePath].
  ///
  /// [outDir] is the download output directory used to resolve relative
  /// dedup paths and the `Duplicates/` sub-folder.
  ///
  /// Returns a [PostProcessResult] describing what happened. Errors inside
  /// individual steps are caught and reported via [PostProcessResult.error]
  /// rather than thrown, so the caller always gets a result.
  Future<PostProcessResult> processCompletedFile(
    String filePath,
    String outDir,
    AppConfig config, {
    /// Mutable copy of the hash index that this call may update in-place.
    /// If omitted the index from [config] is used (read-only).
    Map<String, String>? hashIndex,
  }) async {
    String currentPath = filePath;
    bool extracted = false;
    bool duplicate = false;
    bool encrypted = false;
    String? digest;
    String? errorMsg;

    final index = hashIndex ?? Map<String, String>.from(config.hashIndex);

    // ----- Step 1: Auto-extract ZIP ----------------------------------------
    if (config.autoExtractZip &&
        currentPath.toLowerCase().endsWith('.zip') &&
        await File(currentPath).exists()) {
      try {
        await extractZip(currentPath, outDir);
        extracted = true;
        debugPrint('[PostProcessor] Extracted: $currentPath');
      } catch (e) {
        errorMsg = 'Extract failed: $e';
        debugPrint('[PostProcessor] $errorMsg');
      }
    }

    // ----- Step 2: SHA-256 hash (needed for dedup and possibly encryption) --
    if (await File(currentPath).exists()) {
      try {
        digest = await computeSha256(currentPath);
      } catch (e) {
        debugPrint('[PostProcessor] Hash failed for $currentPath: $e');
      }
    }

    // ----- Step 3: Dedup ----------------------------------------------------
    if (config.dedupOnComplete && digest != null) {
      final existingPath = index[digest];
      if (existingPath != null && await File(existingPath).exists()) {
        // Duplicate – move to Duplicates/ sub-folder.
        try {
          final dupDir = p.join(outDir, 'Duplicates');
          await Directory(dupDir).create(recursive: true);
          final destPath = p.join(dupDir, p.basename(currentPath));
          await File(currentPath).rename(destPath);
          currentPath = destPath;
          duplicate = true;
          debugPrint('[PostProcessor] Duplicate moved: ${p.basename(destPath)}');
        } catch (e) {
          errorMsg = 'Move duplicate failed: $e';
          debugPrint('[PostProcessor] $errorMsg');
        }
      } else {
        // New file – record in index.
        index[digest] = currentPath;
      }
    }

    // ----- Step 4: Encryption -----------------------------------------------
    if (!duplicate &&
        config.encryptCompleted &&
        (config.vaultPassword?.isNotEmpty ?? false) &&
        await File(currentPath).exists()) {
      try {
        final encPath = await encryptFile(currentPath, config.vaultPassword!);
        currentPath = encPath;
        encrypted = true;
        debugPrint('[PostProcessor] Encrypted: ${p.basename(encPath)}');
      } catch (e) {
        errorMsg = 'Encrypt failed: $e';
        debugPrint('[PostProcessor] $errorMsg');
      }
    }

    return PostProcessResult(
      originalPath: filePath,
      finalPath: currentPath,
      extracted: extracted,
      duplicate: duplicate,
      encrypted: encrypted,
      sha256: digest,
      error: errorMsg,
    );
  }

  // ---------------------------------------------------------------------------
  // SHA-256
  // ---------------------------------------------------------------------------

  /// Compute the SHA-256 digest of [filePath] in 64 KiB chunks.
  ///
  /// Reads the file incrementally to avoid loading large downloads into memory.
  Future<String> computeSha256(String filePath) async {
    const chunkSize = 64 * 1024; // 64 KiB

    // Collect the single Digest emitted after close().
    Digest? result;
    final digestSink = _SingleValueSink<Digest>(onValue: (d) => result = d);
    final input = sha256.startChunkedConversion(digestSink);

    final file = File(filePath);
    final raf = await file.open();
    try {
      while (true) {
        final chunk = await raf.read(chunkSize);
        if (chunk.isEmpty) break;
        input.add(chunk);
      }
    } finally {
      await raf.close();
    }
    input.close();
    return result!.toString();
  }

  // ---------------------------------------------------------------------------
  // ZIP extraction
  // ---------------------------------------------------------------------------

  /// Extract [zipPath] into [destDir].
  ///
  /// Uses the [archive] package for pure-Dart in-process extraction.
  /// Attempts to fall back to the system `unzip` command if the archive
  /// package throws (e.g. unsupported compression method).
  Future<void> extractZip(String zipPath, String destDir) async {
    try {
      await _extractZipWithArchivePackage(zipPath, destDir);
    } catch (archiveErr) {
      debugPrint(
        '[PostProcessor] archive package failed ($archiveErr), '
        'falling back to system unzip',
      );
      await _extractZipWithSystem(zipPath, destDir);
    }
  }

  Future<void> _extractZipWithArchivePackage(
    String zipPath,
    String destDir,
  ) async {
    // extractFileToDisk is provided by archive_io and works in isolates.
    await extractFileToDisk(zipPath, destDir);
  }

  Future<void> _extractZipWithSystem(String zipPath, String destDir) async {
    final ProcessResult result;
    if (Platform.isWindows) {
      // PowerShell Expand-Archive is available on Windows 10+.
      // Use -LiteralPath via argument list to avoid command injection.
      result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive',
        '-Force',
        '-LiteralPath',
        zipPath,
        '-DestinationPath',
        destDir,
      ]);
    } else {
      result = await Process.run('unzip', ['-o', zipPath, '-d', destDir]);
    }
    if (result.exitCode != 0) {
      throw ProcessException(
        Platform.isWindows ? 'powershell' : 'unzip',
        [],
        'Extraction failed (exit ${result.exitCode}): ${result.stderr}',
        result.exitCode,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Encryption
  // ---------------------------------------------------------------------------

  /// Encrypt [filePath] using AES-CBC with a SHA-256 derived key.
  ///
  /// NOTE: This is NOT compatible with Python's Fernet encryption.
  /// Files encrypted here cannot be decrypted by the Python app and vice versa.
  /// Scheme:
  ///   1. Derive a 256-bit key: `SHA-256(password.utf8)`.
  ///   2. Generate a random 128-bit IV.
  ///   3. Encrypt the file bytes with AES-CBC (PKCS7 padding).
  ///   4. Write `IV (16 bytes) || ciphertext` to `<filePath>.enc`.
  ///   5. Delete the original file.
  ///
  /// Returns the path of the encrypted `.enc` file.
  Future<String> encryptFile(String filePath, String password) async {
    final rawKey = sha256.convert(utf8.encode(password)).bytes;
    final key = enc.Key(Uint8List.fromList(rawKey));
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    final plainBytes = await File(filePath).readAsBytes();
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);

    // Layout: 16-byte IV followed by ciphertext.
    final outBytes = Uint8List(16 + encrypted.bytes.length);
    outBytes.setRange(0, 16, iv.bytes);
    outBytes.setRange(16, outBytes.length, encrypted.bytes);

    final encPath = '$filePath.enc';
    await File(encPath).writeAsBytes(outBytes, flush: true);

    // Verify the encrypted file was written correctly before deleting original.
    final encStat = await File(encPath).stat();
    if (encStat.size != outBytes.length) {
      throw StateError(
        'Encrypted file size mismatch: expected ${outBytes.length}, '
        'got ${encStat.size}. Original file preserved at $filePath.',
      );
    }
    await File(filePath).delete();
    return encPath;
  }
}

/// Module-level singleton for convenience.
const postProcessor = PostProcessor();

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// A minimal [Sink] that stores the single value emitted into it.
///
/// Used to capture the [Digest] produced by [sha256.startChunkedConversion]
/// without relying on package-private [DigestSink] from the `crypto` package.
class _SingleValueSink<T> implements Sink<T> {
  _SingleValueSink({required this.onValue});

  final void Function(T value) onValue;

  @override
  void add(T data) => onValue(data);

  @override
  void close() {}
}
