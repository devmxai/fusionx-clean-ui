import 'editor_media_tab.dart';

class DeviceMediaItem {
  const DeviceMediaItem({
    required this.id,
    required this.tab,
    required this.uri,
    required this.label,
    this.width,
    this.height,
    this.durationUs,
    this.mimeType,
  });

  final String id;
  final EditorMediaTab tab;
  final String uri;
  final String label;
  final int? width;
  final int? height;
  final int? durationUs;
  final String? mimeType;

  double? get aspectRatio {
    if (width == null || height == null || width == 0 || height == 0) {
      return null;
    }
    return width! / height!;
  }

  static DeviceMediaItem fromMap(Map<Object?, Object?> map) {
    final rawTab = map['tab'] as String? ?? EditorMediaTab.video.name;
    return DeviceMediaItem(
      id: map['id'] as String? ?? '',
      tab: EditorMediaTab.values.firstWhere(
        (candidate) => candidate.name == rawTab,
        orElse: () => EditorMediaTab.video,
      ),
      uri: map['uri'] as String? ?? '',
      label: map['label'] as String? ?? 'Untitled',
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      durationUs: (map['durationUs'] as num?)?.toInt(),
      mimeType: map['mimeType'] as String?,
    );
  }
}
