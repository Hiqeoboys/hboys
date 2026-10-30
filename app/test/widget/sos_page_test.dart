import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/platform/phone_dialer.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/features/safety/application/sos_location.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_category.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
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

class _Harness {
  _Harness({
    required this.clock,
    required this.repository,
    required this.location,
    required this.dialer,
  });

  final FakeClock clock;
  final _FakeSafetyRepository repository;
  final _FakeLocation location;
  final _FakeDialer dialer;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  SosFix? fix = const SosFix(lat: -6.8, lon: 106.9, accuracyM: 8),
  bool failSave = false,
  bool dialResult = true,
}) async {
  tester.view.physicalSize = const Size(390, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final clock = FakeClock(DateTime.utc(2026, 10, 30, 3));
  final repository = _FakeSafetyRepository()..failSave = failSave;
  final location = _FakeLocation(fix);
  final dialer = _FakeDialer()..result = dialResult;

  await tester.pumpWidget(
    MaterialApp(
      theme: altracqLightTheme,
      home: SosPage(
        repository: repository,
        locationProvider: location,
        dialer: dialer,
        clock: clock,
      ),
    ),
  );
  await tester.pump();
  return _Harness(
    clock: clock,
    repository: repository,
    location: location,
    dialer: dialer,
  );
}

Finder get _ring => find.byKey(const ValueKey('sos-ring'));

Future<TestGesture> _hold(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(_ring));
  await tester.pump();
  return gesture;
}

Future<void> _advance(
  WidgetTester tester,
  FakeClock clock,
  Duration duration,
) async {
  clock.advance(duration);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('layar diam jujur dan memakai palet terbalik', (tester) async {
    await _pump(tester);

    expect(find.text('SOS'), findsNWidgets(2));
    expect(
      find.text('Tekan-tahan 3 detik untuk memulai'),
      findsOneWidget,
    );
    expect(
      find.text('SOS hanya tersimpan di HP ini. Tidak ada pengiriman otomatis.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sos-cancel')), findsNothing);
    expect(find.text('Basarnas 115'), findsOneWidget);
    expect(find.text('Darurat 112'), findsOneWidget);
    expect(
      find.text(
        'SOS tidak menjamin pertolongan datang. Altracq tidak mengklaim '
        'telah menghubungi Basarnas.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('dikirim otomatis'), findsNothing);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AltracqColors.dark.background);
  });

  testWidgets('tekan-tahan 3 detik menyimpan SOS lokal dengan lokasi nyata',
      (tester) async {
    final harness = await _pump(tester);
    final gesture = await _hold(tester);
    await _advance(tester, harness.clock, const Duration(seconds: 3));

    expect(find.text('3'), findsOneWidget);
    expect(find.text('Tekan-tahan 3 detik telah terpenuhi'), findsOneWidget);
    expect(
      find.text('SOS disimpan otomatis, kecuali dibatalkan.'),
      findsOneWidget,
    );
    expect(find.text('Batal, saya aman'), findsOneWidget);
    expect(find.text('CEDERA'), findsOneWidget);
    expect(find.text('TERSESAT'), findsOneWidget);
    expect(find.text('CUACA'), findsOneWidget);
    expect(find.text('Diterima 0 anggota'), findsOneWidget);
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

    await _advance(tester, harness.clock, const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await _advance(tester, harness.clock, const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    await _advance(tester, harness.clock, const Duration(seconds: 1));

    expect(
      find.text(
        'SOS tersimpan di HP. Tidak ada pengiriman otomatis ke anggota atau '
        'kontak darurat.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Hanya penyimpanan lokal yang terjadi'),
      findsOneWidget,
    );
  });

  testWidgets('melepas sebelum 3 detik tidak menyimpan apa pun', (tester) async {
    final harness = await _pump(tester);
    final gesture = await _hold(tester);
    await _advance(tester, harness.clock, const Duration(seconds: 2));
    await gesture.up();
    await tester.pump();

    expect(
      find.text('SOS hanya tersimpan di HP ini. Tidak ada pengiriman otomatis.'),
      findsOneWidget,
    );
    expect(harness.repository.events, isEmpty);
    expect(harness.location.calls, 1);
  });

  testWidgets('batal saat hitung mundur menandai event lokal sebagai batal',
      (tester) async {
    final harness = await _pump(tester);
    final gesture = await _hold(tester);
    await _advance(tester, harness.clock, const Duration(seconds: 3));
    await gesture.up();
    expect(harness.repository.events, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('sos-cancel')));
    await tester.pump();
    await tester.pump();

    expect(find.text('SOS dibatalkan'), findsOneWidget);
    expect(
      find.text(
        'SOS dibatalkan. Data lokal ditandai batal; tidak ada pesan terkirim.',
      ),
      findsOneWidget,
    );
    final saved = harness.repository.events.values.single;
    expect(saved.status, SosEventStatus.cancelled);
    expect(saved.cancelledAtUtc, harness.clock.nowUtc());
    expect(find.byKey(const ValueKey('sos-reset')), findsOneWidget);
  });

  testWidgets('batal setelah hitung mundur selesai menandai event lokal batal',
      (tester) async {
    final harness = await _pump(tester);
    final gesture = await _hold(tester);
    await _advance(tester, harness.clock, const Duration(seconds: 3));
    await gesture.up();
    await _advance(tester, harness.clock, const Duration(seconds: 3));
    expect(
      find.text(
        'SOS tersimpan di HP. Tidak ada pengiriman otomatis ke anggota atau '
        'kontak darurat.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('sos-cancel')));
    await tester.pump();
    await tester.pump();

    expect(find.text('SOS dibatalkan'), findsOneWidget);
    expect(
      find.text(
        'SOS dibatalkan. Data lokal ditandai batal; tidak ada pesan terkirim.',
      ),
      findsOneWidget,
    );
    final saved = harness.repository.events.values.single;
    expect(saved.status, SosEventStatus.cancelled);
    expect(saved.cancelledAtUtc, harness.clock.nowUtc());
    expect(find.byKey(const ValueKey('sos-reset')), findsOneWidget);
    expect(find.text('Batal, saya aman'), findsNothing);
  });

  testWidgets('tanpa perbaikan GPS tidak ada SOS yang disimpan', (tester) async {
    final harness = await _pump(tester, fix: null);
    final handle = tester.ensureSemantics();
    final gesture = await _hold(tester);
    await _advance(tester, harness.clock, const Duration(seconds: 3));
    await gesture.up();

    expect(harness.repository.events, isEmpty);
    expect(
      find.textContaining('Lokasi GPS belum tersedia. SOS tidak tersimpan'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('sos-stage-savedLocally'))).label,
      'Tersimpan di HP: belum',
    );

    await _advance(tester, harness.clock, const Duration(seconds: 3));
    expect(
      find.textContaining('Lokasi GPS belum tersedia. SOS tidak tersimpan'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('sos-stage-deliveredToContact'))).label,
      'Pesan sampai ke kontak darurat: belum',
    );
    handle.dispose();
  });

  testWidgets('kategori yang dipilih ikut tersimpan pada event lokal',
      (tester) async {
    final harness = await _pump(tester);
    final handle = tester.ensureSemantics();
    final gesture = await _hold(tester);
    await _advance(tester, harness.clock, const Duration(seconds: 3));
    await gesture.up();
    await _advance(tester, harness.clock, const Duration(seconds: 3));

    await tester.tap(find.byKey(const ValueKey('sos-category-injury')));
    await tester.pump();
    await tester.pump();

    expect(
      harness.repository.events.values.single.category,
      SosCategory.injury,
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('sos-category-injury'))).flagsCollection.isSelected,
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

  testWidgets('tombol telepon membuka nomor darurat yang benar', (tester) async {
    final harness = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('sos-call-115')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sos-call-112')));
    await tester.pump();

    expect(harness.dialer.numbers, <String>['115', '112']);
  });

  testWidgets('aplikasi telepon gagal dibuka menampilkan nomor manual',
      (tester) async {
    final harness = await _pump(tester, dialResult: false);

    await tester.tap(find.byKey(const ValueKey('sos-call-115')));
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

  testWidgets('kegagalan penyimpanan lokal tidak diklaim berhasil',
      (tester) async {
    final harness = await _pump(tester, failSave: true);
    final gesture = await _hold(tester);
    await _advance(tester, harness.clock, const Duration(seconds: 3));
    await gesture.up();

    expect(harness.repository.events, isEmpty);
    expect(
      find.text('SOS gagal disimpan di HP. Coba lagi.'),
      findsOneWidget,
    );

    await _advance(tester, harness.clock, const Duration(seconds: 3));
    expect(
      find.text('SOS gagal disimpan di HP. Coba lagi.'),
      findsOneWidget,
    );
  });
}
