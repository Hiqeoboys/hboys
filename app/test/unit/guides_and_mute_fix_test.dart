import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/chat/presentation/chat_media_preview_page.dart';
import 'package:nama_app/features/chat/presentation/chat_room_chrome.dart';
import 'package:nama_app/features/guides/domain/beginner_guide_data.dart';
import 'package:nama_app/features/guides/domain/field_sketch_spec.dart';
import 'package:nama_app/features/guides/presentation/beginner_guide_page.dart';
import 'package:nama_app/features/guides/presentation/widgets/field_sketch_stepper.dart';
import 'package:nama_app/features/home/beginner_guide_home_card.dart';
import 'package:nama_app/features/safety/domain/first_aid_data.dart';
import 'package:nama_app/features/safety/presentation/first_aid_guide_page.dart';
import 'package:nama_app/features/social/data/chat_mute_service.dart';
import 'package:nama_app/features/social/data/community_service.dart';
import 'package:nama_app/features/social/presentation/community_chat_page.dart';
import 'package:nama_app/infrastructure/notifications/device_notification_group_store.dart';
import 'package:nama_app/infrastructure/notifications/push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PushNotificationService.instance.activeRoomType = null;
    PushNotificationService.instance.activeRoomId = null;
    PushNotificationService.instance.showNotificationForTesting = null;
    PushNotificationService.instance.cancelNotificationForTesting = null;
    await ChatMuteService.instance.clearLocal();
    await DeviceNotificationGroupStore.instance.clearAll();
  });

  tearDown(() {
    PushNotificationService.instance.showNotificationForTesting = null;
    PushNotificationService.instance.cancelNotificationForTesting = null;
  });

  group('Panduan Pemula Data & Technical Field Sketch Mapping', () {
    test('berisi 3 bab, 9 topik, 3-5 langkah bergambar tanpa kuis & tanpa em dash', () {
      expect(kBeginnerChapters, hasLength(3));
      expect(kBeginnerGuideTopics, hasLength(9));

      for (final ch in kBeginnerChapters) {
        expect(ch.title, isNot(contains('—')));
        expect(ch.subtitle, isNot(contains('—')));
      }

      for (final topic in kBeginnerGuideTopics) {
        expect(topic.title, isNot(contains('—')));
        expect(topic.summary, isNot(contains('—')));
        if (!topic.isInteractiveTent) {
          expect(topic.steps.length, inInclusiveRange(3, 5));
          for (final step in topic.steps) {
            expect(step.title, isNot(contains('—')));
            expect(step.instruction, isNot(contains('—')));
            expect(step.tip ?? '', isNot(contains('—')));
            expect(step.warning ?? '', isNot(contains('—')));
          }
        }
      }
    });

    test('pemilih tenda memadukan reuse sketsa per ukuran & ganti konstruksi per jenis', () {
      final domeSolo = buildTentPitchingSteps(
        TentType.domeCross,
        TentSizeCategory.soloDuo1to2,
      );
      final domeSmall = buildTentPitchingSteps(
        TentType.domeCross,
        TentSizeCategory.smallGroup3to4,
      );
      final domeFamily = buildTentPitchingSteps(
        TentType.domeCross,
        TentSizeCategory.family4to6,
      );

      // Ukuran berubah pada jenis tenda sama -> sketsa vektor dasar yang sama dipakai ulang
      expect(
        domeSolo.map((s) => s.sketchId).toList(),
        equals(domeSmall.map((s) => s.sketchId).toList()),
      );
      expect(
        domeSolo.map((s) => s.sketchId).toList(),
        equals(domeFamily.map((s) => s.sketchId).toList()),
      );

      // Namun overlay & anotasi dinamis menyesuaikan kapasitas
      expect(domeSolo[2].overlay?.personBadge, '1 orang');
      expect(domeSmall[2].overlay?.personBadge, '2 orang saat tegakkan frame');
      expect(domeFamily[2].overlay?.personBadge, '2-3 orang saat tegakkan frame');
      expect(domeSolo[1].overlay?.showVestibuleRidgePole, isFalse);
      expect(domeSmall[1].overlay?.showVestibuleRidgePole, isTrue);
      expect(domeFamily[3].overlay?.showExtraStormGuys, isTrue);

      // Mengganti jenis tenda menghasilkan konstruksi dan sketsa yang berbeda
      final tunnelSteps = buildTentPitchingSteps(
        TentType.tunnel,
        TentSizeCategory.smallGroup3to4,
      );
      final trekkingPoleSteps = buildTentPitchingSteps(
        TentType.trekkingPole,
        TentSizeCategory.soloDuo1to2,
      );
      final domeHubSteps = buildTentPitchingSteps(
        TentType.domeHub,
        TentSizeCategory.soloDuo1to2,
      );

      expect(tunnelSteps.first.sketchId, FieldSketchId.tunnelStep1RearStake);
      expect(
        trekkingPoleSteps.first.sketchId,
        FieldSketchId.trekkingPoleStep1FourCorners,
      );
      expect(domeHubSteps.first.sketchId, FieldSketchId.domeHubStep1HubAssemble);

      // Semua jenis tenda wajib memiliki close-up pasak 45 derajat
      for (final list in <List<GuideStep>>[
        domeSolo,
        domeHubSteps,
        tunnelSteps,
        trekkingPoleSteps,
      ]) {
        expect(list.last.sketchId, FieldSketchId.tentStake45Vs90);
      }
    });
  });

  group('Panduan Keselamatan & Survival Data', () {
    test('seluruh 10 topik P3K lama utuh + 6 topik baru Wilderness Survival lengkap', () {
      expect(kFirstAidTopics, hasLength(10));
      expect(kWildernessSurvivalTopics, hasLength(6));
      expect(kAllSafetyTopics, hasLength(16));
      expect(kFirstAidCategories, contains('Survival & Tersesat'));

      for (final topic in kAllSafetyTopics) {
        expect(topic.dangerSigns, isNotEmpty);
        expect(topic.firstAidSteps, isNotEmpty);
        expect(topic.prohibitionsAndMyths, isNotEmpty);
        expect(
          topic.stepSketches.length,
          topic.firstAidSteps.length,
          reason: 'Tiap langkah pada ${topic.id} harus punya 1 sketsa teknis',
        );
      }

      for (final s in kWildernessSurvivalTopics) {
        expect(s.isSurvivalChapter, isTrue);
        expect(s.category, 'Survival & Tersesat');
        expect(s.title, isNot(contains('—')));
        expect(s.summary, isNot(contains('—')));
      }
    });
  });

  group('Widget UI: Beranda Card, BeginnerGuidePage, Zoom & FirstAidGuidePage', () {
    testWidgets('BeginnerGuideHomeCard menampilkan pratinjau, ringkasan & tombol tanpa 3 pintasan', (tester) async {
      var openedAll = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: BeginnerGuideHomeCard(
                onOpenAll: () => openedAll = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PANDUAN OFFLINE GRATIS'), findsNothing);
      expect(find.text('Panduan Pemula'), findsOneWidget);
      expect(find.text('Dirikan Tenda'), findsNothing);
      expect(find.text('Susun Carrier'), findsNothing);
      expect(find.text('Lapis Pakaian'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('home-guide-shortcut-tent')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('home-guide-shortcut-carrier')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('home-guide-shortcut-layering')),
        findsNothing,
      );
      expect(find.text('Buka Panduan Lengkap'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('home-guide-open-all')));
      expect(openedAll, isTrue);
    });

    testWidgets('BeginnerGuidePage akordeon auto-close hanya membuka 1 topik & memutar ikon chevron', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: const BeginnerGuidePage(),
        ),
      );
      await tester.pumpAndSettle();

      final t1 = kBeginnerGuideTopics[0].id;
      final t2 = kBeginnerGuideTopics[1].id;

      // Keadaan awal tertutup semua
      expect(
        tester
            .widget<AnimatedRotation>(
              find.byKey(ValueKey<String>('beginner-topic-chevron-$t1')),
            )
            .turns,
        0.0,
      );
      expect(
        tester
            .widget<AnimatedRotation>(
              find.byKey(ValueKey<String>('beginner-topic-chevron-$t2')),
            )
            .turns,
        0.0,
      );

      // Buka topik 1 -> chevron berputar 180 derajat (0.5 turn)
      await tester.tap(find.byKey(ValueKey<String>('beginner-topic-toggle-$t1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedRotation>(
              find.byKey(ValueKey<String>('beginner-topic-chevron-$t1')),
            )
            .turns,
        0.5,
      );

      // Buka topik 2 -> topik 1 otomatis menutup
      final toggle2 = find.byKey(ValueKey<String>('beginner-topic-toggle-$t2'));
      await tester.ensureVisible(toggle2);
      await tester.pumpAndSettle();
      await tester.tap(toggle2);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<AnimatedRotation>(
              find.byKey(ValueKey<String>('beginner-topic-chevron-$t1')),
            )
            .turns,
        0.0,
      );
      expect(
        tester
            .widget<AnimatedRotation>(
              find.byKey(ValueKey<String>('beginner-topic-chevron-$t2')),
            )
            .turns,
        0.5,
      );

      // Ketuk ulang topik 2 -> menutup kembali
      await tester.ensureVisible(toggle2);
      await tester.pumpAndSettle();
      await tester.tap(toggle2);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedRotation>(
              find.byKey(ValueKey<String>('beginner-topic-chevron-$t2')),
            )
            .turns,
        0.0,
      );
    });

    testWidgets('BeginnerGuidePage membuka topik tenda, mengganti jenis/ukuran, & Tap-to-Zoom InteractiveViewer', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final theme in <ThemeData>[hiqeoLightTheme, hiqeoDarkTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: BeginnerGuidePage(
              key: ValueKey<String>('guide-${theme.brightness.name}'),
              initialTopicId: 'pitch_tent',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('100% Gratis & Bisa Dibaca Offline'), findsNothing);
        expect(find.textContaining('Ketuk tiap diagram teknis'), findsNothing);
        expect(find.text('Pilih Jenis Tenda'), findsOneWidget);
        expect(find.text('1 orang'), findsAtLeastNWidgets(1));

        // Ubah ukuran menjadi 3-4 Orang -> overlay & label berubah dinamis
        final sizeBtn = find.byKey(
          const ValueKey<String>('tent-size-smallGroup3to4'),
        );
        await tester.ensureVisible(sizeBtn);
        await tester.pumpAndSettle();
        await tester.tap(sizeBtn);
        await tester.pumpAndSettle();
        expect(find.text('2 orang saat tegakkan frame'), findsAtLeastNWidgets(1));

        // Ubah jenis menjadi Tunnel
        final tunnelBtn = find.byKey(const ValueKey<String>('tent-type-tunnel'));
        await tester.ensureVisible(tunnelBtn);
        await tester.pumpAndSettle();
        await tester.tap(tunnelBtn);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Pasak Kuat Ujung Ekor Belakang'),
          findsAtLeastNWidgets(1),
        );

        // Tap-to-Zoom pada kanvas langkah
        final zoomCanvas = find.byType(FieldSketchCanvas).first;
        await tester.ensureVisible(zoomCanvas);
        await tester.pumpAndSettle();
        await tester.tap(zoomCanvas);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('field-sketch-interactive-viewer')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('field-sketch-zoom-close')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('field-sketch-interactive-viewer')),
          findsNothing,
        );
      }
    });

    testWidgets('FirstAidGuidePage mempertahankan P3K lama, kategori Survival, & deck sketsa per langkah', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: const FirstAidGuidePage(),
        ),
      );
      await tester.pumpAndSettle();

      // Tombol SOS tunggal tetap ada
      expect(find.byKey(const ValueKey<String>('p3k-sos-button')), findsOneWidget);

      // Filter kategori Survival & Tersesat
      final survivalFilter =
          find.byKey(const ValueKey<String>('p3k-category-Survival & Tersesat'));
      await tester.scrollUntilVisible(
        survivalFilter,
        120,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey<String>('p3k-category-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.drag(
        find.byKey(const ValueKey<String>('p3k-category-list')),
        const Offset(-160, 0),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(survivalFilter);
      await tester.pumpAndSettle();
      await tester.tap(survivalFilter);
      await tester.pumpAndSettle();

      expect(
        find.text('Prinsip STOP & Aturan Emas 3 Jam Pertama'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('p3k-topic-survival_stop_3jam')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Langkah 1/4'), findsOneWidget);
      final nextStepBtn = find.bySemanticsLabel('Langkah berikutnya');
      await tester.ensureVisible(nextStepBtn);
      await tester.pumpAndSettle();
      await tester.tap(nextStepBtn);
      await tester.pumpAndSettle();
      expect(find.text('Langkah 2/4'), findsOneWidget);
    });
  });

  group('Fix Bug Mute Grup & Komunitas (Foreground, Background, & Offline Mesh)', () {
    test('ChatMuteService menyimpan partisi per user_id & tahan refresh server saat offline pending', () async {
      var syncShouldFail = true;
      final svc = ChatMuteService(
        userIdProvider: () => 'user-A',
        remoteUpsert: (_, __, ___, ____) async {
          if (syncShouldFail) throw Exception('offline');
        },
        remoteFetchAll: (_) async => const <Map<String, dynamic>>[],
      );

      await svc.muteForever('group', 'GRP-1');
      expect(svc.isMuted('group', 'grp-1'), isTrue);
      expect(svc.mutedGroupIds, contains('grp-1'));

      // Saat refresh server gagal kirim pending, mute lokal TIDAK boleh terhapus
      await svc.loadAll(forceRemote: true);
      expect(svc.isMuted('group', 'grp-1'), isTrue);

      // Simulasi background isolate baru membaca ulang SharedPreferences untuk user-A
      final isolateSvc = ChatMuteService(
        userIdProvider: () => 'user-A',
        remoteUpsert: (_, __, ___, ____) async {},
        remoteFetchAll: (_) async => const <Map<String, dynamic>>[],
      );
      await isolateSvc.ensureLoaded(forceReload: true);
      expect(isolateSvc.isMuted('group', 'grp-1'), isTrue);
    });

    test('PushNotificationService memblokir 100% pesan, mention, & mesh pada grup/komunitas yang dibisukan, tapi meloloskan SOS', () async {
      final shown = <({int id, String title})>[];
      PushNotificationService.instance.showNotificationForTesting = ({
        required int id,
        required String title,
        required String body,
        required NotificationDetails details,
        required String payload,
      }) async {
        shown.add((id: id, title: title));
      };
      PushNotificationService.instance.cancelNotificationForTesting = (_) async {};

      const mutedGroupId = 'grp-muted-99';
      const mutedCommId = 'comm-muted-88';
      await ChatMuteService.instance.muteFor(
        'group',
        mutedGroupId,
        const Duration(days: 1),
      );
      await ChatMuteService.instance.muteFor(
        'community',
        mutedCommId,
        const Duration(days: 7),
      );

      // 1. Background FCM handler (isolate terpisah) -> DILARANG tampil
      await PushNotificationService.instance.handleBackgroundRemoteMessage(
        const RemoteMessage(
          messageId: 'bg-grp-1',
          data: <String, dynamic>{
            'type': 'group_chat',
            'group_id': mutedGroupId,
            'room_type': 'group',
            'room_id': mutedGroupId,
            'room_name': 'Grup Merapi',
            'sender_id': 'u-other',
            'sender_name': 'Dito',
            'message_text': 'Halo',
          },
        ),
      );
      await PushNotificationService.instance.handleBackgroundRemoteMessage(
        const RemoteMessage(
          messageId: 'bg-comm-mention-1',
          data: <String, dynamic>{
            'type': 'community_mention',
            'community_id': mutedCommId,
            'room_type': 'community',
            'room_id': mutedCommId,
            'room_name': 'Komunitas Lawu',
            'sender_id': 'u-other',
            'sender_name': 'Dito',
            'message_text': '@kamu cek info',
          },
        ),
      );
      expect(shown, isEmpty);

      // 2. Direct showLocalNotification() guard -> DILARANG tampil
      await PushNotificationService.instance.showLocalNotification(
        InAppPushNotification.fromRemoteData(
          id: 'fg-comm-1',
          data: const <String, dynamic>{
            'type': 'community_chat',
            'community_id': mutedCommId,
            'sender_id': 'u-other',
            'sender_name': 'Sari',
            'message_text': 'Pesan baru',
          },
        ),
      );
      expect(shown, isEmpty);

      // 3. Offline Mesh message pada grup yang dibisukan -> DILARANG tampil
      await PushNotificationService.instance.showOfflineMeshMessageNotification(
        record: GroupMessageRecord(
          clientMsgId: 'mesh-1',
          groupId: mutedGroupId,
          senderId: 'u-other',
          senderName: 'Bima',
          messageType: GroupMessageType.text,
          content: 'Sudah di pos 3',
          originTransport: ChatTransportOrigin.bleMesh,
          syncStatus: ChatSyncStatus.pending,
          clientCreatedAtUtc: DateTime.utc(2026, 11, 23, 2, 0),
        ),
        groupName: 'Grup Merapi',
        currentUserId: 'u-me',
      );
      expect(shown, isEmpty);

      // 4. Pengecualian keselamatan: sinyal darurat SOS tetap tembus meskipun grup dibisukan!
      await PushNotificationService.instance.handleBackgroundRemoteMessage(
        const RemoteMessage(
          messageId: 'bg-sos-1',
          data: <String, dynamic>{
            'type': 'sos',
            'group_id': mutedGroupId,
            'sos_id': 'sos-777',
            'sender_id': 'u-other',
            'sender_name': 'Bima',
          },
        ),
      );
      expect(shown, hasLength(1));
      expect(shown.single.title, 'DARURAT SOS HIQEO');
    });
  });

  group('Real Guide Assets, Chat Media Preview & Caption Bubble', () {
    test('seluruh FieldSketchId memetakan slug unik assets/guides/*.webp tanpa duplikat', () {
      final paths = FieldSketchId.values.map((e) => e.assetPath).toList();
      expect(paths, hasLength(102));
      expect(paths.toSet(), hasLength(102));
      for (final p in paths) {
        expect(p, matches(RegExp(r'^assets/guides/[a-z0-9_]+\.webp$')));
      }
    });

    testWidgets('FieldSketchCanvas merender Image.asset + overlay tenda + Zoom tanpa CustomPainter stickman', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: FieldSketchCanvas(
                sketchId: FieldSketchId.domeCrossStep2PolesX,
                overlay: FieldSketchOverlay(
                  personBadge: '2 orang saat tegakkan frame',
                  stakesBadge: 'Min. 6-8 pasak',
                  guylineSpanLabel: 'Rentang guyline 1,5 m',
                  showVestibuleRidgePole: true,
                  showExtraStormGuys: false,
                  sizeTag: '3-4P',
                ),
                stepTitle: 'Rangkai 2 Frame Silang',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('3-4P'), findsOneWidget);
      expect(find.text('+ Ridge Pole'), findsOneWidget);

      await tester.tap(find.byType(FieldSketchCanvas));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('field-sketch-interactive-viewer')),
        findsOneWidget,
      );
    });

    testWidgets('ChatMediaPreviewPage menampilkan InteractiveViewer, pil keterangan putih solid, & mengembalikan caption', (tester) async {
      CapturedMediaSubmission? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoDarkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context)
                        .push<CapturedMediaSubmission>(
                      MaterialPageRoute<CapturedMediaSubmission>(
                        builder: (_) => ChatMediaPreviewPage(
                          file: File('/tmp/nonexistent_preview.webp'),
                          isVideo: false,
                        ),
                      ),
                    );
                  },
                  child: const Text('Buka Preview'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka Preview'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('media-preview-interactive-viewer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('media-preview-back')),
        findsOneWidget,
      );
      expect(find.text('Tambahkan keterangan...'), findsOneWidget);
      expect(
        find.byType(ChatSolidComposerPill),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('media-preview-caption-input')),
        'Pos 3 sudah cerah!',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('media-preview-send')),
      );
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isVideo, isFalse);
      expect(result!.caption, 'Pos 3 sudah cerah!');
    });

    testWidgets('Bubble foto komunitas memakai badge waktu di sudut saat tanpa caption & menaruhnya di bawah teks saat ada caption', (tester) async {
      final community = CommunitySummary(
        id: 'comm-cap',
        name: 'Pendaki Jawa',
        description: 'Info jalur',
        ownerId: 'u-1',
        memberCount: 5,
        isJoined: true,
        createdAt: DateTime.utc(2026, 11, 1),
      );
      final messages = <CommunityMessage>[
        CommunityMessage(
          id: 'img-no-cap',
          communityId: 'comm-cap',
          senderId: 'u-1',
          senderName: 'Raka',
          messageType: CommunityMessageType.image,
          mediaUrl: 'local_missing_1.webp',
          content: null,
          createdAt: DateTime.utc(2026, 11, 22, 8, 10),
        ),
        CommunityMessage(
          id: 'img-with-cap',
          communityId: 'comm-cap',
          senderId: 'u-1',
          senderName: 'Raka',
          messageType: CommunityMessageType.image,
          mediaUrl: 'local_missing_2.webp',
          content: 'Pemandangan sunrise Pos 4',
          createdAt: DateTime.utc(2026, 11, 22, 8, 12),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoDarkTheme,
          home: CommunityChatPage(
            community: community,
            currentUserIdOverride: 'u-1',
            initialMessages: messages,
            hasFullSocialOverride: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final noCapBadge = tester.widget<Container>(
        find.byKey(const ValueKey<String>('community-photo-time-img-no-cap')),
      );
      expect(
        (noCapBadge.decoration! as BoxDecoration).color,
        ChatMediaTimestampBadge.backgroundColor,
      );
      expect(
        find.byKey(const ValueKey<String>('community-photo-time-img-with-cap')),
        findsNothing,
      );
      expect(find.text('Pemandangan sunrise Pos 4'), findsOneWidget);
    });
  });
}
