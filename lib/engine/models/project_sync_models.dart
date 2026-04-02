class FusionXProjectCanvasSnapshot {
  const FusionXProjectCanvasSnapshot({
    required this.width,
    required this.height,
    required this.aspectRatio,
    required this.isLocked,
  });

  final int width;
  final int height;
  final double aspectRatio;
  final bool isLocked;

  static FusionXProjectCanvasSnapshot fromMap(Map<Object?, Object?> map) {
    return FusionXProjectCanvasSnapshot(
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      aspectRatio: (map['aspectRatio'] as num?)?.toDouble() ?? 0,
      isLocked: map['isLocked'] as bool? ?? false,
    );
  }
}

class FusionXProjectSyncPayload {
  const FusionXProjectSyncPayload({
    required this.tracks,
  });

  final List<FusionXProjectTrackPayload> tracks;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'tracks': tracks.map((track) => track.toMap()).toList(growable: false),
    };
  }
}

class FusionXProjectTrackPayload {
  const FusionXProjectTrackPayload({
    required this.id,
    required this.kind,
    required this.layerIndex,
    required this.clips,
  });

  final String id;
  final String kind;
  final int layerIndex;
  final List<FusionXProjectClipPayload> clips;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'kind': kind,
      'layerIndex': layerIndex,
      'clips': clips.map((clip) => clip.toMap()).toList(growable: false),
    };
  }
}

class FusionXProjectClipPayload {
  const FusionXProjectClipPayload({
    required this.id,
    required this.assetId,
    required this.path,
    required this.mediaType,
    required this.label,
    required this.durationUs,
    required this.sourceOffsetUs,
    required this.timelineStartUs,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final String id;
  final String? assetId;
  final String? path;
  final String mediaType;
  final String? label;
  final int durationUs;
  final int sourceOffsetUs;
  final int timelineStartUs;
  final int sourceWidth;
  final int sourceHeight;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'assetId': assetId,
      'path': path,
      'mediaType': mediaType,
      'label': label,
      'durationUs': durationUs,
      'sourceOffsetUs': sourceOffsetUs,
      'timelineStartUs': timelineStartUs,
      'sourceWidth': sourceWidth,
      'sourceHeight': sourceHeight,
    };
  }
}
