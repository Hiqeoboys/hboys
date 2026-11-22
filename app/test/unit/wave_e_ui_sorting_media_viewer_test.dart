import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/gooey/gooey_selector.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/system_ui.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/account_badges.dart';
import 'package:nama_app/design/widgets/fullscreen_avatar_viewer_page.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/auth/presentation/account_page.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/history/presentation/history_page.dart';
import 'package:nama_app/features/profile/presentation/other_user_profile_page.dart';
import 'package:nama_app/features/profile/presentation/profil_page.dart';
import 'package:nama_app/features/social/data/community_media_tools.dart';
import 'package:nama_app/features/social/data/community_service.dart';
import 'package:nama_app/features/social/data/social_unread_store.dart';
import 'package:nama_app/features/social/presentation/social_community_tab.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_chat_local_store.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';
import 'package:nama_app/infrastructure/storage/avatar_image_processor.dart';
import 'package:nama_app/infrastructure/storage/r2_media_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

class _FakeHistoryTrackingRepo implements TrackingRepository {
  _FakeHistoryTrackingRepo(this.sessions);

  final List<TrackingSession> sessions;

  @override
  Future<TrackingSession?> findActiveSession() async => null;

  @override
  Future<TrackingSession?> findSession(String id) async =>
      sessions.where((s) => s.id == id).firstOrNull;

  @override
  Future<void> addPoint(String sessionId, TrackPoint point) async {}

  @override
  Future<void> clearPoints(String sessionId) async {}

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async => null;

  @override
  Future<List<TrackPoint>> points(String sessionId) async =>
      const <TrackPoint>[];

  @override
  Future<void> saveSession(TrackingSession session) async {}

  @override
  Stream<List<TrackingSession>> watchSessions() =>
      Stream<List<TrackingSession>>.value(sessions);
}

Future<Uint8List> _makePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF313851),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SocialUnreadStore.instance.clearForAccountChange();
  });

  tearDown(() {
    SocialUnreadStore.instance.clearForAccountChange();
  });

  group('Wave E #5 — Jarak bawah Akun simetris dengan tombol Keluar -> Hapus akun',
      () {
    Future<void> verifySymmetricGap(
      WidgetTester tester, {
      required double systemInset,
    }) async {
      const viewSize = Size(390, 680);
      tester.view.physicalSize = viewSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final shellBottomPadding =
          HiqeoMetrics.floatingBottomInset(systemInset); // navbar + 12 + inset

      final auth = FakeAuthService(
        currentUser: const AuthUser(
          id: 'u-acc-margin',
          email: 'pendaki@example.com',
          provider: AuthProviderKind.google,
        ),
      );
      final profiles = FakeProfileRepository()
        ..current = UserProfile(
          userId: 'u-acc-margin',
          username: 'pendaki_test',
          fullName: 'Pendaki Nusantara',
          publicKeyBase64: base64Encode(List<int>.filled(32, 7)),
        );
      final controller = AccountController(
        authService: auth,
        profileRepository: profiles,
        keyDirectory: FakeKeyDirectory(),
        identity: FakeIdentity(Uint8List.fromList(List<int>.filled(32, 7))),
        clock: FakeClock(DateTime.utc(2026, 11, 22)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: VisualEffectPolicyScope(
            policy: const VisualEffectPolicy(
              powerProfile: PowerProfile.normal,
              reduceMotion: true,
              deviceTier: DeviceTier.capable,
            ),
            child: HiqeoSystemInset(
              bottom: systemInset,
              child: MediaQuery(
                data: MediaQueryData(
                  size: viewSize,
                  padding: EdgeInsets.only(top: 44, bottom: shellBottomPadding),
                  viewPadding: EdgeInsets.only(top: 44, bottom: systemInset),
                ),
                child: AccountPage(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('account-delete-button')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      final scrollState = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollState.position.maxScrollExtent, greaterThan(0));
      scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
      await tester.pump();

      final signOutRect = tester.getRect(
        find.byKey(const ValueKey<String>('account-signout-button')),
      );
      final deleteRect = tester.getRect(
        find.byKey(const ValueKey<String>('account-delete-button')),
      );

      final topGap = deleteRect.top - signOutRect.bottom;
      final navBarTop = viewSize.height - shellBottomPadding;
      final bottomGap = navBarTop - deleteRect.bottom;

      expect(topGap, closeTo(AccountPage.deleteActionGap, 0.5));
      expect(bottomGap, closeTo(topGap, 0.5));

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await auth.close();
    }

    testWidgets('simetris pada iOS safe area (34 px)', (tester) async {
      await verifySymmetricGap(tester, systemInset: 34.0);
    });

    testWidgets('simetris pada Android gesture inset (16 px)', (tester) async {
      await verifySymmetricGap(tester, systemInset: 16.0);
    });
  });

  group('Wave E #9 — GooeySelector pada Riwayat (Pendakian | Jogging)', () {
    testWidgets(
      'HistoryPage memakai GooeySelector dan mengganti daftar antara Pendakian & Jogging',
      (tester) async {
        final t0 = DateTime.utc(2026, 11, 20, 6, 0);
        final hike = TrackingSession(
          id: 'hike-e-1',
          mountainName: 'Gunung Merbabu',
          startedAtUtc: t0,
          endedAtUtc: t0.add(const Duration(hours: 3)),
          distanceM: 6400,
          movingSeconds: 9800,
          elevationGainM: 820,
          activityType: TrackingSession.activityHiking,
          status: TrackingSessionStatus.completed,
        );
        final jog = TrackingSession(
          id: 'jog-e-1',
          startedAtUtc: t0.add(const Duration(days: 1)),
          endedAtUtc: t0.add(const Duration(days: 1, minutes: 35)),
          distanceM: 4200,
          movingSeconds: 1500,
          elevationGainM: 25,
          activityType: TrackingSession.activityJogging,
          status: TrackingSessionStatus.completed,
        );
        final repo = _FakeHistoryTrackingRepo(<TrackingSession>[hike, jog]);

        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: HistoryPage(repository: repo),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.byKey(const ValueKey<String>('history-tab-selector')),
          findsOneWidget,
        );
        expect(find.byType(GooeySelector<dynamic>), findsNothing);
        expect(
          find.byWidgetPredicate((w) => w is GooeySelector),
          findsOneWidget,
        );

        expect(find.text('Gunung Merbabu'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('history-item-jog-e-1')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('history-tab-jogging')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(
          find.byKey(const ValueKey<String>('history-item-jog-e-1')),
          findsOneWidget,
        );
        expect(find.text('Gunung Merbabu'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey<String>('history-tab-hiking')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text('Gunung Merbabu'), findsOneWidget);
      },
    );
  });

  group('Wave E #10 — Urutan dinamis Grup & Komunitas berdasarkan pesan terbaru',
      () {
    test(
      'compareRoomsByLatestActivity mengutamakan last_message_at DESC NULLS LAST lalu fallback created_at DESC',
      () {
        final tJan = DateTime.utc(2026, 1, 1);
        final tFeb = DateTime.utc(2026, 2, 1);
        final tMar = DateTime.utc(2026, 3, 1);

        final rooms = <({String id, DateTime created, DateTime? lastMsg})>[
          (id: 'no-msg-old', created: tJan, lastMsg: null),
          (id: 'msg-feb', created: tJan, lastMsg: tFeb),
          (id: 'no-msg-new', created: tMar, lastMsg: null),
          (id: 'msg-mar', created: tJan, lastMsg: tMar),
        ];

        rooms.sort(
          (a, b) => compareRoomsByLatestActivity(
            aLastMessageAtUtc: a.lastMsg,
            aCreatedAtUtc: a.created,
            bLastMessageAtUtc: b.lastMsg,
            bCreatedAtUtc: b.created,
            aId: a.id,
            bId: b.id,
          ),
        );

        expect(
          rooms.map((e) => e.id).toList(),
          <String>['msg-mar', 'msg-feb', 'no-msg-new', 'no-msg-old'],
        );
      },
    );

    test(
      'SocialUnreadStore.recordGroupActivity & recordCommunityActivity mempertahankan stempel Mesh lebih baru dan mengabaikan event lama',
      () async {
        final serverAt = DateTime.utc(2026, 11, 20, 8, 0);
        final meshNewerAt = DateTime.utc(2026, 11, 20, 9, 30);
        final staleAt = DateTime.utc(2026, 11, 20, 7, 0);

        final store = SocialUnreadStore(
          currentUserIdProvider: () => 'u-me',
          fetcher: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'room_kind': 'group',
              'room_id': 'g-1',
              'message_id': 'm-srv',
              'sender_id': 'u-other',
              'message_type': 'text',
              'ciphertext': 'cipher',
              'key_version': 1,
              'created_at': serverAt.toIso8601String(),
            },
          ],
          decryptor: ({
            required String kind,
            required String groupId,
            required String recordId,
            required int keyVersion,
            required String ciphertextBase64,
          }) async =>
              <String, dynamic>{'sender_name': 'Budi', 'text': 'Server msg'},
        );

        store.recordGroupActivity(
          groupId: 'g-1',
          createdAtUtc: meshNewerAt,
          snippet: 'Raka: Posisi aman via Mesh',
          senderId: 'u-other',
          messageId: 'mesh-1',
          markUnread: true,
        );

        // Event lebih lama tidak boleh menimpa timestamp terbaru.
        store.recordGroupActivity(
          groupId: 'g-1',
          createdAtUtc: staleAt,
          snippet: 'Pesan lama',
          senderId: 'u-other',
        );
        expect(store.groupPreview('g-1')?.createdAtUtc, meshNewerAt);
        expect(store.groupPreview('g-1')?.snippet, 'Raka: Posisi aman via Mesh');

        // refresh() dari server tidak menurunkan timestamp Mesh offline yang lebih baru.
        await store.refresh();
        expect(store.groupPreview('g-1')?.createdAtUtc, meshNewerAt);

        store.recordCommunityActivity(
          communityId: 'c-1',
          createdAtUtc: meshNewerAt,
          snippet: 'Dina: Jalur licin',
          senderId: 'u-dina',
          markUnread: true,
        );
        expect(store.communityPreview('c-1')?.createdAtUtc, meshNewerAt);
        expect(store.communityPreview('c-1')?.hasUnread, isTrue);
      },
    );

    testWidgets(
      'Daftar Grup di ChatPage otomatis menempatkan grup dengan pesan terbaru di paling atas saat pesan tiba',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final tCreated = DateTime.utc(2026, 11, 1);
        final g1 = GroupCardData(
          remote: RemoteGroup(
            group: Group(
              id: 'grp-lama',
              name: 'Grup Lawas',
              ownerId: 'u-1',
              createdAtUtc: tCreated,
            ),
            role: GroupRole.owner,
          ),
          memberCount: 3,
          lastMessageSnippet: 'Sudah lama',
          lastMessageAtUtc: DateTime.utc(2026, 11, 10, 8, 0),
        );
        final g2 = GroupCardData(
          remote: RemoteGroup(
            group: Group(
              id: 'grp-baru',
              name: 'Grup Aktif',
              ownerId: 'u-1',
              createdAtUtc: tCreated,
            ),
            role: GroupRole.owner,
          ),
          memberCount: 2,
          lastMessageSnippet: 'Kemarin',
          lastMessageAtUtc: DateTime.utc(2026, 11, 15, 8, 0),
        );

        final auth = FakeAuthService(
          currentUser: const AuthUser(
            id: 'u-1',
            email: 'a@example.com',
            provider: AuthProviderKind.google,
          ),
        );
        final controller = AccountController(
          authService: auth,
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List.fromList(List<int>.filled(32, 3))),
          clock: FakeClock(DateTime.utc(2026, 11, 22)),
        );
        final localStore = OffGridChatLocalStore();

        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: ChatPage(
              accountController: controller,
              localStore: localStore,
              initialOnline: true,
              initialLocalGroups: <GroupCardData>[g1, g2],
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Awalnya grp-baru di atas grp-lama.
        final yBaruInitial = tester
            .getTopLeft(find.byKey(const ValueKey<String>('group-card-grp-baru')))
            .dy;
        final yLamaInitial = tester
            .getTopLeft(find.byKey(const ValueKey<String>('group-card-grp-lama')))
            .dy;
        expect(yBaruInitial, lessThan(yLamaInitial));

        // Ada pesan baru masuk di grp-lama -> langsung loncat ke paling atas!
        SocialUnreadStore.instance.recordGroupActivity(
          groupId: 'grp-lama',
          createdAtUtc: DateTime.utc(2026, 11, 22, 12, 0),
          snippet: 'Andi: Baru saja naik',
          senderId: 'u-andi',
          markUnread: true,
        );
        await tester.pump();

        final yLamaAfter = tester
            .getTopLeft(find.byKey(const ValueKey<String>('group-card-grp-lama')))
            .dy;
        final yBaruAfter = tester
            .getTopLeft(find.byKey(const ValueKey<String>('group-card-grp-baru')))
            .dy;
        expect(yLamaAfter, lessThan(yBaruAfter));

        await tester.pumpWidget(const SizedBox());
        await localStore.dispose();
        controller.dispose();
        await auth.close();
      },
    );

    test(
      'OffGridChatLocalStore.latestMessagePerGroup mengembalikan pesan terbaru per grup',
      () async {
        final store = OffGridChatLocalStore();
        addTearDown(store.dispose);

        await store.insertMessageIfAbsent(
          GroupMessageRecord(
            clientMsgId: 'm-old',
            groupId: 'g-alpha',
            senderId: 'u-1',
            senderName: 'Budi',
            messageType: GroupMessageType.text,
            content: 'Pesan lama',
            clientCreatedAtUtc: DateTime.utc(2026, 11, 1, 9, 0),
          ),
        );
        await store.insertMessageIfAbsent(
          GroupMessageRecord(
            clientMsgId: 'm-new',
            groupId: 'g-alpha',
            senderId: 'u-2',
            senderName: 'Siti',
            messageType: GroupMessageType.text,
            content: 'Pesan paling baru',
            clientCreatedAtUtc: DateTime.utc(2026, 11, 1, 10, 30),
          ),
        );

        final latest = await store.latestMessagePerGroup();
        expect(latest['g-alpha']?.clientMsgId, 'm-new');
        expect(latest['g-alpha']?.content, 'Pesan paling baru');
      },
    );

    testWidgets(
      'SocialCommunityTab mengurutkan komunitas berdasarkan lastMessageAt lalu otomatis melompat ke atas saat pesan baru masuk',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final created = DateTime.utc(2026, 11, 1);
        CommunityService.instance.setCommunitiesForTesting(<CommunitySummary>[
          CommunitySummary(
            id: 'comm-old',
            name: 'Komunitas Lawas',
            description: 'Aktif minggu lalu',
            ownerId: 'u-1',
            memberCount: 5,
            isJoined: true,
            createdAt: created,
            lastMessageAt: DateTime.utc(2026, 11, 10, 8, 0),
          ),
          CommunitySummary(
            id: 'comm-fresh',
            name: 'Komunitas Hangat',
            description: 'Aktif kemarin',
            ownerId: 'u-1',
            memberCount: 8,
            isJoined: true,
            createdAt: created,
            lastMessageAt: DateTime.utc(2026, 11, 18, 8, 0),
          ),
        ]);
        addTearDown(CommunityService.instance.clearForAccountChange);

        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: const Scaffold(body: SocialCommunityTab()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          tester.getTopLeft(find.text('Komunitas Hangat')).dy,
          lessThan(tester.getTopLeft(find.text('Komunitas Lawas')).dy),
        );

        // Pesan baru masuk via Realtime di Komunitas Lawas -> otomatis naik ke posisi #1!
        SocialUnreadStore.instance.recordCommunityActivity(
          communityId: 'comm-old',
          createdAtUtc: DateTime.utc(2026, 11, 22, 15, 0),
          snippet: 'Siti: Kondisi cerah di pos 2',
          senderId: 'u-siti',
          markUnread: true,
        );
        await tester.pump();

        expect(
          tester.getTopLeft(find.text('Komunitas Lawas')).dy,
          lessThan(tester.getTopLeft(find.text('Komunitas Hangat')).dy),
        );
      },
    );
  });

  group('Wave E #11 — Kualitas kompresi Foto, Video, & Avatar HD', () {
    test('computeProportionalMaxDimensions menjaga proporsi dan batas 1920 px',
        () {
      expect(
        computeProportionalMaxDimensions(width: 4000, height: 3000),
        (width: 1920, height: 1440),
      );
      expect(
        computeProportionalMaxDimensions(width: 3000, height: 4000),
        (width: 1440, height: 1920),
      );
      expect(
        computeProportionalMaxDimensions(width: 1200, height: 900),
        (width: 1200, height: 900),
      );
    });

    test(
      'computeVideoCompressionProfile memakai 1080p untuk sumber HD pendek & 720p adaptif <= 25 MB (tanpa LowQuality)',
      () {
        final shortHd = computeVideoCompressionProfile(
          durationSec: 20,
          sourceWidth: 1920,
          sourceHeight: 1080,
        );
        expect(shortHd.targetShortSidePx, 1080);
        expect(shortHd.targetVideoBitrateBps, 3800000);
        expect(shortHd.maxBytes, 25 * 1024 * 1024);

        final longHd = computeVideoCompressionProfile(
          durationSec: 60,
          sourceWidth: 1920,
          sourceHeight: 1080,
        );
        expect(longHd.targetShortSidePx, 720);
        expect(longHd.targetVideoBitrateBps, greaterThanOrEqualTo(2500000));
        expect(longHd.targetVideoBitrateBps, lessThanOrEqualTo(4000000));
      },
    );

    test('Avatar 1080x1080 px WebP quality 89 & batas uploadCommunityVideo 25 MB',
        () async {
      final png = await _makePng(1600, 1200);
      int? capturedQuality;
      int? capturedSize;
      final out = await AvatarImageProcessor.cropSquareAndCompressWebp(
        png,
        webpEncoder: (bytes, size, quality) async {
          capturedSize = size;
          capturedQuality = quality;
          return bytes;
        },
      );
      expect(out, isNotEmpty);
      expect(capturedSize, 1080);
      expect(capturedQuality, 89);

      expect(R2MediaService.maxAvatarBytes, 2 * 1024 * 1024);
      expect(R2MediaService.maxCommunityVideoBytes, 25 * 1024 * 1024);

      final tmp = await Directory.systemTemp.createTemp('wave_e_vid_');
      addTearDown(() => tmp.delete(recursive: true));
      final rawFile = File('${tmp.path}/raw.mp4')
        ..writeAsBytesSync(Uint8List(128));
      final compressedFile = File('${tmp.path}/compressed.mp4')
        ..writeAsBytesSync(Uint8List(64));

      var compressorCalled = false;
      VideoCompressionProfile? seenProfile;
      Uint8List? uploadedBytes;

      final service = R2MediaService(
        nowMs: () => 1732200000000,
        videoDurationReader: (_) async => const Duration(seconds: 15),
        videoCompressor: (file, profile) async {
          compressorCalled = true;
          seenProfile = profile;
          return compressedFile;
        },
        presign: (body) async => <String, dynamic>{
          'uploadUrl': 'https://r2.example/up',
          'publicUrl': 'https://cdn.example/${body['objectKey']}',
        },
        put: (_, __, bytes) async {
          uploadedBytes = bytes;
          return 200;
        },
      );

      final uploaded = await service.uploadCommunityVideo(
        rawFile,
        communityId: '11111111-1111-4111-8111-111111111111',
        durationSec: 15,
      );
      expect(compressorCalled, isTrue);
      expect(seenProfile?.targetShortSidePx, greaterThanOrEqualTo(720));
      expect(uploadedBytes?.length, 64);
      expect(uploaded.contentType, 'video/mp4');
    });
  });

  group('Wave E #12 — Fullscreen Profile Photo Viewer + Liquid Glass + Original Quality',
      () {
    final samplePngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );

    testWidgets(
      'FullscreenAvatarViewerPage menampilkan latar gelap, InteractiveViewer, Liquid Glass pill nama + centang resmi, tanpa cacheWidth kecil',
      (tester) async {
        final tmp = await tester.runAsync(
          () => Directory.systemTemp.createTemp('wave_e_avatar_'),
        );
        addTearDown(() async {
          if (tmp != null && await tmp.exists()) {
            await tmp.delete(recursive: true);
          }
        });
        final file = File('${tmp!.path}/avatar_1080.png')
          ..writeAsBytesSync(samplePngBytes);

        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: FullscreenAvatarViewerPage(
              heroTag: profileAvatarHeroTag('other_hiqeo'),
              displayName: 'Hiqeo Official',
              localFile: file,
              isOfficial: true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(const ValueKey<String>('avatar-viewer-backdrop')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('avatar-viewer-interactive')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('avatar-viewer-back-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('avatar-viewer-header-pill')),
          findsOneWidget,
        );
        expect(find.text('Hiqeo Official'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('avatar-viewer-official-badge')),
          findsOneWidget,
        );
        expect(find.byType(OfficialVerifiedBadge), findsOneWidget);

        // Pastikan gambar resolusi penuh tidak dibatasi cacheWidth kecil.
        final img = tester.widget<Image>(
          find.byKey(const ValueKey<String>('avatar-viewer-image')),
        );
        expect(img.fit, BoxFit.contain);
        expect(img.image, isA<FileImage>());
      },
    );

    testWidgets(
      'Ketuk avatar pada OtherUserProfilePage dan ProfilPage membuka FullscreenAvatarViewerPage & tombol kembali menutupnya',
      (tester) async {
        final tmp = await tester.runAsync(
          () => Directory.systemTemp.createTemp('wave_e_prof_avatar_'),
        );
        addTearDown(() async {
          if (tmp != null && await tmp.exists()) {
            await tmp.delete(recursive: true);
          }
        });
        final localFile = File('${tmp!.path}/self_avatar.png')
          ..writeAsBytesSync(samplePngBytes);

        // 1. OtherUserProfilePage
        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: const OtherUserProfilePage(
              userId: 'hiqeo-official-id',
              initialName: 'Hiqeo Resmi',
              initialUsername: 'hiqeo',
              initialAvatarUrl: 'https://127.0.0.1:1/avatars/hiqeo.webp',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        await tester.tap(
          find.byKey(const ValueKey<String>('other-user-avatar-tap')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(FullscreenAvatarViewerPage), findsOneWidget);
        expect(find.text('Hiqeo Resmi'), findsWidgets);
        expect(
          find.byKey(const ValueKey<String>('avatar-viewer-official-badge')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('avatar-viewer-back-button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(FullscreenAvatarViewerPage), findsNothing);

        // 2. ProfilPage milik sendiri memakai foto lokal penuh
        final auth = FakeAuthService(
          currentUser: const AuthUser(
            id: 'u-self',
            email: 'self@example.com',
            provider: AuthProviderKind.google,
          ),
        );
        final profiles = FakeProfileRepository()
          ..current = UserProfile(
            userId: 'u-self',
            username: 'pendaki_self',
            fullName: 'Raka Sendiri',
            localAvatarPath: localFile.path,
            publicKeyBase64: base64Encode(List<int>.filled(32, 9)),
          );
        final controller = AccountController(
          authService: auth,
          profileRepository: profiles,
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List.fromList(List<int>.filled(32, 9))),
          clock: FakeClock(DateTime.utc(2026, 11, 22)),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: Scaffold(
              body: ProfilPage(
                accountController: controller,
                trackingRepository: _FakeHistoryTrackingRepo(const []),
                downloadedMountainCount: () async => 0,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        await tester.tap(find.byKey(const ValueKey<String>('profil-avatar-tap')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(FullscreenAvatarViewerPage), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('avatar-viewer-header-pill')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('avatar-viewer-official-badge')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('avatar-viewer-image')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await auth.close();
      },
    );
  });
}
