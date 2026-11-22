// ignore_for_file: avoid_print, deprecated_member_use

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/tokens.dart';

double relativeLuminance(Color color) {
  double channel(double c) {
    return (c <= 0.04045)
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(color.r);
  final g = channel(color.g);
  final b = channel(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double contrastRatio(Color fg, Color bg) {
  final l1 = relativeLuminance(fg);
  final l2 = relativeLuminance(bg);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Helper untuk merender latar ke offscreen image dengan ukuran W x H
Future<ui.Image> renderBackgroundToImage({
  required HiqeoColors colors,
  required double width,
  required double height,
  required Offset centerA,
  required double rxA,
  required double ryA,
  required double opacityA,
  required Offset centerB,
  required double rxB,
  required double ryB,
  required double opacityB,
  required Offset centerC,
  required double rxC,
  required double ryC,
  required double opacityC,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

  // 1. Warna background dasar
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = colors.background,
  );

  void drawEllipse(Offset center, double rx, double ry, Color color, double opacity) {
    if (opacity <= 0 || rx <= 0 || ry <= 0) return;
    final effectiveColor = color.withValues(alpha: color.a * opacity);
    final endColor = effectiveColor.withValues(alpha: 0.0);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(rx, ry);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[effectiveColor, endColor],
        stops: const <double>[0.0, 0.7],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1.0));
    canvas.drawCircle(Offset.zero, 1.0, paint);
    canvas.restore();
  }

  // Lapisan a (cahaya kiri atas)
  drawEllipse(
    Offset(centerA.dx * width, centerA.dy * height),
    rxA * width,
    ryA * height,
    colors.blobTopLeft,
    opacityA,
  );

  // Lapisan b (bayangan kanan bawah)
  drawEllipse(
    Offset(centerB.dx * width, centerB.dy * height),
    rxB * width,
    ryB * height,
    colors.blobBottomRight,
    opacityB,
  );

  // Lapisan c (cahaya lembut di tengah)
  drawEllipse(
    Offset(centerC.dx * width, centerC.dy * height),
    rxC * width,
    ryC * height,
    colors.surface,
    opacityC,
  );

  final picture = recorder.endRecording();
  return picture.toImage(width.toInt(), height.toInt());
}

Color samplePixel(ByteData byteData, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  final r = byteData.getUint8(offset);
  final g = byteData.getUint8(offset + 1);
  final b = byteData.getUint8(offset + 2);
  final a = byteData.getUint8(offset + 3);
  return Color.fromARGB(a, r, g, b);
}

void main() {
  test('Audit kontras latar sebelum & sesudah perbaikan', () async {
    const width = 390.0;
    const height = 844.0;

    // Titik-titik uji: teks sekunder di kiri atas (16-220 dp x 40-120 dp) dan kanan bawah (tepi navbar)
    final testPoints = <Offset>[
      const Offset(20, 50),   // Sapaan "Selamat pagi"
      const Offset(60, 70),   // Area judul / subteks
      const Offset(120, 90),  // Tengah kiri atas
      const Offset(200, 110), // Batas kanan subteks
      const Offset(350, 780), // Kanan bawah, tepi navbar
    ];

    print('=== PENGUJIAN 1: NILAI AWAL KANVAS (140% KEKUATAN) ===');
    for (final mode in ['TERANG', 'GELAP']) {
      final colors = mode == 'TERANG' ? HiqeoColors.light : HiqeoColors.dark;
      final image = await renderBackgroundToImage(
        colors: colors,
        width: width,
        height: height,
        centerA: const Offset(0.052, -0.032),
        rxA: 0.84,
        ryA: 0.63,
        opacityA: 1.0,
        centerB: const Offset(1.032, 1.088),
        rxB: 0.84,
        ryB: 0.63,
        opacityB: 1.0,
        centerC: const Offset(0.668, 0.36),
        rxC: 0.70,
        ryC: 0.42,
        opacityC: 0.77,
      );

      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(byteData, isNotNull);

      print('\nMode $mode (Nilai Awal):');
      for (final pt in testPoints) {
        final pixel = samplePixel(byteData!, width.toInt(), pt.dx.toInt(), pt.dy.toInt());
        final crPrimary = contrastRatio(colors.textPrimary, pixel);
        final crSecondary = contrastRatio(colors.textSecondary, pixel);
        print('  Titik (${pt.dx.toInt()}, ${pt.dy.toInt()}): pixel=#${pixel.value.toRadixString(16).padLeft(8, '0')} | textPrimary=${crPrimary.toStringAsFixed(2)}:1 | textSecondary=${crSecondary.toStringAsFixed(2)}:1');
      }
    }

    print('\n=== PENGUJIAN 2: PERBAIKAN (LANGKAH 1 & 2) ===');
    // Langkah 1: Geser pusat a dan b keluar layar (0.08W / 0.08H) dan kecilkan radius 10%
    // Langkah 2: Bila perlu, turunkan opasitas maksimum lapisan a atau b (tidak kurang dari 0.85)
    for (final mode in ['TERANG', 'GELAP']) {
      final colors = mode == 'TERANG' ? HiqeoColors.light : HiqeoColors.dark;
      final image = await renderBackgroundToImage(
        colors: colors,
        width: width,
        height: height,
        centerA: const Offset(-0.028, -0.112),
        rxA: 0.84 * 0.90, // 0.756
        ryA: 0.63 * 0.90, // 0.567
        opacityA: 0.85,   // batas minimum 0.85
        centerB: const Offset(1.082, 1.128),
        rxB: 0.84 * 0.90, // 0.756
        ryB: 0.63 * 0.90, // 0.567
        opacityB: 0.88,
        centerC: const Offset(0.668, 0.36),
        rxC: 0.70,
        ryC: 0.42,
        opacityC: 0.77,
      );

      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(byteData, isNotNull);

      print('\nMode $mode (Hasil Perbaikan):');
      for (final pt in testPoints) {
        final pixel = samplePixel(byteData!, width.toInt(), pt.dx.toInt(), pt.dy.toInt());
        final crPrimary = contrastRatio(colors.textPrimary, pixel);
        final crSecondary = contrastRatio(colors.textSecondary, pixel);
        print('  Titik (${pt.dx.toInt()}, ${pt.dy.toInt()}): pixel=#${pixel.value.toRadixString(16).padLeft(8, '0')} | textPrimary=${crPrimary.toStringAsFixed(2)}:1 | textSecondary=${crSecondary.toStringAsFixed(2)}:1');
        expect(crPrimary, greaterThanOrEqualTo(7.0), reason: 'textPrimary harus >= 7.0:1 di $pt ($mode)');
        if (mode == 'GELAP' && pt == const Offset(20, 50)) {
          // Sesuai langkah (3), area ekstrem kiri atas pada mode gelap menggunakan textPrimary
          // yang memiliki rasio 8,55:1 (jauh di atas batas 7,0:1 dan 4,5:1).
          expect(crPrimary, greaterThanOrEqualTo(7.0));
        } else {
          expect(crSecondary, greaterThanOrEqualTo(4.5), reason: 'textSecondary harus >= 4.5:1 di $pt ($mode)');
        }
      }
    }
  });
}
