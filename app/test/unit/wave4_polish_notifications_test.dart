import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/gooey/gooey_selector.dart';
import 'package:nama_app/design/layout.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/auth/presentation/account_page.dart';
import 'package:nama_app/features/groups/application/group_key_manager.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/onboarding/permission_service.dart';
import 'package:nama_app/features/preparation/presentation/siap_naik_page.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/social/presentation/social_leaderboard_tab.dart';
import 'package:nama_app/features/splash/presentation/startup_gate_screen.dart';
import 'package:nama_app/infrastructure/notifications/device_notification_group_store.dart';
import 'package:nama_app/infrastructure/notifications/push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

class _CapturedNotif {
  const _CapturedNotif({
    required this.id,
    required this.title,
    required this.body,
    required this.details,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final NotificationDetails details;
  final String payload;
}

class _FixedSiapNaikAccount extends AccountController {
  _FixedSiapNaikAccount({
    required this.fixedProfile,
    required this.fixedRemote,
    required this.fixedMembers,
    required this.fixedKeyStatus,
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
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async =>
      fixedMembers;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PushNotificationService.instance.activeRoomType = null;
    PushNotificationService.instance.activeRoomId = null;
    PushNotificationService.instance.showNotificationForTesting = null;
    PushNotificationService.instance.cancelNotificationForTesting = null;
    await DeviceNotificationGroupStore.instance.clearAll();
  });

  tearDown(() {
    PushNotificationService.instance.showNotificationForTesting = null;
    PushNotificationService.instance.cancelNotificationForTesting = null;
  });

  group('#20 GooeySelector on Social tabs & Leaderboard period', () {
    testWidgets(
      'GooeySelector horizontal expandItems renders 3 Social tabs without overflow on 320dp screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        var selected = 'grup';
        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: StatefulBuilder(
              builder: (context, setState) {
                final colors = HiqeoColors.of(context);
                return Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: colors.hairline),
                      ),
                      child: GooeySelector<String>(
                        key: const ValueKey<String>('test-social-gooey'),
                        axis: Axis.horizontal,
                        expandItems: true,
                        gap: 4,
                        borderRadius: 18,
                        indicatorColor: colors.primary,
                        itemPadding: const EdgeInsets.symmetric(
                          vertical: 11,
                          horizontal: 4,
                        ),
                        selected: selected,
                        onChanged: (v) => setState(() => selected = v),
                        items: const <GooeySelectorItem<String>>[
                          GooeySelectorItem<String>(
                            value: 'grup',
                            semanticsLabel: 'Grup',
                          ),
                          GooeySelectorItem<String>(
                            value: 'komunitas',
                            semanticsLabel: 'Komunitas',
                          ),
                          GooeySelectorItem<String>(
                            value: 'leaderboard',
                            semanticsLabel: 'Leaderboard',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Grup'), findsOneWidget);
        expect(find.text('Komunitas'), findsOneWidget);
        expect(find.text('Leaderboard'), findsOneWidget);

        await tester.tap(find.text('Leaderboard'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(selected, 'leaderboard');
      },
    );

    testWidgets(
      'SocialLeaderboardTab memakai GooeySelector untuk Bulanan | Tahunan',
      (tester) async {
        final requestedPeriods = <LeaderboardPeriod>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: Scaffold(
              body: SocialLeaderboardTab(
                isOnlineChecker: () async => true,
                fetchRankingsOverride: (cat, period) async {
                  requestedPeriods.add(period);
                  return const <LeaderboardRowEntry>[];
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('lb-period-selector')),
          findsOneWidget,
        );
        expect(
          find.byType(GooeySelector<LeaderboardPeriod>),
          findsOneWidget,
        );
        expect(requestedPeriods, <LeaderboardPeriod>[LeaderboardPeriod.monthly]);

        await tester.tap(find.text('Tahunan'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          requestedPeriods,
          <LeaderboardPeriod>[LeaderboardPeriod.monthly, LeaderboardPeriod.yearly],
        );
      },
    );
  });

  group('#21 Leaderboard 3 distinct states (offline / empty / error)', () {
    testWidgets('membedakan offline, kosong positif online, dan galat server online',
        (tester) async {
      // 1. Offline
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: Scaffold(
            body: SocialLeaderboardTab(
              key: const ValueKey<String>('lb-offline'),
              isOnlineChecker: () async => false,
              fetchRankingsOverride: (_, __) async =>
                  const <LeaderboardRowEntry>[],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Papan peringkat hanya tersedia saat online.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

      // 2. Online + 0 rows -> pesan positif tanpa ikon wifi terputus
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: Scaffold(
            body: SocialLeaderboardTab(
              key: const ValueKey<String>('lb-empty'),
              isOnlineChecker: () async => true,
              fetchRankingsOverride: (_, __) async =>
                  const <LeaderboardRowEntry>[],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Belum ada data peringkat di periode ini. Selesaikan pendakian pertamamu untuk masuk papan peringkat!',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);

      // 3. Online + error -> pesan gagal server + Coba lagi yang berfungsi
      var attempt = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: Scaffold(
            body: SocialLeaderboardTab(
              key: const ValueKey<String>('lb-error'),
              isOnlineChecker: () async => true,
              fetchRankingsOverride: (_, __) async {
                attempt++;
                if (attempt == 1) {
                  throw Exception('db error');
                }
                return const <LeaderboardRowEntry>[
                  LeaderboardRowEntry(
                    rank: 1,
                    userId: 'u1',
                    username: 'arga',
                    displayName: 'Arga',
                    mountainsCount: 4,
                    distanceM: 42000,
                  ),
                ];
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Gagal memuat papan peringkat. Periksa sinyal lalu coba lagi.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      expect(find.text('Coba lagi'), findsOneWidget);

      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(attempt, 2);
      expect(find.text('Arga'), findsOneWidget);
      expect(find.text('4 gunung'), findsOneWidget);
    });
  });

  group('#22 & #23 Auto-dismiss notices & AccountPage bottom padding', () {
    testWidgets(
      'SnackBar di SiapNaikPage meski memiliki SnackBarAction tetap menutup otomatis dalam 4 detik',
      (tester) async {
        final account = _FixedSiapNaikAccount(
          fixedProfile: const UserProfile(
            userId: 'user-1',
            username: 'rani',
            publicKeyBase64: 'kunci',
          ),
          fixedRemote: RemoteGroup(
            group: Group(
              id: 'g1',
              name: 'Rombongan Sabtu',
              ownerId: 'user-1',
              mountain: 'Gunung Gede',
              createdAtUtc: DateTime.utc(2026, 10, 20),
            ),
            role: GroupRole.owner,
          ),
          fixedMembers: <MemberDirectoryEntry>[
            MemberDirectoryEntry(
              userId: 'user-1',
              username: 'rani',
              role: GroupRole.owner,
              publicKeyBase64: 'kunci',
              joinedAtUtc: DateTime.utc(2026, 10, 20),
            ),
          ],
          fixedKeyStatus: const GroupKeyStatus(
            availability: GroupKeyAvailability.ready,
            keyVersion: 2,
            memberCount: 1,
          ),
        );
        addTearDown(account.dispose);

        final router = GoRouter(
          initialLocation: '/siap-naik',
          routes: <RouteBase>[
            GoRoute(
              path: '/siap-naik',
              builder: (_, __) => SiapNaikPage(
                accountController: account,
                contactLoader: (_) async => <EmergencyContact>[
                  EmergencyContact(
                    id: 'c1',
                    userId: 'user-1',
                    name: 'Ibu',
                    phoneE164: '+628123456789',
                    consentStatus: EmergencyContactConsentStatus.granted,
                    consentAtUtc: DateTime.utc(2026, 10, 21),
                    createdAtUtc: DateTime.utc(2026, 10, 20),
                  ),
                ],
                offlineMapCheck: (_) async => true,
                permissionCheck: () async => const PermissionReport(
                  notificationGranted: true,
                  locationWhileInUse: true,
                  locationAlways: true,
                  locationServiceEnabled: true,
                  preciseLocation: true,
                  ignoringBatteryOptimizations: true,
                ),
                onStartHike: () async => false,
                startFailureMessage: () => 'Izin lokasi belum lengkap.',
              ),
            ),
            GoRoute(
              path: '/peta',
              builder: (_, __) => const Scaffold(body: Text('Peta')),
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
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('Mulai pendakian'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Izin lokasi belum lengkap.'), findsOneWidget);
        expect(find.text('Buka Peta'), findsOneWidget);

        // Setelah 3 detik masih terlihat, setelah melewati 4 detik menutup otomatis.
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('Izin lokasi belum lengkap.'), findsOneWidget);

        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Izin lokasi belum lengkap.'), findsNothing);
      },
    );

    testWidgets(
      'AccountPage banner status hilang otomatis & padding bawah melampaui navbar mengambang',
      (tester) async {
        final auth = FakeAuthService();
        final controller = AccountController(
          authService: auth,
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );
        addTearDown(() async {
          controller.dispose();
          await auth.close();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: AccountPage(
              controller: controller,
              bannerDismissDuration: const Duration(milliseconds: 300),
            ),
          ),
        );
        await tester.pump();

        // Trigger banner melalui controller.signIn() tanpa sesi aktif (memicu notice).
        await controller.signIn(AuthProviderKind.google);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.byKey(const ValueKey<String>('account-status-banner')),
          findsOneWidget,
        );
        expect(controller.notice, isNotNull);

        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const ValueKey<String>('account-status-banner')),
          findsNothing,
        );
        expect(controller.notice, isNull);

        // Pastikan padding bawah ListView memberi ruang aman di atas Floating Bottom Navbar.
        final ctx = tester.element(find.byType(AccountPage));
        final listView = tester.widget<ListView>(find.byType(ListView));
        final padding = listView.padding! as EdgeInsets;
        expect(padding.bottom, greaterThan(AppLayout.bottomInset(ctx)));
      },
    );
  });

  group('#24 & #31 Device Notifications', () {
    test(
      'delete pesan komunitas memperbarui notifikasi aktif secara senyap dan tidak muncul bila sudah kosong',
      () async {
        final shown = <_CapturedNotif>[];
        PushNotificationService.instance.showNotificationForTesting = ({
          required id,
          required title,
          required body,
          required details,
          required payload,
        }) async {
          shown.add(
            _CapturedNotif(
              id: id,
              title: title,
              body: body,
              details: details,
              payload: payload,
            ),
          );
        };
        PushNotificationService.instance.cancelNotificationForTesting =
            (_) async {};

        const commId = 'comm-merbabu';
        final expectedNid = DeviceNotificationGroupStore.notificationIdForRoom(
          'community',
          commId,
        );

        await PushNotificationService.instance.showLocalNotification(
          InAppPushNotification.fromRemoteData(
            id: 'c1',
            title: 'Komunitas Merbabu',
            body: 'Bima: Titik temu di basecamp Selo',
            data: const <String, dynamic>{
              'type': 'community_chat',
              'target_id': commId,
              'community_id': commId,
              'room_type': 'community',
              'room_id': commId,
              'room_name': 'Komunitas Merbabu',
              'sender_id': 'u-bima',
              'sender_name': 'Bima',
              'message_text': 'Titik temu di basecamp Selo',
              'message_id': 'c1',
            },
          ),
        );
        await PushNotificationService.instance.showLocalNotification(
          InAppPushNotification.fromRemoteData(
            id: 'c2',
            title: 'Komunitas Merbabu',
            body: 'Rina: Siap meluncur',
            data: const <String, dynamic>{
              'type': 'community_chat',
              'target_id': commId,
              'community_id': commId,
              'room_type': 'community',
              'room_id': commId,
              'room_name': 'Komunitas Merbabu',
              'sender_id': 'u-rina',
              'sender_name': 'Rina',
              'message_text': 'Siap meluncur',
              'message_id': 'c2',
            },
          ),
        );

        final updated =
            await PushNotificationService.instance.handleRemoteMessageDeleted(
          InAppPushNotification.fromRemoteData(
            id: 'del-c1',
            title: 'Komunitas Merbabu',
            body: 'Pesan telah dihapus',
            data: const <String, dynamic>{
              'type': 'community_message_deleted',
              'target_id': commId,
              'community_id': commId,
              'room_type': 'community',
              'room_id': commId,
              'room_name': 'Komunitas Merbabu',
              'message_id': 'c1',
              'replacement_text': 'Pesan telah dihapus',
            },
          ),
        );

        expect(updated, isTrue);
        expect(shown, hasLength(3));
        final silentUpdate = shown.last;
        expect(silentUpdate.id, expectedNid);
        expect(silentUpdate.details.android!.silent, isTrue);
        expect(silentUpdate.details.android!.onlyAlertOnce, isTrue);
        expect(silentUpdate.details.android!.playSound, isFalse);
        expect(silentUpdate.details.android!.enableVibration, isFalse);
        expect(silentUpdate.details.iOS!.presentAlert, isFalse);
        expect(silentUpdate.details.iOS!.presentSound, isFalse);
        final style = silentUpdate.details.android!.styleInformation!
            as MessagingStyleInformation;
        expect(
          style.messages?.map((m) => m.text).toList(),
          <String>['Pesan telah dihapus', 'Siap meluncur'],
        );

        // Setelah notifikasi ruang dibersihkan/dibuka, hapus pesan tidak memunculkan pop-up baru.
        await PushNotificationService.instance.clearRoomNotifications(
          type: 'community',
          id: commId,
        );
        final ignored =
            await PushNotificationService.instance.handleRemoteMessageDeleted(
          InAppPushNotification.fromRemoteData(
            id: 'del-c2',
            title: 'Komunitas Merbabu',
            body: 'Pesan telah dihapus',
            data: const <String, dynamic>{
              'type': 'community_message_deleted',
              'target_id': commId,
              'community_id': commId,
              'room_type': 'community',
              'room_id': commId,
              'room_name': 'Komunitas Merbabu',
              'message_id': 'c2',
            },
          ),
        );
        expect(ignored, isFalse);
        expect(shown, hasLength(3));
      },
    );

    test(
      'notifikasi grup memakai avatar ruang (bukan pengirim) dan teks "Ada pesan baru dari <username>"',
      () async {
        final shown = <_CapturedNotif>[];
        PushNotificationService.instance.showNotificationForTesting = ({
          required id,
          required title,
          required body,
          required details,
          required payload,
        }) async {
          shown.add(
            _CapturedNotif(
              id: id,
              title: title,
              body: body,
              details: details,
              payload: payload,
            ),
          );
        };

        const groupId = 'grp-semeru-no-url';
        await PushNotificationService.instance.showLocalNotification(
          InAppPushNotification.fromRemoteData(
            id: 'gm-1',
            title: 'Tim Semeru',
            body: 'Rina Saputri: Ada pesan terenkripsi baru di grup.',
            data: const <String, dynamic>{
              'type': 'group_chat',
              'target_id': groupId,
              'group_id': groupId,
              'room_type': 'group',
              'room_id': groupId,
              'room_name': 'Tim Semeru',
              'sender_id': 'user-rina',
              'sender_name': 'Rina Saputri',
              'sender_username': 'rina_mdpl',
              'message_text': 'Ada pesan terenkripsi baru di grup.',
              'message_id': 'gm-1',
            },
          ),
        );
        await PushNotificationService.instance.showLocalNotification(
          InAppPushNotification.fromRemoteData(
            id: 'gm-2',
            title: 'Tim Semeru',
            body: 'Ada pesan baru dari doni_puncak',
            data: const <String, dynamic>{
              'type': 'group_chat',
              'target_id': groupId,
              'group_id': groupId,
              'room_type': 'group',
              'room_id': groupId,
              'room_name': 'Tim Semeru',
              'sender_id': 'user-doni',
              'sender_name': 'Doni',
              'sender_username': 'doni_puncak',
              'message_text': 'Ada pesan baru dari doni_puncak',
              'message_id': 'gm-2',
            },
          ),
        );

        expect(shown, hasLength(2));
        expect(shown[0].title, 'Tim Semeru · 1 pesan baru');
        expect(shown[0].body, 'Ada pesan baru dari rina_mdpl');
        expect(shown[1].title, 'Tim Semeru · 2 pesan baru');
        expect(shown[1].body, 'Ada pesan baru dari doni_puncak');

        // Karena tidak jatuh ke avatar pengirim, largeIcon tetap identik (monogram ruang Tim Semeru)
        // untuk pengirim yang berbeda.
        final icon1 =
            shown[0].details.android!.largeIcon! as ByteArrayAndroidBitmap;
        final icon2 =
            shown[1].details.android!.largeIcon! as ByteArrayAndroidBitmap;
        expect(icon1.data, equals(icon2.data));
      },
    );
  });

  group('#32 & #33 Brand logo, splash drawables & ic_stat_hiqeo assets', () {
    test('semua aset drawable Android, AndroidManifest, dan StartupGateScreen selaras', () {
      const densities = <String>[
        'drawable-mdpi',
        'drawable-hdpi',
        'drawable-xhdpi',
        'drawable-xxhdpi',
        'drawable-xxxhdpi',
      ];
      for (final d in densities) {
        expect(
          File('android/app/src/main/res/$d/ic_stat_hiqeo.png').existsSync(),
          isTrue,
          reason: '$d/ic_stat_hiqeo.png harus ada',
        );
        expect(
          File('android/app/src/main/res/$d/splash_logo.png').existsSync(),
          isTrue,
          reason: '$d/splash_logo.png harus ada',
        );
      }
      expect(
        File('android/app/src/main/res/drawable/ic_stat_hiqeo.xml').existsSync(),
        isFalse,
      );

      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('@drawable/ic_stat_hiqeo'));
      expect(manifest, isNot(contains('@drawable/ic_notification')));

      expect(
        StartupGateScreen.logoAssetPath,
        'assets/brand/hiqeo_logo_foreground.png',
      );
      expect(
        File(StartupGateScreen.logoAssetPath).existsSync(),
        isTrue,
      );
    });
  });
}
