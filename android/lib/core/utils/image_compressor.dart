import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Upload-side image compression — port of iOS `ImageCompressor.jpeg`:
/// resize so the longest side ≤ [maxDim], JPEG-encode at [quality].
/// Falls back to the original bytes if decoding fails (server re-encodes to
/// WebP anyway and validates by magic bytes).
class ImageCompressor {
  ImageCompressor._();

  static Future<Uint8List> jpeg(
    Uint8List original, {
    int maxDim = 1600,
    int quality = 70,
  }) async {
    try {
      final out = await FlutterImageCompress.compressWithList(
        original,
        minWidth: maxDim,
        minHeight: maxDim,
        quality: quality,
        format: CompressFormat.jpeg,
        autoCorrectionAngle: true,
        keepExif: false,
      );
      return out.isEmpty ? original : out;
    } catch (_) {
      return original;
    }
  }
}
