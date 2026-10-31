import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/plus/domain/plus_entitlement.dart';
import 'package:nama_app/features/plus/infrastructure/dev_entitlement_issuer.dart';
import 'package:nama_app/features/plus/infrastructure/entitlement_token.dart';

void main() {
  const verifier = Ed25519EntitlementVerifier(
    publicKeyBase64Url: DevelopmentPlusKeys.publicKeyBase64Url,
  );

  group('token Ed25519', () {
    test('token bertanda tangan diverifikasi tanpa jaringan', () async {
      final clock = FakeClock(DateTime.utc(2026, 10, 31, 9));
      final token = await DevEntitlementIssuer(clock: clock).issue(
        planId: 'annual',
        duration: const Duration(days: 365),
      );

      final payload = await verifier.verify(token);

      expect(payload, isNotNull);
      expect(payload!.planId, 'annual');
      expect(payload.subject, 'local-device');
      expect(payload.issuedAtUtc, DateTime.utc(2026, 10, 31, 9));
      expect(payload.expiresAtUtc, DateTime.utc(2027, 10, 31, 9));
    });

    test('token seumur hidup tidak memiliki tanggal kedaluwarsa', () async {
      final clock = FakeClock(DateTime.utc(2026, 10, 31, 9));
      final token = await DevEntitlementIssuer(clock: clock).issue(
        planId: 'founding',
        duration: null,
      );

      final payload = await verifier.verify(token);

      expect(payload, isNotNull);
      expect(payload!.isLifetime, isTrue);
    });

    test('payload yang diubah ditolak', () async {
      final clock = FakeClock(DateTime.utc(2026, 10, 31, 9));
      final token = await DevEntitlementIssuer(clock: clock).issue(
        planId: 'trip7d',
        duration: const Duration(days: 7),
      );
      final parts = token.split('.');
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
      ) as Map<String, Object?>;
      payload['plan'] = 'founding';
      final tamperedPayload = base64Url
          .encode(utf8.encode(jsonEncode(payload)))
          .replaceAll('=', '');

      final verified = await verifier.verify(
        '$tamperedPayload.${parts[1]}',
      );

      expect(verified, isNull);
    });

    test('tanda tangan yang diubah ditolak', () async {
      final clock = FakeClock(DateTime.utc(2026, 10, 31, 9));
      final token = await DevEntitlementIssuer(clock: clock).issue(
        planId: 'annual',
        duration: const Duration(days: 365),
      );
      final parts = token.split('.');
      final signature =
          base64Url.decode(base64Url.normalize(parts[1])).toList();
      signature[0] = signature[0] ^ 0xFF;

      final verified = await verifier.verify(
        '${parts[0]}.${base64Url.encode(signature).replaceAll('=', '')}',
      );

      expect(verified, isNull);
    });

    test('token rusak atau berformat salah ditolak tanpa melempar', () async {
      for (final token in <String>['', 'a', 'a.b', 'a.b.c', '.', 'YQ.Yg']) {
        expect(await verifier.verify(token), isNull, reason: token);
      }
    });

    test('verifier rilis tanpa kunci menolak semua token', () async {
      final clock = FakeClock(DateTime.utc(2026, 10, 31, 9));
      final token = await DevEntitlementIssuer(clock: clock).issue(
        planId: 'annual',
        duration: const Duration(days: 365),
      );

      final verified = await const RejectingEntitlementVerifier().verify(token);

      expect(verified, isNull);
    });
  });

  group('evaluasi akses', () {
    final issuedAt = DateTime.utc(2026, 1, 1);
    final expiresAt = DateTime.utc(2026, 2, 1);
    const graceDays = 10;

    EntitlementPayload payload({DateTime? expiresAtUtc}) => EntitlementPayload(
          version: EntitlementPayload.currentVersion,
          subject: 'local-device',
          planId: 'annual',
          issuedAtUtc: issuedAt,
          expiresAtUtc: expiresAtUtc,
        );

    PlusAccess evaluate(DateTime now, {bool lifetime = false}) =>
        evaluatePlusAccess(
          payload: payload(expiresAtUtc: lifetime ? null : expiresAt),
          nowUtc: now,
          graceDays: graceDays,
        );

    test('tanpa token berarti gratis', () {
      expect(
        evaluatePlusAccess(
          payload: null,
          nowUtc: issuedAt,
          graceDays: graceDays,
        ),
        PlusAccess.free,
      );
    });

    test('sebelum kedaluwarsa aktif', () {
      final access = evaluate(DateTime.utc(2026, 1, 15));

      expect(access.state, PlusAccessState.active);
      expect(access.hasPlus, isTrue);
      expect(access.planId, 'annual');
      expect(access.graceEndsAtUtc, DateTime.utc(2026, 2, 11));
    });

    test('tepat saat kedaluwarsa masuk masa tenggang', () {
      final access = evaluate(expiresAt);

      expect(access.state, PlusAccessState.grace);
      expect(access.hasPlus, isTrue);
      expect(access.isGrace, isTrue);
    });

    test('tenggang berakhir tepat setelah jumlah hari dari konfigurasi', () {
      final almost = evaluate(
        expiresAt.add(const Duration(days: 10)).subtract(
              const Duration(seconds: 1),
            ),
      );
      final ended = evaluate(expiresAt.add(const Duration(days: 10)));

      expect(almost.state, PlusAccessState.grace);
      expect(almost.hasPlus, isTrue);
      expect(ended.state, PlusAccessState.expired);
      expect(ended.hasPlus, isFalse);
    });

    test('token seumur hidup selalu aktif', () {
      final access = evaluate(
        DateTime.utc(2040, 1, 1),
        lifetime: true,
      );

      expect(access.state, PlusAccessState.active);
      expect(access.lifetime, isTrue);
      expect(access.expiresAtUtc, isNull);
      expect(access.hasPlus, isTrue);
    });
  });

  group('payload', () {
    test('versi tidak dikenal ditolak', () {
      expect(
        EntitlementPayload.tryParse(<String, Object?>{
          'v': 2,
          'sub': 'a',
          'plan': 'annual',
          'iat': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
    });

    test('tanggal kedaluwarsa sebelum terbit ditolak', () {
      expect(
        EntitlementPayload.tryParse(<String, Object?>{
          'v': 1,
          'sub': 'a',
          'plan': 'annual',
          'iat': '2026-02-01T00:00:00Z',
          'exp': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
    });

    test('isi wajib kosong ditolak', () {
      expect(
        EntitlementPayload.tryParse(<String, Object?>{
          'v': 1,
          'sub': '',
          'plan': 'annual',
          'iat': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
    });
  });
}
