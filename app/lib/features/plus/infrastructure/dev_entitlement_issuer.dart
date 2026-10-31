import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/utils/clock.dart';

/// Kunci pengembangan untuk menerbitkan token Plus saat backend dan toko
/// pembelian belum ada.
///
/// Kunci ini BUKAN rahasia produksi dan tidak boleh dipakai untuk hak akses
/// nyata. Build rilis hanya memverifikasi kunci dari `--dart-define` dan
/// menolak semua token bila kunci itu tidak diisi. Perlu tinjauan ahli
/// keamanan sebelum penerbitan token sungguhan.
abstract final class DevelopmentPlusKeys {
  static const String seedBase64Url =
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
  static const String publicKeyBase64Url =
      'A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';
}

/// Penerbit token debug. Hanya dipanggil dari [DebugPlusBillingRepository]
/// yang aktif di mode debug.
class DevEntitlementIssuer {
  const DevEntitlementIssuer(
      {required this.clock, this.subject = 'local-device'});

  final Clock clock;
  final String subject;

  Future<String> issue({
    required String planId,
    required Duration? duration,
  }) async {
    final issuedAt = clock.nowUtc();
    final payload = <String, Object?>{
      'v': 1,
      'sub': subject,
      'plan': planId,
      'iat': issuedAt.toIso8601String(),
      'exp': duration == null ? null : issuedAt.add(duration).toIso8601String(),
    };
    final payloadSegment = _encodeBase64Url(
      utf8.encode(jsonEncode(payload)),
    );
    final keyPair = await Ed25519().newKeyPairFromSeed(
      _decodeBase64Url(DevelopmentPlusKeys.seedBase64Url),
    );
    final signature = await Ed25519().sign(
      utf8.encode(payloadSegment),
      keyPair: keyPair,
    );
    return '$payloadSegment.${_encodeBase64Url(signature.bytes)}';
  }

  static String _encodeBase64Url(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static List<int> _decodeBase64Url(String value) =>
      base64Url.decode(base64Url.normalize(value));
}
