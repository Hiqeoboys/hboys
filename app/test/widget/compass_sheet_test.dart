import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/compass/domain/compass_calibration.dart';
import 'package:nama_app/features/compass/presentation/compass_sheet.dart';

class _FakeCompassStore implements CompassOffsetStore {
  _FakeCompassStore({this.offset = 0});

  double offset;
  int writes = 0;

  @override
  Future<double> readOffsetDegrees() async => offset;

  @override
  Future<void> writeOffsetDegrees(double offsetDegrees) async {
    offset = offsetDegrees;
    writes++;
  }
}

CompassEvent _event(double heading, double accuracy) =>
    CompassEvent.fromList(<double>[heading, 0, accuracy]);

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<StreamController<CompassEvent>> _pump(
  WidgetTester tester,
  _FakeCompassStore store,
) async {
  _setPhone(tester);
  final events = StreamController<CompassEvent>.broadcast();
  addTearDown(events.close);
  await tester.pumpWidget(MaterialApp(
    theme: altracqLightTheme,
    home: Scaffold(
      body: CompassSheetBody(events: events.stream, offsetStore: store),
    ),
  ));
  await tester.pumpAndSettle();
  return events;
}

void main() {
  testWidgets('heading memakai koreksi tersimpan dan akurasi sensor',
      (tester) async {
    final store = _FakeCompassStore(offset: 10);
    final events = await _pump(tester, store);

    expect(find.text('Menunggu data kompas…'), findsOneWidget);

    events.add(_event(350, 10));
    await tester.pumpAndSettle();

    expect(find.text('0° U'), findsOneWidget);
    expect(find.textContaining('±10° (tinggi)'), findsOneWidget);
    expect(find.text('Koreksi tersimpan +10,0°'), findsOneWidget);
  });

  testWidgets('menyimpan arah acuan menggeser heading dan menulis store',
      (tester) async {
    final store = _FakeCompassStore();
    final events = await _pump(tester, store);
    events.add(_event(100, 5));
    await tester.pumpAndSettle();

    expect(find.text('100° T'), findsOneWidget);
    expect(find.text('Belum ada koreksi.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '90');
    await tester.tap(find.text('Simpan koreksi'));
    await tester.pumpAndSettle();

    expect(store.writes, 1);
    expect(store.offset, 350);
    expect(find.text('90° T'), findsOneWidget);
    expect(find.text('Koreksi tersimpan.'), findsOneWidget);
    expect(find.text('Koreksi tersimpan -10,0°'), findsOneWidget);
  });

  testWidgets('arah acuan tidak valid ditolak tanpa menulis store',
      (tester) async {
    final store = _FakeCompassStore();
    final events = await _pump(tester, store);
    events.add(_event(100, 5));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'utara');
    await tester.tap(find.text('Simpan koreksi'));
    await tester.pumpAndSettle();

    expect(
      find.text('Masukkan arah acuan berupa angka derajat.'),
      findsOneWidget,
    );
    expect(store.writes, 0);
    expect(find.text('100° T'), findsOneWidget);
  });

  testWidgets('reset koreksi mengembalikan heading mentah', (tester) async {
    final store = _FakeCompassStore(offset: 45);
    final events = await _pump(tester, store);
    events.add(_event(350, 20));
    await tester.pumpAndSettle();

    expect(find.text('35° TL'), findsOneWidget);
    expect(find.textContaining('±20° (sedang)'), findsOneWidget);

    await tester.tap(find.text('Reset koreksi'));
    await tester.pumpAndSettle();

    expect(store.writes, 1);
    expect(store.offset, 0);
    expect(find.text('350° U'), findsOneWidget);
    expect(find.text('Belum ada koreksi.'), findsOneWidget);
    expect(find.text('Koreksi direset.'), findsOneWidget);
  });

  testWidgets('heading dibulatkan setelah normalisasi, bukan 360 derajat',
      (tester) async {
    final store = _FakeCompassStore();
    final events = await _pump(tester, store);
    events.add(_event(359.7, 10));
    await tester.pumpAndSettle();

    expect(find.text('0° U'), findsOneWidget);
    expect(find.text('360° U'), findsNothing);
  });

  testWidgets('platform tanpa sensor menampilkan keterbatasan', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      _setPhone(tester);
      final store = _FakeCompassStore();
      await tester.pumpWidget(MaterialApp(
        theme: altracqLightTheme,
        home: Scaffold(
          body: CompassSheetBody(offsetStore: store),
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('Sensor kompas tidak tersedia di platform ini.'),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
