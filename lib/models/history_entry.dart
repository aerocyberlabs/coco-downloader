/// A single entry in the download history list stored under the "history"
/// key in config.json.
///
/// Each entry records the ISO-8601 timestamp, local filename, output
/// directory and the original link.
class HistoryEntry {
  const HistoryEntry({
    required this.when,
    required this.file,
    required this.outdir,
    required this.link,
  });

  /// ISO-8601 timestamp string (e.g. "2024-06-15T14:32:00").
  final String when;

  /// The downloaded filename (basename only).
  final String file;

  /// Absolute path of the output directory.
  final String outdir;

  /// The original link that was downloaded.
  final String link;

  HistoryEntry copyWith({
    String? when,
    String? file,
    String? outdir,
    String? link,
  }) {
    return HistoryEntry(
      when: when ?? this.when,
      file: file ?? this.file,
      outdir: outdir ?? this.outdir,
      link: link ?? this.link,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'when': when,
      'file': file,
      'outdir': outdir,
      'link': link,
    };
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      when: json['when'] as String? ?? '',
      file: json['file'] as String? ?? '',
      outdir: json['outdir'] as String? ?? '',
      link: json['link'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HistoryEntry &&
        other.when == when &&
        other.file == file &&
        other.outdir == outdir &&
        other.link == link;
  }

  @override
  int get hashCode => Object.hash(when, file, outdir, link);

  @override
  String toString() {
    return 'HistoryEntry(when: $when, file: $file, outdir: $outdir)';
  }
}
