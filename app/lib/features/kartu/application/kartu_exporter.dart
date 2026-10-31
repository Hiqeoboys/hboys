import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/brand/app_brand.dart';

/// Menangkap, menyimpan, dan membagikan PNG kartu pendakian.
///
/// Antarmuka ini disuntikkan agar tes tidak perlu menjalankan galeri atau
/// lembar berbagi platform.
abstract interface class KartuExporter {
  Future<Uint8List?> capturePng(GlobalKey boundaryKey);
  Future<bool> savePng(Uint8List bytes, String fileName);
  Future<bool> sharePng(Uint8List bytes, String fileName);
}

class DeviceKartuExporter implements KartuExporter {
  const DeviceKartuExporter();

  static const MethodChannel _media =
      MethodChannel('id.nama.nama_app/media');

  /// Lebar berkas ekspor dalam piksel. Kartu di layar berukuran ±358 logis,
  /// jadi rasio 3× menghasilkan berkas sekitar 1080 px.
  static const double exportWidthPx = 1080;

  @override
  Future<Uint8List?> capturePng(GlobalKey boundaryKey) async {
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    final width = object.size.width;
    if (width <= 0) return null;
    final pixelRatio = (exportWidthPx / width).clamp(1.0, 4.0);
    ui.Image? image;
    try {
      image = await object.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }

  @override
  Future<bool> savePng(Uint8List bytes, String fileName) async {
    try {
      final uri = await _media.invokeMethod<String>('saveImage', <String, Object?>{
        'name': fileName,
        'bytes': bytes,
      });
      return uri != null && uri.isNotEmpty;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> sharePng(Uint8List bytes, String fileName) async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      final result = await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'image/png')],
          subject: AppBrand.shareSubject,
        ),
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (_) {
      return false;
    }
  }
}
