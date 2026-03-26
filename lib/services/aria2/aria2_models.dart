/// Typed wrappers for aria2 JSON-RPC responses.
///
/// Mirrors the data structures returned by the aria2c daemon and used
/// throughout the Python [Aria2Client] implementation.
library;

/// Represents a single URI within an [Aria2File].
class Aria2Uri {
  final String uri;
  final String status;

  const Aria2Uri({
    required this.uri,
    required this.status,
  });

  factory Aria2Uri.fromJson(Map json) {
    return Aria2Uri(
      uri: json['uri'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }

  @override
  String toString() => 'Aria2Uri(uri: $uri, status: $status)';
}

/// Represents a single file entry within an [Aria2Task].
class Aria2File {
  final int index;
  final String path;
  final int length;
  final int completedLength;
  final bool selected;
  final List<Aria2Uri> uris;

  const Aria2File({
    required this.index,
    required this.path,
    required this.length,
    required this.completedLength,
    required this.selected,
    required this.uris,
  });

  factory Aria2File.fromJson(Map json) {
    final rawUris = json['uris'];
    final uriList = <Aria2Uri>[];
    if (rawUris is List) {
      for (final u in rawUris) {
        if (u is Map) uriList.add(Aria2Uri.fromJson(u));
      }
    }

    return Aria2File(
      index: _parseInt(json['index']),
      path: json['path'] as String? ?? '',
      length: _parseInt(json['length']),
      completedLength: _parseInt(json['completedLength']),
      selected: _parseBool(json['selected']),
      uris: uriList,
    );
  }

  @override
  String toString() => 'Aria2File(index: $index, path: $path, '
      'length: $length, completedLength: $completedLength)';
}

/// Represents a download task tracked by aria2c.
///
/// Maps to the result of [tellActive], [tellWaiting], [tellStopped], and
/// [tellStatus] RPC calls.
class Aria2Task {
  final String gid;
  final String status;
  final int totalLength;
  final int completedLength;
  final int downloadSpeed;
  final int uploadSpeed;
  final List<Aria2File> files;
  final String dir;
  final int? errorCode;
  final String? errorMessage;

  const Aria2Task({
    required this.gid,
    required this.status,
    required this.totalLength,
    required this.completedLength,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.files,
    required this.dir,
    this.errorCode,
    this.errorMessage,
  });

  factory Aria2Task.fromJson(Map json) {
    final rawFiles = json['files'];
    final fileList = <Aria2File>[];
    if (rawFiles is List) {
      for (final f in rawFiles) {
        if (f is Map) fileList.add(Aria2File.fromJson(f));
      }
    }

    final rawErrorCode = json['errorCode'];
    final int? errorCode = rawErrorCode != null
        ? _parseInt(rawErrorCode)
        : null;

    return Aria2Task(
      gid: json['gid'] as String? ?? '',
      status: json['status'] as String? ?? '',
      totalLength: _parseInt(json['totalLength']),
      completedLength: _parseInt(json['completedLength']),
      downloadSpeed: _parseInt(json['downloadSpeed']),
      uploadSpeed: _parseInt(json['uploadSpeed']),
      files: fileList,
      dir: json['dir'] as String? ?? '',
      errorCode: errorCode,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  /// Fraction [0.0, 1.0] of download progress; 0.0 when total is unknown.
  double get progress =>
      totalLength > 0 ? completedLength / totalLength : 0.0;

  /// Whether the task has completed successfully.
  bool get isComplete => status == 'complete';

  /// Whether the task is actively downloading.
  bool get isActive => status == 'active';

  /// Whether the task encountered an error.
  bool get isError => status == 'error';

  @override
  String toString() => 'Aria2Task(gid: $gid, status: $status, '
      'progress: ${(progress * 100).toStringAsFixed(1)}%)';
}

/// Global statistics returned by the [getGlobalStat] RPC call.
class Aria2GlobalStat {
  final int downloadSpeed;
  final int uploadSpeed;
  final int numActive;
  final int numWaiting;
  final int numStopped;
  final int numStoppedTotal;

  const Aria2GlobalStat({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.numActive,
    required this.numWaiting,
    required this.numStopped,
    required this.numStoppedTotal,
  });

  factory Aria2GlobalStat.fromJson(Map json) {
    return Aria2GlobalStat(
      downloadSpeed: _parseInt(json['downloadSpeed']),
      uploadSpeed: _parseInt(json['uploadSpeed']),
      numActive: _parseInt(json['numActive']),
      numWaiting: _parseInt(json['numWaiting']),
      numStopped: _parseInt(json['numStopped']),
      numStoppedTotal: _parseInt(json['numStoppedTotal']),
    );
  }

  @override
  String toString() => 'Aria2GlobalStat(active: $numActive, '
      'waiting: $numWaiting, stopped: $numStopped, '
      'dl: $downloadSpeed B/s, ul: $uploadSpeed B/s)';
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Parse an integer from a value that may arrive as a [String] or [int].
///
/// aria2 encodes numeric fields as JSON strings in its RPC responses.
int _parseInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

/// Parse a boolean from a value that may arrive as a [String] or [bool].
bool _parseBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  final s = value.toString().toLowerCase();
  return s == 'true' || s == '1';
}
