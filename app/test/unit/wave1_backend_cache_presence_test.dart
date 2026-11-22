import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/social/data/chat_mute_service.dart';
import 'package:nama_app/infrastructure/cache/media_cache_manager.dart';
import 'package:nama_app/infrastructure/cache/public_profile_cache_service.dart';
import 'package:nama_app/infrastructure/notifications/push_notification_service.dart';
import 'package:nama_app/infrastructure/storage/media_url_normalizer.dart';
import 'package:nama_app/infrastructure/storage/r2_media_service.dart';
import 'package:nama_app/infrastructure/supabase/app_presence_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaUrlNormalizer & R2MediaService hardening', () {
    test('normalizes duplicate slashes and upgrades http to https', () {
      expect(
        MediaUrlNormalizer.normalize(
          '  http://media.hiqeo.app//community-media///c1/img.webp  ',
        ),
        'https://media.hiqeo.app/community-media/c1/img.webp',
      );
      expect(MediaUrlNormalizer.normalize('   '), isNull);
    });

    test('detects presigned and private r2.cloudflarestorage.com URLs', () {
      expect(
        MediaUrlNormalizer.isPresignedOrPrivateR2Url(
          'https://pub.hiqeo.app/a.webp?X-Amz-Signature=deadbeef',
        ),
        isTrue,
      );
      expect(
        MediaUrlNormalizer.isPresignedOrPrivateR2Url(
          'https://acct.r2.cloudflarestorage.com/bucket/a.webp',
        ),
        isTrue,
      );
      expect(
        MediaUrlNormalizer.isPresignedOrPrivateR2Url(
          'https://media.hiqeo.app/community-media/1/photo.webp',
        ),
        isFalse,
      );
    });

    test('detects JPEG fallback magic bytes instead of hardcoding .webp', () async {
      final jpegBytes = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00]);
      final tmp = await Directory.systemTemp.createTemp('hiqeo_img_magic_');
      addTearDown(() => tmp.delete(recursive: true));
      final f = File('${tmp.path}/fallback.jpg')..writeAsBytesSync(jpegBytes);

      String? sentKey;
      String? sentContentType;
      final r2 = R2MediaService(
        nowMs: () => 1732200000000,
        presign: (body) async {
          sentKey = body['objectKey']?.toString();
          sentContentType = body['contentType']?.toString();
          return <String, dynamic>{
            'uploadUrl': 'https://upload.example/put',
            'publicUrl': 'http://media.hiqeo.app//${body['objectKey']}',
          };
        },
        put: (_, __, ___) async => 200,
      );

      final uploadedUrl = await r2.uploadCommunityImage(
        f,
        communityId: 'cid-1',
      );
      expect(sentKey, endsWith('.jpg'));
      expect(sentContentType, 'image/jpeg');
      expect(uploadedUrl, startsWith('https://media.hiqeo.app/community-media/'));
      expect(uploadedUrl.contains('//community-media'), isFalse);
    });

    test('rejects persisting presigned publicUrl returned by edge function', () async {
      final r2 = R2MediaService(
        nowMs: () => 1732200000000,
        presign: (_) async => <String, dynamic>{
          'uploadUrl': 'https://upload.example/put',
          'publicUrl':
              'https://acct.r2.cloudflarestorage.com/hiqeo-media/avatars/u1.webp',
        },
        put: (_, __, ___) async => 200,
      );

      await expectLater(
        () => r2.uploadPreparedAvatarWebp(
          Uint8List.fromList(<int>[1, 2, 3, 4]),
          userId: 'u1',
        ),
        throwsStateError,
      );
    });
  });

  group('MediaCacheManager app version bump', () {
    test('clears stale media caches once on version change', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final root = await Directory.systemTemp.createTemp('hiqeo_cache_mgr_');
      addTearDown(() => root.delete(recursive: true));
      final supportDir = Directory('${root.path}/support')..createSync();
      final tempDir = Directory('${root.path}/temp')..createSync();

      final thumbDir = Directory('${supportDir.path}/community_video_thumbs')
        ..createSync();
      final thumbFile = File('${thumbDir.path}/old.jpg')..writeAsStringSync('x');
      final avatarDir = Directory('${supportDir.path}/avatar_cache')..createSync();
      File('${avatarDir.path}/me.jpg').writeAsStringSync('x');
      final preserveDb = File('${supportDir.path}/hiqeo.sqlite')
        ..writeAsStringSync('keep');
      final tmpMedia = File('${tempDir.path}/hiqeo_old.mp4')
        ..writeAsStringSync('x');

      var currentVer = '1.0.0+1';
      var imageClearCalls = 0;
      final mgr = MediaCacheManager(
        appVersionReader: () async => currentVer,
        supportDirProvider: () async => supportDir,
        tempDirProvider: () async => tempDir,
        onClearImageCache: () => imageClearCalls++,
      );

      expect(await mgr.ensureCacheUpToDate(), isTrue);
      expect(imageClearCalls, 1);
      expect(thumbFile.existsSync(), isFalse);
      expect(tmpMedia.existsSync(), isFalse);
      expect(preserveDb.existsSync(), isTrue);

      // Same version -> no redundant clear
      expect(await mgr.ensureCacheUpToDate(), isFalse);
      expect(imageClearCalls, 1);

      // Version bump (APK update without uninstall) -> clears again once
      currentVer = '1.1.0+2';
      expect(await mgr.ensureCacheUpToDate(), isTrue);
      expect(imageClearCalls, 2);
    });
  });

  group('PublicProfileCacheService dynamic avatar resolution', () {
    test('updates existing avatar and evicts previous URL from cache', () async {
      final evicted = <String>[];
      final cache = PublicProfileCacheService(
        onEvictImageUrl: evicted.add,
      );
      var notifications = 0;
      cache.addListener(() => notifications++);

      await cache.putAll(
        <PublicProfile>[
          const PublicProfile(
            userId: 'u-1',
            username: 'pendaki_a',
            fullName: 'Raka',
            avatarUrl: 'https://media.hiqeo.app/avatars/u-1.webp?v=1',
          ),
        ],
        persistToDisk: false,
      );
      expect(
        cache.resolveAvatarUrl('u-1', fallback: 'https://stale.example/old.webp'),
        'https://media.hiqeo.app/avatars/u-1.webp?v=1',
      );

      await cache.putAll(
        <PublicProfile>[
          const PublicProfile(
            userId: 'u-1',
            avatarUrl: 'https://media.hiqeo.app/avatars/u-1.webp?v=2',
          ),
        ],
        persistToDisk: false,
      );

      expect(evicted, <String>['https://media.hiqeo.app/avatars/u-1.webp?v=1']);
      expect(
        cache.resolveAvatarUrl('u-1', fallback: 'https://stale.example/old.webp'),
        'https://media.hiqeo.app/avatars/u-1.webp?v=2',
      );
      expect(notifications, 2);
    });
  });

  group('ChatMuteService & PushNotificationService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await ChatMuteService.instance.clearLocal();
      PushNotificationService.instance.activeRoomKey = null;
    });

    test('supports temp mutes, forever 9999-12-31, mention breakthrough & SOS',
        () async {
      const gid = 'g-111';
      const cid = 'c-222';
      final now = DateTime.utc(2026, 11, 21, 12, 0);

      final groupMsg = InAppPushNotification.fromRemoteData(
        title: 'Grup Semeru',
        body: 'Berangkat jam 5',
        data: <String, dynamic>{
          'type': 'group_chat',
          'group_id': gid,
          'room_name': 'Grup Semeru',
          'sender_name': 'Budi',
          'sender_avatar_url': 'http://media.hiqeo.app//avatars/budi.webp',
          'message_id': 'msg-1',
        },
      );
      expect(groupMsg.senderAvatarUrl, 'https://media.hiqeo.app/avatars/budi.webp');
      expect(groupMsg.roomName, 'Grup Semeru');
      expect(groupMsg.messageId, 'msg-1');

      final mentionMsg = InAppPushNotification.fromRemoteData(
        title: 'Komunitas Rinjani',
        body: '@raka cek pos 2',
        data: <String, dynamic>{
          'type': 'community_mention',
          'community_id': cid,
          'message_id': 'cm-99',
        },
      );
      expect(mentionMsg.type, 'community_mention');
      expect(mentionMsg.communityId, cid);
      expect(mentionMsg.messageId, 'cm-99');

      final sosMsg = InAppPushNotification.fromRemoteData(
        data: <String, dynamic>{
          'type': 'sos',
          'group_id': gid,
          'sos_id': 'sos-1',
        },
      );

      // Mute group for 1 day
      await ChatMuteService.instance.muteFor(
        'group',
        gid,
        const Duration(days: 1),
        nowUtc: DateTime.now().toUtc(),
      );
      expect(ChatMuteService.instance.isMuted('group', gid), isTrue);
      expect(ChatMuteService.instance.isMutedForever('group', gid), isFalse);
      expect(
        PushNotificationService.instance.shouldShowForegroundBanner(groupMsg),
        isFalse,
      );
      expect(
        PushNotificationService.instance.shouldShowForegroundBanner(sosMsg),
        isTrue,
      );

      // Mute community for 1 week -> regular chat muted, mention breaks through
      await ChatMuteService.instance.muteFor(
        'community',
        cid,
        const Duration(days: 7),
        nowUtc: DateTime.now().toUtc(),
      );
      final regularCommunity = InAppPushNotification.fromRemoteData(
        data: <String, dynamic>{'type': 'community_chat', 'community_id': cid},
      );
      expect(
        PushNotificationService.instance
            .shouldShowForegroundBanner(regularCommunity),
        isFalse,
      );
      expect(
        PushNotificationService.instance.shouldShowForegroundBanner(mentionMsg),
        isTrue,
      );

      // Mute forever (9999-12-31) -> even mention suppressed, SOS still urgent
      await ChatMuteService.instance.muteForever('community', cid);
      expect(
        ChatMuteService.instance.isMuted('community', cid, nowUtc: now),
        isTrue,
      );
      expect(ChatMuteService.instance.isMutedForever('community', cid), isTrue);
      expect(
        PushNotificationService.instance.shouldShowForegroundBanner(mentionMsg),
        isFalse,
      );
    });
  });

  group('GroupHikePlan & cancel protocol', () {
    test('parses cancelled status and encodes/decodes cancel message', () {
      final rowPlan = GroupHikePlan.fromPrepRow(<String, dynamic>{
        'group_id': 'g-1',
        'invite_id': 'hike_123',
        'mountain_id': 'semeru',
        'mountain_name': 'Gunung Semeru',
        'status': 'cancelled',
        'is_cancelled': true,
        'invite_message_id': 'msg-uuid-1',
      });
      expect(rowPlan, isNotNull);
      expect(rowPlan!.isCancelled, isTrue);
      expect(rowPlan.isActive, isFalse);
      expect(rowPlan.inviteMessageClientId, 'msg-uuid-1');

      final encoded = GroupHikeInviteMessage.encodeCancel(
        inviteId: 'hike_123',
        groupId: 'g-1',
      );
      final decoded = GroupHikeInviteMessage.tryDecodeCancel(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.inviteId, 'hike_123');
      expect(decoded.groupId, 'g-1');
    });
  });

  group('AppPresenceService heartbeat', () {
    test('throttles rapid pings unless force=true and stops timer cleanly',
        () async {
      var pings = 0;
      final svc = AppPresenceService(
        pingFn: () async => pings++,
        interval: const Duration(minutes: 2),
        minGap: const Duration(seconds: 30),
      );

      svc.start();
      await Future<void>.delayed(Duration.zero);
      expect(pings, 1);
      expect(svc.isStarted, isTrue);
      expect(svc.isHeartbeatActive, isTrue);

      // Within minGap -> skipped
      expect(await svc.pingNow(), isFalse);
      expect(pings, 1);

      // Force -> runs
      expect(await svc.pingNow(force: true), isTrue);
      expect(pings, 2);

      svc.stop();
      expect(svc.isStarted, isFalse);
      expect(svc.isHeartbeatActive, isFalse);
    });
  });
}
