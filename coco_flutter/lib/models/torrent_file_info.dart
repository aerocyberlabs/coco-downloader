/// Information about a single file inside a torrent, as returned by the
/// Real-Debrid API (GET /torrents/info/{id} → files array).
class TorrentFileInfo {
  const TorrentFileInfo({
    required this.id,
    required this.path,
    required this.bytes,
    required this.selected,
  });

  /// File identifier within the torrent (1-based index used by the API).
  final int id;

  /// Relative path of the file inside the torrent archive.
  final String path;

  /// Size of the file in bytes.
  final int bytes;

  /// Selection state: 1 = selected for download, 0 = not selected.
  final int selected;

  bool get isSelected => selected == 1;

  TorrentFileInfo copyWith({
    int? id,
    String? path,
    int? bytes,
    int? selected,
  }) {
    return TorrentFileInfo(
      id: id ?? this.id,
      path: path ?? this.path,
      bytes: bytes ?? this.bytes,
      selected: selected ?? this.selected,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'bytes': bytes,
      'selected': selected,
    };
  }

  factory TorrentFileInfo.fromJson(Map<String, dynamic> json) {
    return TorrentFileInfo(
      id: (json['id'] as num).toInt(),
      path: json['path'] as String,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      selected: (json['selected'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TorrentFileInfo &&
        other.id == id &&
        other.path == path &&
        other.bytes == bytes &&
        other.selected == selected;
  }

  @override
  int get hashCode => Object.hash(id, path, bytes, selected);

  @override
  String toString() {
    return 'TorrentFileInfo(id: $id, path: $path, bytes: $bytes, selected: $selected)';
  }
}
