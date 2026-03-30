enum TimelineTrackKind {
  video,
  image,
  audio,
  text,
  lipSync,
}

enum TimelineClipTone {
  hero,
  heroMuted,
  placeholder,
}

enum TimelineClipType {
  media,
  placeholder,
}

class TimelineClipData {
  const TimelineClipData({
    required this.id,
    required this.duration,
    required this.type,
    required this.tone,
    this.assetId,
    this.sourceOffsetSeconds,
    this.label,
    this.splitGroupId,
  });

  final String id;
  final double duration;
  final TimelineClipType type;
  final TimelineClipTone tone;
  final String? assetId;
  final double? sourceOffsetSeconds;
  final String? label;
  final String? splitGroupId;

  TimelineClipData copyWith({
    String? id,
    double? duration,
    TimelineClipType? type,
    TimelineClipTone? tone,
    String? assetId,
    double? sourceOffsetSeconds,
    String? label,
    String? splitGroupId,
  }) {
    return TimelineClipData(
      id: id ?? this.id,
      duration: duration ?? this.duration,
      type: type ?? this.type,
      tone: tone ?? this.tone,
      assetId: assetId ?? this.assetId,
      sourceOffsetSeconds: sourceOffsetSeconds ?? this.sourceOffsetSeconds,
      label: label ?? this.label,
      splitGroupId: splitGroupId ?? this.splitGroupId,
    );
  }

  double visualWidth(double secondsWidth) {
    final baseWidth = duration * secondsWidth;
    final minWidth = type == TimelineClipType.media ? 84.0 : 118.0;
    return baseWidth < minWidth ? minWidth : baseWidth;
  }
}

class TimelineTrackData {
  const TimelineTrackData({
    required this.kind,
    required this.clips,
    this.placeholderLabel,
  });

  final TimelineTrackKind kind;
  final List<TimelineClipData> clips;
  final String? placeholderLabel;

  TimelineTrackData copyWith({
    TimelineTrackKind? kind,
    List<TimelineClipData>? clips,
    String? placeholderLabel,
  }) {
    return TimelineTrackData(
      kind: kind ?? this.kind,
      clips: clips ?? this.clips,
      placeholderLabel: placeholderLabel ?? this.placeholderLabel,
    );
  }
}

List<TimelineTrackData> buildMockTimelineTracks() => const [];
