import 'dart:async';
import 'dart:io' show zlib;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color;
import 'package:http/http.dart' as http;

import '../cache/avatar_disk_cache.dart';
import '../network/hiqeo_http_overrides.dart';
import '../storage/media_url_normalizer.dart';

/// Pembantu pengunduhan, pembacaan cache disk, dan pemotongan avatar menjadi
/// gambar PNG lingkaran rapi untuk `largeIcon` & `MessagingStyleInformation`.
class NotificationAvatarHelper {
  NotificationAvatarHelper._();

  static const int _targetSizePx = 128;
  static const int _monogramSizePx = 64;

  static const List<Color> _monogramPalette = <Color>[
    Color(0xFF334155),
    Color(0xFF1E3A8A),
    Color(0xFF0F766E),
    Color(0xFF6D28D9),
    Color(0xFF9A3412),
    Color(0xFF1D4ED8),
    Color(0xFF3F6212),
    Color(0xFF9D174D),
  ];

  static final Map<String, Uint8List> _monogramMemoryCache =
      <String, Uint8List>{};

  /// Mengambil avatar PNG berbentuk lingkaran untuk notifikasi Android.
  ///
  /// 1. Mengecek [AvatarDiskCache] lebih dulu, lalu mengunduh bila URL valid.
  /// 2. Memotong gambar ke bentuk lingkaran 128×128 px.
  /// 3. Jika URL kosong/gagal diunduh, membuat ikon lingkaran rapi dalam Dart
  ///    murni (bebas ketergantungan GPU/rasterizer sehingga instan di background
  ///    isolate maupun FakeAsync widget test).
  static Future<Uint8List?> resolveCircularAvatarPng({
    required String cacheKey,
    String? avatarUrl,
    required String fallbackLabel,
    bool allowMonogramFallback = true,
  }) async {
    final normalized = MediaUrlNormalizer.normalize(avatarUrl);
    Uint8List? sourceBytes;

    if (cacheKey.trim().isNotEmpty &&
        normalized != null &&
        normalized.isNotEmpty) {
      try {
        await AvatarDiskCache.instance.init();
        var file = AvatarDiskCache.instance.cachedFileFor(cacheKey, normalized);
        if (file == null &&
            MediaUrlNormalizer.isNetworkUrl(normalized) &&
            !MediaUrlNormalizer.isPresignedOrPrivateR2Url(normalized)) {
          file = await AvatarDiskCache.instance
              .ensureCached(cacheKey, normalized)
              .timeout(const Duration(seconds: 3));
        }
        if (file != null && await file.exists()) {
          sourceBytes = await file.readAsBytes();
        }
      } catch (_) {}
    }

    if (sourceBytes == null &&
        normalized != null &&
        normalized.isNotEmpty &&
        MediaUrlNormalizer.isNetworkUrl(normalized) &&
        !MediaUrlNormalizer.isPresignedOrPrivateR2Url(normalized)) {
      sourceBytes = await _downloadRawBytes(normalized);
    }

    if (sourceBytes != null && sourceBytes.isNotEmpty) {
      final cropped = await cropToCirclePng(sourceBytes);
      if (cropped != null && cropped.isNotEmpty) {
        return cropped;
      }
      return sourceBytes;
    }

    if (!allowMonogramFallback) return null;
    return renderMonogramCirclePngSync(
      seed: cacheKey.trim().isNotEmpty ? cacheKey : fallbackLabel,
      label: fallbackLabel,
    );
  }

  static Future<Uint8List?> _downloadRawBytes(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return null;
      }
      final res = await http
          .get(
            uri,
            headers: const <String, String>{
              'User-Agent': HiqeoHttpOverrides.userAgent,
            },
          )
          .timeout(const Duration(seconds: 3));
      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          res.bodyBytes.isEmpty == false) {
        return res.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  /// Memotong byte gambar sembarang (WebP/JPEG/PNG) menjadi PNG lingkaran
  /// berukuran 128×128 px agar tampil proporsional di panel notifikasi Android.
  static Future<Uint8List?> cropToCirclePng(Uint8List rawBytes) async {
    if (rawBytes.isEmpty) return null;
    try {
      final codec = await ui
          .instantiateImageCodec(
            rawBytes,
            targetWidth: _targetSizePx,
            targetHeight: _targetSizePx,
          )
          .timeout(const Duration(milliseconds: 1200));
      final frame = await codec
          .getNextFrame()
          .timeout(const Duration(milliseconds: 1200));
      final srcImage = frame.image;
      try {
        final recorder = ui.PictureRecorder();
        final size = _targetSizePx.toDouble();
        final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, size, size));
        final rect = ui.Rect.fromLTWH(0, 0, size, size);
        canvas.save();
        canvas.clipPath(ui.Path()..addOval(rect));
        final srcRect = _centerCropSquareRect(
          srcImage.width.toDouble(),
          srcImage.height.toDouble(),
        );
        canvas.drawImageRect(
          srcImage,
          srcRect,
          rect,
          ui.Paint()..isAntiAlias = true,
        );
        canvas.restore();

        final picture = recorder.endRecording();
        final output = await picture
            .toImage(_targetSizePx, _targetSizePx)
            .timeout(const Duration(milliseconds: 1200));
        try {
          final byteData = await output
              .toByteData(format: ui.ImageByteFormat.png)
              .timeout(const Duration(milliseconds: 1200));
          return byteData?.buffer.asUint8List();
        } finally {
          output.dispose();
          picture.dispose();
        }
      } finally {
        srcImage.dispose();
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Menghasilkan PNG lingkaran 64×64 px secara sinkron dalam Dart murni
  /// (tanpa `PictureRecorder` / thread GPU) sehingga aman di background isolate
  /// tanpa `FlutterView` maupun di dalam `testWidgets` (`FakeAsync`).
  static Uint8List renderMonogramCirclePngSync({
    required String seed,
    required String label,
  }) {
    final cacheKey = '${seed.trim()}|${label.trim()}';
    final cached = _monogramMemoryCache[cacheKey];
    if (cached != null) return cached;

    final color = _colorForSeed(seed.trim().isNotEmpty ? seed : label);
    final bgR = (color.r * 255.0).round().clamp(0, 255);
    final bgG = (color.g * 255.0).round().clamp(0, 255);
    final bgB = (color.b * 255.0).round().clamp(0, 255);

    const size = _monogramSizePx;
    const center = (size - 1) / 2.0;
    const outerRadius = size / 2.0 - 0.5;
    const ringInnerRadius = outerRadius - 2.0;
    const dotRadius = 6.5;

    // Setiap baris PNG diawali 1 byte filter (0 = None) diikuti size * 4 byte RGBA.
    final rowStride = 1 + size * 4;
    final rawScanlines = Uint8List(size * rowStride);

    for (var y = 0; y < size; y++) {
      final rowOffset = y * rowStride;
      rawScanlines[rowOffset] = 0;
      final dy = y - center;
      for (var x = 0; x < size; x++) {
        final dx = x - center;
        final distSq = dx * dx + dy * dy;
        final pxOffset = rowOffset + 1 + x * 4;
        if (distSq > outerRadius * outerRadius) {
          // Di luar lingkaran: transparan penuh.
          continue;
        }
        if (distSq <= dotRadius * dotRadius) {
          // Titik aksen krem tengah (#F6F3ED).
          rawScanlines[pxOffset] = 0xF6;
          rawScanlines[pxOffset + 1] = 0xF3;
          rawScanlines[pxOffset + 2] = 0xED;
          rawScanlines[pxOffset + 3] = 0xFF;
        } else if (distSq >= ringInnerRadius * ringInnerRadius) {
          // Cincin tepi dalam halus.
          rawScanlines[pxOffset] = ((bgR * 3 + 255) ~/ 4).clamp(0, 255);
          rawScanlines[pxOffset + 1] = ((bgG * 3 + 255) ~/ 4).clamp(0, 255);
          rawScanlines[pxOffset + 2] = ((bgB * 3 + 255) ~/ 4).clamp(0, 255);
          rawScanlines[pxOffset + 3] = 0xFF;
        } else {
          rawScanlines[pxOffset] = bgR;
          rawScanlines[pxOffset + 1] = bgG;
          rawScanlines[pxOffset + 2] = bgB;
          rawScanlines[pxOffset + 3] = 0xFF;
        }
      }
    }

    final png = _encodeRgbaPng(size, size, rawScanlines);
    if (_monogramMemoryCache.length < 64) {
      _monogramMemoryCache[cacheKey] = png;
    }
    return png;
  }

  static Uint8List _encodeRgbaPng(int width, int height, Uint8List scanlines) {
    final ihdr = ByteData(13)
      ..setUint32(0, width, Endian.big)
      ..setUint32(4, height, Endian.big)
      ..setUint8(8, 8) // bit depth 8
      ..setUint8(9, 6) // color type 6 (RGBA)
      ..setUint8(10, 0)
      ..setUint8(11, 0)
      ..setUint8(12, 0);

    final compressed = Uint8List.fromList(zlib.encode(scanlines));
    final out = BytesBuilder(copy: false)
      ..add(const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    _writePngChunk(out, 'IHDR', ihdr.buffer.asUint8List());
    _writePngChunk(out, 'IDAT', compressed);
    _writePngChunk(out, 'IEND', const <int>[]);
    return out.toBytes();
  }

  static void _writePngChunk(BytesBuilder out, String type, List<int> data) {
    final lenBytes = ByteData(4)..setUint32(0, data.length, Endian.big);
    out.add(lenBytes.buffer.asUint8List());
    final typeBytes = type.codeUnits;
    out.add(typeBytes);
    if (data.isNotEmpty) out.add(data);

    var crc = 0xFFFFFFFF;
    for (final b in typeBytes) {
      crc = _updateCrc32(crc, b);
    }
    for (final b in data) {
      crc = _updateCrc32(crc, b);
    }
    crc ^= 0xFFFFFFFF;
    final crcBytes = ByteData(4)..setUint32(0, crc, Endian.big);
    out.add(crcBytes.buffer.asUint8List());
  }

  static int _updateCrc32(int crc, int byte) {
    var c = crc ^ (byte & 0xFF);
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    return c;
  }

  static ui.Rect _centerCropSquareRect(double w, double h) {
    final side = w < h ? w : h;
    final left = (w - side) / 2;
    final top = (h - side) / 2;
    return ui.Rect.fromLTWH(left, top, side, side);
  }

  static Color _colorForSeed(String seed) {
    if (seed.trim().isEmpty) return const Color(0xFF242B40);
    var hash = 0x811c9dc5;
    for (var i = 0; i < seed.length; i++) {
      hash ^= seed.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return _monogramPalette[hash % _monogramPalette.length];
  }
}
