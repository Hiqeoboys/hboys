import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/theme_mode_controller.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/profile/presentation/profil_page.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/infrastructure/power/power_profile_controller.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/account_fakes.dart';

final Uint8List _identityKey =
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

class _FixedBattery implements BatteryReader {
  const _FixedBattery(this.level);

  final int level;

  @override
  Future<int> levelPercent() async => level;

  @override
  Future<bool> isCharging() async => false;
}

class _FakeTrackingRepository implements TrackingRepository {
  _FakeTrackingRepository({this.sessions = const [], this.fail = false});

  List<TrackingSession> sessions;
  bool fail;

  @override
  Stream<List<TrackingSession>> watchSessions() => fail
      ? Stream<List<TrackingSession>>.error(StateError('gagal'))
      : Stream<List<TrackingSession>>.value(sessions);

  @override
  Future<void> saveSession(TrackingSession session) async {}

  @override
  Future<TrackingSession?> findSession(String id) async => null;

  @override
  Future<TrackingSession?> findActiveSession() async => null;

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<void> addPoint(String sessionId, TrackPoint point) async {}

  @override
  Future<List<TrackPoint>> points(String sessionId) async =>
      const <TrackPoint>[];

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async => null;
}

class _FakeSafetyRepository implements SafetyRepository {
  _FakeSafetyRepository({this.contacts = const [], this.failContacts = false});

  List<EmergencyContact> contacts;
  bool failContacts;

  @override
  Future<List<EmergencyContact>> contactsOf(String userId) async {
    if (failContacts) throw StateError('gagal');
    return contacts;
  }

  @override
  Future<void> saveContact(EmergencyContact contact) async {}

  @override
  Stream<List<EmergencyContact>> watchContacts(String userId) =>
      const Stream<List<EmergencyContact>>.empty();

  @override
  Future<void> deleteContact(String id) async {}

  @override
  Future<void> saveSosEvent(SosEvent event) async {}

  @override
  Future<SosEvent?> findSosEvent(String id) async => null;

  @override
  Future<List<SosEvent>> activeSosEvents() async => const <SosEvent>[];

  @override
  Stream<List<SosEvent>> watchSosEvents() =>
      const Stream<List<SosEvent>>.empty();

  @override
  Future<bool> cancelSosEvent(String id, DateTime nowUtc) async => false;
}

class _Harness {
  _Harness({
    required this.account,
    required this.auth,
    required this.power,
    required this.theme,
  });

  final AccountController account;
  final FakeAuthService auth;
  final PowerProfileController power;
  final ThemeModeController theme;
}

TrackingSession _completed({
  required String id,
  double distanceM = 0,
  double gainM = 0,
}) =>
    TrackingSession(
      id: id,
      startedAtUtc: DateTime.utc(2026, 9, 1),
      endedAtUtc: DateTime.utc(2026, 9, 2),
      distanceM: distanceM,
      elevationGainM: gainM,
      status: TrackingSessionStatus.completed,
    );

EmergencyContact _contact({
  String name = 'Budi',
  String phone = '+628123456789',
  EmergencyContactChannel channel = EmergencyContactChannel.whatsapp,
  EmergencyContactConsentStatus status = EmergencyContactConsentStatus.granted,
}) =>
    EmergencyContact(
      id: 'contact-1',
      userId: 'user-1',
      name: name,
      phoneE164: phone,
      channel: channel,
      consentStatus: status,
      createdAtUtc: DateTime.utc(2026, 9, 1),
    );

void _setTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool configured = true,
  bool signedIn = false,
  String? displayName,
  AuthProviderKind? provider,
  UserProfile? profile,
  List<TrackingSession> sessions = const <TrackingSession>[],
  bool failSessions = false,
  List<EmergencyContact> contacts = const <EmergencyContact>[],
  bool failContacts = false,
  int mapCount = 0,
  bool withRouter = false,
}) async {
  _setTallPhone(tester);
  final auth = FakeAuthService(
    isConfigured: configured,
    currentUser: signedIn
        ? AuthUser(id: 'user-1', displayName: displayName, provider: provider)
        : null,
  );
  final account = AccountController(
    authService: auth,
    profileRepository: FakeProfileRepository()..current = profile,
    keyDirectory: FakeKeyDirectory(),
    identity: FakeIdentity(_identityKey),
  );
  final power = PowerProfileController(
    reader: const _FixedBattery(25),
    manager: PowerProfileManager(),
  );
  await power.refresh();
  final theme = ThemeModeController(store: InMemoryThemeModeStore());

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    power.dispose();
    theme.dispose();
    await auth.close();
  });

  final page = ProfilPage(
    accountController: account,
    powerController: power,
    themeController: theme,
    trackingRepository: _FakeTrackingRepository(
      sessions: sessions,
      fail: failSessions,
    ),
    safetyRepository: _FakeSafetyRepository(
      contacts: contacts,
      failContacts: failContacts,
    ),
    downloadedMountainCount: () async => mapCount,
  );

  if (withRouter) {
    final router = GoRouter(
      initialLocation: '/profil',
      routes: <RouteBase>[
        GoRoute(path: '/profil', builder: (context, state) => page),
        GoRoute(
          path: '/peta',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Tujuan Peta')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: theme,
        builder: (context, child) => MaterialApp.router(
          theme: altracqLightTheme,
          darkTheme: altracqDarkTheme,
          themeMode: theme.mode,
          routerConfig: router,
        ),
      ),
    );
  } else {
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: theme,
        builder: (context, child) => MaterialApp(
          theme: altracqLightTheme,
          darkTheme: altracqDarkTheme,
          themeMode: theme.mode,
          home: page,
        ),
      ),
    );
  }
  await tester.pumpAndSettle();
  return _Harness(
    account: account,
    auth: auth,
    power: power,
    theme: theme,
  );
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

UserProfile _profile({String username = 'rani', String? keyBase64}) =>
    UserProfile(
      userId: 'user-1',
      username: username,
      publicKeyBase64: keyBase64 ?? base64Encode(_identityKey),
    );

void main() {
  testWidgets('tamu melihat ringkasan kosong, manfaat, dan tombol login',
      (tester) async {
    final harness = await _pump(
      tester,
      sessions: <TrackingSession>[
        _completed(id: 'selesai', distanceM: 31400, gainM: 1234),
        TrackingSession(
          id: 'aktif',
          startedAtUtc: DateTime.utc(2026, 10, 1),
          distanceM: 90000,
          status: TrackingSessionStatus.active,
        ),
      ],
      mapCount: 2,
    );

    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Pendaki tamu'), findsOneWidget);
    expect(find.text('Data pendakian tersimpan di HP ini'), findsOneWidget);
    expect(find.text('Masuk untuk membuka'), findsOneWidget);
    expect(find.text('Lanjutkan dengan Google'), findsOneWidget);
    expect(find.text('Lanjutkan dengan Apple'), findsOneWidget);
    expect(find.text('Grup dan undangan anggota'), findsOneWidget);
    expect(find.text('SOS diteruskan ke kontak darurat'), findsOneWidget);
    expect(find.text('Cadangan jejak pendakian'), findsOneWidget);
    expect(
      find.text('Penerusan SOS dan cadangan jejak belum tersedia di build ini.'),
      findsOneWidget,
    );
    expect(
      find.text('Isi pesanmu tidak dibaca server. Lokasi hanya tersimpan di HP '
          'ini.'),
      findsOneWidget,
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.text('31 km'), findsOneWidget);
    expect(find.text('1.234 m'), findsOneWidget);
    expect(find.text('Kontak darurat'), findsNothing);

    await _tapKey(tester, 'profil-login-google');
    expect(harness.auth.signInCalls, <AuthProviderKind>[
      AuthProviderKind.google,
    ]);
    expect(
      find.text(
        'Selesaikan login di browser. Aplikasi akan terbuka kembali otomatis.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('login dinonaktifkan dengan catatan jujur bila belum dikonfigurasi',
      (tester) async {
    final harness = await _pump(tester, configured: false);

    expect(
      find.text('Login Google/Apple belum aktif di build ini.'),
      findsOneWidget,
    );

    await _tapKey(tester, 'profil-login-google');
    await _tapKey(tester, 'profil-login-apple');
    expect(harness.auth.signInCalls, isEmpty);
  });

  testWidgets('sudah masuk menampilkan identitas, penyedia, statistik, dan baris',
      (tester) async {
    final harness = await _pump(
      tester,
      signedIn: true,
      displayName: 'Rani Puspita',
      provider: AuthProviderKind.google,
      profile: _profile(),
      sessions: <TrackingSession>[
        _completed(id: 'selesai', distanceM: 31400, gainM: 1234),
        TrackingSession(
          id: 'aktif',
          startedAtUtc: DateTime.utc(2026, 10, 1),
          distanceM: 90000,
          status: TrackingSessionStatus.active,
        ),
      ],
      contacts: <EmergencyContact>[_contact()],
      mapCount: 2,
    );

    expect(harness.account.user, isNotNull);
    expect(find.text('Rani Puspita'), findsOneWidget);
    expect(find.text('@rani'), findsOneWidget);
    expect(find.text('Terhubung dengan Google'), findsOneWidget);
    expect(find.text('Pendaki tamu'), findsNothing);
    expect(find.text('Masuk untuk membuka'), findsNothing);

    expect(find.text('1'), findsOneWidget);
    expect(find.text('31 km'), findsOneWidget);
    expect(find.text('1.234 m'), findsOneWidget);

    expect(find.text('Kontak darurat'), findsOneWidget);
    expect(find.text('Budi · aktif'), findsOneWidget);
    expect(find.text('Peta terunduh'), findsOneWidget);
    expect(find.text('2 gunung'), findsOneWidget);
    expect(find.text('Profil daya'), findsOneWidget);
    expect(find.text('Hemat'), findsOneWidget);
    expect(find.text('Privasi lokasi'), findsOneWidget);
    expect(find.text('Belum ada berbagi lokasi'), findsOneWidget);
    expect(find.text('Tampilan'), findsOneWidget);
    expect(find.text('Ikuti sistem'), findsOneWidget);
    expect(find.byKey(const ValueKey('profil-sign-out')), findsOneWidget);
    expect(find.text('Hapus akun'), findsOneWidget);
  });

  testWidgets('profil tanpa username menampilkan ajakan melengkapi akun',
      (tester) async {
    await _pump(tester, signedIn: true);

    expect(find.text('Pendaki'), findsOneWidget);
    expect(find.text('Username belum dibuat'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profil-complete-account')),
      findsOneWidget,
    );
    expect(find.text('Terhubung dengan Google'), findsNothing);
  });

  testWidgets('kunci perangkat yang berbeda memunculkan peringatan',
      (tester) async {
    await _pump(
      tester,
      signedIn: true,
      profile: _profile(keyBase64: base64Encode(Uint8List(32))),
    );

    expect(
      find.textContaining('Kunci perangkat berbeda dari direktori.'),
      findsOneWidget,
    );
    expect(find.text('Buka akun'), findsOneWidget);
  });

  testWidgets('statistik jujur saat data lokal gagal dibaca', (tester) async {
    await _pump(tester, signedIn: true, failSessions: true);

    expect(find.text('—'), findsNWidgets(3));
    expect(
      find.text('Data pendakian lokal belum dapat dibuka.'),
      findsOneWidget,
    );
  });

  testWidgets('baris Tampilan mengubah mode tanpa memulai ulang',
      (tester) async {
    final harness = await _pump(tester, signedIn: true, profile: _profile());

    await _tapKey(tester, 'profil-row-tampilan');
    expect(find.text('Ikuti sistem'), findsWidgets);
    expect(find.text('Terang'), findsWidgets);
    expect(find.text('Gelap'), findsWidgets);
    expect(
      find.text('Berlaku langsung tanpa memulai ulang aplikasi.'),
      findsOneWidget,
    );

    await _tapKey(tester, 'profil-theme-dark');
    expect(harness.theme.mode, ThemeMode.dark);
    expect(find.text('Gelap'), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.text('Profil'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('sheet kontak menampilkan kontak lokal dan catatan jujur',
      (tester) async {
    await _pump(
      tester,
      signedIn: true,
      profile: _profile(),
      contacts: <EmergencyContact>[_contact()],
    );

    await _tapKey(tester, 'profil-row-kontak');
    expect(find.text('Hanya tersimpan di HP ini'), findsOneWidget);
    expect(find.text('Budi'), findsOneWidget);
    expect(find.text('WhatsApp · +628123456789'), findsOneWidget);
    expect(find.text('aktif'), findsOneWidget);
    expect(
      find.text('Penerusan SOS ke kontak darurat belum tersedia di build ini.'),
      findsOneWidget,
    );
  });

  testWidgets('kontak gagal dibaca tidak diklaim kosong', (tester) async {
    await _pump(
      tester,
      signedIn: true,
      profile: _profile(),
      failContacts: true,
    );

    expect(find.text('Kontak belum dapat dibaca'), findsOneWidget);
    await _tapKey(tester, 'profil-row-kontak');
    expect(
      find.text('Kontak darurat belum dapat dibaca dari HP ini.'),
      findsOneWidget,
    );
  });

  testWidgets('sheet peta memakai jumlah nyata dan membuka layar peta',
      (tester) async {
    await _pump(
      tester,
      signedIn: true,
      profile: _profile(),
      mapCount: 3,
      withRouter: true,
    );

    await _tapKey(tester, 'profil-row-peta');
    expect(find.text('3 gunung'), findsWidgets);
    expect(
      find.textContaining('Status dibaca dari region peta yang benar-benar'),
      findsOneWidget,
    );
    await tester.tap(find.text('Buka Peta'));
    await tester.pumpAndSettle();
    expect(find.text('Tujuan Peta'), findsOneWidget);
  });

  testWidgets('sheet daya menampilkan baterai dan interval tiap profil',
      (tester) async {
    await _pump(tester, signedIn: true, profile: _profile());

    await _tapKey(tester, 'profil-row-daya');
    expect(find.text('Baterai 25%.'), findsOneWidget);
    expect(
      find.text('Normal: GPS tiap 5 detik, gambar aktif.'),
      findsOneWidget,
    );
    expect(
      find.text('Hemat: GPS tiap 15 detik, gambar nonaktif.'),
      findsOneWidget,
    );
    expect(
      find.text('Kritis: GPS tiap 60 detik, gambar nonaktif.'),
      findsOneWidget,
    );
  });

  testWidgets('sheet privasi tidak menjanjikan berbagi lokasi',
      (tester) async {
    await _pump(tester, signedIn: true, profile: _profile());

    await _tapKey(tester, 'profil-row-privasi');
    expect(
      find.textContaining('Belum ada transport yang mengirim lokasi'),
      findsOneWidget,
    );
    expect(
      find.text('Kontrol berbagi lokasi untuk anggota grup belum tersedia di '
          'build ini.'),
      findsOneWidget,
    );
  });

  testWidgets('hapus akun menjelaskan bahwa belum ada yang dihapus',
      (tester) async {
    await _pump(tester, signedIn: true, profile: _profile());

    await _tapKey(tester, 'profil-delete-account');
    expect(
      find.text('Penghapusan akun belum tersedia di build ini. Tidak ada akun '
          'atau data yang dihapus.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    expect(
      find.text('Penghapusan akun belum tersedia di build ini. Tidak ada akun '
          'atau data yang dihapus.'),
      findsNothing,
    );
  });

  testWidgets('keluar mengembalikan layar ke profil tamu', (tester) async {
    final harness = await _pump(
      tester,
      signedIn: true,
      profile: _profile(),
    );

    await _tapKey(tester, 'profil-sign-out');
    expect(harness.auth.signOutCalls, 1);
    expect(find.text('Pendaki tamu'), findsOneWidget);
    expect(find.text('Lanjutkan dengan Google'), findsOneWidget);
    expect(harness.account.user, isNull);
  });
}
