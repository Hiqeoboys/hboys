import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/plus/domain/plus_plan.dart';
import 'package:nama_app/features/plus/domain/plus_remote_config.dart';

void main() {
  final fetchedAt = DateTime.utc(2026, 10, 31, 10);

  Map<String, Object?> validJson() => <String, Object?>{
        'graceDays': 10,
        'flags': <String, Object?>{
          'leaderboard': true,
          'peakBadges': true,
        },
        'plans': <Object?>[
          <String, Object?>{
            'id': 'annual',
            'title': 'Hiqeo Plus Tahunan',
            'priceLabel': 'Rp 249.000',
            'periodLabel': 'per tahun',
            'note': 'Setara Rp 20.750 per bulan.',
            'durationDays': 365,
            'badge': 'Paling hemat',
          },
          <String, Object?>{
            'id': 'founding',
            'title': 'Founding Member',
            'priceLabel': 'Rp 499.000',
            'periodLabel': 'sekali bayar',
            'durationDays': null,
            'quotaRemaining': 87,
            'quotaTotal': 500,
          },
        ],
      };

  group('PlusRemoteConfig', () {
    test('membaca paket, kuota, dan feature flag', () {
      final config = PlusRemoteConfig.fromJson(
        validJson(),
        fetchedAtUtc: fetchedAt,
      );

      expect(config.plans, hasLength(2));
      final annual = config.plans.first;
      expect(annual.id, 'annual');
      expect(annual.priceLabel, 'Rp 249.000');
      expect(annual.durationDays, 365);
      expect(annual.badge, 'Paling hemat');
      expect(annual.isLifetime, isFalse);

      final founding = config.plans.last;
      expect(founding.isLifetime, isTrue);
      expect(founding.quotaRemaining, 87);
      expect(founding.quotaTotal, 500);
      expect(founding.hasQuota, isTrue);

      expect(config.flags.leaderboard, isTrue);
      expect(config.flags.peakBadges, isTrue);
      expect(config.fetchedAtUtc, fetchedAt);
      expect(config.effectiveGraceDays, 3);
    });

    test('saklar yang tidak dikirim dianggap mati', () {
      final config = PlusRemoteConfig.fromJson(
        <String, Object?>{'plans': <Object?>[]},
        fetchedAtUtc: fetchedAt,
      );

      expect(config.flags.leaderboard, isFalse);
      expect(config.flags.peakBadges, isFalse);
      expect(config.plans, isEmpty);
    });

    test('tenggang dikunci ke tepat 3 hari', () {
      final tooShort = PlusRemoteConfig.fromJson(
        <String, Object?>{'graceDays': 1},
        fetchedAtUtc: fetchedAt,
      );
      final tooLong = PlusRemoteConfig.fromJson(
        <String, Object?>{'graceDays': 45},
        fetchedAtUtc: fetchedAt,
      );

      expect(tooShort.effectiveGraceDays, 3);
      expect(tooLong.effectiveGraceDays, 3);
    });

    test('tenggang hilang memakai batas 3 hari, bukan nilai acak', () {
      final config = PlusRemoteConfig.fromJson(
        <String, Object?>{},
        fetchedAtUtc: fetchedAt,
      );

      expect(config.effectiveGraceDays, PlusRemoteConfig.fallbackGraceDays);
      expect(PlusRemoteConfig.fallbackGraceDays, 3);
    });

    test('paket tidak lengkap atau duplikat dilewati', () {
      final config = PlusRemoteConfig.fromJson(
        <String, Object?>{
          'plans': <Object?>[
            <String, Object?>{'id': 'rusak', 'title': 'Tanpa harga'},
            'bukan objek',
            <String, Object?>{
              'id': 'annual',
              'title': 'Tahunan',
              'priceLabel': 'Rp 1',
              'periodLabel': 'per tahun',
              'durationDays': 365,
            },
            <String, Object?>{
              'id': 'annual',
              'title': 'Duplikat',
              'priceLabel': 'Rp 2',
              'periodLabel': 'per tahun',
              'durationDays': 365,
            },
            <String, Object?>{
              'id': 'negatif',
              'title': 'Salah',
              'priceLabel': 'Rp 3',
              'periodLabel': 'per tahun',
              'durationDays': -1,
            },
          ],
        },
        fetchedAtUtc: fetchedAt,
      );

      expect(config.plans, hasLength(1));
      expect(config.plans.single.title, 'Tahunan');
    });

    test('kuota negatif membuat paket dilewati', () {
      final plan = PlusPlan.tryParse(<String, Object?>{
        'id': 'founding',
        'title': 'Founding Member',
        'priceLabel': 'Rp 499.000',
        'periodLabel': 'sekali bayar',
        'quotaRemaining': -1,
      });

      expect(plan, isNull);
    });

    test('bolak-balik JSON mempertahankan isi dan waktu cache', () {
      final original = PlusRemoteConfig.fromJson(
        validJson(),
        fetchedAtUtc: fetchedAt,
      );
      final restored = PlusRemoteConfig.fromJson(original.toJson());

      expect(restored.fetchedAtUtc, fetchedAt);
      expect(restored.effectiveGraceDays, original.effectiveGraceDays);
      expect(restored.flags.leaderboard, isTrue);
      expect(restored.plans.map((plan) => plan.id), <String>[
        'annual',
        'founding',
      ]);
      expect(restored.plans.last.quotaTotal, 500);
    });

    test('waktu cache yang tidak dikirim menjadi zaman Unix', () {
      final config = PlusRemoteConfig.fromJson(<String, Object?>{});

      expect(
        config.fetchedAtUtc,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });
  });
}
