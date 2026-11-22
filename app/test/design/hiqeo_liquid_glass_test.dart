import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/glass/hiqeo_liquid_glass.dart';
import 'package:nama_app/design/widgets/header_icon_button.dart';
import 'package:nama_app/design/widgets/hiqeo_back_button.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/design/widgets/line_icons.dart';
import 'package:nama_app/features/plus/presentation/widgets/plus_widgets.dart';
import 'package:nama_app/features/social/data/community_service.dart';
import 'package:nama_app/features/social/presentation/community_chat_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
      'HiqeoGlassTokens memakai parameter Liquid Glass terkalibrasi (sigma 14 & fill transparan)',
      () {
    expect(HiqeoGlassTokens.blurSigma, 14);
    expect(HiqeoGlassTokens.saturation, 1.0);
    expect(HiqeoGlassTokens.borderWidth, 1);
    expect(HiqeoGlassTokens.shadow, isEmpty);
    expect(HiqeoGlassTokens.fill(Brightness.light),
        Colors.white.withValues(alpha: 0.22));
    expect(HiqeoGlassTokens.fill(Brightness.dark),
        Colors.white.withValues(alpha: 0.16));
    expect(HiqeoGlassTokens.border(Brightness.light),
        Colors.white.withValues(alpha: 0.62));
    expect(HiqeoGlassTokens.border(Brightness.dark),
        Colors.white.withValues(alpha: 0.24));
  });

  testWidgets(
      'HiqeoLiquidGlassSurface selalu membungkus BackdropFilter(14,14) di dalam ClipRRect',
      (tester) async {
    for (final shape in const <BoxShape>[BoxShape.rectangle, BoxShape.circle]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 44,
                height: 44,
                child: HiqeoLiquidGlassSurface(
                  shape: shape,
                  borderRadius: 22,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      final clip = find.byType(ClipRRect);
      expect(clip, findsOneWidget);
      final blurFinder = find.descendant(
        of: clip,
        matching: find.byType(BackdropFilter),
      );
      expect(blurFinder, findsOneWidget);
      final blur = tester.widget<BackdropFilter>(blurFinder);
      expect(
        blur.filter,
        ui.ImageFilter.blur(
            sigmaX: 14, sigmaY: 14, tileMode: ui.TileMode.clamp),
      );
    }
  });

  testWidgets(
      'tombol kembali bulat (HiqeoBackButton, PlusCircleButton, HeaderIconButton) dan navbar memakai HiqeoLiquidGlassSurface seragam',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoDarkTheme,
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const HiqeoBackButton(),
              PlusCircleButton(
                icon: HiqeoIcons.chevronLeft,
                label: 'Kembali Plus',
                onTap: () {},
              ),
              HeaderIconButton(
                icon: HiqeoIcons.close,
                label: 'Tutup SOS',
                onTap: () {},
              ),
              HiqeoNavBar(
                currentIndex: 0,
                onTap: (_) {},
                items: <HiqeoNavBarItem>[
                  HiqeoNavBarItem(
                      label: 'Beranda',
                      icon: HiqeoIcons.home,
                      route: '/beranda'),
                  HiqeoNavBarItem(
                      label: 'Peta', icon: HiqeoIcons.map, route: '/peta'),
                  HiqeoNavBarItem(
                      label: 'Track',
                      icon: HiqeoIcons.activity,
                      route: '/lacak'),
                  HiqeoNavBarItem(
                      label: 'Sosial', icon: HiqeoIcons.group, route: '/grup'),
                  HiqeoNavBarItem(
                      label: 'Profil', icon: HiqeoIcons.user, route: '/profil'),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(HiqeoLiquidGlassSurface), findsNWidgets(4));
    expect(
      find.descendant(
        of: find.byType(HiqeoNavBar),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'CommunityChatPage memakai HiqeoLiquidGlassSurface untuk header, hamburger, input, tombol kirim (sorotan saat ada teks), menu, & profil pengirim',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final community = CommunitySummary(
      id: 'comm-glass',
      name: 'Pendaki Nusantara',
      description: 'Diskusi jalur',
      ownerId: 'owner-1',
      memberCount: 12,
      isJoined: true,
      createdAt: DateTime.utc(2026, 11, 1),
    );
    final messages = <CommunityMessage>[
      CommunityMessage(
        id: 'm1',
        communityId: 'comm-glass',
        senderId: 'other-user',
        senderName: 'Budi',
        senderUsername: 'budi_hike',
        messageType: CommunityMessageType.text,
        content: 'Cuaca cerah di basecamp',
        createdAt: DateTime.utc(2026, 11, 20, 9, 0),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoDarkTheme,
        home: CommunityChatPage(
          community: community,
          initialMessages: messages,
          hasFullSocialOverride: true,
          onSendText: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Header pill, tombol hamburger, pil input, dan tombol kirim memakai Liquid Glass
    expect(
      tester.widget<HiqeoLiquidGlassSurface>(
        find.byKey(const ValueKey('community-glass-header')),
      ),
      isNotNull,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('community-hamburger-button')),
        matching: find.byType(HiqeoLiquidGlassSurface),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<HiqeoLiquidGlassSurface>(
        find.byKey(const ValueKey('community-glass-composer')),
      ),
      isNotNull,
    );

    // Tombol kirim tidak solid putih & sorotan halus aktif hanya saat ada teks
    final sendBtnBefore = tester.widget<HiqeoGlassCircleButton>(
      find.byKey(const ValueKey('community-send-button')),
    );
    expect(sendBtnBefore.emphasized, isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('community-input')),
      'Siap meluncur!',
    );
    await tester.pump();
    final sendBtnAfter = tester.widget<HiqeoGlassCircleButton>(
      find.byKey(const ValueKey('community-send-button')),
    );
    expect(sendBtnAfter.emphasized, isTrue);

    // Menu dropdown hamburger kanan atas memakai HiqeoLiquidGlassSurface
    await tester.tap(find.byKey(const ValueKey('community-hamburger-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('community-dropdown-menu')),
      findsOneWidget,
    );
    expect(
      tester.widget<HiqeoLiquidGlassSurface>(
        find.byKey(const ValueKey<String>('community-dropdown-menu')),
      ),
      isNotNull,
    );
    // Tutup dropdown via tombol hamburger agar bisa mengetuk pesan di bawahnya
    await tester.tap(find.byKey(const ValueKey('community-hamburger-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('community-dropdown-menu')),
      findsNothing,
    );

    // Modal profil pengirim memakai HiqeoLiquidGlassSurface
    await tester.tap(find.text('Budi'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('community-sender-action-sheet')),
      findsOneWidget,
    );
    expect(
      tester.widget<HiqeoLiquidGlassSurface>(
        find.byKey(const ValueKey<String>('community-sender-action-sheet')),
      ),
      isNotNull,
    );
  });

  testWidgets(
      'HiqeoLiquidGlassSurface(enableBlur: false) dan HiqeoGlassCard merender tanpa BackdropFilter & tanpa BoxShadow',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoDarkTheme,
        home: const Scaffold(
          body: Column(
            children: <Widget>[
              HiqeoLiquidGlassSurface(
                key: ValueKey<String>('light-surface'),
                enableBlur: false,
                child: Text('Kaca ringan'),
              ),
              HiqeoGlassCard(
                key: ValueKey<String>('light-card'),
                child: Text('Kartu ringan'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Kaca ringan'), findsOneWidget);
    expect(find.text('Kartu ringan'), findsOneWidget);

    final cardDecor = tester
        .widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('light-card')),
            matching: find.byType(DecoratedBox),
          ),
        )
        .decoration as BoxDecoration;
    expect(cardDecor.boxShadow, isNull);
    expect(cardDecor.border, isNotNull);
  });
}
