import 'dart:math' as math;

import '../domain/route_weather.dart';

/// Prakiraan contoh yang HANYA boleh hidup di build debug.
///
/// Angka dihasilkan deterministik dari nama rute dan tanggal, bukan dari BMKG.
/// [source] sengaja bukan [bmkgSource] agar layar menampilkan penanda demo.
class DebugRouteWeatherRepository implements RouteWeatherRepository {
  const DebugRouteWeatherRepository();

  static const String demoSource = 'Demo lokal';

  @override
  Future<RouteWeatherForecast> fetch({
    required String routeName,
    required DateTime nowLocal,
  }) async {
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final days = <RouteWeatherDay>[];
    for (var offset = 0; offset < 3; offset++) {
      final date = today.add(Duration(days: offset));
      final seed = _seed(routeName, date);
      final base = 16 + (seed % 6);
      final nextSeed = _seed(routeName, date.add(const Duration(days: 1)));
      final hours = <RouteWeatherHour>[];
      for (var hour = 0; hour < 24; hour += 3) {
        final curve = math.cos((hour - 14) / 24 * 2 * math.pi) * 5.5;
        final jitter = (_unit(seed, hour) - 0.5) * 2.4;
        final temperature = (base + curve + jitter).roundToDouble();
        final rain = ((_unit(nextSeed, hour) * 100) + (hour >= 12 ? 8 : 0))
            .round()
            .clamp(0, 95);
        hours.add(
          RouteWeatherHour(
            timeLocal: date.add(Duration(hours: hour)),
            temperatureC: temperature,
            rainPercent: rain,
            condition: _conditionFor(rain),
          ),
        );
      }
      var peak = hours.first;
      var rainiest = hours.first;
      for (final hour in hours) {
        if (hour.temperatureC > peak.temperatureC) peak = hour;
        if (hour.rainPercent > rainiest.rainPercent) rainiest = hour;
      }
      final dayRain = rainiest.rainPercent;
      days.add(
        RouteWeatherDay(
          dateLocal: date,
          peakTemperatureC: peak.temperatureC,
          peakRainPercent: dayRain,
          condition: _conditionFor(dayRain),
          hours: List<RouteWeatherHour>.unmodifiable(hours),
          posts: _posts(seed, dayRain),
        ),
      );
    }
    return RouteWeatherForecast(
      routeName: routeName,
      source: demoSource,
      fetchedAtUtc: nowLocal.toUtc(),
      days: List<RouteWeatherDay>.unmodifiable(days),
    );
  }

  /// Pos generik dengan penurunan suhu 0,6 °C per 100 m.
  List<RouteWeatherPost> _posts(int seed, int dayRain) {
    const names = <String>['Pos 1', 'Pos 2', 'Pos 3', 'Puncak'];
    const altitudes = <double>[1500, 1900, 2300, 2700];
    final base = 20.0 + (seed % 4);
    return <RouteWeatherPost>[
      for (var i = 0; i < names.length; i++)
        RouteWeatherPost(
          name: names[i],
          altitudeM: altitudes[i],
          temperatureC: (base - (altitudes[i] - 1000) * 0.006).roundToDouble(),
          rainPercent: (dayRain + i * 4).clamp(0, 95),
          condition: _conditionFor((dayRain + i * 4).clamp(0, 95)),
        ),
    ];
  }

  WeatherCondition _conditionFor(int rain) {
    if (rain < 20) return WeatherCondition.clear;
    if (rain < 40) return WeatherCondition.partlyCloudy;
    if (rain < 60) return WeatherCondition.lightRain;
    if (rain < 80) return WeatherCondition.rain;
    return WeatherCondition.heavyRain;
  }

  int _seed(String route, DateTime date) {
    var hash = 17;
    for (final code in route.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return (hash ^ (date.year * 10000 + date.month * 100 + date.day)) &
        0x7fffffff;
  }

  double _unit(int seed, int index) {
    final value = (seed * (index + 1) * 1103515245 + 12345) & 0x7fffffff;
    return value / 0x7fffffff;
  }
}

class UnavailableRouteWeatherRepository implements RouteWeatherRepository {
  const UnavailableRouteWeatherRepository();

  @override
  Future<RouteWeatherForecast> fetch({
    required String routeName,
    required DateTime nowLocal,
  }) async {
    throw const RouteWeatherUnavailable(
      'Cuaca rute diambil lewat server dan belum tersambung di build ini.',
    );
  }
}
