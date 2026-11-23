import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/glass/hiqeo_liquid_glass.dart';
import 'package:nama_app/design/widgets/hiqeo_back_button.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/features/social/data/community_media_tools.dart';
import 'package:nama_app/features/social/data/community_service.dart';
import 'package:nama_app/features/social/presentation/community_chat_page.dart';
import 'package:nama_app/features/social/presentation/community_media_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PNG transparan 1x1 valid untuk pengujian render Image.memory tanpa jaringan.
final Uint8List _kSamplePngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NavBarVisibilityController.instance.reset();
  });

  group('Unit: durasi video, ukuran adaptif & disk cache thumbnail', () {
    test('computeVideoRemainingSeconds membulatkan naik lalu kembali ke total saat selesai', () {
      const total = Duration(seconds: 15);
      expect(
        formatVideoRemainingBadge(
          total: total,
          position: Duration.zero,
          isPlaying: true,
        ),
        '15 dtk',
      );
      expect(
        formatVideoRemainingBadge(
          total: total,
          position: const Duration(milliseconds: 200),
          isPlaying: true,
        ),
        '15 dtk',
      );
      expect(
        formatVideoRemainingBadge(
          total: total,
          position: const Duration(milliseconds: 1001),
          isPlaying: true,
        ),
        '14 dtk',
      );
      expect(
        formatVideoRemainingBadge(
          total: total,
          position: const Duration(milliseconds: 14900),
          isPlaying: true,
        ),
        '1 dtk',
      );
      expect(
        formatVideoRemainingBadge(
          total: total,
          position: total,
          isPlaying: true,
        ),
        '0 dtk',
      );
      // Berhenti di akhir -> kembali ke total durasi asli
      expect(
        formatVideoRemainingBadge(
          total: total,
          position: total,
          isPlaying: false,
        ),
        '15 dtk',
      );
      // >= 60 detik memakai format m:ss
      expect(
        formatVideoRemainingBadge(
          total: const Duration(seconds: 65),
          position: Duration.zero,
          isPlaying: false,
        ),
        '1:05',
      );
    });

    test('computeAdaptiveMediaBoxSize menghormati maxWidth dan rentang tinggi [140, 340]', () {
      const maxW = 390 * 0.74;
      final portrait = computeAdaptiveMediaBoxSize(
        maxWidth: maxW,
        aspectRatio: 9 / 16,
      );
      expect(portrait.height, lessThanOrEqualTo(340));
      expect(portrait.height, greaterThanOrEqualTo(140));
      expect(portrait.width, lessThanOrEqualTo(maxW));

      final landscape = computeAdaptiveMediaBoxSize(
        maxWidth: maxW,
        aspectRatio: 16 / 9,
      );
      expect(landscape.width, closeTo(maxW, 0.01));
      expect(landscape.height, closeTo(maxW / (16 / 9), 0.5));

      final ultraWide = computeAdaptiveMediaBoxSize(
        maxWidth: maxW,
        aspectRatio: 4.0,
      );
      expect(ultraWide.height, 140.0);
    });

    test('CommunityVideoThumbnailCache persisten di disk lintas sesi & fallback extractor', () async {
      final tempDir = await Directory.systemTemp.createTemp('hiqeo_thumb_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      var extractCalls = 0;
      final writerCache = CommunityVideoThumbnailCache(
        directoryProvider: () async => tempDir,
        httpFetcher: (_) async => null,
        nativeExtractor: (_) async {
          extractCalls++;
          return _kSamplePngBytes;
        },
      );

      final first = await writerCache.resolveThumbnail(
        videoUrl: 'https://cdn.example.com/v1.mp4',
        messageId: 'vid-1',
      );
      expect(first, equals(_kSamplePngBytes));
      expect(extractCalls, 1);

      // Simulasi instance baru setelah keluar & membuka ulang chat room:
      // pembacaan langsung sukses dari disk tanpa memanggil ulang jaringan/ekstraktor.
      final freshCache = CommunityVideoThumbnailCache(
        directoryProvider: () async => tempDir,
        httpFetcher: (_) async => fail('Tidak boleh unduh ulang saat disk hit'),
        nativeExtractor: (_) async => fail('Tidak boleh ekstrak ulang saat disk hit'),
      );
      final hit = await freshCache.resolveThumbnail(
        videoUrl: 'https://cdn.example.com/v1.mp4',
        messageId: 'vid-1',
      );
      expect(hit, equals(_kSamplePngBytes));
    });
  });

  group('Widget: Community Chat Media & Fullscreen Liquid Glass Viewer', () {
    testWidgets(
        'Header pill memiliki textShadow halus & foto bubble memakai BoxFit.cover + Hero -> buka viewer fullscreen',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync('hiqeo_photo_test_');
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        try {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        } catch (_) {}
      });
      final photoFile = File('${tempDir.path}/photo.png')
        ..writeAsBytesSync(_kSamplePngBytes, flush: true);

      final community = CommunitySummary(
        id: 'comm-media-1',
        name: '7 Summit Indonesia',
        description: 'Info jalur & cuaca',
        ownerId: 'owner-1',
        memberCount: 32,
        isJoined: true,
        createdAt: DateTime.utc(2026, 11, 1),
      );
      final photoMsg = CommunityMessage(
        id: 'msg-photo-1',
        communityId: community.id,
        senderId: 'user-raka',
        senderName: 'Raka Pratama',
        messageType: CommunityMessageType.image,
        mediaUrl: photoFile.path,
        createdAt: DateTime.utc(2026, 11, 20, 6, 37),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 24, bottom: 20),
            ),
            child: CommunityChatPage(
              community: community,
              initialMessages: <CommunityMessage>[photoMsg],
              hasFullSocialOverride: true,
              currentUserIdOverride: 'me-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header pill title memiliki subtle textShadow agar terbaca di atas media terang
      final titleWidget = tester.widget<Text>(find.text('7 Summit Indonesia'));
      expect(titleWidget.style?.shadows, isNotEmpty);

      // Foto bubble mengisi bingkai ClipRRect dengan BoxFit.cover dan dibungkus Hero
      final imgFinder = find.descendant(
        of: find.byKey(const ValueKey<String>('community-photo-frame-msg-photo-1')),
        matching: find.byType(Image),
      );
      expect(imgFinder, findsOneWidget);
      expect(tester.widget<Image>(imgFinder).fit, BoxFit.cover);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('community-photo-frame-msg-photo-1')),
          matching: find.byWidgetPredicate(
            (w) => w is Hero && w.tag == communityMediaHeroTag('msg-photo-1'),
          ),
        ),
        findsOneWidget,
      );

      // Ketuk foto membuka CommunityMediaViewerPage layar penuh (#000000)
      await tester.tap(
        find.byKey(const ValueKey<String>('community-photo-frame-msg-photo-1')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CommunityMediaViewerPage), findsOneWidget);
      final backdrop = tester.widget<ColoredBox>(
        find.byKey(const ValueKey<String>('media-viewer-backdrop')),
      );
      expect(backdrop.color, Colors.black);
    });

    testWidgets(
        'CommunityMediaViewerPage foto: InteractiveViewer 4x, header 3-elemen Liquid Glass, dropdown 12px di bawah hamburger, & single-tap toggle opacity',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final createdUtc = DateTime(2026, 11, 20, 6, 37).toUtc();
      final msg = CommunityMessage(
        id: 'm-full-1',
        communityId: 'comm-1',
        senderId: 'other-user',
        senderName: 'Bima Sakti',
        messageType: CommunityMessageType.image,
        mediaUrl: 'https://example.com/puncak.webp',
        createdAt: createdUtc,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 24, bottom: 20),
            ),
            child: CommunityMediaViewerPage(
              message: msg,
              currentUserId: 'me-1',
              nowUtcOverride: createdUtc,
              photoChildBuilder: (_) => Image.memory(
                _kSamplePngBytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // InteractiveViewer mendukung zoom hingga 4x
      final viewer = tester.widget<InteractiveViewer>(
        find.byKey(const ValueKey<String>('media-viewer-interactive')),
      );
      expect(viewer.maxScale, 4.0);
      expect(viewer.minScale, 1.0);

      // 3 elemen header: tombol back, pil info nama + waktu, tombol hamburger
      expect(
        find.byKey(const ValueKey<String>('media-viewer-back-button')),
        findsOneWidget,
      );
      expect(find.byType(HiqeoBackButton), findsOneWidget);
      final headerPillFinder =
          find.byKey(const ValueKey<String>('media-viewer-header-pill'));
      expect(headerPillFinder, findsOneWidget);
      expect(
        tester.widget<HiqeoLiquidGlassSurface>(headerPillFinder).borderRadius,
        28,
      );
      expect(find.text('Bima Sakti'), findsOneWidget);
      expect(find.text('Hari ini · 06:37'), findsOneWidget);

      final menuBtnFinder =
          find.byKey(const ValueKey<String>('media-viewer-hamburger-button'));
      expect(menuBtnFinder, findsOneWidget);
      expect(
        tester.widget<HiqeoGlassCircleButton>(menuBtnFinder),
        isA<HiqeoGlassCircleButton>(),
      );

      // Ketuk hamburger -> dropdown tampil tepat 12 px di bawah header
      await tester.tap(menuBtnFinder);
      await tester.pumpAndSettle();

      final dropdownFinder =
          find.byKey(const ValueKey<String>('media-viewer-dropdown-menu'));
      expect(dropdownFinder, findsOneWidget);
      final menuBtnRect = tester.getRect(menuBtnFinder);
      final dropdownRect = tester.getRect(dropdownFinder);
      expect(dropdownRect.top - menuBtnRect.bottom, closeTo(12.0, 6.0));
      expect(find.text('Simpan ke galeri'), findsOneWidget);
      expect(find.text('Bagikan'), findsOneWidget);
      expect(find.text('Laporkan media'), findsOneWidget);

      // Tutup dropdown lalu ketuk kosong untuk menyembunyikan chrome (AnimatedOpacity)
      await tester.tapAt(const Offset(20, 400));
      await tester.pumpAndSettle();
      expect(dropdownFinder, findsNothing);

      await tester.tapAt(const Offset(195, 420));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final headerOpacity = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey<String>('media-viewer-header-opacity')),
      );
      expect(headerOpacity.opacity, 0.0);
    });

    testWidgets(
        'Video bubble merender thumbnail dari memory/disk cache seketika & viewer video menampilkan kontrol + Laporkan disembunyikan untuk pengirim sendiri',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Isi cache disk/memori lokal agar cover video tampil langsung saat masuk ulang chat
      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('hiqeo_vid_widget_'),
      );
      addTearDown(() async {
        if (tempDir != null && await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final thumbCache = CommunityVideoThumbnailCache(
        directoryProvider: () async => tempDir!,
      );
      const videoUrl = 'https://example.com/cached_clip.mp4';
      await tester.runAsync(
        () => thumbCache.saveBytes(videoUrl, _kSamplePngBytes),
      );

      final community = CommunitySummary(
        id: 'comm-vid-1',
        name: 'Pendaki Merbabu',
        description: 'Update kondisi',
        ownerId: 'owner-1',
        memberCount: 15,
        isJoined: true,
        createdAt: DateTime.utc(2026, 11, 1),
      );
      final videoMsg = CommunityMessage(
        id: 'msg-vid-1',
        communityId: community.id,
        senderId: 'me-1',
        senderName: 'Saya',
        messageType: CommunityMessageType.video,
        mediaUrl: videoUrl,
        mediaDurationSec: 12,
        createdAt: DateTime.utc(2026, 11, 20, 7, 11),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 24, bottom: 20),
            ),
            child: CommunityChatPage(
              community: community,
              initialMessages: <CommunityMessage>[videoMsg],
              hasFullSocialOverride: true,
              currentUserIdOverride: 'me-1',
              thumbnailCache: thumbCache,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Thumbnail video terender lewat Image (bukan kotak hitam polos!) & lencana durasi 12 dtk
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('community-video-card-msg-vid-1')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('community-video-duration-msg-vid-1')),
          matching: find.text('12 dtk'),
        ),
        findsOneWidget,
      );

      // Buka viewer video langsung -> kontrol pemutar tampil & 'Laporkan media' disembunyikan untuk pengirim sendiri
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 24, bottom: 20),
            ),
            child: CommunityMediaViewerPage(
              message: videoMsg,
              currentUserId: 'me-1',
              initialThumbnailBytes: _kSamplePngBytes,
              thumbnailCache: thumbCache,
              videoControllerBuilder: (_) => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('media-viewer-play-pause')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('media-viewer-scrubber')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('media-viewer-mute')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('media-viewer-video-remaining')),
          matching: find.text('12 dtk'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('media-viewer-hamburger-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Simpan ke galeri'), findsOneWidget);
      expect(find.text('Bagikan'), findsOneWidget);
      expect(find.text('Laporkan media'), findsNothing);
    });
  });
}
