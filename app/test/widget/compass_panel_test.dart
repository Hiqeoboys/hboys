import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/compass/domain/compass_calibration.dart';
import 'package:nama_app/features/compass/presentation/compass_panel.dart';

class FakeCompassOffsetStore implements CompassOffsetStore {
  FakeCompassOffsetStore(this.offset);

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

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late StreamController<CompassEvent> events;
  late FakeCompassOffsetStore store;

  setUp(() {
    events = StreamController<CompassEvent>.broadcast();
    store = FakeCompassOffsetStore(0);
  });

  tearDown(() async {
    await events.close();
  });

  testWidgets('menampilkan heading terkoreksi dan akurasi', (tester) async {
    store.offset = 10;
    await tester.pumpWidget(_app(CompassPanel(
      events: events.stream,
      offsetStore: store,
    )));
    await tester.pumpAndSettle();

    events.add(CompassEvent.fromList(<double>[350, 0, 10]));
    await tester.pumpAndSettle();

    expect(find.text('0° U'), findsOneWidget);
    expect(find.textContaining('±10° (tinggi)'), findsOneWidget);
  });

  testWidgets('koreksi manual disimpan dan diterapkan', (tester) async {
    await tester.pumpWidget(_app(CompassPanel(
      events: events.stream,
      offsetStore: store,
    )));
    await tester.pumpAndSettle();

    events.add(CompassEvent.fromList(<double>[100, 0, 10]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kalibrasi manual'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '90');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(store.writes, 1);
    expect(store.offset, 350);
    expect(find.text('90° T'), findsOneWidget);
    expect(find.textContaining('Koreksi -10.0°'), findsOneWidget);

    await tester.tap(find.text('Reset koreksi'));
    await tester.pumpAndSettle();

    expect(store.offset, 0);
    expect(find.text('100° T'), findsOneWidget);
  });

  testWidgets('tanpa heading menampilkan pesan yang jujur', (tester) async {
    await tester.pumpWidget(_app(CompassPanel(
      events: events.stream,
      offsetStore: store,
    )));
    await tester.pumpAndSettle();

    events.add(CompassEvent.fromList(null));
    await tester.pumpAndSettle();

    expect(
      find.text('Perangkat tidak melaporkan heading kompas.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('hanya bisa menyimpan koreksi arah manual'),
      findsOneWidget,
    );
  });

  testWidgets(
    'stream kosong berarti sensor tidak tersedia',
    (tester) async {
      await tester.pumpWidget(_app(CompassPanel(
        events: null,
        offsetStore: store,
      )));
      await tester.pumpAndSettle();

      expect(
        find.text('Sensor kompas tidak tersedia di platform ini.'),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
