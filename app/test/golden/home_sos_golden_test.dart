import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/core/platform/phone_dialer.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/home/beranda_page.dart';
import 'package:nama_app/features/home/expandable_features_card.dart';
import 'package:nama_app/features/safety/application/sos_location.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
import 'package:nama_app/features/safety/presentation/sos_page.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';

import '../support/account_fakes.dart';
import '../support/real_font.dart';

class _EmptyTrackingRepo implements TrackingRepository {
  @override
  Stream<List<TrackingSession>> watchSessions() =>
      Stream<List<TrackingSession>>.value(const <TrackingSession>[]);
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

class _EmptySafetyRepo implements SafetyRepository {
  @override
  Future<List<EmergencyContact>> contactsOf(String userId) async =>
      const <EmergencyContact>[];
  @override
  Future<void> saveContact(EmergencyContact contact) async {}
  @override
  Stream<List<EmergencyContact>> watchContacts(String userId) =>
      Stream<List<EmergencyContact>>.value(const <EmergencyContact>[]);
  @override
  Future<void> deleteContact(String id) async {}
  @override
  Future<void> saveSosEvent(SosEvent event) async {}
  @override
  Future<SosEvent?> findSosEvent(String id) async => null;
  @override
  Future<List<SosEvent>> activeSosEvents() async => const <SosEvent>[];
  @override
  Stream<List<SosEvent>> watchSosEvents() =>
      const Stream<List<SosEvent>>.empty();
  @override
  Future<bool> cancelSosEvent(String id, DateTime nowUtc) async => false;
}

class _StubLocation implements SosLocationProvider {
  @override
  Future<SosFix?> locate() async =>
      const SosFix(lat: -6.8, lon: 106.9, accuracyM: 8);
}

class _StubDialer implements PhoneDialer {
  @override
  Future<bool> dial(String number) async => true;
}

void main() {
  group('Golden Tests Beranda Fitur Utama & SOS', () {
    for (final mode in <(String, ThemeData)>[
      ('light', hiqeoLightTheme),
      ('dark', hiqeoDarkTheme),
    ]) {
      testWidgets('Beranda Fitur Utama terbuka ${mode.$1}', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPlusJakartaSans(tester);

        final account = AccountController(
          authService: FakeAuthService(isConfigured: false),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );
        addTearDown(account.dispose);

        final router = GoRouter(
          initialLocation: '/beranda',
          routes: <RouteBase>[
            GoRoute(
              path: '/beranda',
              builder: (_, __) => BerandaPage(
                accountController: account,
                repository: _EmptyTrackingRepo(),
                safetyRepository: _EmptySafetyRepo(),
                now: () => DateTime(2026, 10, 30, 7),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            theme: mode.$2,
            debugShowCheckedModeBanner: false,
            routerConfig: router,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('semua-fitur-toggle')));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(ExpandableFeaturesCard),
          matchesGoldenFile('goldens/fitur_utama_${mode.$1}.png'),
        );
      });
    }

    testWidgets('Layar SOS diam tanpa teks tekan-tahan kanan atas',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadPlusJakartaSans(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          debugShowCheckedModeBanner: false,
          home: SosPage(
            repository: _EmptySafetyRepo(),
            locationProvider: _StubLocation(),
            dialer: _StubDialer(),
            clock: FakeClock(DateTime.utc(2026, 10, 30, 3)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(SosPage),
        matchesGoldenFile('goldens/sos_idle.png'),
      );
    });
  });
}
