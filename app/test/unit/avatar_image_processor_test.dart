import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/infrastructure/storage/avatar_image_processor.dart';

Future<Uint8List> _makePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF1F7A54),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('memotong foto 1:1 dan membatasi ukuran maksimal 1080x1080 px', () async {
    int? capturedSizeSmall;
    int? capturedQuality;
    final wideSmall = await _makePng(800, 400);
    final outSmall = await AvatarImageProcessor.cropSquareAndCompressWebp(
      wideSmall,
      webpEncoder: (pngBytes, size, quality) async {
        capturedSizeSmall = size;
        capturedQuality = quality;
        return pngBytes;
      },
    );
    expect(capturedSizeSmall, 400);
    expect(capturedQuality, AvatarImageProcessor.defaultQuality);
    expect(AvatarImageProcessor.defaultMaxSize, 1080);
    expect(AvatarImageProcessor.defaultQuality, 89);
    final codecSmall = await ui.instantiateImageCodec(outSmall);
    final frameSmall = await codecSmall.getNextFrame();
    expect(frameSmall.image.width, 400);
    expect(frameSmall.image.height, 400);
    frameSmall.image.dispose();
    codecSmall.dispose();

    int? capturedSizeLarge;
    final wideLarge = await _makePng(2400, 1600);
    final outLarge = await AvatarImageProcessor.cropSquareAndCompressWebp(
      wideLarge,
      webpEncoder: (pngBytes, size, quality) async {
        capturedSizeLarge = size;
        return pngBytes;
      },
    );
    expect(capturedSizeLarge, 1080);
    final codecLarge = await ui.instantiateImageCodec(outLarge);
    final frameLarge = await codecLarge.getNextFrame();
    expect(frameLarge.image.width, 1080);
    expect(frameLarge.image.height, 1080);
    frameLarge.image.dispose();
    codecLarge.dispose();
  });
}
