import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../supabase/supabase_services.dart';
import 'media_url_normalizer.dart';

/// Jenis unggahan yang diizinkan Edge Function `r2-presign`.
enum R2Kind {
  avatar('avatar'),
  communityAvatar('community-avatar'),
  communityMedia('community-media');

  const R2Kind(this.wire);
  final String wire;
}

typedef R2PresignCall = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> body,
);
typedef R2PutCall = Future<int> Function(
  Uri url,
  Map<String, String> headers,
  Uint8List bytes,
);

/// Pembungkus ringan kompatibel untuk unggahan ke Cloudflare R2 lewat URL PUT
/// bertanda tangan dari Edge Function `r2-presign`.
class R2Uploader {
  R2Uploader({R2PresignCall? presign, R2PutCall? put})
      : _presign = presign ?? _supabasePresign,
        _put = put ?? _httpPut;

  static final R2Uploader instance = R2Uploader();

  final R2PresignCall _presign;
  final R2PutCall _put;

  /// Mengembalikan URL publik berkas. [communityId] wajib untuk jenis komunitas.
  Future<String> upload({
    required R2Kind kind,
    required Uint8List bytes,
    required String contentType,
    String? communityId,
  }) async {
    final grant = await _presign(<String, dynamic>{
      'kind': kind.wire,
      'contentType': contentType,
      'size': bytes.length,
      if (communityId != null) 'communityId': communityId,
    });
    final uploadUrl = grant['uploadUrl'] as String?;
    final rawPublicUrl = grant['publicUrl'] as String?;
    if (uploadUrl == null || rawPublicUrl == null) {
      throw StateError('Izin unggah media ditolak.');
    }
    if (MediaUrlNormalizer.isPresignedOrPrivateR2Url(rawPublicUrl)) {
      throw StateError('URL publik R2 tidak boleh memakai URL presigned.');
    }
    final publicUrl = MediaUrlNormalizer.normalize(rawPublicUrl);
    if (publicUrl == null || !publicUrl.startsWith('https://')) {
      throw StateError('URL publik R2 tidak valid.');
    }
    final headers = <String, String>{
      for (final e in ((grant['headers'] as Map?) ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    };
    final status = await _put(Uri.parse(uploadUrl), headers, bytes);
    if (status < 200 || status >= 300) {
      throw StateError('Unggah media gagal (HTTP $status).');
    }
    return publicUrl;
  }

  static Future<Map<String, dynamic>> _supabasePresign(
    Map<String, dynamic> body,
  ) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Masuk akun dan pastikan internet aktif.');
    }
    final res = await client.functions.invoke('r2-presign', body: body);
    final data = res.data;
    if (data is! Map) throw StateError('Respons izin unggah tidak valid.');
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
