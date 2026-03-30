import 'package:flutter/services.dart';

class FusionXDebugPicker {
  FusionXDebugPicker({
    MethodChannel? methodChannel,
  }) : _methodChannel =
            methodChannel ?? const MethodChannel(_methodChannelName);

  static const String _methodChannelName = 'fusionx.debug/picker';

  final MethodChannel _methodChannel;

  Future<String?> pickVideoClip() async {
    return _methodChannel.invokeMethod<String>('pickVideoClip');
  }
}
