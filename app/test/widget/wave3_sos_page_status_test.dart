import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/platform/phone_dialer.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/safety/application/sos_action_service.dart';
import 'package:nama_app/features/safety/application/sos_location.dart';
import 'package:nama_app/features/safety/application/sos_offline_queue_service.dart';
import 'package:nama_app/features/safety/application/sos_sms_service.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_category.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
import 'package:nama_app/features/safety/presentation/sos_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemSafetyRepo implements SafetyRepository {
  final Map<String, SosEvent> events = <String, SosEvent>{};

  @override
  Future<List<SosEvent>> activeSosEvents() async => events.values.toList();

  @override
  Future<bool> cancelSosEvent(String id, DateTime nowUtc) async => true;

  @override
  Future<List<EmergencyContact>> contactsOf(String userId) async =>
      const <EmergencyContact>[];

  @override
  Future<void> deleteContact(String id) async {}

  @override
  Future<SosEvent?> findSosEvent(String id) async => events[id];

  @override
  Future<void> saveContact(EmergencyContact contact) async {}

  @override
  Future<void> saveSosEvent(SosEvent event) async {
    events[event.id] = event;
  }

  @override
  Stream<List<EmergencyContact>> watchContacts(String userId) =>
      const Stream<List<EmergencyContact>>.empty();

  @override
  Stream<List<SosEvent>> watchSosEvents() =>
      const Stream<List<SosEvent>>.empty();
}

class _FixedSosLocation implements SosLocationProvider {
  @override
  Future<SosFix?> locate() async => const SosFix(
        lat: -6.8,
        lon: 106.9,
        accuracyM: 8,
        altitudeM: 2100,
      );
}

class _NoopDialer implements PhoneDialer {
  @override
  Future<bool> dial(String number) async => true;
}

class _FakeActionRunner implements SosActionRunner {
  _FakeActionRunner(this.outcome);

  final SosDispatchOutcome outcome;
  String? lastUuid;

  @override
  Future<SosDispatchOutcome> activate({
    required String sosUuid,
    required SosFix? fix,
    required SosCategory category,
    required DateTime triggeredAtUtc,
    SafetyRepository? safetyRepository,
  }) async {
    lastUuid = sosUuid;
    return outcome;
  }

  @override
  Future<void> deactivate({String? remoteSosId}) async {}
}

class _MutableSmsSender implements SosSmsSender {
  _MutableSmsSender({this.supported = true, this.granted = false});

  final bool supported;
  bool granted;
  int requestCalls = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async {
    requestCalls++;
    granted = true;
    return true;
  }

  @override
  Future<SosSmsBatchResult> sendSmsBatch({
    required List<String> phones,
    required String message,
  }) async =>
      SosSmsBatchResult(supported: supported, sentCount: phones.length);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
      'SosPage meminta izin SMS darurat secara proaktif dengan penjelasan jelas dan memperbarui status antrean & SMS',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final clock = FakeClock(DateTime.utc(2026, 11, 21, 8, 0));
    final repo = _MemSafetyRepo();
    final queue = SosOfflineQueueService.forTesting();
    final smsSender = _MutableSmsSender(supported: true, granted: false);
    final runner = _FakeActionRunner(
      const SosDispatchOutcome(
        flashlightActive: true,
        sirenActive: true,
        isOnline: false,
        sentDirectSms: true,
        directSmsSentCount: 1,
        directSmsTargetCount: 1,
        hasPhoneEmergencyContacts: true,
        sentMeshBroadcast: true,
        queuedForServerSync: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: SosPage(
          repository: repo,
          locationProvider: _FixedSosLocation(),
          dialer: _NoopDialer(),
          actionRunner: runner,
          smsSender: smsSender,
          offlineQueue: queue,
          clock: clock,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Dialog penjelasan proaktif langsung tampil karena SEND_SMS belum diizinkan.
    expect(find.text('Izinkan SMS darurat otomatis?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('sms-rationale-allow')));
    await tester.pumpAndSettle();
    expect(smsSender.requestCalls, 1);

    // Tahan tombol SOS 3 detik -> status menampilkan per-channel secara jujur.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('sos-ring'))),
    );
    await tester.pump();
    clock.advance(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(find.text('Disiarkan via Hiqeo Mesh (offline)'), findsOneWidget);
    expect(
      find.text('Menunggu sinyal internet untuk sinkronisasi server'),
      findsOneWidget,
    );
    expect(find.text('SMS Darurat terkirim otomatis'), findsOneWidget);

    // Simulasikan SOS masuk antrean lalu sinyal kembali -> status otomatis berubah terkirim ke server!
    final activeId = runner.lastUuid!;
    await queue.enqueue(
      PendingSosSyncItem(
        sosUuid: activeId,
        authorId: 'u1',
        categoryIndex: 0,
        lat: -6.8,
        lon: 106.9,
        message: 'SOS',
        createdAtUtc: clock.nowUtc(),
        queuedAtUtc: clock.nowUtc(),
      ),
    );
    await queue.flushPending(
      connectivityCheckOverride: () async => true,
      uploaderOverride: (_) async => true,
    );
    await tester.pump();

    expect(
      find.text('Terkirim ke server & kontak Hiqeo'),
      findsOneWidget,
    );
  });
}
