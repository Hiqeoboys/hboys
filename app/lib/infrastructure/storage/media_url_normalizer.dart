import 'dart:typed_data';

/// Normalisasi dan validasi URL media Cloudflare R2 serta deteksi format biner gambar.
abstract final class MediaUrlNormalizer {
  /// Menormalkan URL media:
  /// - Trim spasi.
  /// - Mengubah skema `http://` yang tidak sengaja tersimpan menjadi `https://`.
  /// - Menghapus garis miring ganda pada path (mis. `//community-media/...` -> `/community-media/...`).
  static String? normalize(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    var candidate = trimmed;
    if (candidate.toLowerCase().startsWith('http://')) {
      candidate = 'https://${candidate.substring(7)}';
    }

    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return candidate;
    }

    final cleanPath = uri.path.replaceAll(RegExp(r'/+'), '/');
    return uri.replace(path: cleanPath).toString();
  }

  /// Mengembalikan `true` bila [raw] adalah URL jaringan HTTP/HTTPS.
  static bool isNetworkUrl(String? raw) {
    final trimmed = raw?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) return false;
    return trimmed.startsWith('https://') || trimmed.startsWith('http://');
  }

  /// Mengembalikan `true` bila URL adalah *presigned* S3/R2 (yang akan kedaluwarsa)
  /// atau menunjuk langsung ke endpoint S3 privat `*.r2.cloudflarestorage.com`.
  static bool isPresignedOrPrivateR2Url(String raw) {
    final lower = raw.trim().toLowerCase();
    return lower.contains('x-amz-signature=') ||
        lower.contains('x-amz-credential=') ||
        lower.contains('r2.cloudflarestorage.com');
  }

  /// Mengembalikan `true` bila [raw] mengarah ke objek R2 aplikasi (baik domain
  /// publik `*.r2.dev`, endpoint S3 `*.r2.cloudflarestorage.com`, atau custom
  /// domain dengan path `avatars/`, `community-avatars/`, `community-media/`).
  static bool isR2ManagedUrl(String? raw) {
    final normalized = normalize(raw);
    if (normalized == null) return false;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasAuthority) return false;
    final host = uri.host.toLowerCase();
    if (host.endsWith('.r2.dev') || host.endsWith('.r2.cloudflarestorage.com')) {
      return true;
    }
    return extractR2ObjectKey(normalized) != null;
  }

  /// Mengekstrak object key R2 yang aman dari URL publik (`pub-*.r2.dev`),
  /// URL custom domain, maupun URL S3 presigned lama (`*.r2.cloudflarestorage.com`).
  /// Mengembalikan `null` jika URL bukan objek media Hiqeo yang diizinkan.
  static String? extractR2ObjectKey(String? raw, {String? knownBucketName}) {
    final normalized = normalize(raw);
    if (normalized == null) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasAuthority) return null;

    var key = Uri.decodeComponent(uri.path)
        .trim()
        .replaceAll(RegExp(r'/+'), '/')
        .replaceFirst(RegExp(r'^/+'), '');
    if (key.isEmpty ||
        key.endsWith('/') ||
        key.contains('..') ||
        key.contains('\\') ||
        key.contains('\x00') ||
        key.contains('?') ||
        key.contains('#') ||
        RegExp(r'\s').hasMatch(key)) {
      return null;
    }

    final host = uri.host.toLowerCase();
    if (host.endsWith('.r2.cloudflarestorage.com')) {
      final cleanBucket = knownBucketName?.trim().replaceAll('/', '');
      if (cleanBucket != null &&
          cleanBucket.isNotEmpty &&
          key.startsWith('$cleanBucket/')) {
        key = key.substring(cleanBucket.length + 1);
      } else if (!_hasAllowedMediaPrefix(key)) {
        final slash = key.indexOf('/');
        if (slash > 0 && slash + 1 < key.length) {
          final afterBucket = key.substring(slash + 1);
          if (_hasAllowedMediaPrefix(afterBucket)) {
            key = afterBucket;
          }
        }
      }
    }

    return _hasAllowedMediaPrefix(key) ? key : null;
  }

  static bool _hasAllowedMediaPrefix(String key) {
    return key.startsWith('avatars/') ||
        key.startsWith('community-avatars/') ||
        key.startsWith('community-media/');
  }

  /// Mendeteksi format gambar (`image/webp`, `image/jpeg`, `image/png`) dari *magic bytes*.
  static ({String contentType, String ext}) detectImageFormat(Uint8List bytes) {
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return (contentType: 'image/webp', ext: 'webp');
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return (contentType: 'image/jpeg', ext: 'jpg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return (contentType: 'image/png', ext: 'png');
    }
    return (contentType: 'image/webp', ext: 'webp');
  }
}
