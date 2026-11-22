import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nama_app/features/plus/domain/route_estimate.dart';
import 'package:nama_app/features/plus/domain/route_weather.dart';
import 'package:nama_app/features/plus/infrastructure/open_meteo_route_weather.dart';
import 'package:nama_app/features/trails/data/gpx_loader.dart';

Map<String, dynamic> _sampleOpenMeteoJson(DateTime startLocal) {
  final times = <String>[];
  final temps = <double>[];
  final rains = <int>[];
  final hums = <int>[];
  final codes = <int>[];
  final winds = <double>[];
  final uvs = <double>[];

  for (var h = 0; h < 7 * 24; h++) {
    final t = DateTime(startLocal.year, startLocal.month, startLocal.day)
        .add(Duration(hours: h));
    times.add(t.toIso8601String());
    temps.add(16.0 + (h % 24 == 13 ? 4.0 : 0.0));
    rains.add(h % 24 >= 12 ? 60 : 15);
    hums.add(82);
    codes.add(h % 24 >= 12 ? 61 : 2);
    winds.add(h < 24 ? 22.0 : 18.0);
    uvs.add(h % 24 == 12 ? 8.5 : 3.0);
  }

  final dTimes = <String>[];
  final dMax = <double>[];
  final dMin = <double>[];
  final dRain = <int>[];
  final dCode = <int>[];
  final dWind = <double>[];
  final dUv = <double>[];
  final dRise = <String>[];
  final dSet = <String>[];

  for (var d = 0; d < 7; d++) {
    final day = DateTime(startLocal.year, startLocal.month, startLocal.day + d);
    dTimes.add(
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    );
    dMax.add(20.0);
    dMin.add(14.0);
    dRain.add(d == 1 ? 85 : 40);
    dCode.add(d == 1 ? 95 : 61);
    dWind.add(d == 2 ? 42.0 : 20.0);
    dUv.add(7.2);
    dRise.add('${dTimes.last}T05:45');
    dSet.add('${dTimes.last}T17:50');
  }

  return <String, dynamic>{
    'elevation': 1500.0,
    'current': <String, dynamic>{
      'temperature_2m': 18.0,
      'relative_humidity_2m': 78,
      'weather_code': 2,
      'wind_speed_10m': 19.0,
      'precipitation_probability': 30,
    },
    'hourly': <String, dynamic>{
      'time': times,
      'temperature_2m': temps,
      'precipitation_probability': rains,
      'relative_humidity_2m': hums,
      'weather_code': codes,
      'wind_speed_10m': winds,
      'uv_index': uvs,
    },
    'daily': <String, dynamic>{
      'time': dTimes,
      'temperature_2m_max': dMax,
      'temperature_2m_min': dMin,
      'precipitation_probability_max': dRain,
      'weather_code': dCode,
      'wind_speed_10m_max': dWind,
      'uv_index_max': dUv,
      'sunrise': dRise,
      'sunset': dSet,
    },
  };
}

void main() {
  test('lapse rate menurunkan tepat -0,65 C per 100 m kenaikan', () {
    final temp = adjustTempByLapseRate(
      20.0,
      refElevationM: 1500,
      targetElevationM: 2900,
    );
    expect(temp, closeTo(20.0 - (14 * 0.65), 0.001));
  });

  test('formatRelativeUpdatedAgo menghasilkan teks relatif rapi', () {
    final now = DateTime.utc(2026, 11, 21, 10, 0);
    expect(
      formatRelativeUpdatedAgo(now.subtract(const Duration(seconds: 20)), now),
      'Diperbarui baru saja',
    );
    expect(
      formatRelativeUpdatedAgo(now.subtract(const Duration(minutes: 18)), now),
      'Diperbarui 18 menit lalu',
    );
    expect(
      formatRelativeUpdatedAgo(now.subtract(const Duration(hours: 3)), now),
      'Diperbarui 3 jam lalu',
    );
  });

  test('OpenMeteoRouteWeatherRepository memanggil api.open-meteo.com dan menghitung suhu puncak', () async {
    Uri? capturedUri;
    final nowLocal = DateTime(2026, 11, 21, 8, 0);
    final mockClient = MockClient((request) async {
      capturedUri = request.url;
      return http.Response(jsonEncode(_sampleOpenMeteoJson(nowLocal)), 200);
    });

    final repo = OpenMeteoRouteWeatherRepository(client: mockClient);
    final forecast = await repo.fetch(
      routeName: 'Gunung Gede · Via Putri',
      nowLocal: nowLocal,
    );

    expect(capturedUri?.host, 'api.open-meteo.com');
    expect(capturedUri?.path, '/v1/forecast');
    expect(forecast.source, openMeteoSource);
    expect(forecast.days.length, 7);
    expect(forecast.next24Hours.length, 24);
    expect(forecast.currentBasecampTempC, isNotNull);
    expect(forecast.currentSummitTempC, isNotNull);
    expect(
      forecast.currentSummitTempC!,
      lessThan(forecast.currentBasecampTempC! - 8.0),
    );
    expect(forecast.days.first.sunriseLocal, isNotNull);
    expect(forecast.days.first.sunsetLocal, isNotNull);
    expect(forecast.days.first.windSpeedKmh, 20.0);
  });

  test('evaluateWeatherSafetyWarnings mendeteksi hipotermia, badai, dan angin kencang', () {
    final day = RouteWeatherDay(
      dateLocal: DateTime(2026, 11, 21),
      peakTemperatureC: 6.5,
      minTemperatureC: 4.5,
      peakRainPercent: 85,
      windSpeedKmh: 42.0,
      weatherCode: 95,
      condition: WeatherCondition.heavyRain,
      hours: const <RouteWeatherHour>[],
      posts: const <RouteWeatherPost>[],
    );

    final alerts = evaluateWeatherSafetyWarnings(day);
    expect(alerts.map((a) => a.id), containsAll(<String>['hypothermia', 'storm', 'wind']));
  });

  test('HikingPlanEstimate menghitung durasi Naismith/Tobler, air, kalori, dan ETA pos', () {
    const sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1">
  <wpt lat="-6.7676" lon="107.0014"><ele>1868</ele><name>POS 1</name></wpt>
  <wpt lat="-6.7899" lon="106.9831"><ele>2949</ele><name>PUNCAK GEDE</name><sym>Summit</sym></wpt>
  <trk><name>GEDE</name><trkseg>
    <trkpt lat="-6.7556" lon="107.0100"><ele>1548</ele></trkpt>
    <trkpt lat="-6.7676" lon="107.0014"><ele>1868</ele></trkpt>
    <trkpt lat="-6.7899" lon="106.9831"><ele>2949</ele></trkpt>
  </trkseg></trk>
</gpx>''';

    final route = GpxLoader.parseString(sampleGpx);
    expect(route.waypoints.length, 2);
    expect(route.waypoints.first.name, 'POS 1');

    final normalLight = HikingPlanEstimate.calculate(
      routeName: 'Gunung Gede',
      distanceM: 6400,
      elevationGainM: 1410,
      basecampElevationM: 1548,
      summitElevationM: 2958,
      startLocal: DateTime(2026, 11, 21, 6, 0),
      pace: HikingPace.normal,
      load: CarrierLoad.ringan,
      waypoints: route.waypoints,
    );
    final fastLight = HikingPlanEstimate.calculate(
      routeName: 'Gunung Gede',
      distanceM: 6400,
      elevationGainM: 1410,
      basecampElevationM: 1548,
      summitElevationM: 2958,
      startLocal: DateTime(2026, 11, 21, 6, 0),
      pace: HikingPace.cepat,
      load: CarrierLoad.ringan,
      waypoints: route.waypoints,
    );
    final normalHeavy = HikingPlanEstimate.calculate(
      routeName: 'Gunung Gede',
      distanceM: 6400,
      elevationGainM: 1410,
      basecampElevationM: 1548,
      summitElevationM: 2958,
      startLocal: DateTime(2026, 11, 21, 6, 0),
      pace: HikingPace.normal,
      load: CarrierLoad.berat,
      waypoints: route.waypoints,
    );

    expect(fastLight.totalRoundTrip, lessThan(normalLight.totalRoundTrip));
    expect(normalHeavy.totalRoundTrip, greaterThan(normalLight.totalRoundTrip));
    expect(normalHeavy.waterLiters, greaterThan(normalLight.waterLiters));
    expect(normalHeavy.caloriesKcal, greaterThan(normalLight.caloriesKcal));
    expect(
      normalLight.postEtas.map((p) => p.name).toList(),
      <String>['Basecamp', 'POS 1', 'PUNCAK GEDE', 'Kembali ke Basecamp'],
    );
    // ETA selalu urut naik
    for (var i = 1; i < normalLight.postEtas.length; i++) {
      expect(
        normalLight.postEtas[i].etaLocal
            .isBefore(normalLight.postEtas[i - 1].etaLocal),
        isFalse,
      );
    }
  });
}
