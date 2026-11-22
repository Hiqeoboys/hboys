import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../infrastructure/cache/hiqeo_media_cache_service.dart';
import '../../../infrastructure/storage/media_url_normalizer.dart';
import '../../chat/presentation/chat_room_chrome.dart';

/// Tag animasi `Hero` konsisten antara gelembung media chat dan viewer layar penuh.
String communityMediaHeroTag(String messageId) => 'community-media-$messageId';

/// Konfigurasi kualitas & ukuran unggahan media Hiqeo (foto chat, video, & avatar)
/// agar tetap tajam secara visual tanpa mengirim berkas mentah berukuran raksasa.
abstract final class HiqeoMediaCompressionConfig {
  static const int chatPhotoMaxLongestSide = 1920;
  static const int chatPhotoQuality = 86;
  static const int chatPhotoFallbackQuality = 82;

  static const int avatarMaxSize = 1080;
  static const int avatarQuality = 89;

  static const int maxProxyVideoBytes = 25 * 1024 * 1024;
  static const int safeTargetVideoBytes = 23 * 1024 * 1024;
  static const int videoMinBitrateBps = 2500000;
  static const int videoDefault720pBitrateBps = 3000000;
  static const int videoHd1080pBitrateBps = 3800000;
  static const int videoMaxBitrateBps = 4000000;
  static const int videoAudioBitrateBps = 128000;
}

/// Profil target kompresi video H.264 lintas platform (Android Media3 & iOS AVAssetExportSession).
class VideoCompressionProfile {
  const VideoCompressionProfile({
    required this.targetShortSidePx,
    required this.targetVideoBitrateBps,
    required this.maxBytes,
  });

  final int targetShortSidePx;
  final int targetVideoBitrateBps;
  final int maxBytes;

  bool get isHd1080p => targetShortSidePx >= 1080;
}

/// Menghitung dimensi target yang mempertahankan rasio asli dengan sisi terpanjang
/// maksimal [maxLongestSide] (1600-1920 px). Gambar kecil tidak pernah di-upscale.
({int width, int height}) computeProportionalMaxDimensions({
  required int width,
  required int height,
  int maxLongestSide = HiqeoMediaCompressionConfig.chatPhotoMaxLongestSide,
}) {
  if (width <= 0 || height <= 0) {
    return (width: maxLongestSide, height: maxLongestSide);
  }
  final longest = math.max(width, height);
  if (longest <= maxLongestSide) {
    return (width: width, height: height);
  }
  final scale = maxLongestSide / longest;
  return (
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

/// Menentukan resolusi (720p atau 1080p jika sumber HD dan durasi muat) serta
/// bitrate H.264 adaptif ~2.5-4 Mbps agar video tetap jernih di bawah batas 25 MB.
VideoCompressionProfile computeVideoCompressionProfile({
  required int durationSec,
  int? sourceWidth,
  int? sourceHeight,
}) {
  final safeDuration = durationSec.clamp(1, 60);
  final maxTotalBps =
      ((HiqeoMediaCompressionConfig.safeTargetVideoBytes * 8) / safeDuration)
          .floor();
  final budgetVideoBps =
      maxTotalBps - HiqeoMediaCompressionConfig.videoAudioBitrateBps;

  final shortSide = (sourceWidth != null &&
          sourceHeight != null &&
          sourceWidth > 0 &&
          sourceHeight > 0)
      ? math.min(sourceWidth, sourceHeight)
      : 720;

  final canUse1080p = shortSide >= 1080 &&
      budgetVideoBps >= HiqeoMediaCompressionConfig.videoHd1080pBitrateBps;

  final targetShortSide = canUse1080p ? 1080 : 720;
  final idealBitrate = canUse1080p
      ? HiqeoMediaCompressionConfig.videoHd1080pBitrateBps
      : HiqeoMediaCompressionConfig.videoDefault720pBitrateBps;
  final targetBitrate = budgetVideoBps
      .clamp(
        HiqeoMediaCompressionConfig.videoMinBitrateBps,
        math.min(HiqeoMediaCompressionConfig.videoMaxBitrateBps, idealBitrate),
      )
      .toInt();

  return VideoCompressionProfile(
    targetShortSidePx: targetShortSide,
    targetVideoBitrateBps: targetBitrate,
    maxBytes: HiqeoMediaCompressionConfig.maxProxyVideoBytes,
  );
}

/// Menghitung ukuran kotak pratinjau adaptif agar media mengikuti rasio alami
/// dengan batas `maxWidth` (~74% lebar layar) serta tinggi `[minHeight, maxHeight]`.
Size computeAdaptiveMediaBoxSize({
  required double maxWidth,
  double minHeight = 140.0,
  double maxHeight = 340.0,
  double? aspectRatio,
}) {
  if (aspectRatio != null && aspectRatio.isFinite && aspectRatio > 0) {
    var w = maxWidth;
    var h = w / aspectRatio;
    if (h > maxHeight) {
      h = maxHeight;
      w = (h * aspectRatio).clamp(math.min(maxWidth, 120.0), maxWidth);
    } else if (h < minHeight) {
      h = minHeight;
      w = maxWidth;
    }
    return Size(w, h);
  }
  return Size(maxWidth, (maxWidth * 0.72).clamp(minHeight, maxHeight));
}

/// Memformat durasi detik ke `X dtk` (< 60 dtk) atau `m:ss` (>= 60 dtk).
String formatVideoDurationSeconds(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  if (safe < 60) return '$safe dtk';
  final m = safe ~/ 60;
  final s = safe % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Menghitung sisa detik video dibulatkan ke atas per detik agar angka tidak
/// meloncat terlalu dini ke 0, dan kembali ke total durasi saat berhenti di awal/akhir.
int computeVideoRemainingSeconds({
  required Duration total,
  required Duration position,
  required bool isPlaying,
  int? fallbackTotalSec,
}) {
  final effectiveTotalMs =
      total.inMilliseconds > 0 ? total.inMilliseconds : (fallbackTotalSec ?? 0) * 1000;
  if (effectiveTotalMs <= 0) return 0;
  final totalSec = (effectiveTotalMs / 1000.0).ceil();
  if (!isPlaying &&
      (position.inMilliseconds <= 0 ||
          position.inMilliseconds >= effectiveTotalMs)) {
    return totalSec;
  }
  final remainingMs =
      (effectiveTotalMs - position.inMilliseconds).clamp(0, effectiveTotalMs);
  return (remainingMs / 1000.0).ceil().clamp(0, totalSec);
}

/// Format label lencana durasi sisa video untuk pemutar inline & layar penuh.
String formatVideoRemainingBadge({
  required Duration total,
  required Duration position,
  required bool isPlaying,
  int? fallbackTotalSec,
}) {
  return formatVideoDurationSeconds(
    computeVideoRemainingSeconds(
      total: total,
      position: position,
      isPlaying: isPlaying,
      fallbackTotalSec: fallbackTotalSec,
    ),
  );
}

/// Memformat stempel waktu lengkap untuk pil header viewer (mis. `Hari ini · 06:37`).
String formatCommunityMediaTimestamp(
  DateTime createdAtUtc, [
  DateTime? nowUtc,
]) {
  final local = createdAtUtc.toLocal();
  final dayLabel = formatChatDayDividerLabel(
    createdAtUtc,
    nowUtc ?? DateTime.now().toUtc(),
  );
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$dayLabel · $hh:$mm';
}

/// Saluran platform native (`MediaMetadataRetriever` & `MediaStore`) untuk media komunitas.
abstract final class CommunityMediaChannel {
  static const MethodChannel _channel = MethodChannel('id.nama.nama_app/media');

  /// Membaca versi aplikasi (`versionName+versionCode`) untuk cache-busting antar update.
  static Future<String> getAppVersion() async {
    try {
      final raw = await _channel.invokeMethod<String>('getAppVersion');
      if (raw != null && raw.trim().isNotEmpty) return raw.trim();
    } catch (_) {}
    return '0+0';
  }

  /// Mengekstrak frame pertama video (jalur lokal maupun URL HTTP/HTTPS) menjadi byte WebP/JPEG.
  static Future<Uint8List?> extractVideoThumbnail(
    String source, {
    int maxWidth = 960,
  }) async {
    if (source.trim().isEmpty) return null;
    try {
      return await _channel.invokeMethod<Uint8List>(
        'extractVideoThumbnail',
        <String, dynamic>{
          'source': source,
          'maxWidth': maxWidth,
        },
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Mengompresi video menjadi H.264/AAC (720p atau 1080p) secara native pada Android & iOS
  /// sehingga tidak pernah memakai preset beresolusi rendah yang buram.
  static Future<String?> compressVideo(
    String sourcePath, {
    required int maxHeight,
    required int bitrateBps,
    required int maxBytes,
  }) async {
    if (sourcePath.trim().isEmpty) return null;
    try {
      final path = await _channel.invokeMethod<String>(
        'compressVideo',
        <String, dynamic>{
          'sourcePath': sourcePath,
          'maxHeight': maxHeight,
          'bitrateBps': bitrateBps,
          'maxBytes': maxBytes,
        },
      );
      if (path != null && path.trim().isNotEmpty) return path.trim();
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Menyimpan foto/video ke galeri lewat MediaStore Android Q+.
  static Future<String?> saveMediaToGallery({
    required String name,
    required String mimeType,
    String? filePath,
    Uint8List? bytes,
  }) async {
    try {
      return await _channel.invokeMethod<String>(
        'saveMedia',
        <String, dynamic>{
          'name': name,
          'mimeType': mimeType,
          if (filePath != null) 'filePath': filePath,
          if (bytes != null) 'bytes': bytes,
        },
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// Cache disk persisten untuk cover/thumbnail video komunitas di `<appSupportDir>/community_video_thumbs`.
class CommunityVideoThumbnailCache {
  CommunityVideoThumbnailCache({
    Future<Directory> Function()? directoryProvider,
    Future<Uint8List?> Function(String url)? httpFetcher,
    Future<Uint8List?> Function(String source)? nativeExtractor,
  })  : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
        _httpFetcher = httpFetcher ?? _defaultHttpFetch,
        _hasCustomNativeExtractor = nativeExtractor != null,
        _nativeExtractor =
            nativeExtractor ?? CommunityMediaChannel.extractVideoThumbnail;

  static final CommunityVideoThumbnailCache instance =
      CommunityVideoThumbnailCache();

  final Future<Directory> Function() _directoryProvider;
  final Future<Uint8List?> Function(String url) _httpFetcher;
  final bool _hasCustomNativeExtractor;
  final Future<Uint8List?> Function(String source) _nativeExtractor;

  final Map<String, Uint8List> _memory = <String, Uint8List>{};
  final Map<String, double> _aspectRatios = <String, double>{};
  final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};

  /// Hash FNV-1a 64-bit stabil agar nama berkas disk aman lintas sesi.
  static String cacheFileKey(String rawKey) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final code in rawKey.codeUnits) {
      hash = ((hash ^ BigInt.from(code)) * prime) & mask;
    }
    return '${hash.toRadixString(16).padLeft(16, '0')}.webp';
  }

  double? getAspectRatio(String key) => _aspectRatios[key];

  void clearMemoryCache() {
    _memory.clear();
    _aspectRatios.clear();
    _inFlight.clear();
  }

  void setAspectRatio(String key, double ratio) {
    if (ratio.isFinite && ratio > 0) {
      _aspectRatios[key] = ratio;
    }
  }

  /// Pencarian sinkron di memori agar `initState` tidak sempat berkedip hitam.
  Uint8List? getMemoryBytes(String videoUrl, {String? messageId}) {
    final direct = _memory[videoUrl];
    if (direct != null && direct.isNotEmpty) return direct;
    if (messageId != null && messageId.isNotEmpty) {
      final byId = _memory[messageId];
      if (byId != null && byId.isNotEmpty) return byId;
    }
    return null;
  }

  Future<Directory?> _thumbDir() async {
    try {
      final base = await _directoryProvider();
      final dir = Directory(p.join(base.path, 'community_video_thumbs'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  Future<File?> saveBytes(String key, Uint8List bytes) async {
    if (key.isEmpty || bytes.isEmpty) return null;
    _memory[key] = bytes;
    final dir = await _thumbDir();
    if (dir == null) return null;
    try {
      final file = File(p.join(dir.path, cacheFileKey(key)));
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _readDisk(String key) async {
    if (key.isEmpty) return null;
    final dir = await _thumbDir();
    if (dir == null) return null;
    try {
      final file = File(p.join(dir.path, cacheFileKey(key)));
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        _memory[key] = bytes;
        return bytes;
      }
    } catch (_) {}
    return null;
  }

  /// Mengambil thumbnail secara berjenjang: memori -> disk -> URL thumbnail -> ekstraksi native.
  Future<Uint8List?> resolveThumbnail({
    required String videoUrl,
    String? thumbnailUrl,
    String? messageId,
  }) {
    final cleanVideoUrl = MediaUrlNormalizer.normalize(videoUrl) ?? videoUrl;
    final cleanThumbUrl = MediaUrlNormalizer.normalize(thumbnailUrl);
    final mem = getMemoryBytes(cleanVideoUrl, messageId: messageId);
    if (mem != null) return Future<Uint8List?>.value(mem);
    return _inFlight.putIfAbsent(cleanVideoUrl, () async {
      try {
        final fromUrlDisk = await _readDisk(cleanVideoUrl);
        if (fromUrlDisk != null) return fromUrlDisk;

        if (messageId != null && messageId.isNotEmpty) {
          final fromIdDisk = await _readDisk(messageId);
          if (fromIdDisk != null) {
            await saveBytes(cleanVideoUrl, fromIdDisk);
            return fromIdDisk;
          }
        }

        if (cleanThumbUrl != null && cleanThumbUrl.isNotEmpty) {
          final downloaded = await _httpFetcher(cleanThumbUrl);
          if (downloaded != null && downloaded.isNotEmpty) {
            await saveBytes(cleanVideoUrl, downloaded);
            if (messageId != null && messageId.isNotEmpty) {
              await saveBytes(messageId, downloaded);
            }
            return downloaded;
          }
        }

        var extractSource = cleanVideoUrl;
        if (!_hasCustomNativeExtractor) {
          final playable = await HiqeoMediaCacheService.instance
              .resolvePlayableVideoSource(cleanVideoUrl);
          extractSource =
              playable.file?.path ?? playable.streamUrl ?? cleanVideoUrl;
        }
        final extracted = await _nativeExtractor(extractSource);
        if (extracted != null && extracted.isNotEmpty) {
          await saveBytes(cleanVideoUrl, extracted);
          if (messageId != null && messageId.isNotEmpty) {
            await saveBytes(messageId, extracted);
          }
          return extracted;
        }
        return null;
      } finally {
        unawaited(_inFlight.remove(cleanVideoUrl));
      }
    });
  }

  static Future<Uint8List?> _defaultHttpFetch(String url) =>
      HiqeoMediaCacheService.instance.downloadBytes(url);
}
