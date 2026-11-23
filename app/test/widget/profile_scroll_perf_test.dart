import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/glass/hiqeo_liquid_glass.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/auth/presentation/account_page.dart';
import 'package:nama_app/features/profile/presentation/profil_page.dart';
import 'package:nama_app/features/profile/presentation/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';
import '../support/plus_fixtures.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AccountController.evictLocalAvatarFileCache();
  });

  testWidgets(
      'ProfilPage: tanpa BackdropFilter, tanpa Opacity, memakai HiqeoGlassCard, RepaintBoundary, dan cacheWidth 256',
      (tester) async {
    final keyBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final auth = FakeAuthService(
      currentUser: const AuthUser(
        id: 'user-1',
        displayName: 'Bima Sakti',
        provider: AuthProviderKind.google,
      ),
    );
    final profiles = FakeProfileRepository()
      ..current = UserProfile(
        userId: 'user-1',
        username: 'bima_sakti',
        fullName: 'Bima Sakti',
        avatarUrl: 'https://cdn.example.com/avatar.webp',
        publicKeyBase64: base64Encode(keyBytes),
        isProfileComplete: true,
      );
    final account = AccountController(
      authService: auth,
      profileRepository: profiles,
      keyDirectory: FakeKeyDirectory(),
      identity: FakeIdentity(keyBytes),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      account.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoDarkTheme,
        home: Scaffold(
          body: ProfilPage(
            accountController: account,
            trackingRepository: FakeTrackingRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Area scroll dibungkus RepaintBoundary + ListView clipBehavior hardEdge
    expect(
      find.byKey(const ValueKey<String>('profil-scroll-boundary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profil-plus-card-boundary')),
      findsOneWidget,
    );
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.clipBehavior, Clip.hardEdge);

    // 2. Nol BackdropFilter & nol Opacity di area scroll ProfilPage
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(Opacity), findsNothing);

    // 3. Semua kartu memakai HiqeoGlassCard ringan (statistik + 5 baris menu)
    expect(find.byType(HiqeoGlassCard), findsNWidgets(6));

    // 4. Foto profil membatasi resolusi decode GPU (`ResizeImage` width = 256)
    final avatarImg = tester.widget<Image>(find.byType(Image).first);
    expect(avatarImg.image, isA<ResizeImage>());
    expect((avatarImg.image as ResizeImage).width, 256);
  });

  testWidgets(
      'AccountPage & SettingsPage memakai HiqeoGlassCard ringan tanpa BackdropFilter serta RepaintBoundary',
      (tester) async {
    final keyBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final auth = FakeAuthService(
      currentUser: const AuthUser(
        id: 'user-1',
        email: 'bima@example.com',
        displayName: 'Bima Sakti',
        provider: AuthProviderKind.google,
      ),
    );
    final profiles = FakeProfileRepository()
      ..current = UserProfile(
        userId: 'user-1',
        username: 'bima_sakti',
        fullName: 'Bima Sakti',
        avatarUrl: 'https://cdn.example.com/avatar.webp',
        publicKeyBase64: base64Encode(keyBytes),
        isProfileComplete: true,
      );
    final account = AccountController(
      authService: auth,
      profileRepository: profiles,
      keyDirectory: FakeKeyDirectory(),
      identity: FakeIdentity(keyBytes),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      account.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoDarkTheme,
        home: AccountPage(controller: account),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('account-scroll-boundary')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(HiqeoGlassCard), findsNWidgets(4));

    final avatarImg = tester.widget<Image>(find.byType(Image).first);
    expect(avatarImg.image, isA<ResizeImage>());
    expect((avatarImg.image as ResizeImage).width, 256);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoDarkTheme,
        home: SettingsPage(
          accountController: account,
          cacheLoader: () async => const CacheUsageSummary(
            mapCacheBytes: 0,
            tempCacheBytes: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-scroll-boundary')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(HiqeoGlassCard), findsNWidgets(5));
  });
}
