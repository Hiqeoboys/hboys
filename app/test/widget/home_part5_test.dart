import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/groups/application/group_key_manager.dart';
import 'package:nama_app/features/groups/application/group_selection.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/home/beranda_page.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/preparation/presentation/siap_naik_page.dart';
import 'package:nama_app/features/safety/application/sos_action_service.dart';
import 'package:nama_app/features/safety/application/sos_location.dart';
import 'package:nama_app/features/safety/domain/sos_category.dart';
import 'package:nama_app/features/safety/presentation/first_aid_guide_page.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

class _EmptyTrackingRepo implements TrackingRepository {
  @override
  Stream<List<TrackingSession>> watchSessions() =>
      Stream<List<TrackingSession>>.value(const <TrackingSession>[]);

  @override
  Future<List<TrackPoint>> points(String sessionId) async =>
      const <TrackPoint>[];

  @override
  Future<TrackingSession?> findSession(String id) async => null;

  @override
  Future<TrackingSession?> findActiveSession() async => null;

  @override
  Future<void> saveSession(TrackingSession session) async {}

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<void> addPoint(String sessionId, TrackPoint point) async {}

  @override
  Future<void> clearPoints(String sessionId) async {}

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async => null;
}

class _StubAccount extends AccountController {
  _StubAccount({
    required this.stubProfile,
    required List<RemoteGroup> groups,
    Map<String, GroupKeyStatus> keyStatuses = const <String, GroupKeyStatus>{},
  })  : _groups = groups,
        _keyStatuses = keyStatuses,
        super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'user-a'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  final UserProfile stubProfile;
  final List<RemoteGroup> _groups;
  final Map<String, GroupKeyStatus> _keyStatuses;

  @override
  UserProfile? get profile => stubProfile;

  @override
  List<RemoteGroup> get groups => _groups;

  @override
  GroupKeyStatus? keyStatusFor(String groupId) => _keyStatuses[groupId];

  @override
  void initialize() {}
}

RemoteGroup _remoteGroup({
  required String id,
  required String name,
  String? mountain,
}) =>
    RemoteGroup(
      group: Group(
        id: id,
        name: name,
        ownerId: 'user-a',
        mountain: mountain,
        createdAtUtc: DateTime.utc(2026, 5, 1),
      ),
      role: GroupRole.owner,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackingListStore.setInstanceForTesting(PackingListStore());
    await PackingListStore.instance.load();
  });

  tearDown(() {
    PackingListStore.setInstanceForTesting(null);
  });

  group('Part 5.1 — Kartu PENDAKIAN BERIKUTNYA Beranda', () {
    testWidgets(
      'menampilkan status netral kosong meski pengguna punya grup dengan Gunung Ciremai & kunci v2 siap',
      (tester) async {
        final planStore = GroupHikePlanStore();
        final account = _StubAccount(
          stubProfile: const UserProfile(
            userId: 'user-a',
            username: 'pendaki_a',
            fullName: 'Raka',
            publicKeyBase64: 'kunci',
          ),
          groups: <RemoteGroup>[
            _remoteGroup(
              id: 'g-ciremai',
              name: 'Tim Ciremai',
              mountain: 'Gunung Ciremai',
            ),
          ],
          keyStatuses: <String, GroupKeyStatus>{
            'g-ciremai': const GroupKeyStatus(
              keyVersion: 2,
              memberCount: 2,
              availability: GroupKeyAvailability.ready,
            ),
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: Scaffold(
              body: BerandaPage(
                accountController: account,
                repository: _EmptyTrackingRepo(),
                groupHikePlanStore: planStore,
                now: () => DateTime(2026, 5, 1, 8),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Belum ada pendakian'), findsOneWidget);
        expect(
          find.text('Pilih gunung dan atur persiapan sebelum berangkat'),
          findsOneWidget,
        );
        expect(find.text('Gunung Ciremai'), findsNothing);
        expect(find.textContaining('kunci v2 siap'), findsNothing);

        // Jika baru ketua yang siap (1/3), Beranda belum menampilkan gunung grup
        await planStore.setPlan(
          const GroupHikePlan(
            inviteId: 'inv-1',
            groupId: 'g-ciremai',
            groupName: 'Tim Ciremai',
            mountainId: 'ciremai',
            mountainName: 'Gunung Ciremai',
            organizerUserId: 'user-a',
            organizerName: 'Raka',
            readyUserIds: <String>{'user-a'},
            memberCount: 3,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Belum ada pendakian'), findsOneWidget);

        // Begitu anggota lain menekan Siap, Beranda langsung menampilkan gunung & grup
        await planStore.markUserReady('inv-1', 'user-b');
        await tester.pumpAndSettle();
        expect(find.text('Gunung Ciremai'), findsOneWidget);
        expect(
          find.text('2 dari 3 anggota siap · Tim Ciremai'),
          findsOneWidget,
        );

        // Selesai pendakian mereset Beranda kembali ke status netral
        await planStore.completeAndResetAfterHike();
        await tester.pumpAndSettle();
        expect(find.text('Belum ada pendakian'), findsOneWidget);

        // Rencana pendakian solo tampil dengan keterangan Pendakian solo
        await planStore.setSoloPlan(
          const SoloHikePlan(
            mountainId: 'semeru',
            mountainName: 'Gunung Semeru',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Gunung Semeru'), findsOneWidget);
        expect(find.text('Pendakian solo'), findsOneWidget);
      },
    );
  });

  group('Part 5.2 & 5.3 — Sinkron grup, Reset Packing List, Kunci Ketat & Liquid Glass', () {
    testWidgets(
      'SiapNaikPage sinkron dengan grup terhapus/baru, mengunci tombol Mulai pendakian, mendukung Batalkan ajakan grup, dan memakai Liquid Glass Stack',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final planStore = GroupHikePlanStore();
        final groupsStore = SocialGroupsStore();
        final g1 = _remoteGroup(id: 'g-1', name: 'Tim Merbabu');
        final g2 = _remoteGroup(id: 'g-2', name: 'Tim Lama Terhapus');
        await groupsStore.markGroupDeleted('g-2');

        final account = _StubAccount(
          stubProfile: const UserProfile(
            userId: 'user-a',
            username: 'pendaki_a',
            fullName: 'Raka',
            publicKeyBase64: 'kunci',
          ),
          groups: <RemoteGroup>[g1, g2],
        );

        // Set rencana grup 2/3 siap -> tombol Mulai pendakian HARUS tetap terkunci!
        await planStore.setPlan(
          const GroupHikePlan(
            inviteId: 'inv-merbabu',
            groupId: 'g-1',
            groupName: 'Tim Merbabu',
            mountainId: 'merbabu',
            mountainName: 'Gunung Merbabu',
            organizerUserId: 'user-a',
            organizerName: 'Raka',
            readyUserIds: <String>{'user-a', 'user-b'},
            memberCount: 3,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: SiapNaikPage(
              accountController: account,
              groupHikePlanStore: planStore,
              socialGroupsStore: groupsStore,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Liquid Glass header & tombol Mulai pendakian mengambang dalam Stack
        expect(
          find.byKey(const ValueKey<String>('siap-naik-glass-header')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('siap-naik-mulai-glass')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('siap-naik-mulai-glass')),
            matching: find.byType(BackdropFilter),
          ),
          findsOneWidget,
        );

        // Terkunci karena baru 2/3 anggota yang siap
        expect(
          find.byKey(const ValueKey<String>('siap-naik-lock-banner')),
          findsOneWidget,
        );
        final lockedInk = tester.widget<InkWell>(
          find.byKey(const ValueKey('siap-naik-mulai')),
        );
        expect(lockedInk.onTap, isNull);

        // Tekan "Batalkan ajakan grup" -> rencana grup hilang, tombol tidak terkunci lagi,
        // dan hanya grup aktif (g-1) yang muncul sementara grup terhapus (g-2) hilang
        final cancelBtn = find.byKey(
          const ValueKey<String>('siap-naik-cancel-group-invite'),
        );
        await tester.drag(find.byType(ListView).first, const Offset(0, -240));
        await tester.pumpAndSettle();
        await tester.tap(cancelBtn);
        await tester.pumpAndSettle();

        expect(planStore.activePlan, isNull);
        expect(
          find.byKey(const ValueKey<String>('siap-naik-lock-banner')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('siap-naik-group-g-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('siap-naik-group-g-2')), findsNothing);

        final unlockedInk = tester.widget<InkWell>(
          find.byKey(const ValueKey('siap-naik-mulai')),
        );
        expect(unlockedInk.onTap, isNotNull);
      },
    );

    test('PackingListStore reset otomatis mengembalikan ke Tahap 1 bersih', () async {
      final store = PackingListStore.instance;
      await store.toggleSelectItem('carrier');
      await store.finishStage1();
      await store.togglePackedItem('carrier');
      expect(store.stage1Done, isTrue);
      expect(store.packedIds, contains('carrier'));

      await store.clearAll();
      expect(store.stage1Done, isFalse);
      expect(store.selectedIds, isEmpty);
      expect(store.packedIds, isEmpty);
    });
  });

  group('Part 5.4 — SOS Morse & format pesan darurat', () {
    test('pola Morse SOS tepat 3 pendek, 3 panjang, 3 pendek & format pesan lengkap', () {
      final onSteps = kSosMorsePattern.where((s) => s.on).toList();
      expect(onSteps, hasLength(9));
      expect(
        onSteps.map((s) => s.duration.inMilliseconds).toList(),
        <int>[200, 200, 200, 600, 600, 600, 200, 200, 200],
      );

      final msg = formatSosEmergencyMessage(
        senderName: 'Raka',
        fix: const SosFix(
          lat: -7.45512,
          lon: 110.44018,
          accuracyM: 6,
          altitudeM: 3145,
        ),
        mountainName: 'Gunung Merbabu',
        batteryPercent: 42,
        category: SosCategory.injury,
      );
      expect(msg, contains('DARURAT SOS HIQEO'));
      expect(msg, contains('Raka'));
      expect(msg, contains('Gunung Merbabu'));
      expect(msg, contains('-7.45512, 110.44018'));
      expect(msg, contains('3145 mdpl'));
      expect(msg, contains('42%'));
      expect(msg, contains('Cedera'));

      final smsUri = buildEmergencySmsUri(<String>['+628123456789'], msg);
      expect(smsUri.scheme, 'sms');
      expect(smsUri.path, '+628123456789');
      expect(smsUri.queryParameters['body'], msg);
    });
  });

  group('Part 5.5 — Panduan Keselamatan & P3K tombol SOS tunggal', () {
    testWidgets('hanya menampilkan 1 tombol SOS tanpa ikon duplikat', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: const FirstAidGuidePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('p3k-sos-button')),
        findsOneWidget,
      );
      expect(find.text('SOS'), findsOneWidget);
      expect(find.byIcon(Icons.sos_rounded), findsNothing);
    });
  });
}
