import 'dart:async';

import 'package:flutter/services.dart';

import '../contracts/engine_contracts.dart';
import 'fusionx_engine_bridge.dart';

class MethodChannelFusionXEngineBridge implements FusionXEngineBridge {
  MethodChannelFusionXEngineBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel =
            methodChannel ?? const MethodChannel(_methodChannelName),
        _eventChannel = eventChannel ?? const EventChannel(_eventChannelName);

  static const String _methodChannelName = 'fusionx.engine/methods';
  static const String _eventChannelName = 'fusionx.engine/events';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<FusionXEngineEvent>? _events;

  @override
  Stream<FusionXEngineEvent> get events {
    return _events ??=
        _eventChannel.receiveBroadcastStream().map((dynamic raw) {
      if (raw is Map<Object?, Object?>) {
        return FusionXEngineEvent.fromMap(raw);
      }
      return const FusionXEngineEvent(type: FusionXEngineEventType.error);
    });
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<AttachRenderTargetResult> attachRenderTarget({
    required int width,
    required int height,
  }) async {
    final raw = await _methodChannel.invokeMethod<Map<Object?, Object?>>(
      FusionXEngineCommandType.attachRenderTarget.name,
      AttachRenderTargetPayload(
        width: width,
        height: height,
      ).toMap(),
    );
    return AttachRenderTargetResult.fromMap(
      raw ?? const <Object?, Object?>{},
    );
  }

  @override
  Future<void> dispose() async {
    await dispatch(
      const FusionXEngineCommand(
        type: FusionXEngineCommandType.dispose,
      ),
    );
  }

  @override
  Future<void> dispatch(FusionXEngineCommand command) async {
    await _methodChannel.invokeMethod<void>(
      command.type.name,
      command.payload,
    );
  }
}
