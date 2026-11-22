import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/platform/contact_picker.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/theme_mode_controller.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/auth/presentation/account_page.dart';
import 'package:nama_app/features/profile/presentation/profil_page.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
import 'package:nama_app/features/safety/presentation/emergency_contacts_sheet.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/infrastructure/power/power_profile_controller.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/account_fakes.dart';
import '../support/real_font.dart';

final Uint8List _key = Uint8List.fromList(List<int>.generate(32, (i) => i + 7));
final DateTime _now = DateTime.utc(2026, 6, 15, 8);

class _Battery implements BatteryReader {
  @override
  Future<int> levelPercent() async => 85;
  @override
  Future<bool> isCharging() async => false;
}

class _TrackingRepo implements TrackingRepository {
  @override
  Stream<List<TrackingSession>> watchSessions() =>
      Stream<List<TrackingSession>>.value(<TrackingSession>[
        TrackingSession(
          id: 's1',
          startedAtUtc: DateTime.utc(2026, 5, 1),
          endedAtUtc: DateTime.utc(2026, 5, 2),
          distanceM: 28400,
          elevationGainM: 1850,
          status: TrackingSessionStatus.completed,
        ),
      ]);
  @override
  Future<void> saveSession(TrackingSession session) async {}
  @override
  Future<TrackingSession?> findSession(String id) async => null;
  @override
  Future<TrackingSession?> findActiveSession() async => null;
  @override
  Future<void> deleteSession(String id) async {}
  @override
  Future<void> addPoint(String sessionId, TrackPoint point) async {}
  @override
  Future<void> clearPoints(String sessionId) async {}
  @override
  Future<List<TrackPoint>> points(String sessionId) async =>
      const <TrackPoint>[];
  @override
  Future<TrackPoint?> latestPoint(String sessionId) async => null;
}

class _SafetyRepo implements SafetyRepository {
  final List<EmergencyContact> list = <EmergencyContact>[
    EmergencyContact(
      id: 'c1',
      userId: 'u1',
      name: 'Ibu Sinta',
      phoneE164: '+6281234567890',
      createdAtUtc: _now,
    ),
  ];

  @override
  Future<List<EmergencyContact>> contactsOf(String userId) async => list;
  @override
  Future<void> saveContact(EmergencyContact contact) async {}
  @override
  Stream<List<EmergencyContact>> watchContacts(String userId) =>
      Stream<List<EmergencyContact>>.value(list);
  @override
  Future<void> deleteContact(String id) async {}
  @override
  Future<void> saveSosEvent(SosEvent event) async {}
  @override
  Future<SosEvent?> findSosEvent(String id) async => null;
  @override
  Future<List<SosEvent>> activeSosEvents() async => const <SosEvent>[];
  @override
  Stream<List<SosEvent>> watchSosEvents() => const Stream<List<SosEvent>>.empty();
  @override
  Future<bool> cancelSosEvent(String id, DateTime nowUtc) async => false;
}

class _NoopPicker implements ContactPicker {
  @override
  Future<ContactPickResult> pickContact() async =>
      const ContactPickResult(status: ContactPickStatus.cancelled);
}

void main() {
  group('Golden Tests Profil, Kontak Darurat, Akun & Ganti Username', () {
    for (final mode in <(String, ThemeData)>[
      ('light', hiqeoLightTheme),
      ('dark', hiqeoDarkTheme),
    ]) {
      testWidgets('Profil masuk ${mode.$1}', (tester) async {
        tester.view.physicalSize = const Size(390, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPlusJakartaSans(tester);

        final auth = FakeAuthService(
          currentUser: const AuthUser(
            id: 'u1',
            email: 'raka@example.com',
            displayName: 'Raka Pratama',
            provider: AuthProviderKind.google,
          ),
        );
        final account = AccountController(
          authService: auth,
          profileRepository: FakeProfileRepository()
            ..current = UserProfile(
              userId: 'u1',
              fullName: 'Raka Pratama',
              username: 'raka_pratama',
              publicKeyBase64: base64Encode(_key),
            ),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(_key),
          clock: FakeClock(_now),
        );
        final power = PowerProfileController(
          reader: _Battery(),
          manager: PowerProfileManager(),
        );
        final theme = ThemeModeController(store: InMemoryThemeModeStore());
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          account.dispose();
          power.dispose();
          theme.dispose();
          await auth.close();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: mode.$2,
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: ProfilPage(
                accountController: account,
                powerController: power,
                themeController: theme,
                trackingRepository: _TrackingRepo(),
                safetyRepository: _SafetyRepo(),
                contactPicker: _NoopPicker(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/profil_signed_in_${mode.$1}.png'),
        );
      });

      testWidgets('Profil tamu ${mode.$1}', (tester) async {
        tester.view.physicalSize = const Size(390, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPlusJakartaSans(tester);

        final auth = FakeAuthService(isConfigured: true, currentUser: null);
        final account = AccountController(
          authService: auth,
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(_key),
          clock: FakeClock(_now),
        );
        final power = PowerProfileController(
          reader: _Battery(),
          manager: PowerProfileManager(),
        );
        final theme = ThemeModeController(store: InMemoryThemeModeStore());
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          account.dispose();
          power.dispose();
          theme.dispose();
          await auth.close();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: mode.$2,
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: ProfilPage(
                accountController: account,
                powerController: power,
                themeController: theme,
                trackingRepository: _TrackingRepo(),
                safetyRepository: _SafetyRepo(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/profil_guest_${mode.$1}.png'),
        );
      });

      testWidgets('Halaman Akun & Sheet Ganti Username ${mode.$1}',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPlusJakartaSans(tester);

        final auth = FakeAuthService(
          currentUser: const AuthUser(
            id: 'u1',
            email: 'raka@example.com',
            displayName: 'Raka Pratama',
            provider: AuthProviderKind.google,
          ),
        );
        final account = AccountController(
          authService: auth,
          profileRepository: FakeProfileRepository()
            ..current = UserProfile(
              userId: 'u1',
              username: 'raka_pratama',
              publicKeyBase64: base64Encode(_key),
            ),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(_key),
          clock: FakeClock(_now),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          account.dispose();
          await auth.close();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: mode.$2,
            debugShowCheckedModeBanner: false,
            home: AccountPage(controller: account),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(AccountPage),
          matchesGoldenFile('goldens/account_page_${mode.$1}.png'),
        );

        // Buka sheet Ganti username lewat tombol Ganti
        await tester.tap(
          find.byKey(const ValueKey<String>('account-change-username-button')),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byKey(const ValueKey<String>('change-username-sheet')),
          matchesGoldenFile('goldens/change_username_sheet_${mode.$1}.png'),
        );
      });

      testWidgets('Sheet Kontak Darurat ${mode.$1}', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPlusJakartaSans(tester);

        await tester.pumpWidget(
          MaterialApp(
            theme: mode.$2,
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showEmergencyContactsSheet(
                    context,
                    ownerUserId: 'u1',
                    safetyRepository: _SafetyRepo(),
                    contactPicker: _NoopPicker(),
                  ),
                  child: const Text('Buka'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Buka'));
        await tester.pumpAndSettle();

        await expectLater(
          find.byKey(const ValueKey<String>('emergency-contacts-sheet')),
          matchesGoldenFile('goldens/emergency_contacts_sheet_${mode.$1}.png'),
        );
      });
    }
  });
}
