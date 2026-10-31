import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../domain/plus_entitlement.dart';
import '../domain/plus_repositories.dart';

/// Verifikasi token hak akses secara offline dengan kunci publik Ed25519.
///
/// Format token: `payloadB64url.tandaTanganB64url`. Yang ditandatangani adalah
/// byte ASCII dari segmen payload apa adanya, sehingga tidak ada risiko
/// perbedaan normalisasi JSON antara penerbit dan verifier.
class Ed25519EntitlementVerifier implements EntitlementVerifier {
  const Ed25519EntitlementVerifier({required this.publicKeyBase64Url});

  final String publicKeyBase64Url;

  static const String tokenSeparator = '.';

  @override
  Future<EntitlementPayload?> verify(String token) async {
    try {
      final parts = token.split(tokenSeparator);
      if (parts.length != 2) return null;
      final payloadSegment = parts[0];
      final signatureSegment = parts[1];
      if (payloadSegment.isEmpty || signatureSegment.isEmpty) return null;

      final signature = Signature(
        _decodeBase64Url(signatureSegment),
        publicKey: SimplePublicKey(
          _decodeBase64Url(publicKeyBase64Url),
          type: KeyPairType.ed25519,
        ),
      );
      final valid = await Ed25519().verify(
        utf8.encode(payloadSegment),
        signature: signature,
      );
      if (!valid) return null;

      final decoded = jsonDecode(
        utf8.decode(_decodeBase64Url(payloadSegment)),
      );
      return EntitlementPayload.tryParse(decoded);
    } on Object {
      // Token rusak, kunci kosong, atau JSON tidak valid semuanya berarti
      // "tidak berhak"; jangan pernah menjatuhkan aplikasi karena token.
      return null;
    }
  }

  static List<int> _decodeBase64Url(String value) =>
      base64Url.decode(base64Url.normalize(value));
}

/// Verifier yang selalu menolak. Dipakai build rilis yang belum menyertakan
/// kunci publik produksi, sehingga tidak ada token yang dapat lolos.
class RejectingEntitlementVerifier implements EntitlementVerifier {
  const RejectingEntitlementVerifier();

  @override
  Future<EntitlementPayload?> verify(String token) async => null;
}
