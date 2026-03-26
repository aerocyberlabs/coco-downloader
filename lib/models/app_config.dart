import 'package:collection/collection.dart';

import 'history_entry.dart';

/// Application configuration model.
///
/// Mirrors all keys read/written by the Python app (app.py, workers.py,
/// config.py). Fields are named in camelCase with their JSON key listed in the
/// toJson/fromJson methods.
///
/// The factory constructor [AppConfig.defaults] provides sensible initial
/// values matching the Python defaults.
class AppConfig {
  const AppConfig({
    // --- Token / OAuth ---
    this.token,
    this.useKeyring = false,
    this.rdOauthClientId,
    this.rdOauthClientSecret,
    this.rdAccessToken,
    this.rdRefreshToken,

    // --- UI / basic settings ---
    this.outdir = '',
    this.connections = 16,
    this.splits = 16,
    this.concurrency = 1,
    this.darkMode = false,
    this.openOnDone = false,
    this.autoStartRdOnAdd = true,

    // --- File type & categorisation rules ---
    this.autoCategorize = true,
    this.excludeExt = const [],
    this.categoryExts = const {},
    this.categoryFolders = const {},

    // --- Network settings ---
    this.httpProxy = '',
    this.httpsProxy = '',
    this.headers = const [],

    // --- Scheduler ---
    this.quietStart = '',
    this.quietEnd = '',
    this.autoExtractZip = false,

    // --- Power-aware settings ---
    this.enablePowerAware = false,
    this.batteryLimitKib = 5120,
    this.batteryConcurrent = 2,
    this.acConcurrent = 1,

    // --- Privacy ---
    this.rotateUserAgent = false,
    this.userAgents = const [],

    // --- Auto-tune ---
    this.enableAutoTune = false,
    this.tuneMinKib = 64,
    this.tuneMaxConn = 16,
    this.tuneMinConn = 1,
    this.tuneIntervalSec = 20,
    this.tuneEmaAlpha = 0.3,

    // --- Dedup / encryption ---
    this.dedupOnComplete = false,
    this.autoRenameMedia = false,
    this.encryptCompleted = false,
    this.vaultPassword,

    // --- History and hash index ---
    this.history = const [],
    this.hashIndex = const {},

    // --- aria2 ---
    this.aria2Path,

    // --- Table state ---
    this.tableHeaderState,
    this.tableSortCol = -1,
    this.tableSortOrder = 0,
  });

  // -------------------------------------------------------------------------
  // Token / OAuth
  // -------------------------------------------------------------------------

  /// Plain-text API token (only stored when useKeyring is false).
  final String? token;

  /// Whether to store the token in the OS keyring instead of config.json.
  final bool useKeyring;

  /// OAuth client ID obtained via the device-code flow.
  final String? rdOauthClientId;

  /// OAuth client secret obtained via the device-code flow.
  final String? rdOauthClientSecret;

  /// OAuth access token.
  final String? rdAccessToken;

  /// OAuth refresh token.
  final String? rdRefreshToken;

  // -------------------------------------------------------------------------
  // UI / basic settings
  // -------------------------------------------------------------------------

  /// Default output directory for downloads.
  final String outdir;

  /// aria2c -x connections per download.
  final int connections;

  /// aria2c -s splits per download.
  final int splits;

  /// Maximum concurrent downloads (-j).
  final int concurrency;

  /// Whether dark mode is enabled.
  final bool darkMode;

  /// Whether to open the download folder when all downloads complete.
  final bool openOnDone;

  /// Whether to auto-start Real-Debrid unrestrict after adding a link.
  final bool autoStartRdOnAdd;

  // -------------------------------------------------------------------------
  // File type & categorisation rules
  // -------------------------------------------------------------------------

  /// Whether to sort downloads into category sub-folders automatically.
  final bool autoCategorize;

  /// List of file extensions (lowercase, no dot) to exclude from download.
  final List<String> excludeExt;

  /// Map of category name → list of extensions belonging to that category.
  /// e.g. {"Video": ["mkv", "mp4"], "Audio": ["mp3", "flac"]}
  final Map<String, List<String>> categoryExts;

  /// Map of category name → sub-folder name override.
  /// e.g. {"Video": "Movies"}
  final Map<String, String> categoryFolders;

  // -------------------------------------------------------------------------
  // Network settings
  // -------------------------------------------------------------------------

  /// HTTP proxy URL (e.g. "http://proxy:8080").
  final String httpProxy;

  /// HTTPS proxy URL.
  final String httpsProxy;

  /// Extra HTTP headers as "Key: Value" strings.
  final List<String> headers;

  // -------------------------------------------------------------------------
  // Scheduler
  // -------------------------------------------------------------------------

  /// Start of the quiet (paused) time window, "HH:MM" 24-hour format.
  final String quietStart;

  /// End of the quiet time window, "HH:MM" 24-hour format.
  final String quietEnd;

  /// Whether to automatically extract ZIP files after download.
  final bool autoExtractZip;

  // -------------------------------------------------------------------------
  // Power-aware settings
  // -------------------------------------------------------------------------

  /// Whether to throttle downloads when running on battery.
  final bool enablePowerAware;

  /// Speed limit in KiB/s applied when on battery.
  final int batteryLimitKib;

  /// Max concurrent downloads while on battery.
  final int batteryConcurrent;

  /// Max concurrent downloads while on AC power.
  final int acConcurrent;

  // -------------------------------------------------------------------------
  // Privacy
  // -------------------------------------------------------------------------

  /// Whether to rotate the User-Agent header between requests.
  final bool rotateUserAgent;

  /// Pool of User-Agent strings to choose from when rotating.
  final List<String> userAgents;

  // -------------------------------------------------------------------------
  // Auto-tune
  // -------------------------------------------------------------------------

  /// Whether to automatically tune connection counts based on speed.
  final bool enableAutoTune;

  /// Minimum speed threshold in KiB/s before increasing connections.
  final int tuneMinKib;

  /// Maximum connection count the auto-tuner may set.
  final int tuneMaxConn;

  /// Minimum connection count the auto-tuner may set.
  final int tuneMinConn;

  /// How often (seconds) the auto-tuner re-evaluates connection count.
  final int tuneIntervalSec;

  /// Exponential moving average alpha for speed smoothing.
  final double tuneEmaAlpha;

  // -------------------------------------------------------------------------
  // Dedup / encryption
  // -------------------------------------------------------------------------

  /// Whether to check for duplicate files by hash after download.
  final bool dedupOnComplete;

  /// Whether to attempt automatic media file renaming.
  final bool autoRenameMedia;

  /// Whether to encrypt completed downloads into a vault.
  final bool encryptCompleted;

  /// Password used for vault encryption (SHA-256 key derivation).
  final String? vaultPassword;

  // -------------------------------------------------------------------------
  // History and hash index
  // -------------------------------------------------------------------------

  /// Ordered list of completed download history entries.
  final List<HistoryEntry> history;

  /// Map of filename → SHA-256 hash for deduplication.
  final Map<String, String> hashIndex;

  // -------------------------------------------------------------------------
  // aria2
  // -------------------------------------------------------------------------

  /// Path to the aria2c executable; null means locate on PATH.
  final String? aria2Path;

  // -------------------------------------------------------------------------
  // Table state (UI persistence)
  // -------------------------------------------------------------------------

  /// Base-64 encoded QHeaderView state blob for column widths/order.
  final String? tableHeaderState;

  /// Column index of the current sort; -1 means unsorted.
  final int tableSortCol;

  /// Qt::SortOrder int value (0 = ascending, 1 = descending).
  final int tableSortOrder;

  // -------------------------------------------------------------------------
  // Factory constructors
  // -------------------------------------------------------------------------

  /// Creates an AppConfig with sensible defaults matching the Python app.
  factory AppConfig.defaults() {
    return const AppConfig();
  }

  // -------------------------------------------------------------------------
  // copyWith
  // -------------------------------------------------------------------------

  AppConfig copyWith({
    String? token,
    bool? useKeyring,
    String? rdOauthClientId,
    String? rdOauthClientSecret,
    String? rdAccessToken,
    String? rdRefreshToken,
    String? outdir,
    int? connections,
    int? splits,
    int? concurrency,
    bool? darkMode,
    bool? openOnDone,
    bool? autoStartRdOnAdd,
    bool? autoCategorize,
    List<String>? excludeExt,
    Map<String, List<String>>? categoryExts,
    Map<String, String>? categoryFolders,
    String? httpProxy,
    String? httpsProxy,
    List<String>? headers,
    String? quietStart,
    String? quietEnd,
    bool? autoExtractZip,
    bool? enablePowerAware,
    int? batteryLimitKib,
    int? batteryConcurrent,
    int? acConcurrent,
    bool? rotateUserAgent,
    List<String>? userAgents,
    bool? enableAutoTune,
    int? tuneMinKib,
    int? tuneMaxConn,
    int? tuneMinConn,
    int? tuneIntervalSec,
    double? tuneEmaAlpha,
    bool? dedupOnComplete,
    bool? autoRenameMedia,
    bool? encryptCompleted,
    String? vaultPassword,
    List<HistoryEntry>? history,
    Map<String, String>? hashIndex,
    String? aria2Path,
    String? tableHeaderState,
    int? tableSortCol,
    int? tableSortOrder,
    bool clearToken = false,
    bool clearRdOauthClientId = false,
    bool clearRdOauthClientSecret = false,
    bool clearRdAccessToken = false,
    bool clearRdRefreshToken = false,
    bool clearVaultPassword = false,
    bool clearAria2Path = false,
    bool clearTableHeaderState = false,
  }) {
    return AppConfig(
      token: clearToken ? null : (token ?? this.token),
      useKeyring: useKeyring ?? this.useKeyring,
      rdOauthClientId: clearRdOauthClientId
          ? null
          : (rdOauthClientId ?? this.rdOauthClientId),
      rdOauthClientSecret: clearRdOauthClientSecret
          ? null
          : (rdOauthClientSecret ?? this.rdOauthClientSecret),
      rdAccessToken:
          clearRdAccessToken ? null : (rdAccessToken ?? this.rdAccessToken),
      rdRefreshToken:
          clearRdRefreshToken ? null : (rdRefreshToken ?? this.rdRefreshToken),
      outdir: outdir ?? this.outdir,
      connections: connections ?? this.connections,
      splits: splits ?? this.splits,
      concurrency: concurrency ?? this.concurrency,
      darkMode: darkMode ?? this.darkMode,
      openOnDone: openOnDone ?? this.openOnDone,
      autoStartRdOnAdd: autoStartRdOnAdd ?? this.autoStartRdOnAdd,
      autoCategorize: autoCategorize ?? this.autoCategorize,
      excludeExt: excludeExt ?? this.excludeExt,
      categoryExts: categoryExts ?? this.categoryExts,
      categoryFolders: categoryFolders ?? this.categoryFolders,
      httpProxy: httpProxy ?? this.httpProxy,
      httpsProxy: httpsProxy ?? this.httpsProxy,
      headers: headers ?? this.headers,
      quietStart: quietStart ?? this.quietStart,
      quietEnd: quietEnd ?? this.quietEnd,
      autoExtractZip: autoExtractZip ?? this.autoExtractZip,
      enablePowerAware: enablePowerAware ?? this.enablePowerAware,
      batteryLimitKib: batteryLimitKib ?? this.batteryLimitKib,
      batteryConcurrent: batteryConcurrent ?? this.batteryConcurrent,
      acConcurrent: acConcurrent ?? this.acConcurrent,
      rotateUserAgent: rotateUserAgent ?? this.rotateUserAgent,
      userAgents: userAgents ?? this.userAgents,
      enableAutoTune: enableAutoTune ?? this.enableAutoTune,
      tuneMinKib: tuneMinKib ?? this.tuneMinKib,
      tuneMaxConn: tuneMaxConn ?? this.tuneMaxConn,
      tuneMinConn: tuneMinConn ?? this.tuneMinConn,
      tuneIntervalSec: tuneIntervalSec ?? this.tuneIntervalSec,
      tuneEmaAlpha: tuneEmaAlpha ?? this.tuneEmaAlpha,
      dedupOnComplete: dedupOnComplete ?? this.dedupOnComplete,
      autoRenameMedia: autoRenameMedia ?? this.autoRenameMedia,
      encryptCompleted: encryptCompleted ?? this.encryptCompleted,
      vaultPassword:
          clearVaultPassword ? null : (vaultPassword ?? this.vaultPassword),
      history: history ?? this.history,
      hashIndex: hashIndex ?? this.hashIndex,
      aria2Path: clearAria2Path ? null : (aria2Path ?? this.aria2Path),
      tableHeaderState: clearTableHeaderState
          ? null
          : (tableHeaderState ?? this.tableHeaderState),
      tableSortCol: tableSortCol ?? this.tableSortCol,
      tableSortOrder: tableSortOrder ?? this.tableSortOrder,
    );
  }

  // -------------------------------------------------------------------------
  // JSON serialisation
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() {
    return {
      if (token != null) 'token': token,
      'use_keyring': useKeyring,
      if (rdOauthClientId != null) 'rd_oauth_client_id': rdOauthClientId,
      if (rdOauthClientSecret != null)
        'rd_oauth_client_secret': rdOauthClientSecret,
      if (rdAccessToken != null) 'rd_access_token': rdAccessToken,
      if (rdRefreshToken != null) 'rd_refresh_token': rdRefreshToken,
      'outdir': outdir,
      'connections': connections,
      'splits': splits,
      'concurrency': concurrency,
      'dark_mode': darkMode,
      'open_on_done': openOnDone,
      'auto_start_rd_on_add': autoStartRdOnAdd,
      'auto_categorize': autoCategorize,
      'exclude_ext': excludeExt,
      'category_exts': categoryExts,
      'category_folders': categoryFolders,
      'http_proxy': httpProxy,
      'https_proxy': httpsProxy,
      'headers': headers,
      'quiet_start': quietStart,
      'quiet_end': quietEnd,
      'auto_extract_zip': autoExtractZip,
      'enable_power_aware': enablePowerAware,
      'battery_limit_kib': batteryLimitKib,
      'battery_concurrent': batteryConcurrent,
      'ac_concurrent': acConcurrent,
      'rotate_user_agent': rotateUserAgent,
      'user_agents': userAgents,
      'enable_auto_tune': enableAutoTune,
      'tune_min_kib': tuneMinKib,
      'tune_max_conn': tuneMaxConn,
      'tune_min_conn': tuneMinConn,
      'tune_interval_sec': tuneIntervalSec,
      'tune_ema_alpha': tuneEmaAlpha,
      'dedup_on_complete': dedupOnComplete,
      'auto_rename_media': autoRenameMedia,
      'encrypt_completed': encryptCompleted,
      if (vaultPassword != null) 'vault_password': vaultPassword,
      'history': history.map((e) => e.toJson()).toList(),
      'hash_index': hashIndex,
      if (aria2Path != null) 'aria2_path': aria2Path,
      if (tableHeaderState != null) 'table_header_state': tableHeaderState,
      'table_sort_col': tableSortCol,
      'table_sort_order': tableSortOrder,
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    // category_exts: Map<String, dynamic> → Map<String, List<String>>
    Map<String, List<String>> parseCategoryExts(dynamic raw) {
      if (raw == null) return {};
      final map = raw as Map<String, dynamic>;
      return map.map((k, v) {
        final list = (v as List<dynamic>).map((e) => e as String).toList();
        return MapEntry(k, list);
      });
    }

    // category_folders: Map<String, dynamic> → Map<String, String>
    Map<String, String> parseCategoryFolders(dynamic raw) {
      if (raw == null) return {};
      final map = raw as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as String));
    }

    // hash_index: Map<String, dynamic> → Map<String, String>
    Map<String, String> parseHashIndex(dynamic raw) {
      if (raw == null) return {};
      final map = raw as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as String));
    }

    List<String> parseStringList(dynamic raw) {
      if (raw == null) return [];
      return (raw as List<dynamic>).map((e) => e as String).toList();
    }

    List<HistoryEntry> parseHistory(dynamic raw) {
      if (raw == null) return [];
      return (raw as List<dynamic>)
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return AppConfig(
      token: json['token'] as String?,
      useKeyring: json['use_keyring'] as bool? ?? false,
      rdOauthClientId: json['rd_oauth_client_id'] as String?,
      rdOauthClientSecret: json['rd_oauth_client_secret'] as String?,
      rdAccessToken: json['rd_access_token'] as String?,
      rdRefreshToken: json['rd_refresh_token'] as String?,
      outdir: json['outdir'] as String? ?? '',
      connections: (json['connections'] as num?)?.toInt() ?? 16,
      splits: (json['splits'] as num?)?.toInt() ?? 16,
      concurrency: (json['concurrency'] as num?)?.toInt() ?? 1,
      darkMode: json['dark_mode'] as bool? ?? false,
      openOnDone: json['open_on_done'] as bool? ?? false,
      autoStartRdOnAdd: json['auto_start_rd_on_add'] as bool? ?? true,
      autoCategorize: json['auto_categorize'] as bool? ?? true,
      excludeExt: parseStringList(json['exclude_ext']),
      categoryExts: parseCategoryExts(json['category_exts']),
      categoryFolders: parseCategoryFolders(json['category_folders']),
      httpProxy: json['http_proxy'] as String? ?? '',
      httpsProxy: json['https_proxy'] as String? ?? '',
      headers: parseStringList(json['headers']),
      quietStart: json['quiet_start'] as String? ?? '',
      quietEnd: json['quiet_end'] as String? ?? '',
      autoExtractZip: json['auto_extract_zip'] as bool? ?? false,
      enablePowerAware: json['enable_power_aware'] as bool? ?? false,
      batteryLimitKib: (json['battery_limit_kib'] as num?)?.toInt() ?? 5120,
      batteryConcurrent: (json['battery_concurrent'] as num?)?.toInt() ?? 2,
      acConcurrent: (json['ac_concurrent'] as num?)?.toInt() ?? 1,
      rotateUserAgent: json['rotate_user_agent'] as bool? ?? false,
      userAgents: parseStringList(json['user_agents']),
      enableAutoTune: json['enable_auto_tune'] as bool? ?? false,
      tuneMinKib: (json['tune_min_kib'] as num?)?.toInt() ?? 64,
      tuneMaxConn: (json['tune_max_conn'] as num?)?.toInt() ?? 16,
      tuneMinConn: (json['tune_min_conn'] as num?)?.toInt() ?? 1,
      tuneIntervalSec: (json['tune_interval_sec'] as num?)?.toInt() ?? 20,
      tuneEmaAlpha: (json['tune_ema_alpha'] as num?)?.toDouble() ?? 0.3,
      dedupOnComplete: json['dedup_on_complete'] as bool? ?? false,
      autoRenameMedia: json['auto_rename_media'] as bool? ?? false,
      encryptCompleted: json['encrypt_completed'] as bool? ?? false,
      vaultPassword: json['vault_password'] as String?,
      history: parseHistory(json['history']),
      hashIndex: parseHashIndex(json['hash_index']),
      aria2Path: json['aria2_path'] as String?,
      tableHeaderState: json['table_header_state'] as String?,
      tableSortCol: (json['table_sort_col'] as num?)?.toInt() ?? -1,
      tableSortOrder: (json['table_sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  // -------------------------------------------------------------------------
  // Equality and toString
  // -------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AppConfig) return false;
    return other.token == token &&
        other.useKeyring == useKeyring &&
        other.rdOauthClientId == rdOauthClientId &&
        other.rdOauthClientSecret == rdOauthClientSecret &&
        other.rdAccessToken == rdAccessToken &&
        other.rdRefreshToken == rdRefreshToken &&
        other.outdir == outdir &&
        other.connections == connections &&
        other.splits == splits &&
        other.concurrency == concurrency &&
        other.darkMode == darkMode &&
        other.openOnDone == openOnDone &&
        other.autoStartRdOnAdd == autoStartRdOnAdd &&
        other.autoCategorize == autoCategorize &&
        other.httpProxy == httpProxy &&
        other.httpsProxy == httpsProxy &&
        other.quietStart == quietStart &&
        other.quietEnd == quietEnd &&
        other.autoExtractZip == autoExtractZip &&
        other.enablePowerAware == enablePowerAware &&
        other.batteryLimitKib == batteryLimitKib &&
        other.batteryConcurrent == batteryConcurrent &&
        other.acConcurrent == acConcurrent &&
        other.rotateUserAgent == rotateUserAgent &&
        other.enableAutoTune == enableAutoTune &&
        other.tuneMinKib == tuneMinKib &&
        other.tuneMaxConn == tuneMaxConn &&
        other.tuneMinConn == tuneMinConn &&
        other.tuneIntervalSec == tuneIntervalSec &&
        other.tuneEmaAlpha == tuneEmaAlpha &&
        other.dedupOnComplete == dedupOnComplete &&
        other.autoRenameMedia == autoRenameMedia &&
        other.encryptCompleted == encryptCompleted &&
        other.vaultPassword == vaultPassword &&
        other.aria2Path == aria2Path &&
        other.tableHeaderState == tableHeaderState &&
        other.tableSortCol == tableSortCol &&
        other.tableSortOrder == tableSortOrder &&
        const DeepCollectionEquality()
            .equals(other.excludeExt, excludeExt) &&
        const DeepCollectionEquality()
            .equals(other.categoryExts, categoryExts) &&
        const DeepCollectionEquality()
            .equals(other.categoryFolders, categoryFolders) &&
        const DeepCollectionEquality().equals(other.headers, headers) &&
        const DeepCollectionEquality()
            .equals(other.userAgents, userAgents) &&
        const DeepCollectionEquality().equals(other.history, history) &&
        const DeepCollectionEquality()
            .equals(other.hashIndex, hashIndex);
  }

  @override
  int get hashCode => Object.hashAll([
        token,
        useKeyring,
        rdOauthClientId,
        rdOauthClientSecret,
        rdAccessToken,
        rdRefreshToken,
        outdir,
        connections,
        splits,
        concurrency,
        darkMode,
        openOnDone,
        autoStartRdOnAdd,
        autoCategorize,
        httpProxy,
        httpsProxy,
        quietStart,
        quietEnd,
        autoExtractZip,
        enablePowerAware,
        batteryLimitKib,
        batteryConcurrent,
        acConcurrent,
        rotateUserAgent,
        enableAutoTune,
        tuneMinKib,
        tuneMaxConn,
        tuneMinConn,
        tuneIntervalSec,
        tuneEmaAlpha,
        dedupOnComplete,
        autoRenameMedia,
        encryptCompleted,
        vaultPassword,
        aria2Path,
        tableHeaderState,
        tableSortCol,
        tableSortOrder,
        const DeepCollectionEquality().hash(excludeExt),
        const DeepCollectionEquality().hash(categoryExts),
        const DeepCollectionEquality().hash(categoryFolders),
        const DeepCollectionEquality().hash(headers),
        const DeepCollectionEquality().hash(userAgents),
        const DeepCollectionEquality().hash(history),
        const DeepCollectionEquality().hash(hashIndex),
      ]);

  @override
  String toString() {
    return 'AppConfig('
        'outdir: $outdir, '
        'connections: $connections, '
        'splits: $splits, '
        'concurrency: $concurrency, '
        'darkMode: $darkMode, '
        'autoCategorize: $autoCategorize, '
        'enableAutoTune: $enableAutoTune'
        ')';
  }
}
