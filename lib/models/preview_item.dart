/// Result of a link-preview lookup, emitted by PreviewWorker.
///
/// Maps the dict returned by manager.build_preview_item() and the
/// inline dicts built in PreviewWorker.run() (workers.py lines 50-67).
class PreviewItem {
  const PreviewItem({
    required this.ok,
    required this.link,
    this.filename,
    this.filesize = 0,
    this.type = '',
    this.host,
    this.error,
  });

  /// Whether the preview lookup succeeded.
  final bool ok;

  /// The original link that was previewed.
  final String link;

  /// Resolved filename, or null when unavailable.
  final String? filename;

  /// File size in bytes; 0 when unknown.
  final int filesize;

  /// File extension / type string (e.g. "mkv", "rd-torrent", "magnet").
  final String type;

  /// Source host name, or null for direct/torrent links.
  final String? host;

  /// Error message when ok is false.
  final String? error;

  PreviewItem copyWith({
    bool? ok,
    String? link,
    String? filename,
    int? filesize,
    String? type,
    String? host,
    String? error,
    bool clearFilename = false,
    bool clearHost = false,
    bool clearError = false,
  }) {
    return PreviewItem(
      ok: ok ?? this.ok,
      link: link ?? this.link,
      filename: clearFilename ? null : (filename ?? this.filename),
      filesize: filesize ?? this.filesize,
      type: type ?? this.type,
      host: clearHost ? null : (host ?? this.host),
      error: clearError ? null : (error ?? this.error),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ok': ok,
      'link': link,
      'filename': filename,
      'filesize': filesize,
      'type': type,
      'host': host,
      'error': error,
    };
  }

  factory PreviewItem.fromJson(Map<String, dynamic> json) {
    return PreviewItem(
      ok: json['ok'] as bool? ?? false,
      link: json['link'] as String,
      filename: json['filename'] as String?,
      filesize: (json['filesize'] as num?)?.toInt() ?? 0,
      type: json['type'] as String? ?? '',
      host: json['host'] as String?,
      error: json['error'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PreviewItem &&
        other.ok == ok &&
        other.link == link &&
        other.filename == filename &&
        other.filesize == filesize &&
        other.type == type &&
        other.host == host &&
        other.error == error;
  }

  @override
  int get hashCode =>
      Object.hash(ok, link, filename, filesize, type, host, error);

  @override
  String toString() {
    if (ok) {
      return 'PreviewItem(link: $link, filename: $filename, size: $filesize, type: $type)';
    }
    return 'PreviewItem(link: $link, ok: false, error: $error)';
  }
}
