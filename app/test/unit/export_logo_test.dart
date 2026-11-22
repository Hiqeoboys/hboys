import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/line_icons.dart';

Future<void> _renderLogoPng({
  required String path,
  required bool withBackground,
}) async {
  const size = 1024.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, size, size));
  const dark = HiqeoColors.dark;

  if (withBackground) {
    // Latar penuh #313851 seperti SplashPage
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, size, size),
      ui.Paint()..color = dark.background,
    );

    // Kontur tipis konsentris seperti _ContourPainter di SplashPage
    final contourPaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = dark.textPrimary.withValues(alpha: 0.08);
    const center = ui.Offset(size / 2, size / 2);
    for (final factor in <double>[0.28, 0.38, 0.48]) {
      canvas.drawCircle(center, size * factor, contourPaint);
    }

    // Kotak kaca membulat di area aman tengah (sekitar 62% dari 1024 = 636 px)
    final boxRect = ui.Rect.fromCenter(
      center: center,
      width: 636,
      height: 636,
    );
    final boxRRect = ui.RRect.fromRectAndRadius(
      boxRect,
      const ui.Radius.circular(180),
    );
    canvas.drawRRect(
      boxRRect,
      ui.Paint()..color = dark.textPrimary.withValues(alpha: 0.12),
    );
    canvas.drawRRect(
      boxRRect,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..color = dark.glassBorder,
    );
  }

  // Gambar ikon HiqeoIcons.mountain di tengah dalam zona aman (44% dari 1024 = 450 px,
  // jauh di dalam batas aman adaptive icon 66% = 676 px).
  const iconSize = 460.0;
  const offset = (size - iconSize) / 2;
  final scale = iconSize / 24.0;
  final iconPaint = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = HiqeoMetrics.iconStroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..color = dark.textPrimary;

  canvas
    ..save()
    ..translate(offset, offset)
    ..scale(scale, scale);
  for (final p in HiqeoIcons.mountain.paths) {
    canvas.drawPath(p, iconPaint);
  }
  canvas.restore();

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(byteData!.buffer.asUint8List(), flush: true);
}

void main() {
  test('ekspor logo SplashPage (HiqeoIcons.mountain) ke PNG 1024x1024', () async {
    await _renderLogoPng(
      path: 'assets/brand/hiqeo_logo_1024.png',
      withBackground: true,
    );
    await _renderLogoPng(
      path: 'assets/brand/hiqeo_logo_foreground.png',
      withBackground: false,
    );
    expect(File('assets/brand/hiqeo_logo_1024.png').existsSync(), isTrue);
    expect(File('assets/brand/hiqeo_logo_foreground.png').existsSync(), isTrue);
  });
}

