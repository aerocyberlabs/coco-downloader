/// Per-file progress snapshot emitted by the download worker.
///
/// Mirrors the Python FileProgress dataclass from models.py, plus the
/// additional fields carried in the file_update signal:
///   link, percent, speed (B/s), eta (seconds), status.
class FileProgress {
  const FileProgress({
    required this.link,
    required this.percent,
    required this.speed,
    required this.eta,
    required this.status,
  });

  /// The original link (used as a key to identify the download).
  final String link;

  /// Progress percentage 0–100.
  final int percent;

  /// Current download speed in bytes per second.
  final int speed;

  /// Estimated time remaining in seconds; -1 when unknown.
  final int eta;

  /// Human-readable status string (e.g. "active", "paused", "complete").
  final String status;

  FileProgress copyWith({
    String? link,
    int? percent,
    int? speed,
    int? eta,
    String? status,
  }) {
    return FileProgress(
      link: link ?? this.link,
      percent: percent ?? this.percent,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'link': link,
      'percent': percent,
      'speed': speed,
      'eta': eta,
      'status': status,
    };
  }

  factory FileProgress.fromJson(Map<String, dynamic> json) {
    return FileProgress(
      link: json['link'] as String,
      percent: (json['percent'] as num?)?.toInt() ?? 0,
      speed: (json['speed'] as num?)?.toInt() ?? 0,
      eta: (json['eta'] as num?)?.toInt() ?? -1,
      status: json['status'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileProgress &&
        other.link == link &&
        other.percent == percent &&
        other.speed == speed &&
        other.eta == eta &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(link, percent, speed, eta, status);

  @override
  String toString() {
    return 'FileProgress(link: $link, percent: $percent%, speed: $speed B/s, eta: ${eta}s, status: $status)';
  }
}
