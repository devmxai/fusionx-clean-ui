import '../contracts/engine_contracts.dart';

abstract class FusionXEngineBridge {
  Stream<FusionXEngineEvent> get events;

  Future<void> initialize();

  Future<AttachRenderTargetResult> attachRenderTarget({
    required int width,
    required int height,
  });

  Future<void> dispose();

  Future<void> dispatch(FusionXEngineCommand command);
}
