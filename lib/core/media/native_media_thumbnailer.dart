import 'dart:typed_data';

class NativeMediaThumbnailer {
  NativeMediaThumbnailer._();

  static Future<List<Uint8List>> generateVideoThumbnails({
    required String path,
    required List<double> timestampsSeconds,
    int targetWidth = 80,
    int targetHeight = 48,
  }) async {
    return const <Uint8List>[];
  }
}
