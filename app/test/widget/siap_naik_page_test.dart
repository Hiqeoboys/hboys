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
import 'package:nama_app/features/onboarding/permission_service.dart';
import 'package:nama_app/features/preparation/presentation/siap_naik_page.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';

import '../support/account_fakes.dart';

class _FixedAccount extends AccountController {
  _FixedAccount({
    required this.fixedProfile,
    required this.fixedRemote,
    required this.fixedMembers,
    required this.fixedKeyStatus,
    this.membersFail = false,
  }) : super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'user-1'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  final UserProfile fixedProfile;
  final RemoteGroup fixedRemote;
  final List<MemberDirectoryEntry> fixedMembers;
  final GroupKeyStatus fixedKeyStatus;
  final bool membersFail;

  @override
  void initialize() {}

  @override
  UserProfile? get profile => fixedProfile;

  @override
  AuthUser? get user => const AuthUser(id: 'user-1');

  @override
  List<RemoteGroup> get groups => <RemoteGroup>[fixedRemote];

  @override
  GroupKeyStatus? keyStatusFor(String groupId) => fixedKeyStatus;

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async {
    if (membersFail) throw StateError('jaringan mati');
    return fixedMembers;
  }
}

RemoteGroup _remoteGroup() => RemoteGroup(
      group: Group(
        id: 'g1',
        name: 'Rombongan Sabtu',
        ownerId: 'user-1',
        mountain: 'Gunung Gede',
        createdAtUtc: DateTime.utc(2026, 10, 20),
      ),
      role: GroupRole.owner,
    );

MemberDirectoryEntry _member(String id, String username) =>
    MemberDirectoryEntry(
      userId: id,
      username: username,
      role: id == 'user-1' ? GroupRole.owner : GroupRole.member,
      publicKeyBase64: 'kunci',
      joinedAtUtc: DateTime.utc(2026, 10, 20),
    );

PermissionReport _permission({required bool ready}) => PermissionReport(
      notificationGranted: true,
      locationWhileInUse: true,
      locationAlways: ready,
      locationServiceEnabled: true,
      preciseLocation: true,
      ignoringBatteryOptimizations: true,
    );

EmergencyContact _grantedContact() => EmergencyContact(
      id: 'c1',
      userId: 'user-1',
      name: 'Ibu',
      phoneE164: '+628123456789',
      consentStatus: EmergencyContactConsentStatus.granted,
      consentAtUtc: DateTime.utc(2026, 10, 21),
      createdAtUtc: DateTime.utc(2026, 10, 20),
    );

GoRouter _router(Widget page) {
  Widget destination(String text) => Scaffold(body: Center(child: Text(text)));
  return GoRouter(
    initialLocation: '/siap-naik',
    routes: <RouteBase>[
      GoRoute(path: '/siap-naik', builder: (_, __) => page),
      GoRoute(path: '/lacak', builder: (_, __) => destination('Tujuan Lacak')),
      GoRoute(path: '/profil', builder: (_, __) => destination('Tujuan Profil')),
      GoRoute(path: '/grup', builder: (_, __) => destination('Tujuan Grup')),
    ],
  );
}

AccountController _guest() => AccountController(
      authService: FakeAuthService(isConfigured: false),
      profileRepository: FakeProfileRepository(),
      keyDirectory: FakeKeyDirectory(),
      identity: FakeIdentity(Uint8List(32)),
    );

void _setTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  _setTallPhone(tester);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: altracqLightTheme,
      routerConfig: _router(page),
    ),
  );
  await tester.pumpAndSettle();
}

SiapNaikPage _page(
  AccountController account, {
  bool permissionReady = true,
  bool mapReady = true,
  Future<List<EmergencyContact>> Function(String userId)? contactLoader,
  Future<bool> Function()? onStartHike,
  String? Function()? startFailureMessage,
  bool hikeActive = false,
}) =>
    SiapNaikPage(
      accountController: account,
      permissionCheck: () async => _permission(ready: permissionReady),
      offlineMapCheck: (mountain) async => mapReady,
      contactLoader: contactLoader ??
          (userId) async => <EmergencyContact>[_grantedContact()],
      onStartHike: onStartHike ?? () async => true,
      startFailureMessage: startFailureMessage,
      hikeActive: () => hikeActive,
    );

void main() {
  testWidgets('tanpa akun menampilkan keadaan offline dan jalan ke Profil',
      (tester) async {
    final account = _guest();
    addTearDown(account.dispose);
    await _pump(tester, _page(account));

    expect(find.text('Siap naik?'), findsOneWidget);
    expect(find.text('Belum ada rombongan'), findsOneWidget);
    expect(find.text('Aplikasi berjalan offline'), findsOneWidget);
    expect(find.text('Mulai pendakian'), findsNothing);

    await tester.tap(find.text('Buka Profil'));
    await tester.pumpAndSettle();
    expect(find.text('Tujuan Profil'), findsOneWidget);
  });

  testWidgets('rombongan menampilkan kesiapan, anggota, dan kontak nyata',
      (tester) async {
    final account = _FixedAccount(
      fixedProfile: const UserProfile(
        userId: 'user-1',
        username: 'rani',
        publicKeyBase64: 'kunci',
      ),
      fixedRemote: _remoteGroup(),
      fixedMembers: <MemberDirectoryEntry>[
        _member('user-1', 'rani'),
        _member('user-2', 'dimas'),
      ],
      fixedKeyStatus: const GroupKeyStatus(
        availability: GroupKeyAvailability.ready,
        keyVersion: 2,
        memberCount: 2,
      ),
    );
    addTearDown(account.dispose);
    await _pump(tester, _page(account));
    final handle = tester.ensureSemantics();

    expect(find.text('Gunung Gede · Rombongan Sabtu'), findsOneWidget);
    expect(find.text('1 dari 2 anggota melapor siap'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.textSpan?.toPlainText() == 'rani (kamu)',
      ),
      findsOneWidget,
    );
    expect(find.text('dimas'), findsOneWidget);
    expect(find.text('Belum melapor'), findsOneWidget);
    expect(find.text('Ibu · sudah menyetujui'), findsOneWidget);
    expect(find.text('Aktif'), findsOneWidget);

    expect(find.bySemanticsLabel('Kunci grup: siap'), findsOneWidget);
    expect(find.bySemanticsLabel('Peta: siap'), findsOneWidget);
    expect(find.bySemanticsLabel('Izin: siap'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Kesiapan dimas belum dilaporkan'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Kontak darurat aktif'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('kesiapan yang belum lengkap tidak diklaim siap', (tester) async {
    final account = _FixedAccount(
      fixedProfile: const UserProfile(
        userId: 'user-1',
        username: 'rani',
        publicKeyBase64: 'kunci',
      ),
      fixedRemote: _remoteGroup(),
      fixedMembers: <MemberDirectoryEntry>[_member('user-1', 'rani')],
      fixedKeyStatus: const GroupKeyStatus(
        availability: GroupKeyAvailability.waitingForOwner,
        keyVersion: 3,
        memberCount: 1,
      ),
    );
    addTearDown(account.dispose);
    await _pump(
      tester,
      _page(account, permissionReady: false, mapReady: false),
    );
    final handle = tester.ensureSemantics();

    expect(find.text('0 dari 1 anggota melapor siap'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.bySemanticsLabel('Kunci grup: belum siap'), findsOneWidget);
    expect(find.bySemanticsLabel('Peta: belum siap'), findsOneWidget);
    expect(find.bySemanticsLabel('Izin: belum siap'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('daftar anggota gagal dimuat tetap jujur soal jumlah',
      (tester) async {
    final account = _FixedAccount(
      fixedProfile: const UserProfile(
        userId: 'user-1',
        username: 'rani',
        publicKeyBase64: 'kunci',
      ),
      fixedRemote: _remoteGroup(),
      fixedMembers: const <MemberDirectoryEntry>[],
      fixedKeyStatus: const GroupKeyStatus(
        availability: GroupKeyAvailability.ready,
        keyVersion: 2,
        memberCount: 4,
      ),
      membersFail: true,
    );
    addTearDown(account.dispose);
    await _pump(tester, _page(account));

    expect(find.text('Daftar anggota belum dapat dimuat.'), findsOneWidget);
    expect(
      find.text('4 anggota tercatat menurut kunci grup.'),
      findsOneWidget,
    );
    expect(find.text('1 dari 4 anggota melapor siap'), findsOneWidget);
    expect(find.text('Muat ulang'), findsOneWidget);
  });

  testWidgets('mulai pendakian membuka layar pelacakan saat berhasil',
      (tester) async {
    final account = _FixedAccount(
      fixedProfile: const UserProfile(
        userId: 'user-1',
        username: 'rani',
        publicKeyBase64: 'kunci',
      ),
      fixedRemote: _remoteGroup(),
      fixedMembers: <MemberDirectoryEntry>[_member('user-1', 'rani')],
      fixedKeyStatus: const GroupKeyStatus(
        availability: GroupKeyAvailability.ready,
        keyVersion: 2,
        memberCount: 1,
      ),
    );
    addTearDown(account.dispose);
    await _pump(tester, _page(account));

    await tester.tap(find.text('Mulai pendakian'));
    await tester.pumpAndSettle();
    expect(find.text('Tujuan Lacak'), findsOneWidget);
  });

  testWidgets('mulai pendakian gagal memberi pesan dan tetap di layar',
      (tester) async {
    final account = _FixedAccount(
      fixedProfile: const UserProfile(
        userId: 'user-1',
        username: 'rani',
        publicKeyBase64: 'kunci',
      ),
      fixedRemote: _remoteGroup(),
      fixedMembers: <MemberDirectoryEntry>[_member('user-1', 'rani')],
      fixedKeyStatus: const GroupKeyStatus(
        availability: GroupKeyAvailability.ready,
        keyVersion: 2,
        memberCount: 1,
      ),
    );
    addTearDown(account.dispose);
    await _pump(
      tester,
      _page(
        account,
        onStartHike: () async => false,
        startFailureMessage: () => 'Izin lokasi belum lengkap.',
      ),
    );

    await tester.tap(find.text('Mulai pendakian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Izin lokasi belum lengkap.'), findsOneWidget);
    expect(find.text('Siap naik?'), findsOneWidget);
  });
}
