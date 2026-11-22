import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/glass/glass_config.dart';
import 'package:nama_app/design/glass/hiqeo_liquid_glass.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/features/shell/hiqeo_shell.dart';
import 'package:nama_app/features/social/data/social_unread_store.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart';
import 'package:nama_app/infrastructure/notifications/device_notification_group_store.dart';
import 'package:nama_app/infrastructure/notifications/push_notification_overlay.dart';
import 'package:nama_app/infrastructure/notifications/push_notification_service.dart';
import 'package:nama_app/infrastructure/power/power_profile_controller.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedBatteryReader implements BatteryReader {
  const _FixedBatteryReader(this.percent);

  final int percent;

  @override
  Future<bool> isCharging() async => false;

  @override
  Future<int> levelPercent() async => percent;
}

class _CapturedLocalNotification {
  const _CapturedLocalNotification({
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

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GlassConfig.resetForTesting();
    NavBarVisibilityController.instance.reset();
    PushNotificationService.instance.activeRoomType = null;
    PushNotificationService.instance.activeRoomId = null;
    PushNotificationService.instance.consumeSocialIntent();
    PushNotificationService.instance.showNotificationForTesting = null;
    PushNotificationService.instance.cancelNotificationForTesting = null;
    await DeviceNotificationGroupStore.instance.clearAll();
  });

  tearDown(() {
    GlassConfig.resetForTesting();
    NavBarVisibilityController.instance.reset();
    PushNotificationService.instance.showNotificationForTesting = null;
    PushNotificationService.instance.cancelNotificationForTesting = null;
  });

  group('Wave 4 Modul 1 — Hapus notifikasi in-app & deep-link navbar aman', () {
    testWidgets(
      'dispatchPushNavigation mereset NavBarVisibilityController dan menjaga Floating Bottom Navbar utuh saat kembali',
      (tester) async {
        tester.view.physicalSize = const Size(400, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final power = PowerProfileController(
          reader: const _FixedBatteryReader(85),
          manager: PowerProfileManager(),
        );
        await power.refresh();
        addTearDown(power.dispose);

        final router = GoRouter(
          initialLocation: '/beranda',
          routes: <RouteBase>[
            GoRoute(
              path: '/teman',
              builder: (ctx, _) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => ctx.pop(),
                    child: const Text('Halaman Teman'),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/sos',
              builder: (_, __) =>
                  const Scaffold(body: Center(child: Text('Halaman SOS'))),
            ),
            StatefulShellRoute.indexedStack(
              builder: (_, __, shell) =>
                  HiqeoShell(navigationShell: shell, powerController: power),
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
                        builder: (_, __) => Scaffold(body: Center(child: Text(path))),
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
            builder: (context, child) => PushNotificationOverlayHost(
              router: router,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Simulasikan pengguna sedang berada di dalam room chat / peta rute di mana navbar disembunyikan.
        NavBarVisibilityController.instance.setRoomChatOpen(true);
        NavBarVisibilityController.instance.setRouteScreenOpen(true);
        expect(NavBarVisibilityController.instance.isHidden, isTrue);

        // Pesan foreground tidak memunculkan banner in-app sama sekali.
        PushNotificationService.instance.emitForegroundForTesting(
          InAppPushNotification.fromRemoteData(
            title: 'Grup Semeru',
            body: 'Budi: Sampai Pos 2',
            data: <String, dynamic>{
              'type': 'group_chat',
              'target_id': 'grp-semeru',
            },
          ),
        );
        await tester.pump();
        expect(find.byKey(const ValueKey<String>('in-app-fcm-banner')), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('in-app-invitation-banner')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('in-app-friend-request-banner')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('in-app-emergency-contact-banner')),
          findsNothing,
        );

        // Ketuk notifikasi perangkat -> mereset visibility navbar & kembali memunculkan Floating Bottom Navbar.
        PushNotificationService.instance.emitTapForTesting(
          InAppPushNotification.fromRemoteData(
            data: <String, dynamic>{
              'type': 'friend_request',
              'target_id': 'fr-42',
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Halaman Teman'), findsOneWidget);
        expect(NavBarVisibilityController.instance.isHidden, isFalse);

        // Kembali dari /teman mendarat ke shell dengan HiqeoNavBar tetap tampil utuh.
        await tester.tap(find.text('Halaman Teman'));
        await tester.pumpAndSettle();
        expect(find.byType(HiqeoNavBar), findsOneWidget);
      },
    );
  });

  group('Wave 4 Modul 2 — Perbaikan menyeluruh efek Liquid Glass blur', () {
    test('GlassConfig mendukung blur API 26+ dan fallback pada < API 26', () {
      expect(GlassConfig.minAndroidSdkForBlur, 26);
      expect(
        GlassConfig.shouldFallbackForDevice(
          model: 'Pixel 7',
          androidSdkInt: 26,
        ),
        isFalse,
      );
      expect(
        GlassConfig.shouldFallbackForDevice(
          model: 'Galaxy S7',
          androidSdkInt: 25,
        ),
        isTrue,
      );
    });

    testWidgets(
      'HiqeoLiquidGlassSurface tetap memburam (sigma 22, fill alpha 0.16-0.22) saat baterai Hemat (<40%), dan fallback buram padat saat baterai Kritis',
      (tester) async {
        for (final brightness in const <Brightness>[
          Brightness.light,
          Brightness.dark,
        ]) {
          final theme =
              brightness == Brightness.dark ? hiqeoDarkTheme : hiqeoLightTheme;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: VisualEffectPolicyScope(
                  policy: const VisualEffectPolicy(
                    powerProfile: PowerProfile.saver,
                    reduceMotion: false,
                    deviceTier: DeviceTier.capable,
                  ),
                  child: HiqeoLiquidGlassSurface(
                    key: ValueKey<String>('saver-${brightness.name}'),
                    borderRadius: 24,
                    child: const SizedBox(width: 120, height: 48),
                  ),
                ),
              ),
            ),
          );

          final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
          expect(
            backdrop.filter,
            ui.ImageFilter.blur(
              sigmaX: 14,
              sigmaY: 14,
              tileMode: ui.TileMode.clamp,
            ),
          );

          final fill = HiqeoGlassTokens.fill(brightness);
          expect(fill.a, inInclusiveRange(0.14, 0.24));
        }

        // Pada baterai kritis (<20%), blur nonaktif NAMUN fill menjadi glassFillFallback (bukan bening tembus baca).
        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoDarkTheme,
            home: const Scaffold(
              body: VisualEffectPolicyScope(
                policy: VisualEffectPolicy(
                  powerProfile: PowerProfile.critical,
                  reduceMotion: false,
                  deviceTier: DeviceTier.capable,
                ),
                child: HiqeoLiquidGlassSurface(
                  borderRadius: 24,
                  child: SizedBox(width: 120, height: 48),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        final surface = find.byType(HiqeoLiquidGlassSurface);
        final decBoxes = tester.widgetList<DecoratedBox>(
          find.descendant(of: surface, matching: find.byType(DecoratedBox)),
        );
        final hasFallbackFill = decBoxes.any((d) {
          final dec = d.decoration;
          return dec is BoxDecoration &&
              dec.color == HiqeoColors.dark.glassFillFallback;
        });
        expect(hasFallbackFill, isTrue);

        // overMap tetap bebas BackdropFilter secara bawaan dan kartu gulir HiqeoGlassCard tanpa BackdropFilter.
        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoDarkTheme,
            home: const Scaffold(
              body: Column(
                children: <Widget>[
                  HiqeoLiquidGlassSurface(
                    overMap: true,
                    child: Text('Kontrol Peta'),
                  ),
                  HiqeoGlassCard(
                    child: Text('Kartu Daftar'),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.byType(BackdropFilter), findsNothing);
      },
    );
  });

  group('Wave 4 Modul 3 — Desain ulang notifikasi & pengelompokan unread persisten', () {
    test('pemetaan 5 Notification Channel Android terpisah dengan benar', () {
      expect(
        PushNotificationService.resolveChannelId(
          InAppPushNotification.fromRemoteData(
            data: <String, dynamic>{'type': 'group_chat', 'target_id': 'g1'},
          ),
        ),
        kHiqeoGroupMessagesChannelId,
      );
      expect(
        PushNotificationService.resolveChannelId(
          InAppPushNotification.fromRemoteData(
            data: <String, dynamic>{'type': 'community_chat', 'target_id': 'c1'},
          ),
        ),
        kHiqeoCommunityMessagesChannelId,
      );
      expect(
        PushNotificationService.resolveChannelId(
          InAppPushNotification.fromRemoteData(
            data: <String, dynamic>{'type': 'community_mention', 'target_id': 'c1'},
          ),
        ),
        kHiqeoMentionsChannelId,
      );
      expect(
        PushNotificationService.resolveChannelId(
          InAppPushNotification.fromRemoteData(
            data: <String, dynamic>{'type': 'friend_request', 'target_id': 'f1'},
          ),
        ),
        kHiqeoSocialPrepChannelId,
      );
      expect(
        PushNotificationService.resolveChannelId(
          InAppPushNotification.fromRemoteData(
            data: <String, dynamic>{'type': 'sos', 'target_id': 's1'},
          ),
        ),
        kHiqeoSosChannelId,
      );
    });

    test(
      'pesan berturut di grup yang sama membentuk 1 kartu MessagingStyle dengan counter persisten, bertahan saat swipe/dismiss, dan reset saat room dibuka',
      () async {
        final shown = <_CapturedLocalNotification>[];
        final cancelledIds = <int>[];
        PushNotificationService.instance.showNotificationForTesting = ({
          required id,
          required title,
          required body,
          required details,
          required payload,
        }) async {
          shown.add(
            _CapturedLocalNotification(
              id: id,
              title: title,
              body: body,
              details: details,
              payload: payload,
            ),
          );
        };
        PushNotificationService.instance.cancelNotificationForTesting =
            (id) async {
          cancelledIds.add(id);
        };

        const groupId = 'grp-gede-123';
        final expectedNid =
            DeviceNotificationGroupStore.notificationIdForRoom('group', groupId);

        InAppPushNotification msgNotif({
          required String msgId,
          required String senderId,
          required String senderName,
          required String text,
        }) =>
            InAppPushNotification.fromRemoteData(
              id: msgId,
              title: 'Pendakian Gunung Gede',
              body: '$senderName: $text',
              data: <String, dynamic>{
                'type': 'group_chat',
                'target_id': groupId,
                'group_id': groupId,
                'room_type': 'group',
                'room_id': groupId,
                'room_name': 'Pendakian Gunung Gede',
                'sender_id': senderId,
                'sender_name': senderName,
                'message_text': text,
                'message_id': msgId,
              },
            );

        // 1 -> 2 -> 3 pesan berturut-turut di grup yang sama.
        await PushNotificationService.instance.showLocalNotification(
          msgNotif(
            msgId: 'm1',
            senderId: 'user-a',
            senderName: 'User A',
            text: 'Kumpul jam 6 pagi ya',
          ),
        );
        await PushNotificationService.instance.showLocalNotification(
          msgNotif(
            msgId: 'm2',
            senderId: 'user-b',
            senderName: 'User B',
            text: 'Siap, tenda aman',
          ),
        );
        await PushNotificationService.instance.showLocalNotification(
          msgNotif(
            msgId: 'm3',
            senderId: 'user-c',
            senderName: 'User C',
            text: 'Ketemu di gerbang Cibodas',
          ),
        );
        // Duplikat m3 tidak menambah penghitung.
        await PushNotificationService.instance.showLocalNotification(
          msgNotif(
            msgId: 'm3',
            senderId: 'user-c',
            senderName: 'User C',
            text: 'Ketemu di gerbang Cibodas',
          ),
        );

        expect(shown, hasLength(4));
        expect(shown[0].id, expectedNid);
        expect(shown[1].id, expectedNid);
        expect(shown[2].id, expectedNid);
        expect(shown[0].title, 'Pendakian Gunung Gede · 1 pesan baru');
        expect(shown[1].title, 'Pendakian Gunung Gede · 2 pesan baru');
        expect(shown[2].title, 'Pendakian Gunung Gede · 3 pesan baru');
        expect(shown[3].title, 'Pendakian Gunung Gede · 3 pesan baru');

        final androidDetails = shown[2].details.android!;
        expect(androidDetails.channelId, kHiqeoGroupMessagesChannelId);
        expect(androidDetails.icon, 'ic_stat_hiqeo');
        expect(androidDetails.color, kHiqeoNotificationAccentColor);
        expect(androidDetails.subText, '3 pesan baru');
        expect(androidDetails.number, 3);
        expect(androidDetails.largeIcon, isA<ByteArrayAndroidBitmap>());

        final style =
            androidDetails.styleInformation! as MessagingStyleInformation;
        expect(style.groupConversation, isTrue);
        expect(style.conversationTitle, 'Pendakian Gunung Gede · 3 pesan baru');
        expect(style.messages?.map((m) => m.person?.name), <String?>[
          'User A',
          'User B',
          'User C',
        ]);
        expect(style.messages?.map((m) => m.text), <String>[
          'Kumpul jam 6 pagi ya',
          'Siap, tenda aman',
          'Ketemu di gerbang Cibodas',
        ]);

        // Simulasi swipe/dismiss dari shade Android: antrean TIDAK direset.
        // Ketika m4 datang, hitungan lanjut menjadi 4 pesan baru.
        await PushNotificationService.instance.showLocalNotification(
          msgNotif(
            msgId: 'm4',
            senderId: 'user-a',
            senderName: 'User A',
            text: 'Sudah di parkiran',
          ),
        );
        expect(shown[4].title, 'Pendakian Gunung Gede · 4 pesan baru');

        // User masuk ke ruang obrolan & membaca -> cancel(roomNotificationId) + reset hitungan ke 0.
        await SocialUnreadStore.instance.markGroupRead(groupId);
        expect(cancelledIds, contains(expectedNid));
        expect(
          await DeviceNotificationGroupStore.instance.getRoomState('group', groupId),
          isNull,
        );

        // Saat pesan baru tiba setelah user keluar dari ruang, hitungan mulai ulang dari 1 pesan baru.
        await PushNotificationService.instance.showLocalNotification(
          msgNotif(
            msgId: 'm5',
            senderId: 'user-b',
            senderName: 'User B',
            text: 'Lanjut jalur utara',
          ),
        );
        expect(shown.last.title, 'Pendakian Gunung Gede · 1 pesan baru');
      },
    );
  });
}
