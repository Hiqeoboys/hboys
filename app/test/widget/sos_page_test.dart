import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/platform/phone_dialer.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/features/safety/application/sos_action_service.dart';
import 'package:nama_app/features/safety/application/sos_location.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_category.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
import 'package:nama_app/features/safety/presentation/slide_to_call.dart';
import 'package:nama_app/features/safety/presentation/sos_page.dart';

class _FakeSafetyRepository implements SafetyRepository {
  final Map<String, SosEvent> events = <String, SosEvent>{};
  bool failSave = false;

  @override
  Future<void> saveSosEvent(SosEvent event) async {
    if (failSave) throw StateError('penyimpanan penuh');
    events[event.id] = event;
  }

  @override
  Future<SosEvent?> findSosEvent(String id) async => events[id];

  @override
  Future<List<SosEvent>> activeSosEvents() async => events.values
      .where((event) => event.status == SosEventStatus.active)
      .toList(growable: false);

  @override
  Stream<List<SosEvent>> watchSosEvents() =>
      const Stream<List<SosEvent>>.empty();

  @override
  Future<bool> cancelSosEvent(String id, DateTime nowUtc) async {
    final event = events[id];
    if (event == null || event.status != SosEventStatus.active) return false;
    events[id] = SosEvent(
      id: event.id,
      authorId: event.authorId,
      groupId: event.groupId,
      category: event.category,
      lat: event.lat,
      lon: event.lon,
      accuracyM: event.accuracyM,
      batteryPercent: event.batteryPercent,
      createdAtUtc: event.createdAtUtc,
      receivedAtUtc: event.receivedAtUtc,
      status: SosEventStatus.cancelled,
      cancelledAtUtc: nowUtc,
    );
    return true;
  }

  @override
  Future<void> saveContact(EmergencyContact contact) async {}

  @override
  Future<List<EmergencyContact>> contactsOf(String userId) async =>
      const <EmergencyContact>[];

  @override
  Stream<List<EmergencyContact>> watchContacts(String userId) =>
      const Stream<List<EmergencyContact>>.empty();

  @override
  Future<void> deleteContact(String id) async {}
}

class _FakeLocation implements SosLocationProvider {
  _FakeLocation(this.fix);

  final SosFix? fix;
  int calls = 0;

  @override
  Future<SosFix?> locate() async {
    calls++;
    return fix;
  }
}

class _FakeDialer implements PhoneDialer {
  final List<String> numbers = <String>[];
  bool result = true;

  @override
  Future<bool> dial(String number) async {
    numbers.add(number);
    return result;
  }
}

class _FakeSosActionRunner implements SosActionRunner {
  _FakeSosActionRunner({
    this.outcome = const SosDispatchOutcome(
      flashlightActive: true,
      sirenActive: true,
      savedRemoteUpsert: true,
      sentGroupMessage: true,
      notifiedEmergencyContacts: true,
      remoteSosId: 'remote-sos-1',
    ),
  });

  final SosDispatchOutcome outcome;
  int activateCalls = 0;
  int deactivateCalls = 0;
  String? lastActivatedUuid;
  String? lastDeactivatedRemoteId;

  @override
  Future<SosDispatchOutcome> activate({
    required String sosUuid,
    required SosFix? fix,
    required SosCategory category,
    required DateTime triggeredAtUtc,
    SafetyRepository? safetyRepository,
  }) async {
    activateCalls++;
    lastActivatedUuid = sosUuid;
    return outcome;
  }

  @override
  Future<void> deactivate({String? remoteSosId}) async {
    deactivateCalls++;
    lastDeactivatedRemoteId = remoteSosId;
  }
}

class _Harness {
  _Harness({
    required this.clock,
    required this.repository,
    required this.location,
    required this.dialer,
    required this.actionRunner,
  });

  final FakeClock clock;
  final _FakeSafetyRepository repository;
  final _FakeLocation location;
  final _FakeDialer dialer;
  final _FakeSosActionRunner actionRunner;
}

const String _baseRouteText = 'layar-dasar';

Future<_Harness> _pump(
  WidgetTester tester, {
  SosFix? fix = const SosFix(
    lat: -6.8,
    lon: 106.9,
    accuracyM: 8,
    altitudeM: 2150,
  ),
  bool failSave = false,
  bool dialResult = true,
  SosDispatchOutcome outcome = const SosDispatchOutcome(
    flashlightActive: true,
    sirenActive: true,
    savedRemoteUpsert: true,
    sentGroupMessage: true,
    notifiedEmergencyContacts: true,
    remoteSosId: 'remote-sos-1',
  ),
}) async {
  tester.view.physicalSize = const Size(390, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final clock = FakeClock(DateTime.utc(2026, 10, 30, 3));
  final repository = _FakeSafetyRepository()..failSave = failSave;
  final location = _FakeLocation(fix);
  final dialer = _FakeDialer()..result = dialResult;
  final actionRunner = _FakeSosActionRunner(outcome: outcome);
  _mockPlatformChannel(tester);

  await tester.pumpWidget(
    MaterialApp(
      theme: hiqeoLightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SosPage(
                    repository: repository,
                    locationProvider: location,
                    dialer: dialer,
                    actionRunner: actionRunner,
                    clock: clock,
                  ),
                ),
              ),
              child: const Text(_baseRouteText),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_baseRouteText));
  await tester.pumpAndSettle();
  return _Harness(
    clock: clock,
    repository: repository,
    location: location,
    dialer: dialer,
    actionRunner: actionRunner,
  );
}

void _mockPlatformChannel(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

SemanticsOwner _semanticsOwner() =>
    RendererBinding.instance.renderViews.single.owner!.semanticsOwner!;

Finder get _ring => find.byKey(const ValueKey('sos-ring'));

Finder get _closeButton => find.byKey(const ValueKey('sos-close'));

Finder _callTrack(String key) => find.byKey(ValueKey<String>(key));

Future<TestGesture> _hold(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(_ring));
  await tester.pump();
  return gesture;
}

Future<void> _slidePast(WidgetTester tester, String key) async {
  final finder = _callTrack(key);
  final width = tester.getSize(finder).width;
  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump();
  await gesture.moveBy(Offset(width, 0));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

Future<void> _semanticsTap(WidgetTester tester, String key) async {
  final handle = tester.ensureSemantics();
  try {
    await tester.pump();
    final node = tester.getSemantics(_callTrack(key));
    _semanticsOwner().performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
  } finally {
    handle.dispose();
  }
}

/// Menahan 3 detik penuh langsung mengaktifkan SOS tanpa hitung mundur tambahan.
Future<void> _triggerSos(WidgetTester tester, _Harness harness) async {
  final gesture = await _hold(tester);
  await _advance(tester, harness.clock, const Duration(seconds: 3));
  await gesture.up();
  await tester.pump();
}

Future<void> _advance(
  WidgetTester tester,
  FakeClock clock,
  Duration duration,
) async {
  clock.advance(duration);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('layar diam menampilkan Tekan dan tahan 3 detik dan palet gelap',
      (tester) async {
    await _pump(tester);

    expect(find.text('SOS'), findsOneWidget);
    expect(_closeButton, findsOneWidget);
    expect(tester.getSize(_closeButton), const Size(44, 44));
    expect(find.text('Tekan dan tahan 3 detik'), findsOneWidget);
    expect(
      find.text('SOS hanya tersimpan di HP ini. Tidak ada pengiriman otomatis.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('sos-cancel')), findsNothing);
    expect(_callTrack('sos-call-115'), findsOneWidget);
    expect(_callTrack('sos-call-112'), findsOneWidget);
    expect(find.text('Basarnas 115'), findsOneWidget);
    expect(find.text('Darurat 112'), findsOneWidget);
    expect(find.text('Geser untuk menelepon'), findsOneWidget);

    final scaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(SosPage),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.backgroundColor, HiqeoColors.dark.background);
  });

  testWidgets(
      'tekan-tahan 3 detik langsung memicu SOS, senter, sirene, dan tombol Matikan SOS',
      (tester) async {
    final harness = await _pump(tester);
    final gesture = await _hold(tester);
    await _advance(tester, harness.clock, const Duration(seconds: 3));

    // Langsung aktif (tanpa hitung mundur tambahan)
    expect(find.text('SOS aktif'), findsOneWidget);
    expect(find.text('Matikan SOS'), findsOneWidget);
    expect(find.text('Batal, saya aman'), findsNothing);
    expect(find.text('CEDERA'), findsOneWidget);
    expect(find.text('TERSESAT'), findsOneWidget);
    expect(find.text('CUACA'), findsOneWidget);
    expect(find.byKey(const ValueKey('sos-hardware-flashlight')), findsOneWidget);
    expect(find.byKey(const ValueKey('sos-hardware-siren')), findsOneWidget);
    expect(harness.actionRunner.activateCalls, 1);
    expect(harness.repository.events, hasLength(1));

    final saved = harness.repository.events.values.single;
    expect(saved.authorId, 'perangkat-lokal');
    expect(saved.category, SosCategory.other);
    expect(saved.lat, -6.8);
    expect(saved.lon, 106.9);
    expect(saved.accuracyM, 8);
    expect(saved.status, SosEventStatus.active);
    expect(saved.createdAtUtc, DateTime.utc(2026, 10, 30, 3, 0, 3));
    await gesture.up();
    await tester.pump();
  });

  testWidgets('melepas sebelum 3 detik tidak memicu SOS atau menyimpan apa pun',
      (tester) async {
    final harness = await _pump(tester);
    final gesture = await _hold(tester);
    await _advance(tester, harness.clock, const Duration(seconds: 2));
    await gesture.up();
    await tester.pump();

    expect(find.text('Tekan dan tahan 3 detik'), findsOneWidget);
    expect(harness.repository.events, isEmpty);
    expect(harness.actionRunner.activateCalls, 0);
    expect(harness.location.calls, 1);
  });

  testWidgets('Matikan SOS menghentikan senter/sirene dan menandai event batal',
      (tester) async {
    final harness = await _pump(tester);
    await _triggerSos(tester, harness);
    expect(harness.repository.events, hasLength(1));
    expect(harness.actionRunner.activateCalls, 1);

    await tester.tap(find.byKey(const ValueKey('sos-cancel')));
    await tester.pump();
    await tester.pump();

    expect(find.text('SOS dimatikan'), findsOneWidget);
    expect(harness.actionRunner.deactivateCalls, 1);
    expect(harness.actionRunner.lastDeactivatedRemoteId, 'remote-sos-1');
    final saved = harness.repository.events.values.single;
    expect(saved.status, SosEventStatus.cancelled);
    expect(saved.cancelledAtUtc, harness.clock.nowUtc());
    expect(find.byKey(const ValueKey('sos-reset')), findsOneWidget);
    expect(find.text('Matikan SOS'), findsNothing);
  });

  testWidgets(
      'tanpa perbaikan GPS senter & sirene tetap aktif meski koordinat tidak tersimpan',
      (tester) async {
    final harness = await _pump(
      tester,
      fix: null,
      outcome: const SosDispatchOutcome(
        flashlightActive: true,
        sirenActive: true,
      ),
    );
    final handle = tester.ensureSemantics();
    await _triggerSos(tester, harness);

    expect(harness.repository.events, isEmpty);
    expect(harness.actionRunner.activateCalls, 1);
    expect(
      find.textContaining('Lokasi GPS belum tersedia'),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('sos-stage-savedLocally')))
          .label,
      'Tersimpan di HP: belum',
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('sos-stage-deliveredToContact')),
          )
          .label,
      'Pesan sampai ke kontak darurat: belum',
    );
    handle.dispose();
  });

  testWidgets('kategori yang dipilih ikut tersimpan pada event lokal',
      (tester) async {
    final harness = await _pump(tester);
    final handle = tester.ensureSemantics();
    await _triggerSos(tester, harness);

    await tester.tap(find.byKey(const ValueKey('sos-category-injury')));
    await tester.pump();
    await tester.pump();

    expect(
      harness.repository.events.values.single.category,
      SosCategory.injury,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('sos-category-injury')))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('sos-category-lost')));
    await tester.pump();
    await tester.pump();
    expect(
      harness.repository.events.values.single.category,
      SosCategory.lost,
    );
    handle.dispose();
  });

  testWidgets('geser trek membuka nomor darurat yang benar', (tester) async {
    final harness = await _pump(tester);

    await _slidePast(tester, 'sos-call-115');
    await tester.pumpAndSettle();
    expect(harness.dialer.numbers, <String>['115']);

    await _slidePast(tester, 'sos-call-112');
    await tester.pumpAndSettle();
    expect(harness.dialer.numbers, <String>['115', '112']);
  });

  testWidgets('geser di bawah ambang tidak membuka nomor', (tester) async {
    final harness = await _pump(tester);
    final finder = _callTrack('sos-call-115');
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await tester.pump();
    await gesture.moveBy(Offset(tester.getSize(finder).width * 0.4, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(harness.dialer.numbers, isEmpty);
  });

  testWidgets('ketukan biasa tidak membuka nomor darurat', (tester) async {
    final harness = await _pump(tester);

    await tester.tap(_callTrack('sos-call-115'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(harness.dialer.numbers, isEmpty);
  });

  testWidgets('hanya satu trek yang dapat digeser pada satu waktu',
      (tester) async {
    final harness = await _pump(tester);
    final finder = _callTrack('sos-call-115');
    expect(
      tester.widget<SlideToCall>(_callTrack('sos-call-112')).interactive,
      isTrue,
    );

    final gesture = await tester.startGesture(tester.getCenter(finder));
    await tester.pump();
    expect(
      tester.widget<SlideToCall>(_callTrack('sos-call-112')).interactive,
      isFalse,
    );

    await gesture.moveBy(Offset(tester.getSize(finder).width * 0.4, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(harness.dialer.numbers, isEmpty);
    expect(
      tester.widget<SlideToCall>(_callTrack('sos-call-112')).interactive,
      isTrue,
    );
  });

  testWidgets('aksi semantik trek meminta konfirmasi sebelum membuka telepon',
      (tester) async {
    final harness = await _pump(tester);

    await _semanticsTap(tester, 'sos-call-112');
    expect(find.text('Telepon Darurat 112?'), findsOneWidget);
    expect(harness.dialer.numbers, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Batal'));
    await tester.pumpAndSettle();
    expect(harness.dialer.numbers, isEmpty);

    await _semanticsTap(tester, 'sos-call-112');
    await tester.tap(find.widgetWithText(FilledButton, 'Buka telepon'));
    await tester.pumpAndSettle();
    expect(harness.dialer.numbers, <String>['112']);
  });

  testWidgets('aplikasi telepon gagal dibuka menampilkan nomor manual',
      (tester) async {
    final harness = await _pump(tester, dialResult: false);

    await _slidePast(tester, 'sos-call-115');
    await tester.pump();
    await tester.pump();

    expect(harness.dialer.numbers, <String>['115']);
    expect(
      find.text(
        'Aplikasi telepon tidak dapat dibuka. Nomor 115 dapat diketik manual.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tombol tutup langsung menutup layar saat SOS tidak aktif',
      (tester) async {
    await _pump(tester);

    await tester.tap(_closeButton);
    await tester.pumpAndSettle();

    expect(find.byType(SosPage), findsNothing);
    expect(find.text(_baseRouteText), findsOneWidget);
  });

  testWidgets('tombol tutup saat SOS aktif meminta konfirmasi lalu mematikan',
      (tester) async {
    final harness = await _pump(tester);
    await _triggerSos(tester, harness);
    expect(
      harness.repository.events.values.single.status,
      SosEventStatus.active,
    );

    await tester.tap(_closeButton);
    await tester.pumpAndSettle();
    expect(find.text('Matikan SOS?'), findsOneWidget);
    expect(find.byType(SosPage), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Biarkan aktif'));
    await tester.pumpAndSettle();
    expect(find.text('Matikan SOS?'), findsNothing);
    expect(find.byType(SosPage), findsOneWidget);
    expect(
      harness.repository.events.values.single.status,
      SosEventStatus.active,
    );

    await tester.tap(_closeButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Matikan SOS'));
    await tester.pumpAndSettle();

    expect(harness.actionRunner.deactivateCalls, 1);
    expect(
      harness.repository.events.values.single.status,
      SosEventStatus.cancelled,
    );
    expect(find.byType(SosPage), findsNothing);
    expect(find.text(_baseRouteText), findsOneWidget);
  });

  testWidgets('tombol kembali Android saat SOS aktif meminta konfirmasi',
      (tester) async {
    final harness = await _pump(tester);
    await _triggerSos(tester, harness);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Matikan SOS?'), findsOneWidget);
    expect(find.byType(SosPage), findsOneWidget);
    expect(
      harness.repository.events.values.single.status,
      SosEventStatus.active,
    );
  });

  testWidgets('tombol kembali Android saat SOS diam langsung menutup layar',
      (tester) async {
    await _pump(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(SosPage), findsNothing);
  });

  testWidgets('kegagalan penyimpanan lokal tidak diklaim berhasil',
      (tester) async {
    final harness = await _pump(tester, failSave: true);
    await _triggerSos(tester, harness);

    expect(harness.repository.events, isEmpty);
    expect(
      find.text('SOS gagal disimpan di HP. Coba lagi.'),
      findsOneWidget,
    );
  });
}
