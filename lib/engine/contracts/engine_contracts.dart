import '../models/engine_time.dart';

enum FusionXEngineCommandType {
  attachRenderTarget,
  detachRenderTarget,
  loadClip,
  play,
  pause,
  seekTo,
  scrubTo,
  setTrim,
  dispose,
}

enum FusionXEngineEventType {
  ready,
  durationResolved,
  positionChanged,
  playbackStateChanged,
  firstFrameRendered,
  scrubFrameAvailable,
  trimChanged,
  error,
}

enum FusionXTransportState {
  idle,
  ready,
  playing,
  paused,
  seeking,
  completed,
  error,
}

class FusionXEngineCommand {
  const FusionXEngineCommand({
    required this.type,
    this.payload = const <String, Object?>{},
  });

  final FusionXEngineCommandType type;
  final Map<String, Object?> payload;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'type': type.name,
      'payload': payload,
    };
  }
}

class FusionXEngineEvent {
  const FusionXEngineEvent({
    required this.type,
    this.payload = const <String, Object?>{},
  });

  final FusionXEngineEventType type;
  final Map<String, Object?> payload;

  static FusionXEngineEvent fromMap(Map<Object?, Object?> map) {
    final rawType = map['type'] as String? ?? FusionXEngineEventType.error.name;
    return FusionXEngineEvent(
      type: FusionXEngineEventType.values.firstWhere(
        (candidate) => candidate.name == rawType,
        orElse: () => FusionXEngineEventType.error,
      ),
      payload: Map<String, Object?>.from(
        (map['payload'] as Map<Object?, Object?>?) ??
            const <Object?, Object?>{},
      ),
    );
  }
}

class AttachRenderTargetPayload {
  const AttachRenderTargetPayload({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;

  Map<String, Object> toMap() {
    return <String, Object>{
      'width': width,
      'height': height,
    };
  }
}

class AttachRenderTargetResult {
  const AttachRenderTargetResult({
    required this.textureId,
  });

  final int textureId;

  static AttachRenderTargetResult fromMap(Map<Object?, Object?> map) {
    return AttachRenderTargetResult(
      textureId: (map['textureId'] as num?)?.toInt() ?? -1,
    );
  }
}

class LoadClipPayload {
  const LoadClipPayload({
    required this.path,
  });

  final String path;

  Map<String, Object> toMap() {
    return <String, Object>{
      'path': path,
    };
  }
}

class SeekToPayload {
  const SeekToPayload({
    required this.timelineTime,
  });

  final EngineTime timelineTime;

  Map<String, Object> toMap() {
    return <String, Object>{
      'timelineTimeUs': timelineTime.inMicroseconds,
    };
  }
}

class SetTrimPayload {
  const SetTrimPayload({
    required this.trimStartUs,
    required this.trimEndUs,
  });

  final int trimStartUs;
  final int trimEndUs;

  Map<String, Object> toMap() {
    return <String, Object>{
      'trimStartUs': trimStartUs,
      'trimEndUs': trimEndUs,
    };
  }
}
