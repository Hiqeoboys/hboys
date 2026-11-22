import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/auth/domain/username_policy.dart';

void main() {
  group('UsernamePolicy.normalizeForModeration', () {
    test('mengubah huruf besar ke kecil dan memetakan leetspeak 0,1,3,4,5,7,@,\$',
        () {
      expect(UsernamePolicy.normalizeForModeration('4DM1N'), 'admin');
      expect(UsernamePolicy.normalizeForModeration('h1q30'), 'hiqeo');
      expect(UsernamePolicy.normalizeForModeration('@57r0'), 'astro');
      expect(UsernamePolicy.normalizeForModeration(r'$upp0r7'), 'suport');
    });

    test('menghapus pemisah titik, garis bawah, spasi, strip dan menciutkan ulang',
        () {
      expect(UsernamePolicy.normalizeForModeration('a.d_m i-n'), 'admin');
      expect(UsernamePolicy.normalizeForModeration('aaaa.bbbb_cccc'), 'abc');
      expect(UsernamePolicy.normalizeForModeration('h111q333000'), 'hiqeo');
      expect(UsernamePolicy.normalizeForModeration('___...'), '');
    });
  });

  group('UsernamePolicy.validate', () {
    test('menerima format 3–20 huruf kecil, angka, titik, dan garis bawah', () {
      for (final ok in <String>[
        'raka',
        'raka_pratama',
        'raka.99',
        'abc',
        'a1234567890123456789',
        '@pendaki_merapi',
      ]) {
        final res = UsernamePolicy.validate(ok);
        expect(res.isValid, isTrue, reason: 'Harus valid: $ok');
        expect(res.errorMessage, isNull);
      }
    });

    test('menolak panjang <3 atau >20 karakter', () {
      expect(UsernamePolicy.validate('ab').isValid, isFalse);
      expect(UsernamePolicy.validate('ab').lengthOk, isFalse);

      final tooLong = 'a' * 21;
      expect(UsernamePolicy.validate(tooLong).isValid, isFalse);
      expect(UsernamePolicy.validate(tooLong).lengthOk, isFalse);
    });

    test('menolak karakter terlarang, tanda baca di tepi, dan dua titik (..)',
        () {
      expect(UsernamePolicy.validate('raka-jaya').charsOk, isFalse);
      expect(UsernamePolicy.validate('raka jaya').charsOk, isFalse);
      expect(UsernamePolicy.validate('.raka').edgesOk, isFalse);
      expect(UsernamePolicy.validate('raka.').edgesOk, isFalse);
      expect(UsernamePolicy.validate('_raka').edgesOk, isFalse);
      expect(UsernamePolicy.validate('raka_').edgesOk, isFalse);
      expect(UsernamePolicy.validate('ra..ka').noDoubleDot, isFalse);
    });

    test('menolak kata cadangan termasuk varian leetspeak dan pemisah', () {
      for (final reserved in <String>[
        'admin',
        'hiqeo',
        'basarnas',
        '4dm1n',
        'h.i.q.e.o',
        'm0d3r470r',
      ]) {
        final res = UsernamePolicy.validate(reserved);
        expect(res.isValid, isFalse, reason: 'Harus ditolak: $reserved');
        expect(res.isReserved, isTrue);
      }
    });
  });

  group('UsernamePolicy.cooldownDaysRemaining (jeda 7 hari)', () {
    final now = DateTime.utc(2026, 6, 15, 12, 0);

    test('0 hari bila belum pernah mengganti username', () {
      expect(
        UsernamePolicy.cooldownDaysRemaining(
          usernameChangedAtUtc: null,
          nowUtc: now,
          currentUsername: 'raka_pratama',
        ),
        0,
      );
    });

    test('menghitung sisa hari saat masih dalam jendela 7 hari', () {
      expect(
        UsernamePolicy.cooldownDaysRemaining(
          usernameChangedAtUtc: now.subtract(const Duration(hours: 1)),
          nowUtc: now,
          currentUsername: 'raka_pratama',
        ),
        7,
      );
      expect(
        UsernamePolicy.cooldownDaysRemaining(
          usernameChangedAtUtc: now.subtract(const Duration(days: 4, hours: 1)),
          nowUtc: now,
          currentUsername: 'raka_pratama',
        ),
        3,
      );
    });

    test('0 hari setelah melewati 7 hari penuh', () {
      expect(
        UsernamePolicy.cooldownDaysRemaining(
          usernameChangedAtUtc: now.subtract(const Duration(days: 7)),
          nowUtc: now,
          currentUsername: 'raka_pratama',
        ),
        0,
      );
    });

    test('jeda dilewati bila username lama belum mematuhi aturan', () {
      expect(
        UsernamePolicy.cooldownDaysRemaining(
          usernameChangedAtUtc: now.subtract(const Duration(days: 1)),
          nowUtc: now,
          currentUsername: 'ra..ka',
        ),
        0,
      );
      expect(
        UsernamePolicy.cooldownDaysRemaining(
          usernameChangedAtUtc: now.subtract(const Duration(days: 1)),
          nowUtc: now,
          currentUsername: 'ab',
        ),
        0,
      );
    });
  });

  group('UsernamePolicy.mapServerError', () {
    test('memetakan semua kode galat RPC set_username ke pesan netral', () {
      expect(
        UsernamePolicy.mapServerError('invalid_format').code,
        'invalid_format',
      );
      final blocked = UsernamePolicy.mapServerError('blocked');
      expect(blocked.code, 'blocked');
      expect(blocked.message, contains('tidak diperbolehkan'));

      final taken = UsernamePolicy.mapServerError('taken');
      expect(taken.code, 'taken');
      expect(taken.message, contains('sudah dipakai'));

      final cooldown = UsernamePolicy.mapServerError('cooldown:3');
      expect(cooldown.code, 'cooldown:3');
      expect(cooldown.cooldownDays, 3);
      expect(cooldown.message, 'Username baru bisa diganti lagi dalam 3 hari');
    });
  });
}
