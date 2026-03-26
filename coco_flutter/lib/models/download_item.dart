/// Download status enum matching Python status strings.
enum DownloadStatus {
  queued,
  active,
  paused,
  completed,
  error,
  removed,
  excluded;

  static DownloadStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'queued':
        return DownloadStatus.queued;
      case 'active':
        return DownloadStatus.active;
      case 'paused':
        return DownloadStatus.paused;
      case 'complete':
      case 'completed':
        return DownloadStatus.completed;
      case 'waiting':
        return DownloadStatus.queued;
      case 'error':
        return DownloadStatus.error;
      case 'removed':
        return DownloadStatus.removed;
      case 'excluded':
        return DownloadStatus.excluded;
      default:
        return DownloadStatus.queued;
    }
  }

  String toJson() {
    switch (this) {
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.active:
        return 'Active';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.completed:
        return 'Completed';
      case DownloadStatus.error:
        return 'Error';
      case DownloadStatus.removed:
        return 'Removed';
      case DownloadStatus.excluded:
        return 'Excluded';
    }
  }
}

/// Mirrors the Python DownloadItem dataclass from models.py, extended with
/// fields used by the GUI (percent, speed, eta, downloadUrl, selected,
/// excluded, extension).
class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.link,
    required this.name,
    this.size = 0,
    this.category = 'Other',
    this.source = '',
    this.status = DownloadStatus.queued,
    this.gid,
    this.percent = 0,
    this.speed = 0,
    this.eta = -1,
    this.downloadUrl,
    this.selected = false,
    this.excluded = false,
    this.extension = '',
  });

  /// Unique identifier (UUID).
  final String id;

  /// Original URL or rd-torrent:tid:fid compound key.
  final String link;

  /// Display filename shown in the UI.
  final String name;

  /// File size in bytes; 0 when unknown.
  final int size;

  /// Category label: Video, Audio, Image, Document, Compressed, Program, Other.
  final String category;

  /// Host name or "Direct" / "Real-Debrid".
  final String source;

  final DownloadStatus status;

  /// aria2 GID assigned after download starts.
  final String? gid;

  /// Download progress 0–100.
  final int percent;

  /// Current download speed in bytes per second.
  final int speed;

  /// Estimated time remaining in seconds; -1 when unknown.
  final int eta;

  /// Resolved download URL after Real-Debrid unrestrict, if applicable.
  final String? downloadUrl;

  /// Whether the item is selected in the preview table checkbox.
  final bool selected;

  /// Whether the item has been excluded by file-type rules.
  final bool excluded;

  /// Lowercase file extension without the leading dot.
  final String extension;

  DownloadItem copyWith({
    String? id,
    String? link,
    String? name,
    int? size,
    String? category,
    String? source,
    DownloadStatus? status,
    String? gid,
    int? percent,
    int? speed,
    int? eta,
    String? downloadUrl,
    bool? selected,
    bool? excluded,
    String? extension,
    bool clearGid = false,
    bool clearDownloadUrl = false,
  }) {
    return DownloadItem(
      id: id ?? this.id,
      link: link ?? this.link,
      name: name ?? this.name,
      size: size ?? this.size,
      category: category ?? this.category,
      source: source ?? this.source,
      status: status ?? this.status,
      gid: clearGid ? null : (gid ?? this.gid),
      percent: percent ?? this.percent,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
      downloadUrl: clearDownloadUrl ? null : (downloadUrl ?? this.downloadUrl),
      selected: selected ?? this.selected,
      excluded: excluded ?? this.excluded,
      extension: extension ?? this.extension,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'link': link,
      'name': name,
      'size': size,
      'category': category,
      'source': source,
      'status': status.toJson(),
      'gid': gid,
      'percent': percent,
      'speed': speed,
      'eta': eta,
      'downloadUrl': downloadUrl,
      'selected': selected,
      'excluded': excluded,
      'extension': extension,
    };
  }

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      id: json['id'] as String,
      link: json['link'] as String,
      name: json['name'] as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? 'Other',
      source: json['source'] as String? ?? '',
      status: DownloadStatus.fromString(json['status'] as String? ?? 'Queued'),
      gid: json['gid'] as String?,
      percent: (json['percent'] as num?)?.toInt() ?? 0,
      speed: (json['speed'] as num?)?.toInt() ?? 0,
      eta: (json['eta'] as num?)?.toInt() ?? -1,
      downloadUrl: json['downloadUrl'] as String?,
      selected: json['selected'] as bool? ?? false,
      excluded: json['excluded'] as bool? ?? false,
      extension: json['extension'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'DownloadItem(id: $id, name: $name, status: ${status.name}, percent: $percent%)';
  }
}
