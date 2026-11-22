import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/config/supabase_config.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/background/background_motion_controller.dart';
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
}) async {
  tester.view.physicalSize = const Size(390, 2800);
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
      'merender semua bagian secara berurutan dan menyembunyikan Batalkan langganan untuk non-Plus',
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
    expect(
      find.text('Cache peta: 42 MB, Data sementara: 8 MB'),
      findsOneWidget,
    );
    expect(find.text('Batalkan langganan'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('settings-open-privacy-policy')),
    );
    await tester.pumpAndSettle();
    expect(harness.openedUrls, <String>[kPrivacyPolicyUrl]);
  });

  testWidgets(
      'menampilkan bagian Batalkan langganan hanya ketika pengguna berstatus Plus',
      (tester) async {
    final plus = await buildPlusController(
      token: 'valid-token',
      payload: plusPayload(),
    );
    await _pumpSettings(tester, plus: plus);

    expect(find.text('Batalkan langganan'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-manage-store-subscription')),
      findsOneWidget,
    );
  });

  testWidgets('mengganti tema langsung berlaku tanpa memulai ulang aplikasi',
      (tester) async {
    final harness = await _pumpSettings(tester);

    expect(harness.theme.mode, ThemeMode.system);
    await tester.tap(find.byKey(const ValueKey('settings-theme-dark')));
    await tester.pumpAndSettle();

    expect(harness.theme.mode, ThemeMode.dark);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('membersihkan cache menampilkan konfirmasi dan mereset ukuran',
      (tester) async {
    final harness = await _pumpSettings(tester);

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
    expect(find.textContaining('bersifat sukarela (baku nonaktif)'), findsOneWidget);
  });

  testWidgets('sakelar gerak latar dihapus dari Pengaturan dan gerak latar selalu aktif',
      (tester) async {
    await _pumpSettings(tester);

    expect(find.text('Gerak latar'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-background-motion')),
      findsNothing,
    );
    expect(await const SharedPreferencesBackgroundMotionStore().readEnabled(), isTrue);
  });
}
