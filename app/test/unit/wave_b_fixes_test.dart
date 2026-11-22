import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/glass/hiqeo_liquid_glass.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/design/widgets/persistent_media_image.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/preparation/presentation/siap_naik_page.dart';
import 'package:nama_app/features/social/data/community_service.dart';
import 'package:nama_app/features/social/presentation/community_chat_page.dart';
import 'package:nama_app/infrastructure/cache/avatar_disk_cache.dart';
import 'package:nama_app/infrastructure/cache/hiqeo_media_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

final Uint8List _kSamplePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _StubAccount extends AccountController {
  _StubAccount(this.fixedGroup)
      : super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'u-1'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  final RemoteGroup fixedGroup;

  @override
  void initialize() {}

  @override
  UserProfile? get profile => const UserProfile(
        userId: 'u-1',
        username: 'rani',
        publicKeyBase64: 'pk',
      );

  @override
  AuthUser? get user => const AuthUser(id: 'u-1');

  @override
  List<RemoteGroup> get groups => <RemoteGroup>[fixedGroup];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NavBarVisibilityController.instance.reset();
    GroupHikePlanStore.setInstanceForTesting(null);
  });

  group('Wave B #1, #2 & #9: Launcher icons, version sync, & Codemagic', () {
    test('pubspec.yaml, Android XML, iOS Info.plist, & codemagic.yaml tersinkronisasi', () async {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('version: 0.1.0+2'));
      expect(pubspec, contains('ios: true'));
      expect(pubspec, contains('remove_alpha_ios: true'));
      expect(pubspec, contains('adaptive_icon_background: "#242B40"'));
      expect(
        pubspec,
        contains(
          'adaptive_icon_foreground: "assets/brand/hiqeo_launcher_foreground.png"',
        ),
      );
      expect(pubspec, contains('adaptive_icon_foreground_inset: 0'));

      final icLauncherXml = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      expect(icLauncherXml, contains('android:inset="0%"'));

      final colorsXml = File(
        'android/app/src/main/res/values/colors.xml',
      ).readAsStringSync();
      expect(colorsXml, contains('#242B40'));

      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains(r'$(FLUTTER_BUILD_NAME)'));
      expect(plist, contains(r'$(FLUTTER_BUILD_NUMBER)'));

      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('versionCode = flutter.versionCode'));
      expect(gradle, contains('versionName = flutter.versionName'));

      final rootCodemagic = File('../codemagic.yaml').readAsStringSync();
      final appCodemagic = File('codemagic.yaml').readAsStringSync();
      expect(rootCodemagic, contains('ENV_FILE_BASE64'));
      expect(appCodemagic, contains('ENV_FILE_BASE64'));
      expect(rootCodemagic, contains('GOOGLE_SERVICE_INFO_PLIST_BASE64'));
      expect(appCodemagic, contains('GOOGLE_SERVICE_INFO_PLIST_BASE64'));

      for (final assetPath in <String>[
        'assets/brand/hiqeo_launcher_foreground.png',
        'assets/brand/hiqeo_launcher_ios.png',
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
      ]) {
        final file = File(assetPath);
        expect(file.existsSync(), isTrue, reason: '$assetPath harus ada');
        final bytes = file.readAsBytesSync();
        expect(bytes, isNotEmpty);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1024);
        expect(frame.image.height, 1024);
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  group('Wave B #7: Prepare hike gear ListView top padding', () {
    testWidgets('ListView perlengkapan memakai padding zero & tidak terdorong status bar', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final account = _StubAccount(
        RemoteGroup(
          group: Group(
            id: '11111111-1111-4111-8111-111111111111',
            name: 'Tim Prau',
            ownerId: 'u-1',
            mountain: 'Gunung Prau',
            createdAtUtc: DateTime.utc(2026, 11, 20),
          ),
          role: GroupRole.owner,
        ),
      );
      addTearDown(account.dispose);

      final router = GoRouter(
        initialLocation: '/siap-naik',
        routes: <RouteBase>[
          GoRoute(
            path: '/siap-naik',
            builder: (_, __) => MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 1200),
                padding: EdgeInsets.only(top: 56, bottom: 34),
              ),
              child: SiapNaikPage(
                accountController: account,
                offlineMapCheck: (_) async => true,
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
      );
      await tester.pumpAndSettle();

      final firstGearFinder = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('packing-s1-'),
      );
      expect(firstGearFinder, findsWidgets);

      final gearListFinder = find
          .ancestor(of: firstGearFinder.first, matching: find.byType(ListView))
          .first;
      final listView = tester.widget<ListView>(gearListFinder);
      expect(listView.padding, EdgeInsets.zero);

      final listElement = tester.element(gearListFinder);
      expect(MediaQuery.paddingOf(listElement).top, 0.0);

      final cardMaterialFinder = find
          .ancestor(of: gearListFinder, matching: find.byType(Material))
          .first;
      final cardTop = tester.getTopLeft(cardMaterialFinder).dy;
      final firstItemTop = tester.getTopLeft(firstGearFinder.first).dy;
      expect(firstItemTop - cardTop, lessThan(4.0));
    });
  });

  group('Wave B #8: Media cache, decode bounds, RepaintBoundary, & Glass blur', () {
    test('AvatarDiskCache & HiqeoMediaCacheService mendukung eviksi & lookup memori', () async {
      final tempDir = await Directory.systemTemp.createTemp('wave_b_cache_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final diskCache = AvatarDiskCache(
        supportDirProvider: () async => tempDir,
        prefsLoader: SharedPreferences.getInstance,
        httpGet: (_, {headers}) async => http.Response.bytes(_kSamplePng, 200),
      );
      const avatarUrl = 'https://cdn.example.com/u1.png';
      expect(diskCache.cachedFileFor('u-1', avatarUrl), isNull);
      expect(diskCache.needsDownload('u-1', avatarUrl), isTrue);

      final cachedAvatar = await diskCache.ensureCached('u-1', avatarUrl);
      expect(cachedAvatar, isNotNull);
      expect(diskCache.cachedFileFor('u-1', avatarUrl)?.path, cachedAvatar!.path);
      expect(diskCache.needsDownload('u-1', avatarUrl), isFalse);

      var notified = 0;
      diskCache.addListener(() => notified++);
      diskCache.markFileMissing('u-1');
      expect(notified, 1);
      expect(diskCache.cachedFileFor('u-1', avatarUrl), isNull);
      expect(diskCache.needsDownload('u-1', avatarUrl), isTrue);

      final mediaService = HiqeoMediaCacheService(
        cacheDirResolver: () async => tempDir,
        httpFetcher: (_) async => (statusCode: 200, bytes: _kSamplePng),
      );
      const photoUrl = 'https://cdn.example.com/photo.png';
      final resolved = await mediaService.resolveMediaFile(photoUrl);
      expect(resolved, isNotNull);
      expect(mediaService.cachedFileSync(photoUrl)?.path, resolved!.path);

      mediaService.evictMemoryEntry(photoUrl);
      expect(mediaService.cachedFileSync(photoUrl), isNull);
    });

    testWidgets('CommunityChatPage membungkus ListView & bubble media dengan RepaintBoundary, cacheExtent 600, dan cacheWidth proporsional', (tester) async {
      final community = CommunitySummary(
        id: 'comm-b',
        name: 'Merbabu',
        description: 'Info jalur',
        ownerId: 'owner-1',
        memberCount: 10,
        isJoined: true,
        createdAt: DateTime.utc(2026, 11, 20),
      );
      final photoMsg = CommunityMessage(
        id: 'm-net-1',
        communityId: community.id,
        senderId: 'user-2',
        senderName: 'Budi',
        messageType: CommunityMessageType.image,
        mediaUrl: 'https://cdn.example.com/merbabu.webp',
        createdAt: DateTime.utc(2026, 11, 22, 8, 0),
      );
      final replyMsg = CommunityMessage(
        id: 'm-reply-1',
        communityId: community.id,
        senderId: 'me-1',
        senderName: 'Rani',
        messageType: CommunityMessageType.text,
        content: 'Mantap fotonya!',
        replyToMessageId: 'm-net-1',
        createdAt: DateTime.utc(2026, 11, 22, 8, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              devicePixelRatio: 2.0,
            ),
            child: CommunityChatPage(
              community: community,
              initialMessages: <CommunityMessage>[photoMsg, replyMsg],
              hasFullSocialOverride: true,
              currentUserIdOverride: 'me-1',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(HiqeoGlassTokens.blurSigma, 14);
      final listViewFinder = find.byType(ListView);
      expect(listViewFinder, findsOneWidget);
      expect(
        find.ancestor(
          of: listViewFinder,
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );

      final photoFrameFinder = find.byKey(
        const ValueKey<String>('community-photo-frame-m-net-1'),
      );
      expect(photoFrameFinder, findsOneWidget);
      expect(
        find.ancestor(
          of: photoFrameFinder,
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );

      final persistentImgFinder = find.descendant(
        of: photoFrameFinder,
        matching: find.byType(PersistentMediaImage),
      );
      expect(persistentImgFinder, findsOneWidget);
      final persistentImg =
          tester.widget<PersistentMediaImage>(persistentImgFinder);
      expect(persistentImg.cacheWidth, isNotNull);
      expect(persistentImg.cacheWidth, inInclusiveRange(240, 900));
    });
  });
}
