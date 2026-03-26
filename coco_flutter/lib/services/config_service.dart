import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../constants.dart';

/// Keyring service name used for secure token storage.
///
/// Mirrors the Python [APP_NAME] constant ("Coco Downloader") so that tokens
/// written by one implementation are readable by the other during migration
/// periods.
const _keyringService = appName;

/// Composite storage key: "<service>/<attribute>".
///
/// flutter_secure_storage uses a flat key namespace, so we embed the service
/// name in the key to mirror the Python keyring.set_password(APP_NAME, "token")
/// call and avoid collisions with other applications.
const _keyringTokenKey = '$_keyringService/token';

/// Old config directory written by the Python realdebrid_gui predecessor.
const _oldConfigDirName = 'realdebrid_gui';

/// Configuration management service for Coco Downloader.
///
/// This service is the Dart equivalent of [config.py] in the Python backend.
/// It handles:
///   - Reading/writing the JSON config file at the platform-appropriate path.
///   - Secure token storage via [flutter_secure_storage] (mirrors Python keyring).
///   - One-time migration from the old ~/.config/realdebrid_gui/ directory.
///
/// The service works with raw [Map<String, dynamic>] so it can operate
/// independently of the AppConfig model. When the model is available the
/// caller should convert with [AppConfig.fromJson] / [AppConfig.toJson].
class ConfigService {
  ConfigService._();

  static final ConfigService instance = ConfigService._();

  // flutter_secure_storage is lazily created so the service can be
  // instantiated on every platform without crashing; actual read/write calls
  // are guarded by [keyringAvailable].
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    // Use the most appropriate backend per platform.
    linuxOptions: LinuxOptions(),
    macOsOptions: MacOsOptions(),
    windowsOptions: WindowsOptions(),
  );

  // ---------------------------------------------------------------------------
  // Paths
  // ---------------------------------------------------------------------------

  /// Returns the platform-specific configuration directory path.
  ///
  /// - Linux / other POSIX: `~/.config/coco-downloader/`
  /// - macOS: `~/Library/Application Support/coco-downloader/`
  /// - Windows: `%APPDATA%\coco-downloader\`
  Future<String> get configDir async {
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      return '$home/.config/$appSlug';
    }
    if (Platform.isMacOS) {
      final support = await getApplicationSupportDirectory();
      return '${support.path}/$appSlug';
    }
    if (Platform.isWindows) {
      final appData =
          Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '.';
      return '$appData\\$appSlug';
    }
    // Android / iOS / Fuchsia – fall back to the documents directory.
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/$appSlug';
  }

  /// Full path to the JSON configuration file.
  ///
  /// Linux/macOS: `~/.config/coco-downloader/config.json`
  Future<String> get configPath async {
    final dir = await configDir;
    if (Platform.isWindows) return '$dir\\config.json';
    return '$dir/config.json';
  }

  /// Directory used for log files (config dir + /logs/).
  Future<String> get logPath async {
    final dir = await configDir;
    if (Platform.isWindows) return '$dir\\logs\\';
    return '$dir/logs/';
  }

  // ---------------------------------------------------------------------------
  // Load / Save
  // ---------------------------------------------------------------------------

  /// Load configuration from disk.
  ///
  /// Returns an empty map when the file does not exist or cannot be parsed,
  /// mirroring the Python [load_config] behaviour.
  Future<Map<String, dynamic>> loadConfig() async {
    try {
      final path = await configPath;
      final file = File(path);
      if (!await file.exists()) return {};
      final contents = await file.readAsString();
      final decoded = jsonDecode(contents);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (e) {
      debugPrint('[ConfigService] loadConfig error: $e');
      return {};
    }
  }

  /// Save [config] to disk as indented JSON.
  ///
  /// Creates the config directory if necessary and, on POSIX platforms, sets
  /// directory permissions to 0700 and file permissions to 0600 – matching the
  /// Python [save_config] implementation.
  Future<void> saveConfig(Map<String, dynamic> config) async {
    try {
      final dirPath = await configDir;
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // chmod 700 on the directory (POSIX only).
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['700', dirPath]);
        } catch (_) {
          // Ignore chmod failures – e.g. on read-only file systems.
        }
      }

      final path = await configPath;
      final file = File(path);
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(config));

      // chmod 600 on the file (POSIX only).
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['600', path]);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[ConfigService] saveConfig error: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Migration
  // ---------------------------------------------------------------------------

  /// Migrate the old `~/.config/realdebrid_gui/` directory.
  ///
  /// Mirrors the top-level migration logic in [config.py]:
  ///   1. If the old directory exists and the new one does not, try a rename.
  ///   2. On failure, copy files individually.
  ///
  /// Safe to call multiple times; does nothing after the first migration.
  Future<void> migrateOldConfig() async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    try {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return;

      final oldDir = Directory('$home/.config/$_oldConfigDirName');
      final newDirPath = await configDir;
      final newDir = Directory(newDirPath);

      if (!await oldDir.exists()) return;
      if (await newDir.exists()) return;

      // Prefer rename (preserves permissions).
      try {
        await oldDir.rename(newDirPath);
        debugPrint('[ConfigService] Migrated config via rename.');
        return;
      } catch (_) {
        // Rename may fail across filesystems; fall through to copy.
      }

      await newDir.create(recursive: true);
      await for (final entity in oldDir.list()) {
        try {
          final target = '${newDir.path}/${entity.uri.pathSegments.last}';
          if (entity is File) {
            await entity.copy(target);
          } else if (entity is Directory) {
            await _copyDirectory(entity, Directory(target));
          }
        } catch (e) {
          debugPrint('[ConfigService] migrateOldConfig copy error: $e');
        }
      }
      debugPrint('[ConfigService] Migrated config via copy.');
    } catch (e) {
      debugPrint('[ConfigService] migrateOldConfig error: $e');
    }
  }

  /// Recursively copy [src] directory contents into [dst].
  Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is File) {
        await entity.copy('${dst.path}/$name');
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory('${dst.path}/$name'));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Keyring / Secure Storage
  // ---------------------------------------------------------------------------

  /// Whether flutter_secure_storage is likely to function on this platform.
  ///
  /// On Linux the secret service daemon (e.g. GNOME Keyring, KWallet) must be
  /// running; on other desktop platforms it is almost always available.
  bool keyringAvailable() {
    // flutter_secure_storage compiles on all platforms but may throw at runtime
    // on Linux without a secret service. We optimistically return true here and
    // catch errors in the individual read/write helpers.
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  /// Read the Real-Debrid API token from the platform keychain / secret service.
  ///
  /// Returns `null` if the token is not stored or the keyring is unavailable.
  Future<String?> loadTokenFromKeyring() async {
    if (!keyringAvailable()) return null;
    try {
      return await _secureStorage.read(
        key: _keyringTokenKey,
        aOptions: const AndroidOptions(encryptedSharedPreferences: true),
      );
    } catch (e) {
      debugPrint('[ConfigService] loadTokenFromKeyring error: $e');
      return null;
    }
  }

  /// Write [token] to the platform keychain / secret service.
  ///
  /// The key is namespaced under [_keyringService] to match the Python keyring
  /// implementation which uses `keyring.set_password(APP_NAME, "token", …)`.
  Future<void> saveTokenToKeyring(String token) async {
    if (!keyringAvailable()) return;
    try {
      await _secureStorage.write(
        key: _keyringTokenKey,
        value: token,
        aOptions: const AndroidOptions(encryptedSharedPreferences: true),
      );
    } catch (e) {
      debugPrint('[ConfigService] saveTokenToKeyring error: $e');
      rethrow;
    }
  }

  /// Remove the stored API token from the platform keychain / secret service.
  Future<void> deleteTokenFromKeyring() async {
    if (!keyringAvailable()) return;
    try {
      await _secureStorage.delete(
        key: _keyringTokenKey,
        aOptions: const AndroidOptions(encryptedSharedPreferences: true),
      );
    } catch (e) {
      debugPrint('[ConfigService] deleteTokenFromKeyring error: $e');
    }
  }
}

// Convenience accessor mirroring the module-level functions in config.py.
final configService = ConfigService.instance;
