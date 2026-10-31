import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/plus/domain/leaderboard.dart';
import 'package:nama_app/features/plus/infrastructure/debug_leaderboard.dart';
import 'package:nama_app/features/plus/infrastructure/local_plus_stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('label angka', () {
    test('jumlah gunung memakai satuan gunung', () {
      expect(leaderboardValueLabel(LeaderboardMetric.totalMountains, 9),
          '9 gunung');
      expect(leaderboardValueLabel(LeaderboardMetric.totalMountains, 0),
          '0 gunung');
    });

    test('jarak memakai kilometer dengan koma desimal', () {
      expect(leaderboardValueLabel(LeaderboardMetric.totalDistance, 128400),
          '128 km');
      expect(leaderboardValueLabel(LeaderboardMetric.totalDistance, 42500),
          '42,5 km');
      expect(leaderboardValueLabel(LeaderboardMetric.totalDistance, 21900),
          '21,9 km');
    });
  });

  group('LeaderboardEntry', () {
    test('inisial diambil dari huruf pertama nama', () {
      const entry = LeaderboardEntry(
        rank: 1,
        displayName: 'dimas',
        value: 3,
      );
      expect(entry.initial, 'D');
    });

    test('nama kosong memakai tanda tanya', () {
      const entry = LeaderboardEntry(rank: 1, displayName: '  ', value: 0);
      expect(entry.initial, '?');
    });
  });

  group('LeaderboardBoard', () {
    test('pemuncak dan kemajuan dihitung terhadap peringkat satu', () {
      const board = LeaderboardBoard(
        scope: LeaderboardScope.group,
        metric: LeaderboardMetric.totalMountains,
        period: LeaderboardPeriod.monthly,
        entries: <LeaderboardEntry>[
          LeaderboardEntry(rank: 1, displayName: 'Rani', value: 5),
          LeaderboardEntry(rank: 2, displayName: 'Dimas', value: 4),
        ],
      );

      expect(board.topValue, 5);
      expect(board.progressFor(board.entries.first), 1);
      expect(board.progressFor(board.entries.last), 0.8);
    });

    test('papan kosong bernilai nol tanpa pembagian nol', () {
      const board = LeaderboardBoard(
        scope: LeaderboardScope.national,
        metric: LeaderboardMetric.totalDistance,
        period: LeaderboardPeriod.weekly,
        entries: <LeaderboardEntry>[],
      );
      expect(board.topValue, 0);
      expect(
        board.progressFor(
          const LeaderboardEntry(rank: 1, displayName: 'A', value: 0),
        ),
        0,
      );
    });
  });

  group('papan demo national', () {
    test('bulanan total gunung berisi sepuluh besar dan baris sendiri',
        () async {
      final board = await const DebugLeaderboardRepository().load(
        scope: LeaderboardScope.national,
        metric: LeaderboardMetric.totalMountains,
        period: LeaderboardPeriod.monthly,
      );

      expect(board.entries, hasLength(10));
      expect(board.entries.first.displayName, 'Dimas A.');
      expect(board.entries.first.value, 9);
      expect(board.entries.first.rank, 1);
      expect(board.entries.last.displayName, 'Ayu L.');
      expect(board.entries.last.value, 3);
      expect(board.currentUser, isNotNull);
      expect(board.currentUser!.rank, 27);
      expect(board.currentUser!.displayName, 'Rani');
      expect(board.currentUser!.value, 2);
      expect(board.currentUser!.isCurrentUser, isTrue);
      expect(board.groupName, isNull);
    });

    test('nama pengguna sendiri bisa diganti', () async {
      final board = await const DebugLeaderboardRepository(
        currentUserName: 'Pendaki Uji',
      ).load(
        scope: LeaderboardScope.national,
        metric: LeaderboardMetric.totalMountains,
        period: LeaderboardPeriod.monthly,
      );
      expect(board.currentUser!.displayName, 'Pendaki Uji');
    });

    test('mingguan memperkecil angka gunung tanpa nol', () {
      final board = buildDemoLeaderboard(
        scope: LeaderboardScope.national,
        metric: LeaderboardMetric.totalMountains,
        period: LeaderboardPeriod.weekly,
      );
      expect(board.entries.first.value, 3);
      expect(board.entries.last.value, 1);
      expect(board.currentUser!.value, 1);
    });

    test('tahunan memperbesar angka gunung', () {
      final board = buildDemoLeaderboard(
        scope: LeaderboardScope.national,
        metric: LeaderboardMetric.totalMountains,
        period: LeaderboardPeriod.yearly,
      );
      expect(board.entries.first.value, 24);
      expect(board.currentUser!.value, 5);
    });

    test('jarak memakai meter dan diskalakan per periode', () {
      final monthly = buildDemoLeaderboard(
        scope: LeaderboardScope.national,
        metric: LeaderboardMetric.totalDistance,
        period: LeaderboardPeriod.monthly,
      );
      expect(monthly.entries.first.value, 128400);
      expect(monthly.currentUser!.value, 41200);

      final weekly = buildDemoLeaderboard(
        scope: LeaderboardScope.national,
        metric: LeaderboardMetric.totalDistance,
        period: LeaderboardPeriod.weekly,
      );
      expect(weekly.entries.first.value, 33384);
      expect(weekly.currentUser!.value, 10712);
    });
  });

  group('papan demo grup', () {
    test('semua anggota tampil dan pengguna sendiri di baris pertama', () {
      final board = buildDemoLeaderboard(
        scope: LeaderboardScope.group,
        metric: LeaderboardMetric.totalMountains,
        period: LeaderboardPeriod.monthly,
      );

      expect(board.groupName, 'Rombongan Sabtu');
      expect(board.groupMemberCount, 4);
      expect(board.entries, hasLength(4));
      expect(
        board.entries.map((entry) => entry.displayName),
        <String>['Rani', 'Dimas', 'Sari', 'Bayu'],
      );
      expect(board.entries.map((entry) => entry.rank), <int>[1, 2, 3, 4]);
      expect(board.entries.map((entry) => entry.isCurrentUser), <bool>[
        true,
        false,
        false,
        false,
      ]);
      expect(board.currentUser!.displayName, 'Rani');
      expect(board.progressFor(board.entries[1]), 0.8);
      expect(board.progressFor(board.entries[3]), 0.4);
    });

    test('jarak grup memakai meter dan nama sendiri mengikuti pengguna', () {
      final board = buildDemoLeaderboard(
        scope: LeaderboardScope.group,
        metric: LeaderboardMetric.totalDistance,
        period: LeaderboardPeriod.monthly,
        currentUserName: 'Pendaki Uji',
      );
      expect(board.entries.first.displayName, 'Pendaki Uji');
      expect(board.entries.first.value, 42500);
      expect(board.topValue, 42500);
      expect(board.progressFor(board.entries.last), closeTo(0.515, 0.001));
    });
  });

  group('repositori', () {
    test('demo yang dimatikan melempar pesan tidak tersedia', () async {
      expect(
        () => const DebugLeaderboardRepository(enabled: false).load(
          scope: LeaderboardScope.national,
          metric: LeaderboardMetric.totalMountains,
          period: LeaderboardPeriod.monthly,
        ),
        throwsA(isA<LeaderboardUnavailable>()),
      );
    });

    test('demo tidak mengirim laporan atau blokir ke mana pun', () async {
      const repository = DebugLeaderboardRepository();
      expect(await repository.report('Dimas A.'), isFalse);
      expect(await repository.block('Dimas A.'), isFalse);
    });

    test('repositori rilis selalu tidak tersedia', () async {
      const repository = UnavailableLeaderboardRepository();
      expect(
        repository.load(
          scope: LeaderboardScope.group,
          metric: LeaderboardMetric.totalMountains,
          period: LeaderboardPeriod.monthly,
        ),
        throwsA(
          isA<LeaderboardUnavailable>().having(
            (error) => error.message,
            'pesan',
            contains('belum tersedia'),
          ),
        ),
      );
      expect(
          () => repository.report('A'), throwsA(isA<LeaderboardUnavailable>()));
      expect(
          () => repository.block('A'), throwsA(isA<LeaderboardUnavailable>()));
    });
  });

  group('LeaderboardConsentStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('mulai kosong lalu menyimpan pilihan', () async {
      const store = SharedPreferencesLeaderboardConsentStore();

      expect(await store.readVisible(), isNull);

      await store.writeVisible(true);
      expect(await store.readVisible(), isTrue);

      await store.writeVisible(false);
      expect(await store.readVisible(), isFalse);
    });

    test('kunci penyimpanan bernama versi', () {
      expect(
        SharedPreferencesLeaderboardConsentStore.visibleKey,
        'leaderboard_consent_visible_v1',
      );
    });

    test('penyimpanan memori mencatat setiap penulisan', () async {
      final store = InMemoryLeaderboardConsentStore();
      expect(await store.readVisible(), isNull);

      await store.writeVisible(true);
      await store.writeVisible(false);

      expect(store.visible, isFalse);
      expect(store.writes, 2);
    });
  });
}
