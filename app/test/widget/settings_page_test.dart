import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/config/supabase_config.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/background/background_motion_controller.dart';
import 'package:nama_app/design/glass/hiqeo_liquid_glass.dart';
import 'package:nama_app/design/theme_mode_controller.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/onboarding/permission_service.dart';
import 'package:nama_app/features/plus/application/plus_controller.dart';
import 'package:nama_app/features/plus/application/plus_scope.dart';
import 'package:nama_app/features/profile/presentation/settings_page.dart';

import '../support/account_fakes.dart';
import '../support/plus_fixtures.dart';

final Uint8List _identityKey =
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

class _MemoryThemeStore implements ThemeModeStore {
  ThemeMode saved = ThemeMode.system;

  @override
  Future<ThemeMode> readMode() async => saved;

  @override
  Future<void> writeMode(ThemeMode mode) async => saved = mode;
}

class _SettingsHarness {
  _SettingsHarness({
    required this.auth,
    required this.account,
    required this.theme,
  });

  final FakeAuthService auth;
  final AccountController account;
  final ThemeModeController theme;
  final List<String> openedUrls = <String>[];
  int systemSettingsCalls = 0;
  int batteryExceptionCalls = 0;
  int clearCacheCalls = 0;
  int clearAllLocalCalls = 0;
}

Future<_SettingsHarness> _pumpSettings(
  WidgetTester tester, {
  bool signedIn = true,
  PermissionReport? permissions,
  PlusController? plus,
  Size size = const Size(390, 2800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = FakeAuthService(
    isConfigured: true,
    currentUser: signedIn
        ? const AuthUser(
            id: 'user-1',
            email: 'rani@example.com',
            displayName: 'Rani Puspita',
            provider: AuthProviderKind.google,
          )
        : null,
  );
  final profiles = FakeProfileRepository()
    ..current = signedIn
        ? UserProfile(
            userId: 'user-1',
            username: 'rani',
            publicKeyBase64: base64Encode(_identityKey),
          )
        : null;
  final account = AccountController(
    authService: auth,
    profileRepository: profiles,
    keyDirectory: FakeKeyDirectory(),
    identity: FakeIdentity(_identityKey),
  );
  final theme = ThemeModeController(store: _MemoryThemeStore());
  await theme.load();

  final harness = _SettingsHarness(
    auth: auth,
    account: account,
    theme: theme,
  );
  addTearDown(() async {
    account.dispose();
    await auth.close();
  });

  final report = permissions ??
      const PermissionReport(
        notificationGranted: true,
        locationWhileInUse: true,
        locationAlways: false,
        locationServiceEnabled: true,
        preciseLocation: true,
        ignoringBatteryOptimizations: false,
        activityRecognitionGranted: true,
      );

  Widget page = SettingsPage(
    accountController: account,
    themeController: theme,
    permissionLoader: () async => report,
    onOpenSystemSettings: () async {
      harness.systemSettingsCalls++;
      return true;
    },
    onRequestBatteryException: () async {
      harness.batteryExceptionCalls++;
      return true;
    },
    cacheLoader: () async => const CacheUsageSummary(
      mapCacheBytes: 42 * 1024 * 1024,
      tempCacheBytes: 8 * 1024 * 1024,
    ),
    onClearCache: () async {
      harness.clearCacheCalls++;
    },
    onClearAllLocalData: () async {
      harness.clearAllLocalCalls++;
    },
    onOpenExternalUrl: (url) async {
      harness.openedUrls.add(url);
      return true;
    },
  );

  if (plus != null) {
    page = PlusScope(controller: plus, child: page);
  }

  await tester.pumpWidget(
    ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        theme: hiqeoLightTheme,
        darkTheme: hiqeoDarkTheme,
        themeMode: theme.mode,
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets(
      'seluruh 4 menu dropdown mulai dalam keadaan tertutup dan isi dibuka di tempat',
      (tester) async {
    final harness = await _pumpSettings(tester);

    expect(find.text('Pengaturan'), findsOneWidget);
    expect(find.text('Izin & baterai'), findsOneWidget);
    expect(find.text('Saat digunakan'), findsOneWidget);
    expect(find.text('Dibatasi sistem'), findsOneWidget);
    // Ganti akun & Hapus akun telah dipindahkan ke halaman Akun.
    expect(find.text('Ganti akun'), findsNothing);
    expect(find.text('Hapus akun'), findsNothing);
    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('Kebijakan privasi'), findsOneWidget);
    expect(find.text('Hapus cache'), findsOneWidget);
    expect(find.text('Batalkan langganan'), findsOneWidget);
    expect(
      find.text('Cache peta: 42 MB, Data sementara: 8 MB'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('settings-scroll-boundary')),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
    expect(find.byType(HiqeoGlassCard), findsNWidgets(5));

    // Keadaan awal tertutup (turns == 0.0, isi tidak dirender di pohon)
    for (final chevronKey in const <String>[
      'settings-chevron-theme',
      'settings-chevron-privacy',
      'settings-chevron-cache',
      'settings-chevron-subscription',
    ]) {
      final rot = tester.widget<AnimatedRotation>(
        find.byKey(ValueKey<String>(chevronKey)),
      );
      expect(rot.turns, 0.0);
    }
    expect(
      find.byKey(const ValueKey('settings-theme-dark')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings-open-privacy-policy')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings-clear-cache-button')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('settings-dropdown-privacy')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('settings-open-privacy-policy')),
    );
    await tester.pumpAndSettle();
    expect(harness.openedUrls, <String>[kPrivacyPolicyUrl]);
  });

  testWidgets(
      'auto-close akordeon: membuka menu baru menutup menu sebelumnya & ketuk ulang menutup diri',
      (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.byKey(const ValueKey('settings-dropdown-theme')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AnimatedRotation>(
            find.byKey(const ValueKey('settings-chevron-theme')),
          )
          .turns,
      0.5,
    );
    expect(find.byKey(const ValueKey('settings-theme-dark')), findsOneWidget);

    // Ketuk Hapus cache -> Tema otomatis menutup, Hapus cache membuka
    await tester.tap(find.byKey(const ValueKey('settings-dropdown-cache')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AnimatedRotation>(
            find.byKey(const ValueKey('settings-chevron-theme')),
          )
          .turns,
      0.0,
    );
    expect(find.byKey(const ValueKey('settings-theme-dark')), findsNothing);
    expect(
      tester
          .widget<AnimatedRotation>(
            find.byKey(const ValueKey('settings-chevron-cache')),
          )
          .turns,
      0.5,
    );
    expect(
      find.byKey(const ValueKey('settings-clear-cache-button')),
      findsOneWidget,
    );

    // Ketuk ulang Hapus cache -> menutup kembali
    await tester.tap(find.byKey(const ValueKey('settings-dropdown-cache')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AnimatedRotation>(
            find.byKey(const ValueKey('settings-chevron-cache')),
          )
          .turns,
      0.0,
    );
    expect(
      find.byKey(const ValueKey('settings-clear-cache-button')),
      findsNothing,
    );
  });

  testWidgets(
      'dropdown Batalkan langganan menampilkan ringkasan gratis untuk non-Plus & opsi toko untuk Plus',
      (tester) async {
    // 1. Pengguna Gratis
    await _pumpSettings(tester);
    await tester.tap(
      find.byKey(const ValueKey('settings-dropdown-subscription')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gratis'), findsOneWidget);
    expect(
      find.textContaining('Tidak ada langganan berbayar aktif'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-manage-store-subscription')),
      findsNothing,
    );

    // 2. Pengguna Plus aktif
    final plus = await buildPlusController(
      token: 'valid-token',
      payload: plusPayload(),
    );
    await _pumpSettings(tester, plus: plus);
    await tester.tap(
      find.byKey(const ValueKey('settings-dropdown-subscription')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Aktif ('), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-manage-store-subscription')),
      findsOneWidget,
    );
  });

  testWidgets('mengganti tema langsung berlaku tanpa memulai ulang aplikasi',
      (tester) async {
    final harness = await _pumpSettings(tester);

    expect(harness.theme.mode, ThemeMode.system);
    await tester.tap(find.byKey(const ValueKey('settings-dropdown-theme')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-theme-dark')));
    await tester.pumpAndSettle();

    expect(harness.theme.mode, ThemeMode.dark);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('membersihkan cache menampilkan konfirmasi dan mereset ukuran',
      (tester) async {
    final harness = await _pumpSettings(tester);

    await tester.tap(find.byKey(const ValueKey('settings-dropdown-cache')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-clear-cache-button')));
    await tester.pumpAndSettle();

    expect(find.text('Bersihkan cache?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('settings-confirm-clear-cache')),
    );
    await tester.pumpAndSettle();

    expect(harness.clearCacheCalls, 1);
    expect(
      find.text('Cache peta: 0 MB, Data sementara: 0 MB'),
      findsOneWidget,
    );
  });

  testWidgets(
      'Pengaturan tidak memuat tombol Hapus akun atau Ganti akun duplikat (dipindahkan ke halaman Akun)',
      (tester) async {
    await _pumpSettings(tester);

    expect(
      find.byKey(const ValueKey('settings-delete-account-button')),
      findsNothing,
    );
    expect(find.text('Ganti akun'), findsNothing);
    expect(find.text('Hapus akun'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-dropdown-privacy')));
    await tester.pumpAndSettle();
    expect(find.textContaining('bersifat sukarela (baku nonaktif)'), findsOneWidget);
  });

  testWidgets(
      'sakelar gerak latar dihapus dari Pengaturan dan gerak latar selalu aktif',
      (tester) async {
    await _pumpSettings(tester);

    expect(find.text('Gerak latar'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-background-motion')),
      findsNothing,
    );
    expect(
      await const SharedPreferencesBackgroundMotionStore().readEnabled(),
      isTrue,
    );
  });

  testWidgets(
      'akordeon Pengaturan bebas overflow di viewport sempit 360px untuk tema terang dan gelap',
      (tester) async {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(const SizedBox.shrink());
      final harness = await _pumpSettings(
        tester,
        size: const Size(360, 780),
      );
      if (brightness == Brightness.dark) {
        await harness.theme.setMode(ThemeMode.dark);
        await tester.pumpAndSettle();
      }

      for (final headerKey in const <String>[
        'settings-dropdown-theme',
        'settings-dropdown-privacy',
        'settings-dropdown-cache',
        'settings-dropdown-subscription',
      ]) {
        final finder = find.byKey(ValueKey<String>(headerKey));
        await tester.scrollUntilVisible(
          finder,
          180,
          scrollable: find.byType(Scrollable),
        );
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    }
  });
}
