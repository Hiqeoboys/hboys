import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/features/plus/domain/route_weather.dart';
import 'package:nama_app/features/plus/infrastructure/plus_local_caches.dart';
import 'package:nama_app/features/plus/presentation/route_weather_page.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/plus_fixtures.dart';
import '../support/plus_widget_harness.dart';

const String _route = 'Gunung Gede via Cibodas';
final DateTime _now = DateTime.utc(2026, 10, 31, 8);

const ValueKey<String> _sundayTempBar =
    ValueKey<String>('weather-temp-bar-2026-11-01T06:00:00.000');

const VisualEffectPolicy _reduceMotion = VisualEffectPolicy(
  powerProfile: PowerProfile.normal,
  reduceMotion: true,
  deviceTier: DeviceTier.capable,
);

void main() {
  testWidgets('unduhan demo menulis cache dan menampilkan atribusi demo',
      (tester) async {
    final repository = FakeRouteWeatherRepository(
      forecast: weatherForecast(routeName: _route, fetchedAtUtc: _now),
    );
    final cache = InMemoryRouteWeatherCache();

    await pumpPlusPage(
      tester,
      RouteWeatherPage(
        routeName: _route,
        repository: repository,
        cache: cache,
        nowUtc: _now,
      ),
    );

    expect(find.text('Cuaca rute'), findsOneWidget);
    expect(find.text(_route), findsOneWidget);
    expect(repository.fetches, 1);
    expect(cache.writes, 1);
    expect(cache.entries[_route], isNotNull);
    expect(
      find.text(
        'Menampilkan perkiraan cuaca lokal. Cuaca gunung dapat '
        'berubah sewaktu-waktu.',
      ),
      findsOneWidget,
    );
    expect(
        find.text('Sumber: BMKG · perkiraan, bukan jaminan. Cuaca gunung '
            'dapat berubah cepat.'),
        findsNothing);
    expect(find.textContaining('tersimpan offline'), findsNothing);
    expect(find.text('18°C'), findsOneWidget);
    expect(find.text('Per 3 jam'), findsOneWidget);
    expect(find.text('Per pos'), findsOneWidget);
    expect(find.text('Pos 1'), findsOneWidget);
    expect(find.text('Puncak'), findsOneWidget);
    expect(find.text('Memperbarui prakiraan…'), findsNothing);
  });

  testWidgets('sumber BMKG memakai atribusi resmi dan label perkiraan',
      (tester) async {
    final repository = FakeRouteWeatherRepository(
      forecast: weatherForecast(
        routeName: _route,
        fetchedAtUtc: _now,
        source: bmkgSource,
      ),
    );

    await pumpPlusPage(
      tester,
      RouteWeatherPage(
        routeName: _route,
        repository: repository,
        cache: InMemoryRouteWeatherCache(),
        nowUtc: _now,
      ),
    );

    expect(
      find.text(
        'Sumber: BMKG · perkiraan, bukan jaminan. Cuaca gunung dapat '
        'berubah cepat.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Menampilkan perkiraan cuaca lokal'),
      findsNothing,
    );
    expect(find.text('SUHU PUNCAK · PERKIRAAN'), findsOneWidget);
  });

  testWidgets(
      'cache segar dipakai tanpa memanggil jaringan (tersimpan offline)',
      (tester) async {
    final cache = InMemoryRouteWeatherCache();
    final cached = weatherForecast(
      routeName: _route,
      fetchedAtUtc: _now.subtract(const Duration(hours: 1)),
    );
    cache.entries[_route] = cached;
    final repository = FakeRouteWeatherRepository();

    await pumpPlusPage(
      tester,
      RouteWeatherPage(
        routeName: _route,
        repository: repository,
        cache: cache,
        nowUtc: _now,
      ),
    );

    expect(repository.fetches, 0);
    expect(find.textContaining('tersimpan offline'), findsOneWidget);
    expect(find.text('18°C'), findsOneWidget);
    expect(find.text('Cuaca belum tersedia'), findsNothing);
  });

  testWidgets('cache kedaluwarsa + gagal unduh tetap menampilkan data cache',
      (tester) async {
    final cache = InMemoryRouteWeatherCache();
    cache.entries[_route] = weatherForecast(
      routeName: _route,
      fetchedAtUtc: _now.subtract(const Duration(hours: 13)),
    );
    final repository = FakeRouteWeatherRepository(
      error: 'Server cuaca sedang sibuk.',
    );

    await pumpPlusPage(
      tester,
      RouteWeatherPage(
        routeName: _route,
        repository: repository,
        cache: cache,
        nowUtc: _now,
      ),
    );

    expect(repository.fetches, 1);
    expect(find.textContaining('tersimpan offline'), findsOneWidget);
    expect(find.text('Pos 1'), findsOneWidget);
    expect(
      find.text('Server cuaca sedang sibuk. Data tersimpan tetap dipakai.'),
      findsOneWidget,
    );
    expect(find.text('Cuaca belum tersedia'), findsNothing);
  });

  testWidgets(
      'galat tanpa cache menampilkan keadaan kosong lalu bisa dicoba lagi',
      (tester) async {
    final repository =
        FakeRouteWeatherRepository(error: 'Prakiraan belum ada.');
    final cache = InMemoryRouteWeatherCache();

    await pumpPlusPage(
      tester,
      RouteWeatherPage(
        routeName: _route,
        repository: repository,
        cache: cache,
        nowUtc: _now,
      ),
    );

    expect(find.text('Cuaca belum tersedia'), findsOneWidget);
    expect(find.text('Prakiraan belum ada.'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);
    expect(repository.fetches, 1);

    repository.error = null;
    repository.forecast = weatherForecast(
      routeName: _route,
      fetchedAtUtc: _now,
    );
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(repository.fetches, 2);
    expect(cache.writes, 1);
    expect(find.text('Cuaca belum tersedia'), findsNothing);
    expect(find.text('18°C'), findsOneWidget);
    expect(find.text('Pos 1'), findsOneWidget);
  });

  testWidgets('tab hari mengganti isi prakiraan', (tester) async {
    final repository = FakeRouteWeatherRepository(
      forecast: weatherForecast(routeName: _route, fetchedAtUtc: _now),
    );

    await pumpPlusPage(
      tester,
      RouteWeatherPage(
        routeName: _route,
        repository: repository,
        cache: InMemoryRouteWeatherCache(),
        nowUtc: _now,
      ),
    );

    expect(find.byKey(const ValueKey('weather-day-tabs')), findsOneWidget);
    expect(find.text('Sabtu'), findsOneWidget);
    expect(find.text('Minggu'), findsOneWidget);
    expect(find.text('18°C'), findsOneWidget);
    expect(find.text('19°C'), findsNothing);

    await tester.tap(find.text('Minggu'));
    await tester.pumpAndSettle();

    expect(find.text('19°C'), findsOneWidget);
    expect(find.text('18°C'), findsNothing);
    expect(find.text('41%'), findsOneWidget);
  });

  testWidgets('batang grafik tumbuh dengan pegas saat hari berganti',
      (tester) async {
    final repository = FakeRouteWeatherRepository(
      forecast: weatherForecast(routeName: _route, fetchedAtUtc: _now),
    );

    await pumpPlusPage(
      tester,
      RouteWeatherPage(
        routeName: _route,
        repository: repository,
        cache: InMemoryRouteWeatherCache(),
        nowUtc: _now,
      ),
    );

    await tester.tap(find.text('Minggu'));
    await tester.pump();

    final start = tester.getSize(find.byKey(_sundayTempBar)).height;
    await tester.pump(const Duration(milliseconds: 50));
    final mid = tester.getSize(find.byKey(_sundayTempBar)).height;
    await tester.pumpAndSettle();
    final end = tester.getSize(find.byKey(_sundayTempBar)).height;

    expect(start, closeTo(26 * 0.62, 0.001));
    expect(mid, greaterThan(start));
    expect(mid, lessThan(end));
    expect(end, closeTo(26, 0.001));
  });

  testWidgets('kurangi gerakan membuat batang langsung setinggi akhir',
      (tester) async {
    final repository = FakeRouteWeatherRepository(
      forecast: weatherForecast(routeName: _route, fetchedAtUtc: _now),
    );

    await pumpPlusPage(
      tester,
      RouteWeatherPage(
        routeName: _route,
        repository: repository,
        cache: InMemoryRouteWeatherCache(),
        nowUtc: _now,
      ),
      policy: _reduceMotion,
    );

    await tester.tap(find.text('Minggu'));
    await tester.pump();

    expect(
      tester.getSize(find.byKey(_sundayTempBar)).height,
      closeTo(26, 0.001),
    );
  });
}
