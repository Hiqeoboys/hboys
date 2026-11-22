import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../features/chat/domain/group_chat_models.dart';
import '../supabase/supabase_services.dart';
import 'avatar_image_processor.dart';
import 'media_url_normalizer.dart';

typedef R2MediaPresignCall = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> body,
);
typedef R2MediaPutCall = Future<int> Function(
  Uri url,
  Map<String, String> headers,
  Uint8List bytes,
);
typedef VideoDurationReader = Future<Duration?> Function(File file);

/// Layanan unggahan media ke Cloudflare R2 lewat Edge Function `r2-presign`.
///
/// Aturan keamanan:
/// - Tidak ada kredensial R2 di kode Flutter; semua izin PUT berumur 60 detik
///   diterbitkan oleh Edge Function `r2-presign` setelah memverifikasi JWT.
/// - Foto profil akun selalu menimpa `avatars/{user_id}.webp` + `?v=timestamp`.
/// - Foto profil komunitas selalu menimpa `community-avatars/{community_id}.webp`.
/// - Media obrolan komunitas (foto WebP / video maks. 60 detik) disimpan di
///   `community-media/{community_id}/{timestamp}_{uuid}.{ext}`.
class R2MediaService {
  R2MediaService({
    R2MediaPresignCall? presign,
    R2MediaPutCall? put,
    VideoDurationReader? videoDurationReader,
    int Function()? nowMs,
  })  : _presign = presign ?? _invokeR2Presign,
        _put = put ?? _httpPut,
        _videoDurationReader = videoDurationReader ?? _probeVideoDuration,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  static final R2MediaService instance = R2MediaService();

  static const int maxAvatarBytes = 512 * 1024;
  static const int maxCommunityImageBytes = 5 * 1024 * 1024;
  static const int maxCommunityVideoBytes = 40 * 1024 * 1024;
  static const int maxVideoDurationSec = 60;

  final R2MediaPresignCall _presign;
  final R2MediaPutCall _put;
  final VideoDurationReader _videoDurationReader;
  final int Function() _nowMs;

  /// Menambahkan query `?v=timestamp` (atau memperbarui bila sudah ada) agar
  /// gambar avatar yang menimpa nama berkas tetap langsung segar di UI.
  static String withCacheBuster(String url, int timestampMs) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '$url?v=$timestampMs';
    final nextQuery = Map<String, String>.from(uri.queryParameters)
      ..['v'] = '$timestampMs';
    return uri.replace(queryParameters: nextQuery).toString();
  }

  /// Memotong 1:1 (maks. 512x512 px), kompresi ke WebP, lalu unggah ke R2
  /// pada `avatars/{userId}.webp` dengan `?v=timestamp`.
  Future<String> uploadAccountAvatar(
    Uint8List rawBytes, {
    required String userId,
  }) async {
    final webpBytes =
        await AvatarImageProcessor.cropSquareAndCompressWebp(rawBytes);
    return uploadPreparedAvatarWebp(webpBytes, userId: userId);
  }

  /// Mengunggah byte WebP foto profil akun yang sudah dipotong 1:1 <= 512 px
  /// ke `avatars/{userId}.webp` lalu mengembalikan `publicUrl?v=timestamp`.
  Future<String> uploadPreparedAvatarWebp(
    Uint8List webpBytes, {
    required String userId,
  }) async {
    if (userId.trim().isEmpty) {
      throw StateError('Pengguna belum masuk akun.');
    }
    if (webpBytes.isEmpty || webpBytes.length > maxAvatarBytes) {
      throw StateError('Ukuran foto profil terlalu besar (maks. 512 KB).');
    }
    final publicUrl = await uploadObject(
      objectKey: 'avatars/$userId.webp',
      contentType: 'image/webp',
      bytes: webpBytes,
    );
    return withCacheBuster(publicUrl, _nowMs());
  }

  /// Memotong 1:1 <= 512 px dan mengompresi foto menjadi WebP agar siap
  /// diunggah paralel bersamaan dengan penulisan metadata di Postgres.
  Future<Uint8List> prepareAvatarWebp(File file) async {
    final raw = await file.readAsBytes();
    try {
      return await AvatarImageProcessor.cropSquareAndCompressWebp(raw);
    } catch (_) {
      return _compressImageToWebp(
        file,
        quality: 80,
        minWidth: 512,
        minHeight: 512,
      );
    }
  }

  /// Mengunggah byte WebP foto profil komunitas yang sudah siap ke R2
  /// (`community-avatars/{communityId}.webp?v=timestamp`).
  Future<String> uploadPreparedCommunityAvatarWebp(
    Uint8List webpBytes, {
    required String communityId,
  }) async {
    final publicUrl = await uploadObject(
      objectKey: 'community-avatars/$communityId.webp',
      contentType: 'image/webp',
      bytes: webpBytes,
    );
    return withCacheBuster(publicUrl, _nowMs());
  }

  /// Memotong 1:1 <= 512 px WebP dan mengunggah foto profil komunitas ke
  /// `community-avatars/{communityId}.webp` dengan `?v=timestamp`.
  Future<String> uploadCommunityAvatar(
    File file, {
    required String communityId,
  }) async {
    final webpBytes = await prepareAvatarWebp(file);
    return uploadPreparedCommunityAvatarWebp(
      webpBytes,
      communityId: communityId,
    );
  }

  /// Mengunggah byte WebP foto profil grup yang sudah siap ke R2
  /// (`group-avatars/{groupId}.webp?v=timestamp`).
  Future<String> uploadPreparedGroupAvatarWebp(
    Uint8List webpBytes, {
    required String groupId,
  }) async {
    final publicUrl = await uploadObject(
      objectKey: 'group-avatars/$groupId.webp',
      contentType: 'image/webp',
      bytes: webpBytes,
    );
    return withCacheBuster(publicUrl, _nowMs());
  }

  /// Memotong 1:1 <= 512 px WebP dan mengunggah foto profil grup ke
  /// `group-avatars/{groupId}.webp` dengan `?v=timestamp`.
  Future<String> uploadGroupAvatar(
    File file, {
    required String groupId,
  }) async {
    final webpBytes = await prepareAvatarWebp(file);
    return uploadPreparedGroupAvatarWebp(
      webpBytes,
      groupId: groupId,
    );
  }

  /// Mengompresi gambar ke WebP lalu mengunggahnya ke
  /// `community-media/{communityId}/{timestamp}_{uuid}.{ext}`.
  Future<String> uploadCommunityImage(
    File file, {
    required String communityId,
  }) async {
    final webpBytes = await _compressImageToWebp(
      file,
      quality: 76,
      minWidth: 1280,
      minHeight: 1280,
    );
    if (webpBytes.isEmpty || webpBytes.length > maxCommunityImageBytes) {
      throw StateError('Ukuran gambar terlalu besar (maks. 5 MB).');
    }
    final detected = MediaUrlNormalizer.detectImageFormat(webpBytes);
    final ts = _nowMs();
    final key =
        'community-media/$communityId/${ts}_${generateUuidV4()}.${detected.ext}';
    return uploadObject(
      objectKey: key,
      contentType: detected.contentType,
      bytes: webpBytes,
    );
  }

  /// Mengunggah byte WebP (mis. thumbnail frame pertama video) ke
  /// `community-media/{communityId}/{timestamp}_{uuid}.webp` sesuai aturan r2-presign.
  Future<String> uploadCommunityImageBytes(
    Uint8List webpBytes, {
    required String communityId,
  }) async {
    if (webpBytes.isEmpty || webpBytes.length > maxCommunityImageBytes) {
      throw StateError('Ukuran gambar terlalu besar (maks. 5 MB).');
    }
    final ts = _nowMs();
    final key = 'community-media/$communityId/${ts}_${generateUuidV4()}.webp';
    return uploadObject(
      objectKey: key,
      contentType: 'image/webp',
      bytes: webpBytes,
    );
  }

  /// Memvalidasi durasi video (maks. 60 detik) dan ukuran berkas sebelum
  /// mengunggahnya ke `community-media/{communityId}/{timestamp}_{uuid}.{ext}`.
  // shortcut: uses camera ResolutionPreset.medium MP4/WebM without adding an
  // AGP-incompatible native video transcoder; add MediaCodec transcoding when a
  // compatible AGP 9 / Kotlin 2.4 plugin is available.
  Future<({String publicUrl, int durationSec, String contentType})>
      uploadCommunityVideo(
    File file, {
    required String communityId,
    int? durationSec,
  }) async {
    var resolvedDuration = durationSec ?? 0;
    if (resolvedDuration <= 0) {
      final probed = await _videoDurationReader(file);
      if (probed != null) {
        resolvedDuration = probed.inSeconds;
      }
    }
    if (resolvedDuration > maxVideoDurationSec) {
      throw StateError(
        'Durasi video maksimal $maxVideoDurationSec detik.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxCommunityVideoBytes) {
      throw StateError('Ukuran video terlalu besar (maks. 40 MB).');
    }

    final lowerExt = p.extension(file.path).toLowerCase();
    final String ext;
    final String contentType;
    if (lowerExt == '.webm') {
      ext = 'webm';
      contentType = 'video/webm';
    } else {
      ext = 'mp4';
      contentType = 'video/mp4';
    }

    final ts = _nowMs();
    final key = 'community-media/$communityId/${ts}_${generateUuidV4()}.$ext';
    final publicUrl = await uploadObject(
      objectKey: key,
      contentType: contentType,
      bytes: bytes,
    );
    return (
      publicUrl: publicUrl,
      durationSec: resolvedDuration.clamp(1, maxVideoDurationSec),
      contentType: contentType,
    );
  }

  /// Meminta Presigned PUT URL dari Edge Function `r2-presign` lalu mengunggah
  /// langsung ke Cloudflare R2 lewat `http.put`.
  Future<String> uploadObject({
    required String objectKey,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final grant = await _presign(<String, dynamic>{
      'objectKey': objectKey,
      'contentType': contentType,
      'size': bytes.length,
    });
    final uploadUrl = grant['uploadUrl']?.toString().trim();
    final rawPublicUrl = grant['publicUrl']?.toString().trim();
    if (uploadUrl == null ||
        uploadUrl.isEmpty ||
        rawPublicUrl == null ||
        rawPublicUrl.isEmpty) {
      if (kDebugMode) {
        debugPrint('R2MediaService.uploadObject: missing upload/public URL.');
      }
      throw StateError(
        'Izin unggah media ditolak. Periksa koneksi lalu coba lagi.',
      );
    }
    if (MediaUrlNormalizer.isPresignedOrPrivateR2Url(rawPublicUrl)) {
      throw StateError(
        'Konfigurasi URL publik R2 tidak valid (terdeteksi URL presigned/privat).',
      );
    }
    final publicUrl = MediaUrlNormalizer.normalize(rawPublicUrl);
    if (publicUrl == null || !publicUrl.startsWith('https://')) {
      throw StateError(
        'Konfigurasi URL publik R2 harus menggunakan HTTPS.',
      );
    }

    final headers = <String, String>{
      'Content-Type': contentType,
      for (final e in ((grant['headers'] as Map?) ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    };
    final status = await _put(Uri.parse(uploadUrl), headers, bytes);
    if (status < 200 || status >= 300) {
      if (kDebugMode) {
        debugPrint('R2MediaService.uploadObject: HTTP $status');
      }
      throw StateError(
          'Gagal mengunggah media. Periksa sinyal lalu coba lagi.');
    }
    return publicUrl;
  }

  static Future<Uint8List> _compressImageToWebp(
    File source, {
    int quality = 76,
    int minWidth = 1280,
    int minHeight = 1280,
  }) async {
    try {
      final result = await FlutterImageCompress.compressWithFile(
        source.absolute.path,
        format: CompressFormat.webp,
        quality: quality,
        minWidth: minWidth,
        minHeight: minHeight,
      );
      if (result != null && result.isNotEmpty) return result;
    } catch (_) {
      // Fallback bila plugin kompresi native tidak tersedia (mis. unit test).
    }
    return source.readAsBytes();
  }

  static Future<Duration?> _probeVideoDuration(File file) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(file);
      await controller.initialize();
      return controller.value.duration;
    } catch (_) {
      return null;
    } finally {
      await controller?.dispose();
    }
  }

  static Future<Map<String, dynamic>> _invokeR2Presign(
    Map<String, dynamic> body,
  ) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Masuk akun dan pastikan internet aktif.');
    }
    final res = await client.functions.invoke('r2-presign', body: body);
    final data = res.data;
    if (data is! Map) {
      if (kDebugMode) {
        debugPrint('R2MediaService._invokeR2Presign: invalid payload type.');
      }
      throw StateError(
        'Gagal menyiapkan unggahan media. Periksa koneksi lalu coba lagi.',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  static Future<int> _httpPut(
    Uri url,
    Map<String, String> headers,
    Uint8List bytes,
  ) async {
    final response = await http.put(url, headers: headers, body: bytes);
    return response.statusCode;
  }
}
