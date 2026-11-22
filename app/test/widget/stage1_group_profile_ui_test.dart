import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/profile/presentation/profil_page.dart';
import 'package:nama_app/features/shell/hiqeo_shell.dart';
import 'package:nama_app/infrastructure/offgrid/mesh_packet_codec.dart';
import 'package:nama_app/infrastructure/offgrid/mesh_router_service.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_chat_local_store.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_transport_adapter.dart';
import 'package:nama_app/infrastructure/power/power_profile_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

class _FixedAccountController extends AccountController {
  _FixedAccountController({
    required AuthUser user,
    required UserProfile profile,
    List<RemoteGroup> groups = const <RemoteGroup>[],
    Map<String, List<MemberDirectoryEntry>> membersByGroup =
        const <String, List<MemberDirectoryEntry>>{},
    List<IncomingInvitation> invitations = const <IncomingInvitation>[],
  })  : _fixedUser = user,
        _fixedProfile = profile,
        _fixedGroups = groups,
        _fixedMembers = membersByGroup,
        _fixedInvitations = invitations,
        super(
          authService: FakeAuthService(currentUser: user),
          profileRepository: FakeProfileRepository()..current = profile,
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
          connectivityStream: const Stream<bool>.empty(),
        );

  final AuthUser _fixedUser;
  final UserProfile _fixedProfile;
  final List<RemoteGroup> _fixedGroups;
  final Map<String, List<MemberDirectoryEntry>> _fixedMembers;
  List<IncomingInvitation> _fixedInvitations;
  final StreamController<IncomingInvitation> _inviteCtrl =
      StreamController<IncomingInvitation>.broadcast();

  @override
  void initialize() {}

  @override
  AuthUser? get user => _fixedUser;

  @override
  UserProfile? get profile => _fixedProfile;

  @override
  List<RemoteGroup> get groups => _fixedGroups;

  @override
  List<IncomingInvitation> get invitations => _fixedInvitations;

  @override
  int get pendingInvitationCount => _fixedInvitations.length;

  @override
  Stream<IncomingInvitation> get onIncomingInvitation => _inviteCtrl.stream;

  @override
  int memberCountFor(String groupId) => _fixedMembers[groupId]?.length ?? 1;

  @override
  List<MemberDirectoryEntry> cachedMembersOf(String groupId) =>
      _fixedMembers[groupId] ?? const <MemberDirectoryEntry>[];

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async =>
      _fixedMembers[groupId] ?? const <MemberDirectoryEntry>[];

  void emitIncomingInvitation(IncomingInvitation inv) {
    _fixedInvitations = <IncomingInvitation>[inv, ..._fixedInvitations];
    _inviteCtrl.add(inv);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_inviteCtrl.close());
    super.dispose();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NavBarVisibilityController.instance.reset();
  });

  tearDown(() => NavBarVisibilityController.instance.reset());

  testWidgets(
      'Room Chat: Info anggota dibuka dari header & menu, BLE Mesh tidak jalan saat online dan tampil jumlah perangkat saat offline',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final group = RemoteGroup(
      group: Group(
        id: 'g-semeru',
        name: 'Ekspedisi Semeru',
        ownerId: 'u-1',
        mountain: 'Gunung Semeru',
        createdAtUtc: DateTime.utc(2026, 11, 1),
      ),
      role: GroupRole.owner,
    );
    final members = <MemberDirectoryEntry>[
      MemberDirectoryEntry(
        userId: 'u-1',
        username: 'raka_leader',
        displayName: 'Raka Pratama',
        role: GroupRole.owner,
        publicKeyBase64: 'pk1',
        joinedAtUtc: DateTime.utc(2026, 11, 1),
      ),
      MemberDirectoryEntry(
        userId: 'u-2',
        username: 'sari_trail',
        displayName: 'Sari Dewi',
        role: GroupRole.member,
        publicKeyBase64: 'pk2',
        joinedAtUtc: DateTime.utc(2026, 11, 2),
      ),
    ];

    final account = _FixedAccountController(
      user: const AuthUser(id: 'u-1', displayName: 'Raka Pratama'),
      profile: const UserProfile(
        userId: 'u-1',
        username: 'raka_leader',
        fullName: 'Raka Pratama',
      ),
      groups: <RemoteGroup>[group],
      membersByGroup: <String, List<MemberDirectoryEntry>>{'g-semeru': members},
    );
    addTearDown(account.dispose);

    final bus = LoopbackOffGridMeshBus();
    final localAdapter = InMemoryOffGridTransportAdapter(nodeId: 'hp-1', bus: bus);
    final peerAdapter = InMemoryOffGridTransportAdapter(nodeId: 'hp-2', bus: bus);
    final localStore = OffGridChatLocalStore();
    final meshRouter = MeshRouterService(
      adapter: localAdapter,
      codec: MeshPacketCodec(),
      localStore: localStore,
    );
    addTearDown(() async {
      await meshRouter.dispose();
      await localAdapter.dispose();
      await peerAdapter.dispose();
      await localStore.dispose();
    });

    Widget buildApp({required bool online}) => MaterialApp(
          theme: hiqeoLightTheme,
          home: Scaffold(
            body: ChatPage(
              accountController: account,
              localStore: localStore,
              meshRouter: meshRouter,
              initialOnline: online,
            ),
          ),
        );

    // 1. Buka dalam mode ONLINE
    await tester.pumpWidget(buildApp(online: true));
    await tester.pumpAndSettle();

    expect(find.text('Gunung Semeru · 2 anggota'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('group-card-g-semeru')));
    await tester.pumpAndSettle();

    // Saat ONLINE, Foreground Service & BLE Mesh TIDAK dijalankan!
    expect(localAdapter.isStarted, isFalse);
    expect(localAdapter.isForegroundServiceActive, isFalse);
    expect(find.text('Online · 2 anggota'), findsOneWidget);

    // 2. Ketuk header judul/jumlah anggota -> membuka sheet "Info anggota"
    await tester.tap(
      find.byKey(const ValueKey<String>('room-chat-header-info-btn')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('group-members-info-sheet')),
      findsOneWidget,
    );
    expect(find.text('Info anggota'), findsOneWidget);
    expect(find.text('Raka Pratama (Kamu)'), findsOneWidget);
    expect(find.text('Sari Dewi'), findsOneWidget);
    expect(find.text('Pemilik'), findsOneWidget);
    expect(find.text('Anggota'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('group-members-close-btn')),
    );
    await tester.pumpAndSettle();

    // 3. Buka "Info anggota" dari menu hamburger kanan atas
    await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('menu-member-info')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('menu-member-info')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('group-members-info-sheet')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('group-members-close-btn')),
    );
    await tester.pumpAndSettle();

    // 4. Beralih ke mode OFFLINE -> BLE Mesh + Foreground Service aktif &
    //    header menampilkan jumlah perangkat BLE sekitar secara realtime!
    await tester.pumpWidget(buildApp(online: false));
    await tester.pumpAndSettle();
    expect(localAdapter.isStarted, isTrue);
    expect(localAdapter.isForegroundServiceActive, isTrue);
    expect(find.text('Offline · 0 perangkat sekitar'), findsOneWidget);

    await peerAdapter.start(groupHashHex: 'any', highDuty: true);
    bus.connect('hp-1', 'hp-2');
    await tester.pumpAndSettle();
    expect(find.text('Offline · 1 perangkat sekitar'), findsOneWidget);

    // 5. Kembali ONLINE -> BLE Mesh & Foreground Service otomatis berhenti
    await tester.pumpWidget(buildApp(online: true));
    await tester.pumpAndSettle();
    expect(localAdapter.isStarted, isFalse);
    expect(localAdapter.isForegroundServiceActive, isFalse);
  });

  testWidgets(
      'ProfilPage offline: foto avatar dari file lokal tampil & tidak memunculkan Username belum dibuat',
      (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('hiqeo_profil_avatar');
    // 1x1 transparent PNG bytes valid
    final pngBytes = Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
    final avatarFile = File('${tempDir.path}${Platform.pathSeparator}me.png')
      ..writeAsBytesSync(pngBytes);
    addTearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    final account = _FixedAccountController(
      user: const AuthUser(id: 'u-1', displayName: 'Nadia Putri'),
      profile: UserProfile(
        userId: 'u-1',
        username: 'nadia_hikes',
        fullName: 'Nadia Putri',
        localAvatarPath: avatarFile.path,
        isProfileComplete: true,
      ),
    );
    addTearDown(account.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(body: ProfilPage(accountController: account)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('profil-avatar-local-file')),
      findsOneWidget,
    );
    expect(find.text('@nadia_hikes'), findsOneWidget);
    expect(find.text('Username belum dibuat'), findsNothing);
  });

  testWidgets(
      'HiqeoShell menampilkan banner melayang in-app undangan grup & lencana badge di tab Grup navbar',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final account = _FixedAccountController(
      user: const AuthUser(id: 'u-1', displayName: 'Raka'),
      profile: const UserProfile(userId: 'u-1', username: 'raka'),
    );
    final power = PowerProfileController();
    addTearDown(() {
      account.dispose();
      power.dispose();
    });

    final router = GoRouter(
      initialLocation: '/beranda',
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => HiqeoShell(
            navigationShell: shell,
            powerController: power,
            accountController: account,
          ),
          branches: <StatefulShellBranch>[
            for (final path in const <String>[
              '/beranda',
              '/peta',
              '/lacak',
              '/grup',
              '/profil',
            ])
              StatefulShellBranch(
                routes: <RouteBase>[
                  GoRoute(
                    path: path,
                    builder: (_, __) => Center(child: Text('Halaman $path')),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: hiqeoLightTheme,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('navbar-badge-3')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('in-app-invitation-banner')),
      findsNothing,
    );

    // Simulasikan undangan grup baru tiba via Realtime
    account.emitIncomingInvitation(
      IncomingInvitation(
        id: 'inv-live-1',
        groupId: 'g-live',
        groupName: 'Tim Prau Sunrise',
        inviterUsername: 'budi_trail',
        createdAtUtc: DateTime.utc(2026, 11, 19),
        expiresAtUtc: DateTime.utc(2026, 11, 26),
      ),
    );
    await tester.pumpAndSettle();

    // Banner in-app & lencana di tab Grup tampil!
    expect(
      find.byKey(const ValueKey<String>('in-app-invitation-banner')),
      findsOneWidget,
    );
    expect(find.text('Undangan grup baru'), findsOneWidget);
    expect(
      find.text('@budi_trail mengundangmu ke Tim Prau Sunrise'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('navbar-badge-3')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // Ketuk tombol aksi cepat "Lihat" -> pindah ke tab Grup & banner hilang
    await tester.tap(
      find.byKey(const ValueKey<String>('in-app-invitation-view')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Halaman /grup'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('in-app-invitation-banner')),
      findsNothing,
    );
  });
}
