import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/groups/application/group_key_manager.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/home/beranda_page.dart';
import 'package:nama_app/features/home/expandable_features_card.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';

import '../support/account_fakes.dart';
import '../support/real_font.dart';

const List<String> _featureTitles = <String>[
  'Pelacakan',
  'Peta offline',
  'Jalur terverifikasi',
  'Kompas',
  'Grup chat',
  'Lokasi terakhir',
  'Kartu pendakian',
  'SOS',
];

final DateTime _tripStartUtc = DateTime(2026, 10, 30, 7, 12).toUtc();

class _FakeTrackingRepository implements TrackingRepository {
  _FakeTrackingRepository({
    List<TrackingSession> sessions = const <TrackingSession>[],
    Map<String, List<TrackPoint>> points = const <String, List<TrackPoint>>{},
  })  : _sessions = sessions,
        _points = points;

  final List<TrackingSession> _sessions;
  final Map<String, List<TrackPoint>> _points;

  @override
  Stream<List<TrackingSession>> watchSessions() =>
      Stream<List<TrackingSession>>.value(_sessions);

  @override
  Future<List<TrackPoint>> points(String sessionId) async =>
      _points[sessionId] ?? const <TrackPoint>[];

  @override
  Future<TrackingSession?> findSession(String id) async {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  @override
  Future<TrackingSession?> findActiveSession() async => null;

  @override
  Future<void> saveSession(TrackingSession session) async {}

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<void> addPoint(String sessionId, TrackPoint point) async {}

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async => null;
}

class _FixedAccount extends AccountController {
  _FixedAccount({
    required this.fixedProfile,
    required List<RemoteGroup> groups,
    required Map<String, GroupKeyStatus> keyStatuses,
  })  : _groups = groups,
        _keyStatuses = keyStatuses,
        super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'user-1'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  final UserProfile fixedProfile;
  final List<RemoteGroup> _groups;
  final Map<String, GroupKeyStatus> _keyStatuses;

  @override
  UserProfile? get profile => fixedProfile;

  @override
  List<RemoteGroup> get groups => _groups;

  @override
  GroupKeyStatus? keyStatusFor(String groupId) => _keyStatuses[groupId];

  @override
  void initialize() {}
}

AccountController _guestAccount() {
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
  return AccountController(
    authService: FakeAuthService(isConfigured: false),
    profileRepository: FakeProfileRepository(),
    keyDirectory: FakeKeyDirectory(),
    identity: FakeIdentity(key),
  );
}

Group _group({
  required String id,
  required DateTime created,
  String? mountain,
}) =>
    Group(
      id: id,
      name: 'Rombongan $id',
      ownerId: 'user-1',
      createdAtUtc: created,
      mountain: mountain,
    );

TrackingSession _session({
  String id = 'sesi-1',
  TrackingSessionStatus status = TrackingSessionStatus.completed,
  DateTime? startedAtUtc,
  double distanceM = 12840,
  int movingSeconds = 25920,
  double elevationGainM = 1140,
  String? groupId,
}) {
  final start = startedAtUtc ?? _tripStartUtc;
  return TrackingSession(
    id: id,
    startedAtUtc: start,
    endedAtUtc: start.add(const Duration(hours: 8)),
    distanceM: distanceM,
    movingSeconds: movingSeconds,
    elevationGainM: elevationGainM,
    status: status,
    groupId: groupId,
  );
}

List<TrackPoint> _points() => <TrackPoint>[
      TrackPoint(
        lat: -6.800,
        lon: 106.800,
        timestampUtc: _tripStartUtc,
        accuracyM: 8,
        altitudeM: 1500,
      ),
      TrackPoint(
        lat: -6.799,
        lon: 106.800,
        timestampUtc: _tripStartUtc.add(const Duration(minutes: 30)),
        accuracyM: 8,
        altitudeM: 1900,
      ),
      TrackPoint(
        lat: -6.798,
        lon: 106.800,
        timestampUtc: _tripStartUtc.add(const Duration(minutes: 60)),
        accuracyM: 8,
        altitudeM: 1800,
      ),
      TrackPoint(
        lat: -6.797,
        lon: 106.800,
        timestampUtc: _tripStartUtc.add(const Duration(minutes: 90)),
        accuracyM: 8,
        altitudeM: 1700,
      ),
    ];

List<TrackingSession> _completedTrip() => <TrackingSession>[_session()];

Map<String, List<TrackPoint>> _tripPoints(List<TrackingSession> sessions) =>
    <String, List<TrackPoint>>{
      for (final session in sessions) session.id: _points(),
    };

GoRouter _router({
  required AccountController account,
  TrackingRepository? repository,
}) {
  Widget destination(String text) => Scaffold(body: Center(child: Text(text)));
  return GoRouter(
    initialLocation: '/beranda',
    routes: <RouteBase>[
      GoRoute(
        path: '/beranda',
        builder: (context, state) => BerandaPage(
          accountController: account,
          repository: repository ?? _FakeTrackingRepository(),
          now: () => DateTime(2026, 10, 30, 7),
        ),
      ),
      GoRoute(path: '/lacak', builder: (_, __) => destination('Tujuan Lacak')),
      GoRoute(path: '/peta', builder: (_, __) => destination('Tujuan Peta')),
      GoRoute(path: '/grup', builder: (_, __) => destination('Tujuan Grup')),
      GoRoute(
        path: '/siap-naik',
        builder: (_, __) => destination('Tujuan Siap Naik'),
      ),
      GoRoute(
        path: '/kartu',
        // Sesi yang diminta ditampilkan supaya uji bisa memeriksa parameternya;
        // RouteMatchList.uri sengaja tidak mencerminkan push imperatif.
        builder: (_, state) => destination(
          'Tujuan Kartu ${state.uri.queryParameters['sesi'] ?? 'tanpa sesi'}',
        ),
      ),
      GoRoute(path: '/sos', builder: (_, __) => destination('Tujuan SOS')),
    ],
  );
}

void _setTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Grid fitur mulai tertutup sesuai revisi, jadi tombolnya diketuk dulu.
Future<void> _openFeatures(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('semua-fitur-toggle')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tamu melihat sapaan dan keadaan kosong', (tester) async {
    _setTallPhone(tester);
    final account = _guestAccount();
    addTearDown(account.dispose);
    final router = _router(account: account);

    await tester.pumpWidget(
      MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selamat pagi'), findsOneWidget);
    expect(find.text('Halo, Pendaki'), findsOneWidget);
    expect(find.text('Belum ada pendakian'), findsOneWidget);
    expect(find.text('Semua fitur'), findsOneWidget);
    expect(find.text('Belum ada riwayat pendakian'), findsOneWidget);
    // Revisi Beranda: grid "Semua fitur" mulai tertutup, jadi judul kartu
    // belum ada di pohon sampai tombolnya diketuk.
    for (final title in _featureTitles) {
      expect(find.text(title), findsNothing, reason: 'kartu $title bocor');
    }

    await _openFeatures(tester);
    for (final title in _featureTitles) {
      expect(find.text(title), findsOneWidget, reason: 'kartu $title hilang');
    }
  });

  testWidgets('akun dengan grup menampilkan pendakian dan status kunci nyata',
      (tester) async {
    _setTallPhone(tester);
    final group = _group(
      id: 'g1',
      created: DateTime.utc(2026, 10, 20),
      mountain: 'Gunung Gede',
    );
    final account = _FixedAccount(
      fixedProfile: const UserProfile(
        userId: 'user-1',
        username: 'rani',
        publicKeyBase64: 'kunci',
      ),
      groups: <RemoteGroup>[
        RemoteGroup(group: group, role: GroupRole.owner),
      ],
      keyStatuses: <String, GroupKeyStatus>{
        'g1': const GroupKeyStatus(
          availability: GroupKeyAvailability.ready,
          keyVersion: 2,
          memberCount: 4,
        ),
      },
    );
    addTearDown(account.dispose);
    final router = _router(account: account);

    await tester.pumpWidget(
      MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.text('Halo, rani'), findsOneWidget);
    expect(find.text('Gunung Gede'), findsOneWidget);
    expect(find.text('4 anggota · kunci v2 siap'), findsOneWidget);
  });

  testWidgets('kartu membuka rute yang benar setelah grid dibuka',
      (tester) async {
    _setTallPhone(tester);
    final account = _guestAccount();
    addTearDown(account.dispose);
    final router = _router(account: account);

    await tester.pumpWidget(
      MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();
    await _openFeatures(tester);

    await tester.tap(find.text('Pelacakan'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/lacak',
    );

    router.go('/beranda');
    await tester.pumpAndSettle();
    await _openFeatures(tester);
    await tester.tap(find.text('SOS'));
    await tester.pumpAndSettle();
    expect(find.text('Tujuan SOS'), findsOneWidget);

    router.go('/beranda');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siapkan pendakian'));
    await tester.pumpAndSettle();
    expect(find.text('Tujuan Siap Naik'), findsOneWidget);
  });

  testWidgets('kartu fitur adalah tombol berlabel untuk pembaca layar',
      (tester) async {
    _setTallPhone(tester);
    final account = _guestAccount();
    addTearDown(account.dispose);
    final router = _router(account: account);
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();
    await _openFeatures(tester);

    final node = tester.getSemantics(
      find.bySemanticsLabel('SOS. Tekan-tahan 3 detik'),
    );
    expect(node.flagsCollection.isButton, isTrue);
    final card = tester.getSemantics(
      find.bySemanticsLabel('Kartu pendakian. Foto dan ringkasan'),
    );
    expect(card.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('ringkasan memakai sesi selesai terbaru dan membuka sesi itu',
      (tester) async {
    _setTallPhone(tester);
    final account = _guestAccount();
    addTearDown(account.dispose);
    final sessions = <TrackingSession>[
      _session(
        id: 'lama',
        distanceM: 5000,
        startedAtUtc: DateTime(2026, 10, 1, 7).toUtc(),
      ),
      _session(id: 'baru'),
      _session(
        id: 'aktif',
        status: TrackingSessionStatus.active,
        distanceM: 9999,
        startedAtUtc: DateTime(2026, 10, 31, 7).toUtc(),
      ),
    ];
    final router = _router(
      account: account,
      repository: _FakeTrackingRepository(
        sessions: sessions,
        points: _tripPoints(sessions),
      ),
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.text('PENDAKIAN TERAKHIR'), findsOneWidget);
    expect(find.text('Pendakian 30 Okt 2026'), findsOneWidget);
    expect(find.text('12,8 km'), findsOneWidget);
    expect(find.text('+1.140 m'), findsOneWidget);
    expect(find.text('5,0 km'), findsNothing);

    await tester.tap(find.text('Lihat kartu'));
    await tester.pumpAndSettle();

    expect(find.text('Tujuan Kartu baru'), findsOneWidget);
  });

  testWidgets('nama gunung ringkasan diambil dari grup sesi itu',
      (tester) async {
    _setTallPhone(tester);
    final group = _group(
      id: 'g1',
      created: DateTime.utc(2026, 10, 20),
      mountain: 'Gunung Gede',
    );
    final account = _FixedAccount(
      fixedProfile: const UserProfile(
        userId: 'user-1',
        username: 'rani',
        publicKeyBase64: 'kunci',
      ),
      groups: <RemoteGroup>[
        RemoteGroup(group: group, role: GroupRole.owner),
      ],
      keyStatuses: <String, GroupKeyStatus>{
        'g1': const GroupKeyStatus(
          availability: GroupKeyAvailability.ready,
          keyVersion: 2,
          memberCount: 4,
        ),
      },
    );
    addTearDown(account.dispose);
    final sessions = <TrackingSession>[_session(groupId: 'g1')];
    final router = _router(
      account: account,
      repository: _FakeTrackingRepository(
        sessions: sessions,
        points: _tripPoints(sessions),
      ),
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    // Sekali di kartu "Pendakian berikutnya", sekali di ringkasan terakhir.
    expect(find.text('Gunung Gede'), findsNWidgets(2));
    expect(find.textContaining('Pendakian '), findsNothing);
  });

  testWidgets('semua muat tanpa gulir di layar 844 px dengan navigasi',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    // Ukuran teks harus dari huruf asli supaya syarat "muat 844 px" bermakna.
    await loadPlusJakartaSans(tester);

    final account = _guestAccount();
    addTearDown(account.dispose);
    final sessions = _completedTrip();
    final router = _router(
      account: account,
      repository: _FakeTrackingRepository(
        sessions: sessions,
        points: _tripPoints(sessions),
      ),
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: hiqeoLightTheme,
        routerConfig: router,
        builder: (context, child) => Scaffold(
          body: child,
          // Tinggi navigasi bawah yang dipakai shell saat ini: 64 + 16.
          bottomNavigationBar: const SizedBox(height: 80),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PENDAKIAN TERAKHIR'), findsOneWidget);
    expect(find.text('Semua fitur'), findsOneWidget);
    expect(find.byType(ExpandableFeaturesCard), findsOneWidget);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(
      position.maxScrollExtent,
      0,
      reason: 'kartu tertutup harus muat tanpa gulir di 844 px',
    );
  });
}
