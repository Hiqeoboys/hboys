import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/plus/domain/plus_plan.dart';
import 'package:nama_app/features/plus/domain/plus_remote_config.dart';
import 'package:nama_app/features/plus/infrastructure/local_plus_stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fetchedAt = DateTime.utc(2026, 10, 31, 11);
  PlusRemoteConfig config() => PlusRemoteConfig(
        plans: const <PlusPlan>[
          PlusPlan(
            id: 'annual',
            title: 'Hiqeo Plus Tahunan',
            priceLabel: 'Rp 249.000',
            periodLabel: 'per tahun',
            durationDays: 365,
          ),
        ],
        graceDays: 10,
        flags: const PlusFeatureFlags(leaderboard: true),
        fetchedAtUtc: fetchedAt,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SharedPreferencesPlusConfigStore', () {
    test('menyimpan dan membaca ulang konfigurasi', () async {
      const store = SharedPreferencesPlusConfigStore();

      await store.write(config());
      final read = await store.read();

      expect(read, isNotNull);
      expect(read!.plans.single.id, 'annual');
      expect(read.effectiveGraceDays, 10);
      expect(read.flags.leaderboard, isTrue);
      expect(read.flags.peakBadges, isFalse);
      expect(read.fetchedAtUtc, fetchedAt);
    });

    test('cache rusak diabaikan tanpa melempar', () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        SharedPreferencesPlusConfigStore.key,
        '{bukan json',
      );

      expect(await const SharedPreferencesPlusConfigStore().read(), isNull);
    });

    test('cache berisi JSON non-objek diabaikan', () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        SharedPreferencesPlusConfigStore.key,
        jsonEncode(<String>['bukan', 'objek']),
      );

      expect(await const SharedPreferencesPlusConfigStore().read(), isNull);
    });
  });

  group('SharedPreferencesEntitlementLocalStore', () {
    test('token dan checkpoint tersimpan terpisah', () async {
      const store = SharedPreferencesEntitlementLocalStore();
      final checkpoint = DateTime.utc(2026, 11, 1, 8, 30);

      await store.writeToken('header.signature');
      await store.writeLastSeenUtc(checkpoint);

      expect(await store.readToken(), 'header.signature');
      expect(await store.readLastSeenUtc(), checkpoint);

      await store.clearToken();
      expect(await store.readToken(), isNull);
      expect(await store.readLastSeenUtc(), checkpoint);
    });

    test('checkpoint rusak diabaikan', () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        SharedPreferencesEntitlementLocalStore.lastSeenKey,
        'kemarin',
      );

      expect(
        await const SharedPreferencesEntitlementLocalStore().readLastSeenUtc(),
        isNull,
      );
    });
  });
}
