import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/design/glass/hiqeo_liquid_glass.dart';
import 'package:nama_app/features/plus/application/plus_navigation.dart';
import 'package:nama_app/features/plus/domain/route_weather.dart';
import 'package:nama_app/features/plus/infrastructure/plus_local_caches.dart';
import 'package:nama_app/features/plus/presentation/route_estimate_page.dart';
import 'package:nama_app/features/plus/presentation/route_weather_page.dart';

import '../support/plus_fixtures.dart';
import '../support/plus_widget_harness.dart';

void main() {
  testWidgets(
      'RouteWeatherPage Open-Meteo menampilkan suhu basecamp vs puncak, 24 jam, 7 hari, peringatan hipotermia & cache offline',
      (tester) async {
    final nowUtc = DateTime.utc(2026, 11, 21, 5, 0);
    final baseLocal = nowUtc.toLocal();
    final day0 = DateTime(baseLocal.year, baseLocal.month, baseLocal.day);

    final forecast = RouteWeatherForecast(
      routeName: 'Gunung Gede · Via Putri',
      source: openMeteoSource,
      fetchedAtUtc: nowUtc.subtract(const Duration(minutes: 42)),
      basecampElevationM: 1548,
      summitElevationM: 2958,
      currentBasecampTempC: 16.0,
      currentSummitTempC: 6.8,
      currentRainPercent: 60,
      currentWindSpeedKmh: 28.0,
      currentHumidityPercent: 84,
      currentUvIndex: 7.4,
      next24Hours: <RouteWeatherHour>[
        RouteWeatherHour(
          timeLocal: day0.add(const Duration(hours: 12)),
          temperatureC: 7.0,
          rainPercent: 60,
          condition: WeatherCondition.lightRain,
          windSpeedKmh: 28.0,
        ),
        RouteWeatherHour(
          timeLocal: day0.add(const Duration(hours: 15)),
          temperatureC: 6.5,
          rainPercent: 75,
          condition: WeatherCondition.rain,
          windSpeedKmh: 30.0,
        ),
      ],
      days: <RouteWeatherDay>[
        for (var i = 0; i < 6; i++)
          RouteWeatherDay(
            dateLocal: day0.add(Duration(days: i)),
            peakTemperatureC: 9.0,
            minTemperatureC: 6.5,
            basecampTemperatureC: 18.0,
            peakRainPercent: 65,
            windSpeedKmh: 28.0,
            humidityPercent: 84,
            uvIndexMax: 7.4,
            sunriseLocal: day0.add(Duration(days: i, hours: 5, minutes: 45)),
            sunsetLocal: day0.add(Duration(days: i, hours: 17, minutes: 50)),
            condition: WeatherCondition.rain,
            hours: <RouteWeatherHour>[
              RouteWeatherHour(
                timeLocal: day0.add(Duration(days: i, hours: 6)),
                temperatureC: 6.5,
                rainPercent: 40,
                condition: WeatherCondition.partlyCloudy,
              ),
              RouteWeatherHour(
                timeLocal: day0.add(Duration(days: i, hours: 12)),
                temperatureC: 9.0,
                rainPercent: 65,
                condition: WeatherCondition.rain,
              ),
            ],
            posts: const <RouteWeatherPost>[
              RouteWeatherPost(
                name: 'Basecamp',
                altitudeM: 1548,
                temperatureC: 18.0,
                rainPercent: 55,
                condition: WeatherCondition.rain,
              ),
              RouteWeatherPost(
                name: 'Puncak Gede',
                altitudeM: 2958,
                temperatureC: 9.0,
                rainPercent: 65,
                condition: WeatherCondition.rain,
              ),
            ],
          ),
      ],
    );

    final cache = InMemoryRouteWeatherCache();
    cache.entries['Gunung Gede · Via Putri'] = forecast;

    await pumpPlusPage(
      tester,
      RouteWeatherPage(
        routeName: 'Gunung Gede · Via Putri',
        repository: FakeRouteWeatherRepository(forecast: forecast),
        cache: cache,
        nowUtc: nowUtc,
      ),
    );

    // Tombol kembali Liquid Glass bundar aktif
    expect(find.byType(HiqeoGlassCircleButton), findsOneWidget);

    // Peringatan hipotermia otomatis muncul karena suhu puncak < 8°C
    expect(
      find.byKey(const ValueKey<String>('weather-warning-hypothermia')),
      findsOneWidget,
    );

    // Perbedaan Basecamp vs Puncak & metrik pendaki
    expect(
      find.byKey(const ValueKey<String>('weather-basecamp-temp')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('weather-summit-temp')),
      findsOneWidget,
    );
    expect(find.text('16°C'), findsOneWidget);
    expect(find.text('7°C'), findsWidgets);
    expect(find.text('28 km/jam'), findsOneWidget);
    expect(find.text('84%'), findsOneWidget);
    expect(find.text('7,4'), findsOneWidget);
    expect(find.text('05.45'), findsOneWidget);
    expect(find.text('17.50'), findsOneWidget);

    // Strip 24 jam ke depan + timestamp cache relatif + offline badge
    expect(find.byKey(const ValueKey<String>('weather-24h-card')), findsOneWidget);
    expect(
      find.textContaining('Diperbarui 42 menit lalu'),
      findsOneWidget,
    );
    expect(find.textContaining('tersimpan offline'), findsOneWidget);
  });

  testWidgets(
      'RouteEstimatePage kalkulator menghitung ulang otomatis tanpa DB saat kecepatan & beban diubah',
      (tester) async {
    await pumpPlusPage(
      tester,
      RouteEstimatePage(
        route: const PlusRouteContext(
          name: 'Gunung Gede · Via Putri',
          mountainId: 'gede',
          trailId: 'gede_putri',
          trailName: 'Via Putri',
          gpxAssetPath: 'assets/gpx/GEDE VIA PUTRI.gpx',
          distanceM: 6400,
          elevationGainM: 1410,
          basecampElevationM: 1548,
          summitElevationM: 2958,
          points: <LatLng>[
            LatLng(-6.7556, 107.0100),
            LatLng(-6.7899, 106.9831),
          ],
        ),
        nowLocal: DateTime(2026, 11, 21, 6, 0),
      ),
    );

    // Memakai tombol kembali Liquid Glass bundar
    expect(find.byType(HiqeoGlassCircleButton), findsOneWidget);

    // Kontrol & rincian hasil lengkap
    expect(find.byKey(const ValueKey<String>('estimate-pace-cepat')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('estimate-load-berat')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('estimate-start-time-picker')), findsOneWidget);
    expect(find.text('Rencana jam mulai'), findsOneWidget);
    expect(find.text('Ketuk tombol jam untuk menyesuaikan waktu'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('estimate-start-time-picker')),
        matching: find.byIcon(Icons.schedule_rounded),
      ),
      findsOneWidget,
    );
    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      (scrollView.padding! as EdgeInsets).top,
      greaterThanOrEqualTo(8.0),
    );
    expect(find.byKey(const ValueKey<String>('estimate-post-timeline')), findsOneWidget);

    String textInside(String key) {
      final col = tester.widget<Column>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(Column),
        ),
      );
      return (col.children[2] as Text).data ?? '';
    }

    final normalTotal = textInside('estimate-total-value');
    final normalWater = textInside('estimate-water-value');
    final normalCalories = textInside('estimate-calories-value');

    // Ganti ke Cepat -> total durasi langsung memendek
    await tester.tap(find.byKey(const ValueKey<String>('estimate-pace-cepat')));
    await tester.pumpAndSettle();
    final fastTotal = textInside('estimate-total-value');
    expect(fastTotal, isNot(normalTotal));

    // Kembali Normal & pilih Beban Berat -> durasi, air, & kalori meningkat
    await tester.tap(find.byKey(const ValueKey<String>('estimate-pace-normal')));
    await tester.tap(find.byKey(const ValueKey<String>('estimate-load-berat')));
    await tester.pumpAndSettle();
    expect(textInside('estimate-total-value'), isNot(normalTotal));
    expect(textInside('estimate-water-value'), isNot(normalWater));
    expect(textInside('estimate-calories-value'), isNot(normalCalories));
  });
}
