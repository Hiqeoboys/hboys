import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/widgets/account_badges.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/auth/domain/username_policy.dart';
import 'package:nama_app/features/auth/presentation/account_page.dart';
import 'package:nama_app/features/auth/presentation/profile_onboarding_page.dart';
import 'package:nama_app/features/plus/application/plus_scope.dart';
import 'package:nama_app/features/plus/domain/plus_entitlement.dart';
import 'package:nama_app/features/plus/domain/plus_repositories.dart';
import 'package:nama_app/features/plus/domain/plus_subscription_history.dart';
import 'package:nama_app/features/plus/presentation/paywall_page.dart';
import 'package:nama_app/features/plus/presentation/widgets/plus_grace_warning_card.dart';
import 'package:nama_app/features/plus/presentation/widgets/plus_subscription_history_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';
import '../support/plus_fixtures.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Wave D Part 1: 3-Day Grace, History, & Ultima', () {
    test('masa tenggang 3 hari membuka Plus umum tapi langsung mengunci Komunitas & Leaderboard',
        () {
      final issuedAt = DateTime.utc(2026, 1, 1);
      final expiresAt = DateTime.utc(2026, 2, 1);
      final payload = EntitlementPayload(
        version: EntitlementPayload.currentVersion,
        subject: 'u1',
        planId: 'annual',
        issuedAtUtc: issuedAt,
        expiresAtUtc: expiresAt,
      );

      final active = evaluatePlusAccess(
        payload: payload,
        nowUtc: DateTime.utc(2026, 1, 20),
        graceDays: 3,
      );
      expect(active.state, PlusAccessState.active);
      expect(active.hasPlus, isTrue);
      expect(active.hasFullSocialAccess, isTrue);

      // Tepat saat expired -> masuk masa tenggang 3 hari; Plus umum & Analitik/Rekap terbuka,
      // tapi hasFullSocialAccess LANGSUNG terkunci (false)!
      final graceDay1 = evaluatePlusAccess(
        payload: payload,
        nowUtc: expiresAt.add(const Duration(hours: 12)),
        graceDays: 3,
      );
      expect(graceDay1.state, PlusAccessState.grace);
      expect(graceDay1.hasPlus, isTrue);
      expect(graceDay1.hasFullPlanIncludingGrace, isTrue);
      expect(graceDay1.isGrace, isTrue);
      expect(graceDay1.hasFullSocialAccess, isFalse);

      // Hari ke-4 (> 3 hari) -> terkunci total!
      final expiredAfterGrace = evaluatePlusAccess(
        payload: payload,
        nowUtc: expiresAt.add(const Duration(days: 3)),
        graceDays: 3,
      );
      expect(expiredAfterGrace.state, PlusAccessState.expired);
      expect(expiredAfterGrace.hasPlus, isFalse);
      expect(expiredAfterGrace.hasFullPlanIncludingGrace, isFalse);
      expect(expiredAfterGrace.hasFullSocialAccess, isFalse);
    });

    test('isUltima bernilai true untuk paket lifetime / founding / ultima aktif', () {
      final access = evaluatePlusAccess(
        payload: EntitlementPayload(
          version: EntitlementPayload.currentVersion,
          subject: 'u1',
          planId: 'founding',
          issuedAtUtc: DateTime.utc(2026, 1, 1),
          expiresAtUtc: null,
        ),
        nowUtc: DateTime.utc(2030, 1, 1),
        graceDays: 3,
      );
      expect(access.isUltima, isTrue);
      expect(access.hasPlus, isTrue);
      expect(access.hasFullSocialAccess, isTrue);
    });

    testWidgets('PlusGraceWarningCard, PlusSubscriptionHistoryCard, & UltimaBadge render sesuai aturan',
        (tester) async {
      var resubscribed = false;
      final graceAccess = PlusAccess(
        state: PlusAccessState.grace,
        planId: 'annual',
        expiresAtUtc: DateTime.utc(2026, 11, 20),
        graceEndsAtUtc: DateTime.utc(2026, 11, 23),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                PlusGraceWarningCard(
                  access: graceAccess,
                  onSubscribeAgain: () => resubscribed = true,
                ),
                PlusSubscriptionHistoryCard(
                  entries: <PlusSubscriptionHistoryEntry>[
                    PlusSubscriptionHistoryEntry(
                      id: 'h1',
                      planId: 'annual',
                      planTitle: 'Hiqeo Plus Tahunan',
                      status: PlusSubscriptionHistoryStatus.grace,
                      startedAtUtc: DateTime.utc(2025, 11, 20),
                      expiresAtUtc: DateTime.utc(2026, 11, 20),
                    ),
                  ],
                ),
                const PlusSubscriptionHistoryCard(
                  entries: <PlusSubscriptionHistoryEntry>[],
                ),
                const UltimaBadge(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('3 hari'), findsOneWidget);
      expect(find.textContaining('Komunitas dan Leaderboard'), findsOneWidget);
      expect(find.text('Berlangganan lagi'), findsOneWidget);
      expect(find.text('RIWAYAT BERLANGGANAN'), findsOneWidget);
      expect(find.text('Hiqeo Plus Tahunan'), findsOneWidget);
      expect(find.text('Masa tenggang'), findsOneWidget);
      expect(find.text('Ultima'), findsOneWidget);
      // Empty history renders nothing (only 1 card exists).
      expect(
        find.byKey(const ValueKey<String>('plus-subscription-history-card')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('plus-grace-resubscribe-button')),
      );
      expect(resubscribed, isTrue);
    });
  });

  group('Wave D Part 2: First-Time Profile Onboarding', () {
    final identityKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

    test('needsProfileOnboarding bernilai true untuk akun baru dan false untuk akun lama lengkap',
        () async {
      final authNew = FakeAuthService(
        currentUser: const AuthUser(
          id: 'u-new',
          email: 'baru@example.com',
          displayName: 'Pendaki Baru',
          provider: AuthProviderKind.google,
        ),
      );
      final repoNew = FakeProfileRepository();
      final ctrlNew = AccountController(
        authService: authNew,
        profileRepository: repoNew,
        keyDirectory: FakeKeyDirectory(),
        identity: FakeIdentity(identityKey),
        clock: FakeClock(DateTime.utc(2026, 11, 22)),
      );
      ctrlNew.initialize();
      await pumpEventQueue(times: 20);
      expect(ctrlNew.isProfileResolved, isTrue);
      expect(ctrlNew.needsProfileOnboarding, isTrue);
      ctrlNew.dispose();
      await authNew.close();

      final authOld = FakeAuthService(
        currentUser: const AuthUser(
          id: 'u-old',
          email: 'lama@example.com',
          displayName: 'Pendaki Lama',
          provider: AuthProviderKind.google,
        ),
      );
      final repoOld = FakeProfileRepository()
        ..current = UserProfile(
          userId: 'u-old',
          username: 'pendaki_lama',
          fullName: 'Pendaki Lama',
          publicKeyBase64: base64Encode(identityKey),
        );
      final ctrlOld = AccountController(
        authService: authOld,
        profileRepository: repoOld,
        keyDirectory: FakeKeyDirectory(),
        identity: FakeIdentity(identityKey),
        clock: FakeClock(DateTime.utc(2026, 11, 22)),
      );
      ctrlOld.initialize();
      await pumpEventQueue(times: 20);
      expect(ctrlOld.needsProfileOnboarding, isFalse);
      ctrlOld.dispose();
      await authOld.close();
    });

    testWidgets('ProfileOnboardingPage bisa lewati foto, cek ketersediaan username realtime, & simpan profil',
        (tester) async {
      final auth = FakeAuthService(
        currentUser: const AuthUser(
          id: 'u-new',
          email: 'raka@example.com',
          provider: AuthProviderKind.google,
        ),
      );
      final repo = FakeProfileRepository()..takenUsernames.add('sudah_dipakai');
      final ctrl = AccountController(
        authService: auth,
        profileRepository: repo,
        keyDirectory: FakeKeyDirectory(),
        identity: FakeIdentity(identityKey),
        clock: FakeClock(DateTime.utc(2026, 11, 22)),
      );
      ctrl.initialize();
      await tester.pumpAndSettle();

      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: ProfileOnboardingPage(
            controller: ctrl,
            onCompleted: () => completed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Foto bisa dilewati
      await tester.tap(
        find.byKey(const ValueKey<String>('onboarding-skip-photo')),
      );
      await tester.pump();
      expect(find.textContaining('Dilewati'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('onboarding-name-input')),
        'Raka Pratama',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('onboarding-username-input')),
        'sudah_dipakai',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      expect(find.textContaining('sudah dipakai'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('onboarding-username-input')),
        'raka_unik',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      expect(find.textContaining('@raka_unik tersedia'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('onboarding-submit-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('onboarding-submit-button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(completed, isTrue);
      expect(repo.current?.username, 'raka_unik');
      expect(repo.current?.fullName, 'Raka Pratama');

      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
      await auth.close();
    });
  });

  group('Wave D Part 3: Anonymous Paywall Guard', () {
    testWidgets('tamu belum login di Paywall diarahkan masuk dulu sebelum membeli',
        (tester) async {
      final billing = FakePlusBilling()
        ..purchaseResult = const PlusBillingResult.purchased('tok-annual');
      final controller = await buildPlusController(billing: billing);

      final router = GoRouter(
        initialLocation: '/plus',
        routes: <RouteBase>[
          GoRoute(
            path: '/plus',
            builder: (context, state) => const PaywallPage(
              isSignedInOverride: false,
            ),
          ),
          GoRoute(
            path: '/akun',
            builder: (context, state) => Scaffold(
              body: Text('akun-login:${state.uri.queryParameters['returnTo']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        PlusScope(
          controller: controller,
          child: MaterialApp.router(
            theme: hiqeoLightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('paywall-cta')));
      await tester.pumpAndSettle();

      expect(find.text('Masuk akun dulu'), findsOneWidget);
      expect(billing.purchases, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey<String>('paywall-login-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('akun-login:/plus'), findsOneWidget);
    });
  });

  group('Wave D Part 4: Google & Apple Account Linking', () {
    final identityKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

    testWidgets('AccountPage menampilkan Akun tertaut dan menolak konflik tanpa hapus data aktif',
        (tester) async {
      final auth = FakeAuthService(
        currentUser: const AuthUser(
          id: 'u-1',
          email: 'pendaki@example.com',
          provider: AuthProviderKind.google,
        ),
      );
      final repo = FakeProfileRepository()
        ..current = UserProfile(
          userId: 'u-1',
          username: 'pendaki_gunung',
          fullName: 'Pendaki Gunung',
          publicKeyBase64: base64Encode(identityKey),
        );
      final ctrl = AccountController(
        authService: auth,
        profileRepository: repo,
        keyDirectory: FakeKeyDirectory(),
        identity: FakeIdentity(identityKey),
        clock: FakeClock(DateTime.utc(2026, 11, 22)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: AccountPage(controller: ctrl),
        ),
      );
      await tester.pumpAndSettle();

      final linkedCard = find.byKey(
        const ValueKey<String>('account-linked-accounts-card'),
      );
      await tester.ensureVisible(linkedCard);
      await tester.pumpAndSettle();

      expect(find.text('Akun tertaut'), findsOneWidget);
      expect(find.text('Google'), findsOneWidget);
      expect(find.text('Apple'), findsOneWidget);

      // Uji konflik akun sudah dipakai user lain -> pesan ramah, user tetap login.
      auth.linkError = const AuthFailure(
        AuthFailureCode.identityAlreadyLinked,
        'Akun Apple ini sudah terdaftar di akun Hiqeo lain. Data akun aktifmu tetap aman.',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('account-link-button-apple')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('account-link-error')),
        findsOneWidget,
      );
      expect(ctrl.user?.id, 'u-1');

      // Tautkan Apple sukses -> identitas bertambah tanpa ubah UID.
      auth.linkError = null;
      await tester.tap(
        find.byKey(const ValueKey<String>('account-link-button-apple')),
      );
      await tester.pumpAndSettle();
      expect(ctrl.isProviderLinked(AuthProviderKind.google), isTrue);
      expect(ctrl.isProviderLinked(AuthProviderKind.apple), isTrue);
      expect(ctrl.user?.id, 'u-1');

      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
      await auth.close();
    });
  });

  group('Wave D Part 5: Official @hiqeo Whitelist & Checkmark', () {
    test('hanya hiqeoofficial@gmail.com yang boleh memakai @hiqeo dan Hiqeo Official',
        () {
      final officialRes = UsernamePolicy.validate(
        'hiqeo',
        userEmail: 'hiqeoofficial@gmail.com',
      );
      expect(officialRes.isValid, isTrue);
      expect(officialRes.isReserved, isFalse);
      expect(officialRes.errorMessage, isNull);
      expect(
        UsernamePolicy.validateDisplayName(
          'Hiqeo Official',
          userEmail: 'hiqeoofficial@gmail.com',
        ),
        isNull,
      );

      final otherUserRes = UsernamePolicy.validate(
        'hiqeo',
        userEmail: 'oranglain@gmail.com',
      );
      expect(otherUserRes.isValid, isFalse);
      expect(otherUserRes.isReserved, isTrue);
      expect(
        UsernamePolicy.validateDisplayName(
          'Hiqeo Official',
          userEmail: 'oranglain@gmail.com',
        ),
        isNotNull,
      );
    });

    testWidgets('OfficialVerifiedBadge merender ikon terverifikasi dengan semantics jelas',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: const Scaffold(
            body: Center(child: OfficialVerifiedBadge()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(
        find.bySemanticsLabel('Akun resmi Hiqeo terverifikasi'),
        findsOneWidget,
      );
    });
  });
}
