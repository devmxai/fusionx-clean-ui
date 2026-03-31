import 'dart:typed_data';

import 'editor_media_tab.dart';

class MockAssetItem {
  const MockAssetItem({
    required this.id,
    required this.tab,
    required this.label,
    required this.tone,
    this.localPath,
    this.isImported = false,
    this.durationSeconds,
    this.width,
    this.height,
    this.posterBytes,
  });

  final String id;
  final EditorMediaTab tab;
  final String label;
  final int tone;
  final String? localPath;
  final bool isImported;
  final double? durationSeconds;
  final int? width;
  final int? height;
  final Uint8List? posterBytes;

  bool get isVisual =>
      tab == EditorMediaTab.video || tab == EditorMediaTab.image;

  double? get aspectRatio {
    if (width == null || height == null || width == 0 || height == 0) {
      return null;
    }
    return width! / height!;
  }

  MockAssetItem copyWith({
    String? id,
    EditorMediaTab? tab,
    String? label,
    int? tone,
    String? localPath,
    bool? isImported,
    double? durationSeconds,
    int? width,
    int? height,
    Uint8List? posterBytes,
  }) {
    return MockAssetItem(
      id: id ?? this.id,
      tab: tab ?? this.tab,
      label: label ?? this.label,
      tone: tone ?? this.tone,
      localPath: localPath ?? this.localPath,
      isImported: isImported ?? this.isImported,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      width: width ?? this.width,
      height: height ?? this.height,
      posterBytes: posterBytes ?? this.posterBytes,
    );
  }
}
