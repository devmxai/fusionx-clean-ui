class FusionXProjectPlaybackSnapshot {
  const FusionXProjectPlaybackSnapshot({
    required this.hasActiveClip,
    required this.projectDurationUs,
    required this.timelineTimeUs,
    required this.activeClipId,
    required this.activeAssetId,
    required this.activePath,
    required this.activeMediaType,
    required this.activeLabel,
    required this.activeClipTimelineStartUs,
    required this.activeClipTimelineEndUs,
    required this.activeClipDurationUs,
    required this.activeClipLocalTimeUs,
    required this.activeSourceOffsetUs,
    required this.activeSourceTimeUs,
    required this.nextClipId,
    required this.nextAssetId,
    required this.nextPath,
    required this.nextTimelineStartUs,
    required this.nextDurationUs,
  });

  final bool hasActiveClip;
  final int projectDurationUs;
  final int timelineTimeUs;
  final String? activeClipId;
  final String? activeAssetId;
  final String? activePath;
  final String? activeMediaType;
  final String? activeLabel;
  final int activeClipTimelineStartUs;
  final int activeClipTimelineEndUs;
  final int activeClipDurationUs;
  final int activeClipLocalTimeUs;
  final int activeSourceOffsetUs;
  final int activeSourceTimeUs;
  final String? nextClipId;
  final String? nextAssetId;
  final String? nextPath;
  final int? nextTimelineStartUs;
  final int? nextDurationUs;

  static FusionXProjectPlaybackSnapshot fromMap(Map<Object?, Object?> map) {
    return FusionXProjectPlaybackSnapshot(
      hasActiveClip: map['hasActiveClip'] as bool? ?? false,
      projectDurationUs: (map['projectDurationUs'] as num?)?.toInt() ?? 0,
      timelineTimeUs: (map['timelineTimeUs'] as num?)?.toInt() ?? 0,
      activeClipId: map['activeClipId'] as String?,
      activeAssetId: map['activeAssetId'] as String?,
      activePath: map['activePath'] as String?,
      activeMediaType: map['activeMediaType'] as String?,
      activeLabel: map['activeLabel'] as String?,
      activeClipTimelineStartUs:
          (map['activeClipTimelineStartUs'] as num?)?.toInt() ?? 0,
      activeClipTimelineEndUs:
          (map['activeClipTimelineEndUs'] as num?)?.toInt() ?? 0,
      activeClipDurationUs: (map['activeClipDurationUs'] as num?)?.toInt() ?? 0,
      activeClipLocalTimeUs:
          (map['activeClipLocalTimeUs'] as num?)?.toInt() ?? 0,
      activeSourceOffsetUs: (map['activeSourceOffsetUs'] as num?)?.toInt() ?? 0,
      activeSourceTimeUs: (map['activeSourceTimeUs'] as num?)?.toInt() ?? 0,
      nextClipId: map['nextClipId'] as String?,
      nextAssetId: map['nextAssetId'] as String?,
      nextPath: map['nextPath'] as String?,
      nextTimelineStartUs: (map['nextTimelineStartUs'] as num?)?.toInt(),
      nextDurationUs: (map['nextDurationUs'] as num?)?.toInt(),
    );
  }
}
