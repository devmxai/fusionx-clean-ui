import '../contracts/engine_contracts.dart';
import '../models/project_playback_models.dart';
import '../models/project_sync_models.dart';

abstract class FusionXEngineBridge {
  Stream<FusionXEngineEvent> get events;

  Future<void> initialize();

  Future<AttachRenderTargetResult> attachRenderTarget({
    required int width,
    required int height,
  });

  Future<void> syncProject(FusionXProjectSyncPayload payload);

  Future<FusionXProjectCanvasSnapshot> getProjectCanvas();

  Future<FusionXProjectPlaybackSnapshot> resolveProjectPlayback(
    int timelineTimeUs,
  );

  Future<void> dispose();

  Future<void> dispatch(FusionXEngineCommand command);
}
