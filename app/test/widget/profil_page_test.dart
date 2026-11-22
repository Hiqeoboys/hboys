import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/core/platform/contact_picker.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/theme_mode_controller.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/plus/application/plus_controller.dart';
import 'package:nama_app/features/plus/application/plus_scope.dart';
import 'package:nama_app/features/profile/presentation/profil_page.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
import 'package:nama_app/features/safety/presentation/emergency_contacts_sheet.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/infrastructure/power/power_profile_controller.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/account_fakes.dart';
import '../support/plus_fixtures.dart';

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
  Future<void> clearPoints(String sessionId) async {}

  @override
  Future<List<TrackPoint>> points(String sessionId) async =>
      const <TrackPoint>[];

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async => null;
}

class _FakeSafetyRepository implements SafetyRepository {
  _FakeSafetyRepository({
    List<EmergencyContact> contacts = const <EmergencyContact>[],
    this.failContacts = false,
  }) : contacts = List<EmergencyContact>.of(contacts);

  final List<EmergencyContact> contacts;
  bool failContacts;

  @override
  Future<List<EmergencyContact>> contactsOf(String userId) async {
    if (failContacts) throw StateError('gagal');
    return List<EmergencyContact>.of(contacts);
  }

  @override
  Future<void> saveContact(EmergencyContact contact) async {
    contacts.removeWhere((c) => c.id == contact.id);
    contacts.add(contact);
  }

  @override
  Stream<List<EmergencyContact>> watchContacts(String userId) =>
      Stream<List<EmergencyContact>>.value(List<EmergencyContact>.of(contacts));

  @override
  Future<void> deleteContact(String id) async {
    contacts.removeWhere((c) => c.id == id);
  }

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

class _FakeContactPicker implements ContactPicker {
  _FakeContactPicker(this.result);

  ContactPickResult result;
  int calls = 0;

  @override
  Future<ContactPickResult> pickContact() async {
    calls++;
    return result;
  }
}

class _Harness {
  _Harness({
    required this.account,
    required this.auth,
    required this.power,
    required this.theme,
    required this.safety,
  });

  final AccountController account;
  final FakeAuthService auth;
  final PowerProfileController power;
  final ThemeModeController theme;
  final _FakeSafetyRepository safety;
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
  String id = 'contact-1',
  String name = 'Budi',
  String phone = '+6281234567890',
  EmergencyContactChannel channel = EmergencyContactChannel.whatsapp,
  EmergencyContactConsentStatus status = EmergencyContactConsentStatus.granted,
}) =>
    EmergencyContact(
      id: id,
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

Widget _withPlus(PlusController? plus, Widget child) =>
    plus == null ? child : PlusScope(controller: plus, child: child);

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
  PlusController? plus,
  ContactPicker? contactPicker,
}) async {
  _setTallPhone(tester);
  if (plus != null) addTearDown(plus.dispose);
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
  final safety = _FakeSafetyRepository(
    contacts: contacts,
    failContacts: failContacts,
  );

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
    safetyRepository: safety,
    downloadedMountainCount: () async => mapCount,
    contactPicker: contactPicker,
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
        GoRoute(
          path: '/plus/leaderboard',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Tujuan Leaderboard')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _withPlus(
        plus,
        ListenableBuilder(
          listenable: theme,
          builder: (context, child) => MaterialApp.router(
            theme: hiqeoLightTheme,
            darkTheme: hiqeoDarkTheme,
            themeMode: theme.mode,
            routerConfig: router,
          ),
        ),
      ),
    );
  } else {
    await tester.pumpWidget(
      _withPlus(
        plus,
        ListenableBuilder(
          listenable: theme,
          builder: (context, child) => MaterialApp(
            theme: hiqeoLightTheme,
            darkTheme: hiqeoDarkTheme,
            themeMode: theme.mode,
            home: page,
          ),
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
    safety: safety,
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
  testWidgets('tamu melihat ringkasan, manfaat, spasi rapi, dan tombol login',
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
    expect(find.text('Hiqeo Plus'), findsOneWidget);
    expect(find.text('Pengaturan'), findsOneWidget);
    expect(find.text('Analitik lanjutan'), findsNothing);
    expect(find.text('Rekap tahunan'), findsNothing);
    expect(find.text('Grup dan obrolan terenkripsi'), findsOneWidget);
    expect(find.text('Undang teman lewat username'), findsOneWidget);
    expect(find.text('Berbagi lokasi terakhir saat mendaki'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('guest-privacy-footnote')),
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

  testWidgets(
      'login dinonaktifkan dengan catatan jujur bila belum dikonfigurasi',
      (tester) async {
    final harness = await _pump(tester, configured: false);

    expect(
      find.text('Layanan masuk akun sedang tidak tersedia saat ini'),
      findsOneWidget,
    );

    await _tapKey(tester, 'profil-login-google');
    expect(harness.auth.signInCalls, isEmpty);
  });

  testWidgets(
      'analitik lanjutan dan rekap tahunan dipindahkan ke Hiqeo Plus (tidak tampil di Profil)',
      (tester) async {
    final plus = await buildPlusController(
      token: 'valid-token',
      payload: plusPayload(),
    );
    await _pump(tester, plus: plus);

    expect(find.text('Hiqeo Plus'), findsOneWidget);
    expect(find.text('Analitik lanjutan'), findsNothing);
    expect(find.text('Rekap tahunan'), findsNothing);
    expect(find.text('Pengaturan'), findsOneWidget);
  });

  testWidgets(
      'sudah masuk menampilkan urutan bersih: identitas, statistik, Hiqeo Plus -> Akun -> Riwayat -> Daftar teman -> Pengaturan (tanpa Kontak darurat)',
      (tester) async {
    final harness = await _pump(
      tester,
      signedIn: true,
      displayName: 'Rani Puspita',
      provider: AuthProviderKind.google,
      profile: _profile(),
      sessions: <TrackingSession>[
        _completed(id: 'selesai', distanceM: 31400, gainM: 1234),
      ],
      contacts: <EmergencyContact>[_contact()],
      mapCount: 2,
    );

    expect(harness.account.user, isNotNull);
    expect(find.text('Rani Puspita'), findsOneWidget);
    expect(find.text('@rani'), findsOneWidget);
    expect(find.text('Pendaki tamu'), findsNothing);
    expect(find.text('Masuk untuk membuka'), findsNothing);

    // Statistik
    expect(find.text('1'), findsOneWidget);
    expect(find.text('31 km'), findsOneWidget);
    expect(find.text('1.234 m'), findsOneWidget);

    // Baris inti & Kontak Darurat dipindahkan ke Fitur Utama Beranda
    expect(find.text('Hiqeo Plus'), findsOneWidget);
    expect(find.text('Akun'), findsOneWidget);
    expect(find.text('Username dan akun Google'), findsOneWidget);
    expect(find.text('Riwayat'), findsOneWidget);
    expect(find.text('Daftar teman'), findsOneWidget);
    expect(find.text('Pengaturan'), findsOneWidget);
    expect(find.text('Kontak darurat'), findsNothing);
    expect(find.text('Tambah kontak darurat'), findsNothing);

    // Baris yang dihapus dari Profil tidak boleh ada
    expect(find.text('Peta terunduh'), findsNothing);
    expect(find.text('Profil daya'), findsNothing);
    expect(find.text('Privasi lokasi'), findsNothing);
    expect(find.text('Tampilan'), findsNothing);
    expect(find.byKey(const ValueKey('profil-sign-out')), findsNothing);
    expect(find.text('Hapus akun'), findsNothing);

    // Verifikasi urutan vertikal: Header -> Hiqeo Plus -> Akun -> Riwayat -> Daftar teman -> Pengaturan
    final yHeader = tester.getTopLeft(find.text('Rani Puspita')).dy;
    final yPlus = tester.getTopLeft(find.text('Hiqeo Plus')).dy;
    final yAccount = tester.getTopLeft(find.text('Akun')).dy;
    final yHistory = tester.getTopLeft(find.text('Riwayat')).dy;
    final yFriends = tester.getTopLeft(find.text('Daftar teman')).dy;
    final ySettings = tester.getTopLeft(find.text('Pengaturan')).dy;
    expect(yHeader, lessThan(yPlus));
    expect(yPlus, lessThan(yAccount));
    expect(yAccount, lessThan(yHistory));
    expect(yHistory, lessThan(yFriends));
    expect(yFriends, lessThan(ySettings));
  });

  testWidgets('profil tanpa username menampilkan keterangan Username belum dibuat',
      (tester) async {
    await _pump(tester, signedIn: true);

    expect(find.text('Pendaki'), findsOneWidget);
    expect(find.text('Username belum dibuat'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('profil-row-akun')), findsOneWidget);
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
  });

  testWidgets('statistik jujur saat data lokal gagal dibaca', (tester) async {
    await _pump(tester, signedIn: true, failSessions: true);

    expect(find.text('—'), findsNWidgets(3));
    expect(
      find.text('Data pendakian lokal belum dapat dibuka.'),
      findsOneWidget,
    );
  });

  testWidgets('sheet kontak darurat dapat menambah kontak manual & menghapus dengan konfirmasi',
      (tester) async {
    final safety = _FakeSafetyRepository(contacts: <EmergencyContact>[_contact()]);
    final picker = _FakeContactPicker(
      const ContactPickResult(status: ContactPickStatus.cancelled),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showEmergencyContactsSheet(
                context,
                ownerUserId: 'user-1',
                safetyRepository: safety,
                contactPicker: picker,
              ),
              child: const Text('Buka kontak'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buka kontak'));
    await tester.pumpAndSettle();

    expect(find.text('Budi'), findsWidgets);
    expect(
      find.textContaining('Kontak nomor HP langsung aktif'),
      findsOneWidget,
    );

    // Hapus Budi dengan konfirmasi
    await tester.tap(
      find.byKey(const ValueKey<String>('emergency-contact-delete-contact-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hapus kontak darurat?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('emergency-delete-confirm')),
    );
    await tester.pumpAndSettle();
    expect(safety.contacts, isEmpty);

    // Tambah kontak baru secara manual
    await tester.tap(
      find.byKey(const ValueKey<String>('emergency-sheet-add-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('emergency-contact-name-input')),
      'Ibu Sinta',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('emergency-contact-phone-input')),
      '0813-9876-5432',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('emergency-contact-save-button')),
    );
    await tester.pumpAndSettle();

    expect(safety.contacts, hasLength(1));
    expect(safety.contacts.single.name, 'Ibu Sinta');
    expect(safety.contacts.single.phoneE164, '+6281398765432');
    expect(
      safety.contacts.single.consentStatus,
      EmergencyContactConsentStatus.granted,
    );
    expect(safety.contacts.single.isActive, isTrue);
  });

  testWidgets('sheet kontak gagal dibaca tidak diklaim kosong', (tester) async {
    final safety = _FakeSafetyRepository(failContacts: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showEmergencyContactsSheet(
                context,
                ownerUserId: 'user-1',
                safetyRepository: safety,
              ),
              child: const Text('Buka kontak'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buka kontak'));
    await tester.pumpAndSettle();

    expect(
      find.text('Kontak darurat belum dapat dibaca dari HP ini.'),
      findsOneWidget,
    );
  });

  testWidgets('baris leaderboard tidak tampil di Profil meski flag aktif (pindah ke Sosial)',
      (tester) async {
    await _pump(tester);
    expect(
      find.byKey(const ValueKey<String>('profil-row-leaderboard')),
      findsNothing,
    );

    final plus = await buildPlusController(leaderboard: true);
    await _pump(tester, plus: plus, withRouter: true);
    expect(find.text('Hiqeo Plus'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('profil-row-leaderboard')),
      findsNothing,
    );
    expect(find.text('Leaderboard'), findsNothing);
  });

  testWidgets(
      'pembatalan login Google oleh pengguna (AUTH_CANCELLED) tidak memunculkan pesan error',
      (tester) async {
    final harness = await _pump(tester, configured: true, signedIn: false);
    harness.auth.signInError = const AccountException(
      'AUTH_CANCELLED',
      'Login Google dibatalkan pengguna',
    );

    await tester.tap(find.byKey(const ValueKey<String>('profil-login-google')));
    await tester.pumpAndSettle();

    expect(harness.account.error, isNull);
    expect(find.text('Login Google dibatalkan pengguna'), findsNothing);
    expect(find.text('Pendaki tamu'), findsOneWidget);
  });

  testWidgets(
      'tombol Google menampilkan loading spinner dan mencegah ketukan ganda saat sibuk',
      (tester) async {
    final harness = await _pump(tester, configured: true, signedIn: false);
    final completer = Completer<void>();
    harness.auth.signInCompleter = completer;

    await tester.tap(find.byKey(const ValueKey<String>('profil-login-google')));
    await tester.pump();

    expect(harness.account.isBusy, isTrue);
    expect(find.text('Menghubungkan…'), findsAtLeastNWidgets(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('profil-login-google')));
    await tester.pump();

    expect(harness.auth.signInCalls.length, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(harness.account.isBusy, isFalse);
  });

  testWidgets(
      'login Google berhasil menampilkan nama lengkap menggantikan Pendaki tamu',
      (tester) async {
    await _pump(
      tester,
      configured: true,
      signedIn: true,
      provider: AuthProviderKind.google,
      displayName: 'Nama Akun Google',
      profile: const UserProfile(
        userId: 'user-1',
        fullName: 'Rian Santoso',
        avatarUrl: 'https://example.com/avatar.jpg',
        username: null,
      ),
    );

    expect(find.text('Pendaki tamu'), findsNothing);
    expect(find.text('Rian Santoso'), findsOneWidget);
    expect(find.text('Username belum dibuat'), findsOneWidget);
  });

  testWidgets(
      'kesalahan konfigurasi atau developer error (ApiException: 10) menampilkan status gagal dengan spasi konsisten',
      (tester) async {
    final harness = await _pump(tester, configured: true, signedIn: false);
    harness.auth.signInError = const AccountException(
      'GOOGLE_DEVELOPER_ERROR',
      'Konfigurasi OAuth Android belum cocok (ApiException: 10). Pastikan SHA-1 debug/release dan package id.nama.nama_app terdaftar di Google Cloud Console',
    );

    await tester.tap(find.byKey(const ValueKey<String>('profil-login-google')));
    await tester.pumpAndSettle();

    expect(harness.account.error, contains('ApiException: 10'));
    expect(find.byKey(const ValueKey<String>('guest-status-error')), findsOneWidget);
    expect(find.textContaining('ApiException: 10'), findsOneWidget);
  });
}
