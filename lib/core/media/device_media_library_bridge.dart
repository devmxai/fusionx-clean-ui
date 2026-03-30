import 'package:flutter/services.dart';

import '../../features/editor/presentation/models/device_media_item.dart';
import '../../features/editor/presentation/models/editor_media_tab.dart';

class DeviceMediaLibraryBridge {
  DeviceMediaLibraryBridge({
    MethodChannel? methodChannel,
  }) : _methodChannel =
            methodChannel ?? const MethodChannel(_methodChannelName);

  static const String _methodChannelName = 'fusionx.media/library';

  final MethodChannel _methodChannel;

  Future<bool> hasMediaPermission(EditorMediaTab tab) async {
    final granted = await _methodChannel.invokeMethod<bool>(
      'hasMediaPermission',
      <String, Object?>{
        'tab': tab.name,
      },
    );
    return granted ?? false;
  }

  Future<List<DeviceMediaItem>> listMedia(EditorMediaTab tab) async {
    final raw = await _methodChannel.invokeMethod<List<dynamic>>(
      'listDeviceMedia',
      <String, Object?>{
        'tab': tab.name,
      },
    );

    if (raw == null) {
      return const <DeviceMediaItem>[];
    }

    return raw
        .whereType<Map<Object?, Object?>>()
        .map(DeviceMediaItem.fromMap)
        .toList(growable: false);
  }

  Future<Uint8List?> loadThumbnail({
    required DeviceMediaItem item,
    int targetWidth = 240,
    int targetHeight = 240,
  }) async {
    return _methodChannel.invokeMethod<Uint8List>(
      'loadMediaThumbnail',
      <String, Object?>{
        'uri': item.uri,
        'tab': item.tab.name,
        'targetWidth': targetWidth,
        'targetHeight': targetHeight,
      },
    );
  }
}
