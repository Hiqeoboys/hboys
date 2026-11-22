import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/home/beranda_page.dart';
import 'package:nama_app/features/notifications/data/user_notifications_service.dart';
import 'package:nama_app/features/notifications/presentation/notifications_page.dart';
import 'package:nama_app/features/shell/hiqeo_shell.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/infrastructure/power/power_profile_controller.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

class _EmptyTrackingRepo implements TrackingRepository {
  @override
  Future<void> addPoint(String sessionId, TrackPoint point) async {}

  @override
  Future<void> clearPoints(String sessionId) async {}

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<TrackingSession?> findActiveSession() async => null;

  @override
  Future<TrackingSession?> findSession(String id) async => null;

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async => null;

  @override
  Future<List<TrackPoint>> points(String sessionId) async =>
      const <TrackPoint>[];

  @override
  Future<void> saveSession(TrackingSession session) async {}

  @override
  Stream<List<TrackingSession>> watchSessions() =>
      Stream<List<TrackingSession>>.value(const <TrackingSession>[]);
}

class _FixedPowerController extends PowerProfileController {
  @override
  PowerProfile get profile => PowerProfile.normal;

  @override
  Future<void> refresh() async {}
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
      'tombol lonceng Beranda menampilkan titik merah & langsung hilang saat masuk Notifikasi meski item belum diketuk satu per satu',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now().toUtc();
    final notifService = UserNotificationsService.createForTesting(
      initialItems: <UserNotificationItem>[
        UserNotificationItem(
          id: 'n-mention',
          userId: 'u1',
          type: 'community_mention',
          title: 'Kamu disebut @rani',
          body: 'Halo @andi jangan lupa jaket!',
          roomType: 'community',
          roomId: 'c1',
          messageId: 'm1',
          isRead: false,
          createdAtUtc: now.subtract(const Duration(minutes: 2)),
        ),
        // Pesan chat biasa harus terfilter otomatis agar tidak masuk inbox Beranda.
        UserNotificationItem(
          id: 'n-chat-biasa',
          userId: 'u1',
          type: 'group_chat',
          title: 'Pesan Grup',
          body: 'Pesan biasa yang harus disembunyikan',
          isRead: false,
          createdAtUtc: now.subtract(const Duration(minutes: 1)),
        ),
        UserNotificationItem(
          id: 'n-read',
          userId: 'u1',
          type: 'friend_request',
          title: 'Permintaan pertemanan diterima',
          body: 'Budi sekarang menjadi temanmu.',
          isRead: true,
          createdAtUtc: now.subtract(const Duration(hours: 2)),
        ),
      ],
    );

    final account = _guestAccount();
    addTearDown(account.dispose);

    final router = GoRouter(
      initialLocation: '/beranda',
      routes: <RouteBase>[
        GoRoute(
          path: '/beranda',
          builder: (context, _) => BerandaPage(
            accountController: account,
            repository: _EmptyTrackingRepo(),
            notificationsService: notifService,
            now: () => DateTime(2026, 11, 21, 9, 0),
          ),
        ),
        GoRoute(
          path: '/notifikasi',
          builder: (context, _) => NotificationsPage(
            service: notifService,
            autoLoad: false,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    // Titik merah tampak di Beranda saat ada notifikasi baru yang belum dilihat.
    expect(
      find.byKey(const ValueKey<String>('beranda-notif-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('beranda-notif-red-dot')),
      findsOneWidget,
    );
    expect(notifService.hasUnreadNotifications, isTrue);

    // Masuk ke halaman Notifikasi lewat tombol lonceng.
    await tester.tap(find.byKey(const ValueKey<String>('beranda-notif-button')));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsPage), findsOneWidget);
    // Pesan obrolan biasa tidak pernah muncul di halaman Notifikasi.
    expect(find.text('Pesan Grup'), findsNothing);
    // Item unread tetap tampil dengan penanda visual (border highlight + dot + shadow, tanpa garis tepi kiri 3px),
    // tetapi `hasUnreadNotifications` untuk red dot Beranda sudah langsung padam.
    expect(find.text('Kamu disebut @rani'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('notif-accent-bar-n-mention')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('notif-unread-dot-n-mention')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('notif-unread-dot-n-read')),
      findsNothing,
    );
    expect(notifService.hasUnreadNotifications, isFalse);
    expect(notifService.unreadCount, 1);

    final unreadBox = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('notif-card-n-mention')),
    );
    final unreadDeco = unreadBox.decoration as BoxDecoration;
    expect(unreadDeco.boxShadow, isNotEmpty);

    final readBox = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('notif-card-n-read')),
    );
    final readDeco = readBox.decoration as BoxDecoration;
    expect(readDeco.boxShadow, isEmpty);

    // Kembali ke Beranda tanpa mengetuk item unread satu per satu:
    // titik merah tetap hilang.
    router.pop();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('beranda-notif-red-dot')),
      findsNothing,
    );
  });

  testWidgets(
      'mengetuk item notifikasi menandai is_read=true dan menavigasi tanpa menghilangkan Floating Bottom Navbar',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now().toUtc();
    final notifService = UserNotificationsService.createForTesting(
      initialItems: <UserNotificationItem>[
        UserNotificationItem(
          id: 'n-invite',
          userId: 'u1',
          type: 'group_invitation',
          title: 'Undangan Grup',
          body: 'Rani mengundangmu ke Rombongan Semeru.',
          roomType: 'group',
          roomId: 'g-semeru',
          isRead: false,
          createdAtUtc: now.subtract(const Duration(minutes: 5)),
        ),
      ],
    );

    final account = _guestAccount();
    final power = _FixedPowerController();
    addTearDown(account.dispose);
    addTearDown(power.dispose);

    final router = GoRouter(
      initialLocation: '/beranda',
      routes: <RouteBase>[
        GoRoute(
          path: '/notifikasi',
          builder: (context, _) => NotificationsPage(
            service: notifService,
            autoLoad: false,
          ),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => HiqeoShell(
            navigationShell: shell,
            powerController: power,
            accountController: account,
          ),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/beranda',
                  builder: (_, __) => BerandaPage(
                    accountController: account,
                    repository: _EmptyTrackingRepo(),
                    notificationsService: notifService,
                    now: () => DateTime(2026, 11, 21, 9, 0),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/peta',
                  builder: (_, __) => const Scaffold(body: Text('Tab Peta')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/lacak',
                  builder: (_, __) => const Scaffold(body: Text('Tab Track')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/grup',
                  builder: (_, __) =>
                      const Scaffold(body: Center(child: Text('Tab Sosial'))),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/profil',
                  builder: (_, __) => const Scaffold(body: Text('Tab Profil')),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('beranda-notif-button')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsPage), findsOneWidget);

    await tester.tap(find.text('Undangan Grup'));
    await tester.pumpAndSettle();

    // Item ditandai sudah dibaca, berpindah ke tab Sosial (/grup), dan Floating Bottom Navbar tetap utuh.
    expect(notifService.items.single.isRead, isTrue);
    expect(notifService.unreadCount, 0);
    expect(find.text('Tab Sosial'), findsOneWidget);
    expect(find.byType(HiqeoNavBar), findsOneWidget);
    expect(find.bySemanticsLabel('Beranda'), findsOneWidget);
    expect(find.text('Sosial'), findsOneWidget);
  });
}
