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
import 'package:nama_app/features/tracking/application/tracking_runtime.dart';
import 'package:nama_app/infrastructure/power/power_profile_controller.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/account_fakes.dart';

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

class _FixedBattery implements BatteryReader {
  const _FixedBattery(this.level);

  final int level;

  @override
  Future<int> levelPercent() async => level;

  @override
  Future<bool> isCharging() async => false;
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

GoRouter _router({
  required AccountController account,
  required PowerProfileController power,
}) {
  Widget destination(String text) => Scaffold(body: Center(child: Text(text)));
  return GoRouter(
    initialLocation: '/beranda',
    routes: <RouteBase>[
      GoRoute(
        path: '/beranda',
        builder: (context, state) => BerandaPage(
          accountController: account,
          powerController: power,
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
      GoRoute(path: '/kartu', builder: (_, __) => destination('Tujuan Kartu')),
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

Future<PowerProfileController> _power() async {
  final controller = PowerProfileController(
    reader: const _FixedBattery(62),
    manager: PowerProfileManager(),
  );
  await controller.refresh();
  return controller;
}

void main() {
  testWidgets('tamu melihat sapaan, baterai nyata, dan keadaan kosong',
      (tester) async {
    _setTallPhone(tester);
    final power = await _power();
    addTearDown(power.dispose);
    final account = _guestAccount();
    addTearDown(account.dispose);
    final router = _router(account: account, power: power);

    await tester.pumpWidget(
      MaterialApp.router(theme: altracqLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selamat pagi'), findsOneWidget);
    expect(find.text('Halo, Pendaki'), findsOneWidget);
    expect(find.text('Baterai 62% · Normal'), findsOneWidget);
    expect(find.text('Belum ada pendakian'), findsOneWidget);
    expect(find.text('Semua fitur'), findsOneWidget);
    for (final title in _featureTitles) {
      expect(find.text(title), findsOneWidget, reason: 'kartu $title hilang');
    }
  });

  testWidgets('akun dengan grup menampilkan pendakian dan status kunci nyata',
      (tester) async {
    _setTallPhone(tester);
    final power = await _power();
    addTearDown(power.dispose);
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
    final router = _router(account: account, power: power);

    await tester.pumpWidget(
      MaterialApp.router(theme: altracqLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.text('Halo, rani'), findsOneWidget);
    expect(find.text('Gunung Gede'), findsOneWidget);
    expect(find.text('4 anggota · kunci v2 siap'), findsOneWidget);
  });

  testWidgets('kartu membuka rute yang benar', (tester) async {
    _setTallPhone(tester);
    final power = await _power();
    addTearDown(power.dispose);
    final account = _guestAccount();
    addTearDown(account.dispose);
    final router = _router(account: account, power: power);

    await tester.pumpWidget(
      MaterialApp.router(theme: altracqLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pelacakan'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/lacak',
    );

    router.go('/beranda');
    await tester.pumpAndSettle();
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
    final power = await _power();
    addTearDown(power.dispose);
    final account = _guestAccount();
    addTearDown(account.dispose);
    final router = _router(account: account, power: power);
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp.router(theme: altracqLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

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
}
