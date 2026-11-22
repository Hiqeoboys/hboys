import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/home/beranda_page.dart';
import 'package:nama_app/features/home/expandable_features_card.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';

import '../support/account_fakes.dart';

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

class _StubSafetyRepo implements SafetyRepository {
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

AccountController _guest() => AccountController(
      authService: FakeAuthService(isConfigured: false),
      profileRepository: FakeProfileRepository(),
      keyDirectory: FakeKeyDirectory(),
      identity: FakeIdentity(Uint8List(32)),
    );

void main() {
  testWidgets(
      'Fitur Utama menampilkan tepat 4 ubin 2x2 (Hiqeo Plus, SOS, Peta offline, Kontak darurat) tanpa subjudul dan aksi langsung bekerja',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final account = _guest();
    addTearDown(account.dispose);

    String? petaFilterQuery;
    final router = GoRouter(
      initialLocation: '/beranda',
      routes: <RouteBase>[
        GoRoute(
          path: '/beranda',
          builder: (_, __) => BerandaPage(
            accountController: account,
            repository: _EmptyTrackingRepo(),
            safetyRepository: _StubSafetyRepo(),
            now: () => DateTime(2026, 10, 30, 7),
          ),
        ),
        GoRoute(
          path: '/peta',
          builder: (_, state) {
            petaFilterQuery = state.uri.queryParameters['filter'];
            return Scaffold(body: Text('Peta filter: $petaFilterQuery'));
          },
        ),
        GoRoute(
          path: '/plus',
          builder: (_, __) => const Scaffold(body: Text('Layar Plus')),
        ),
        GoRoute(
          path: '/sos',
          builder: (_, __) => const Scaffold(body: Text('Layar SOS')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('semua-fitur-toggle')));
    await tester.pumpAndSettle();

    // Urutan 2x2: kiri atas Hiqeo Plus, kanan atas SOS, kiri bawah Peta offline, kanan bawah Kontak darurat
    final plusPos = tester.getBottomLeft(find.text('Hiqeo Plus'));
    final sosPos = tester.getBottomLeft(find.text('SOS'));
    final mapPos = tester.getBottomLeft(find.text('Peta offline'));
    final contactPos = tester.getBottomLeft(find.text('Kontak darurat'));

    expect(plusPos.dx, lessThan(sosPos.dx));
    expect(plusPos.dy, closeTo(sosPos.dy, 4.0));
    expect(mapPos.dx, lessThan(contactPos.dx));
    expect(mapPos.dy, closeTo(contactPos.dy, 4.0));
    expect(mapPos.dy, greaterThan(plusPos.dy));

    // Tidak ada subjudul pada tiap ubin (hanya 1 Text per FeatureTile)
    for (final tileElement in find.byType(FeatureTile).evaluate()) {
      final texts = find.descendant(
        of: find.byWidget(tileElement.widget),
        matching: find.byType(Text),
      );
      expect(texts, findsOneWidget);
    }

    // Ketuk Kontak darurat -> membuka sheet bersama langsung di Beranda
    await tester.tap(find.text('Kontak darurat'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('emergency-contacts-sheet')),
      findsOneWidget,
    );
    Navigator.of(tester.element(find.byType(BerandaPage))).pop();
    await tester.pumpAndSettle();

    // Ketuk Peta offline -> membuka /peta?filter=terunduh
    await tester.tap(find.text('Peta offline'));
    await tester.pumpAndSettle();
    expect(petaFilterQuery, 'terunduh');
  });

  testWidgets('HomeFeatureSet.withPreparation mengganti ubin ke Persiapan pendakian',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final account = _guest();
    addTearDown(account.dispose);

    final router = GoRouter(
      initialLocation: '/beranda',
      routes: <RouteBase>[
        GoRoute(
          path: '/beranda',
          builder: (_, __) => BerandaPage(
            accountController: account,
            repository: _EmptyTrackingRepo(),
            featureSet: HomeFeatureSet.withPreparation,
            now: () => DateTime(2026, 10, 30, 7),
          ),
        ),
        GoRoute(
          path: '/siap-naik',
          builder: (_, __) => const Scaffold(body: Text('Siap Naik')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('semua-fitur-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Persiapan pendakian'), findsOneWidget);
    expect(find.text('Kontak darurat'), findsNothing);
  });
}
