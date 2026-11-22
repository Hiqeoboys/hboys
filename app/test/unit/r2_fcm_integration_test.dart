import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/infrastructure/notifications/push_notification_overlay.dart';
import 'package:nama_app/infrastructure/notifications/push_notification_service.dart';
import 'package:nama_app/infrastructure/storage/r2_media_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Part A — R2MediaService', () {
    test('uploadPreparedAvatarWebp memakai key avatars/{uid}.webp dan cache-buster ?v=',
        () async {
      Map<String, dynamic>? asked;
      Map<String, String>? putHeaders;
      final service = R2MediaService(
        nowMs: () => 1732100000000,
        presign: (body) async {
          asked = body;
          return <String, dynamic>{
            'uploadUrl': 'https://r2.example/avatars/user-123.webp?sig=abc',
            'publicUrl': 'https://media.hiqeo.app/avatars/user-123.webp',
            'headers': <String, String>{'Content-Type': 'image/webp'},
          };
        },
        put: (url, headers, bytes) async {
          putHeaders = headers;
          return 200;
        },
      );

      final url = await service.uploadPreparedAvatarWebp(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        userId: 'user-123',
      );
      expect(asked?['objectKey'], 'avatars/user-123.webp');
      expect(asked?['contentType'], 'image/webp');
      expect(putHeaders?['Content-Type'], 'image/webp');
      expect(
        url,
        'https://media.hiqeo.app/avatars/user-123.webp?v=1732100000000',
      );
      // Cache-buster tidak menggandakan query ?v=
      expect(
        R2MediaService.withCacheBuster(url, 1732100009999),
        'https://media.hiqeo.app/avatars/user-123.webp?v=1732100009999',
      );
    });

    test('uploadCommunityVideo menolak durasi > 60 detik dan menerima <= 60 detik',
        () async {
      final tmp = await Directory.systemTemp.createTemp('hiqeo_r2_test_');
      addTearDown(() => tmp.delete(recursive: true));
      final mp4 = File('${tmp.path}/clip.mp4')
        ..writeAsBytesSync(<int>[0, 1, 2, 3, 4, 5]);

      String? requestedKey;
      String? requestedMime;
      final service = R2MediaService(
        nowMs: () => 1732100000123,
        videoDurationReader: (_) async => const Duration(seconds: 75),
        presign: (body) async {
          requestedKey = body['objectKey']?.toString();
          requestedMime = body['contentType']?.toString();
          return <String, dynamic>{
            'uploadUrl': 'https://r2.example/upload',
            'publicUrl': 'https://media.hiqeo.app/$requestedKey',
          };
        },
        put: (_, __, ___) async => 200,
      );

      // Tanpa durationSec eksplisit -> dibaca dari videoDurationReader (75s) -> ditolak!
      await expectLater(
        () => service.uploadCommunityVideo(
          mp4,
          communityId: '11111111-1111-4111-8111-111111111111',
        ),
        throwsStateError,
      );

      // Durasi <= 60 detik -> sukses unggah ke community-media/{cid}/{ts}_{uuid}.mp4
      final res = await service.uploadCommunityVideo(
        mp4,
        communityId: '11111111-1111-4111-8111-111111111111',
        durationSec: 45,
      );
      expect(res.durationSec, 45);
      expect(res.contentType, 'video/mp4');
      expect(requestedMime, 'video/mp4');
      expect(
        requestedKey,
        matches(
          RegExp(
            r'^community-media/11111111-1111-4111-8111-111111111111/1732100000123_[0-9a-f-]+\.mp4$',
          ),
        ),
      );
    });
  });

  group('Part B — PushNotificationService & Overlay Routing', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      NavBarVisibilityController.instance.reset();
      PushNotificationService.instance.activeRoomType = null;
      PushNotificationService.instance.activeRoomId = null;
      PushNotificationService.instance.consumeSocialIntent();
      PushNotificationService.instance.showNotificationForTesting = null;
      PushNotificationService.instance.cancelNotificationForTesting = null;
    });

    tearDown(() {
      NavBarVisibilityController.instance.reset();
      PushNotificationService.instance.showNotificationForTesting = null;
      PushNotificationService.instance.cancelNotificationForTesting = null;
    });

    test('anti-spam ruang aktif & normalisasi tipe notifikasi baru + JSON payload',
        () {
      final service = PushNotificationService.instance;
      final groupMsg = InAppPushNotification.fromRemoteData(
        title: 'Tim Semeru',
        body: 'Ada pesan terenkripsi baru di grup.',
        data: <String, dynamic>{
          'type': 'group_chat',
          'target_id': 'grp-1',
        },
      );
      expect(groupMsg.type, 'group_chat');
      expect(groupMsg.groupId, 'grp-1');
      expect(groupMsg.route, '/grup');
      expect(service.shouldShowForegroundBanner(groupMsg), isTrue);

      service.setActiveRoom(type: 'group', id: 'grp-1');
      expect(service.shouldShowForegroundBanner(groupMsg), isFalse);

      // Ruang komunitas lain tetap menampilkan banner
      final commMsg = InAppPushNotification.fromRemoteData(
        title: 'Pendaki Nusantara',
        body: 'Raka: Foto baru',
        data: <String, dynamic>{
          'type': 'community_chat',
          'target_id': 'comm-9',
        },
      );
      expect(commMsg.communityId, 'comm-9');
      expect(service.shouldShowForegroundBanner(commMsg), isTrue);

      // Payload JSON local notification round-trip utuh
      final roundTrip =
          InAppPushNotification.fromPayloadJson(commMsg.toPayloadJson());
      expect(roundTrip?.type, 'community_chat');
      expect(roundTrip?.communityId, 'comm-9');
      expect(roundTrip?.title, 'Pendaki Nusantara');

      // SOS darurat tidak pernah ditekan meskipun di ruang aktif yang sama
      final sos = InAppPushNotification.fromRemoteData(
        data: <String, dynamic>{
          'type': 'sos',
          'target_id': 'sos-1',
          'group_id': 'grp-1',
          'lat': '-7.45512',
          'lon': '110.44018',
        },
      );
      expect(sos.isUrgent, isTrue);
      expect(service.shouldShowForegroundBanner(sos), isTrue);
    });

    testWidgets(
      'PushNotificationOverlayHost tidak memunculkan banner in-app dan menavigasi ketukan notifikasi perangkat melalui GoRouter',
      (tester) async {
        final shownTitles = <String>[];
        PushNotificationService.instance.showNotificationForTesting = ({
          required id,
          required title,
          required body,
          required details,
          required payload,
        }) async {
          shownTitles.add(title);
        };
        final visited = <String>[];
        final router = GoRouter(
          initialLocation: '/beranda',
          routes: <RouteBase>[
            GoRoute(
              path: '/beranda',
              builder: (_, __) => const Scaffold(body: Text('Layar Beranda')),
            ),
            GoRoute(
              path: '/grup',
              builder: (_, __) {
                visited.add('/grup');
                return const Scaffold(body: Text('Layar Sosial'));
              },
            ),
            GoRoute(
              path: '/teman',
              builder: (_, __) {
                visited.add('/teman');
                return const Scaffold(body: Text('Layar Teman'));
              },
            ),
            GoRoute(
              path: '/sos',
              builder: (_, __) {
                visited.add('/sos');
                return const Scaffold(body: Text('Layar SOS'));
              },
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

        // 1. Pesan foreground tidak memunculkan banner in-app, melainkan diproses sebagai OS notification.
        PushNotificationService.instance.emitForegroundForTesting(
          InAppPushNotification.fromRemoteData(
            title: 'Komunitas Merbabu',
            body: 'Andi: Cuaca cerah di basecamp',
            data: <String, dynamic>{
              'type': 'community_chat',
              'target_id': 'comm-42',
            },
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.byKey(const ValueKey<String>('in-app-fcm-banner')),
          findsNothing,
        );
        expect(shownTitles, contains('Komunitas Merbabu · 1 pesan baru'));

        // Ketuk notifikasi perangkat -> navigasi ke /grup dengan pending intent communityRoom('comm-42')
        PushNotificationService.instance.emitTapForTesting(
          InAppPushNotification.fromRemoteData(
            title: 'Komunitas Merbabu',
            body: 'Andi: Cuaca cerah di basecamp',
            data: <String, dynamic>{
              'type': 'community_chat',
              'target_id': 'comm-42',
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(visited, contains('/grup'));
        expect(NavBarVisibilityController.instance.isHidden, isFalse);
        final commIntent = PushNotificationService.instance.consumeSocialIntent();
        expect(commIntent?.kind, SocialNavigationTargetKind.communityRoom);
        expect(commIntent?.targetId, 'comm-42');

        // 2. Ketuk notifikasi background friend_request -> /teman
        PushNotificationService.instance.emitTapForTesting(
          InAppPushNotification.fromRemoteData(
            data: <String, dynamic>{
              'type': 'friend_request',
              'target_id': 'fr-1',
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(visited, contains('/teman'));
        expect(NavBarVisibilityController.instance.isHidden, isFalse);

        // 3. Ketuk notifikasi group_ready -> /grup dengan intent groupRoom
        PushNotificationService.instance.emitTapForTesting(
          InAppPushNotification.fromRemoteData(
            data: <String, dynamic>{
              'type': 'group_ready',
              'target_id': 'grp-77',
            },
          ),
        );
        await tester.pumpAndSettle();
        final readyIntent = PushNotificationService.instance.consumeSocialIntent();
        expect(readyIntent?.kind, SocialNavigationTargetKind.groupRoom);
        expect(readyIntent?.targetId, 'grp-77');

        // 4. Ketuk notifikasi sos grup -> /grup dengan intent groupLastLocation
        PushNotificationService.instance.emitTapForTesting(
          InAppPushNotification.fromRemoteData(
            data: <String, dynamic>{
              'type': 'sos',
              'target_id': 'sos-9',
              'group_id': 'grp-77',
            },
          ),
        );
        await tester.pumpAndSettle();
        final sosIntent = PushNotificationService.instance.consumeSocialIntent();
        expect(sosIntent?.kind, SocialNavigationTargetKind.groupLastLocation);
        expect(sosIntent?.targetId, 'grp-77');
      },
    );
  });
}
