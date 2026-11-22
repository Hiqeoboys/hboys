import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

typedef WebpCompressFn = Future<Uint8List> Function(
  Uint8List pngBytes,
  int size,
  int quality,
);

/// Memotong foto profil menjadi 1:1 persegi di tengah, mengubah ukuran
/// maksimal 1080×1080 px agar tetap tajam di mode layar penuh, lalu mengompresinya ke format WebP.
abstract final class AvatarImageProcessor {
  static const int defaultMaxSize = 1080;
  static const int defaultQuality = 89;

  static Future<Uint8List> cropSquareAndCompressWebp(
    Uint8List sourceBytes, {
    int maxSize = defaultMaxSize,
    int quality = defaultQuality,
    WebpCompressFn? webpEncoder,
  }) async {
    final codec = await ui.instantiateImageCodec(sourceBytes);
    ui.Image? decoded;
    ui.Image? cropped;
    try {
      final frame = await codec.getNextFrame();
      decoded = frame.image;
      final w = decoded.width.toDouble();
      final h = decoded.height.toDouble();
      final side = math.min(w, h);
      final outDim = math.min(side.round(), maxSize).clamp(1, maxSize);
      final src = ui.Rect.fromLTWH((w - side) / 2, (h - side) / 2, side, side);
      final dst = ui.Rect.fromLTWH(0, 0, outDim.toDouble(), outDim.toDouble());

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, dst);
      canvas.drawImageRect(
        decoded,
        src,
        dst,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      cropped = await picture.toImage(outDim, outDim);
      picture.dispose();
      final pngData = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (pngData == null) {
        throw StateError('Gagal memproses gambar profil.');
      }
      final pngBytes = pngData.buffer.asUint8List();
      if (webpEncoder != null) {
        return await webpEncoder(pngBytes, outDim, quality);
      }
      try {
        final webp = await FlutterImageCompress.compressWithList(
          pngBytes,
          minWidth: outDim,
          minHeight: outDim,
          quality: quality,
          format: CompressFormat.webp,
        );
        if (webp.isNotEmpty) return webp;
      } on MissingPluginException {
        // Fallback ke PNG terpotong pada uji tanpa plugin platform.
      }
      return pngBytes;
    } finally {
      cropped?.dispose();
      decoded?.dispose();
      codec.dispose();
    }
  }
}
