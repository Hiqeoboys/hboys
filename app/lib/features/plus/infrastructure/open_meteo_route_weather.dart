import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:http/http.dart' as http;

import '../../map/domain/map_package.dart';
import '../../map/domain/mountain_pack.dart';
import '../../map/domain/mountain_pack_data.dart';
import '../../trails/data/gpx_loader.dart';
import '../application/plus_navigation.dart';
import '../domain/route_weather.dart';

class _ResolvedMountainTarget {
  const _ResolvedMountainTarget({
    required this.summitCoord,
    required this.basecampElevationM,
    required this.summitElevationM,
    required this.posts,
  });

  final LatLng summitCoord;
  final double basecampElevationM;
  final double summitElevationM;
  final List<({String name, double elevationM})> posts;
}

/// Mengambil prakiraan cuaca gunung langsung dari Open-Meteo API
/// (`https://api.open-meteo.com/v1/forecast`, tanpa API key & 0 kueri Supabase)
/// lalu mengoreksi suhu puncak & per pos menggunakan lapse rate `-0,65°C / 100 m`.
class OpenMeteoRouteWeatherRepository implements RouteWeatherRepository {
  OpenMeteoRouteWeatherRepository({
    http.Client? client,
    AssetBundle? bundle,
  })  : _client = client,
        _bundle = bundle;

  final http.Client? _client;
  final AssetBundle? _bundle;

  @override
  Future<RouteWeatherForecast> fetch({
    required String routeName,
    required DateTime nowLocal,
  }) =>
      fetchForContext(
        route: PlusRouteContext(name: routeName),
        nowLocal: nowLocal,
      );

  Future<RouteWeatherForecast> fetchForContext({
    required PlusRouteContext route,
    required DateTime nowLocal,
  }) async {
    final target = await _resolveTarget(route);
    final uri = buildForecastUri(target.summitCoord);

    final ownsClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const RouteWeatherUnavailable(
          'Server cuaca Open-Meteo tidak merespons. Coba lagi saat sinyal lebih stabil.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?> && decoded is! Map) {
        throw const RouteWeatherUnavailable(
          'Format data cuaca Open-Meteo tidak valid.',
        );
      }
      return parseOpenMeteoForecast(
        routeName: route.name,
        json: Map<String, dynamic>.from(decoded as Map),
        nowLocal: nowLocal,
        basecampElevationM: target.basecampElevationM,
        summitElevationM: target.summitElevationM,
        posts: target.posts,
      );
    } on TimeoutException {
      throw const RouteWeatherUnavailable(
        'Koneksi ke Open-Meteo kehabisan waktu. Pastikan internet aktif untuk memperbarui cuaca.',
      );
    } on RouteWeatherUnavailable {
      rethrow;
    } catch (_) {
      throw const RouteWeatherUnavailable(
        'Tidak bisa terhubung ke Open-Meteo. Menampilkan data tersimpan jika ada.',
      );
    } finally {
      if (ownsClient) client.close();
    }
  }

  static Uri buildForecastUri(LatLng coord) {
    return Uri.https(
      'api.open-meteo.com',
      '/v1/forecast',
      <String, String>{
        'latitude': coord.lat.toStringAsFixed(4),
        'longitude': coord.lon.toStringAsFixed(4),
        'current':
            'temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,precipitation_probability',
        'hourly':
            'temperature_2m,relative_humidity_2m,precipitation_probability,weather_code,wind_speed_10m,uv_index',
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,uv_index_max,sunrise,sunset',
        'timezone': 'auto',
        'forecast_days': '7',
      },
    );
  }

  Future<_ResolvedMountainTarget> _resolveTarget(PlusRouteContext route) async {
    final packs = MountainPackData.createDefaultPacks();
    final lowerName = route.name.trim().toLowerCase();
    final idNeedle = route.mountainId?.trim().toLowerCase();

    MountainPack? matchedPack;
    for (final p in packs) {
      if (idNeedle != null && p.id.toLowerCase() == idNeedle) {
        matchedPack = p;
        break;
      }
      if (lowerName.contains(p.name.toLowerCase()) ||
          p.name.toLowerCase().contains(lowerName) ||
          lowerName.contains(p.id.toLowerCase())) {
        matchedPack = p;
        break;
      }
    }

    MapTrail? matchedTrail;
    if (matchedPack != null && matchedPack.package.trails.isNotEmpty) {
      final trailNeedle = route.trailId?.trim().toLowerCase();
      final trailNameNeedle = route.trailName?.trim().toLowerCase();
      for (final t in matchedPack.package.trails) {
        if ((trailNeedle != null && t.id.toLowerCase() == trailNeedle) ||
            (trailNameNeedle != null &&
                t.name.toLowerCase() == trailNameNeedle) ||
            lowerName.contains(t.name.toLowerCase())) {
          matchedTrail = t;
          break;
        }
      }
      matchedTrail ??= matchedPack.package.trails.first;
    }

    final gpxPath =
        route.gpxAssetPath ?? matchedTrail?.gpxAssetPath ?? matchedPack?.gpxAssetPath;

    double summitElev = route.summitElevationM ??
        matchedTrail?.maxElevationM ??
        (matchedPack?.elevationM.toDouble() ?? 2958.0);
    double basecampElev = route.basecampElevationM ??
        (summitElev - (route.elevationGainM ?? matchedTrail?.elevationGainM ?? 1100.0))
            .clamp(300.0, summitElev - 200.0)
            .toDouble();
    LatLng summitCoord = route.summitCoord ??
        (route.points.isNotEmpty
            ? route.points.last
            : (matchedTrail != null && matchedTrail.points.isNotEmpty
                ? matchedTrail.points.last
                : (matchedPack?.package.offline.bounds.center ??
                    const LatLng(-6.7899, 106.9831))));

    final posts = <({String name, double elevationM})>[];

    if (gpxPath != null && gpxPath.isNotEmpty) {
      try {
        final loaded = await GpxLoader.loadAsset(gpxPath, bundle: _bundle);
        if (loaded.points.isNotEmpty) {
          final startEle = loaded.points.first.ele ?? loaded.minElevationM;
          final highPt = loaded.summitPoint;
          if (startEle != null && startEle.isFinite) {
            basecampElev = startEle;
          }
          if (highPt != null) {
            summitCoord = highPt.position;
            if (highPt.ele != null && highPt.ele!.isFinite) {
              summitElev = highPt.ele!;
            }
          }
        }
        if (loaded.waypoints.isNotEmpty) {
          posts.add((name: 'Basecamp', elevationM: basecampElev));
          for (final wp in loaded.waypoints) {
            final ele = wp.elevationM ??
                (basecampElev +
                    (summitElev - basecampElev) *
                        (loaded.totalDistanceM > 0
                            ? (wp.distanceFromStartM / loaded.totalDistanceM)
                                .clamp(0.0, 1.0)
                            : 0.5));
            posts.add((name: wp.name, elevationM: ele));
          }
        }
      } catch (_) {
        // Asset GPX opsional bila dipanggil di unit test tanpa bundle aset.
      }
    }

    if (posts.isEmpty) {
      final midElev = ((basecampElev + summitElev) / 2.0).roundToDouble();
      posts.addAll(<({String name, double elevationM})>[
        (name: 'Basecamp', elevationM: basecampElev),
        (name: 'Pos Tengah', elevationM: midElev),
        (name: 'Puncak', elevationM: summitElev),
      ]);
    }

    return _ResolvedMountainTarget(
      summitCoord: summitCoord,
      basecampElevationM: basecampElev,
      summitElevationM: summitElev,
      posts: posts,
    );
  }

  /// Mem-parsing JSON respon `/v1/forecast` Open-Meteo menjadi [RouteWeatherForecast].
  static RouteWeatherForecast parseOpenMeteoForecast({
    required String routeName,
    required Map<String, dynamic> json,
    required DateTime nowLocal,
    required double basecampElevationM,
    required double summitElevationM,
    required List<({String name, double elevationM})> posts,
  }) {
    final modelElev = _asDouble(json['elevation']) ?? basecampElevationM;
    final currentMap = _asMap(json['current']);
    final hourlyMap = _asMap(json['hourly']);
    final dailyMap = _asMap(json['daily']);

    final hourlyTimes = _asStringList(hourlyMap?['time']);
    final hourlyTemps = _asDoubleList(hourlyMap?['temperature_2m']);
    final hourlyRain = _asIntList(hourlyMap?['precipitation_probability']);
    final hourlyHumidity = _asIntList(hourlyMap?['relative_humidity_2m']);
    final hourlyCodes = _asIntList(hourlyMap?['weather_code']);
    final hourlyWinds = _asDoubleList(hourlyMap?['wind_speed_10m']);
    final hourlyUvs = _asDoubleList(hourlyMap?['uv_index']);

    final allHours = <RouteWeatherHour>[];
    for (var i = 0; i < hourlyTimes.length; i++) {
      final parsedTime = DateTime.tryParse(hourlyTimes[i]);
      final rawTemp = i < hourlyTemps.length ? hourlyTemps[i] : null;
      if (parsedTime == null || rawTemp == null) continue;
      final summitTemp = adjustTempByLapseRate(
        rawTemp,
        refElevationM: modelElev,
        targetElevationM: summitElevationM,
      );
      final rainPct =
          (i < hourlyRain.length ? (hourlyRain[i] ?? 0) : 0).clamp(0, 100);
      final code = i < hourlyCodes.length ? hourlyCodes[i] : null;
      final wind = i < hourlyWinds.length ? hourlyWinds[i] : null;
      final hum = i < hourlyHumidity.length ? hourlyHumidity[i] : null;
      final uv = i < hourlyUvs.length ? hourlyUvs[i] : null;
      allHours.add(
        RouteWeatherHour(
          timeLocal: parsedTime,
          temperatureC: _round1(summitTemp),
          rainPercent: rainPct,
          condition: WeatherConditionLabel.fromWmoCode(code),
          windSpeedKmh: wind != null ? _round1(wind) : null,
          humidityPercent: hum?.clamp(0, 100),
          uvIndex: uv != null ? _round1(uv) : null,
          weatherCode: code,
        ),
      );
    }

    // Ambil 24 jam ke depan mulai jam saat ini.
    final nowHourFloor = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      nowLocal.hour,
    );
    final next24Hours = allHours
        .where((h) => !h.timeLocal.isBefore(nowHourFloor))
        .take(24)
        .toList(growable: false);

    final dailyTimes = _asStringList(dailyMap?['time']);
    final dailyMaxTemps = _asDoubleList(dailyMap?['temperature_2m_max']);
    final dailyMinTemps = _asDoubleList(dailyMap?['temperature_2m_min']);
    final dailyRainMax =
        _asIntList(dailyMap?['precipitation_probability_max']);
    final dailyCodes = _asIntList(dailyMap?['weather_code']);
    final dailyWindMax = _asDoubleList(dailyMap?['wind_speed_10m_max']);
    final dailyUvMax = _asDoubleList(dailyMap?['uv_index_max']);
    final dailySunrises = _asStringList(dailyMap?['sunrise']);
    final dailySunsets = _asStringList(dailyMap?['sunset']);

    final days = <RouteWeatherDay>[];
    for (var d = 0; d < dailyTimes.length; d++) {
      final date = DateTime.tryParse(dailyTimes[d]);
      if (date == null) continue;
      final dayDate = DateTime(date.year, date.month, date.day);

      final dayHoursFull = allHours
          .where(
            (h) =>
                h.timeLocal.year == dayDate.year &&
                h.timeLocal.month == dayDate.month &&
                h.timeLocal.day == dayDate.day,
          )
          .toList(growable: false);

      // Contoh tiap 3 jam untuk grafik bar (maks 8 titik per hari).
      final chartHours = <RouteWeatherHour>[
        for (final h in dayHoursFull)
          if (h.timeLocal.hour % 3 == 0) h,
      ];

      final rawMax = d < dailyMaxTemps.length ? dailyMaxTemps[d] : null;
      final rawMin = d < dailyMinTemps.length ? dailyMinTemps[d] : null;
      final fallbackModelTemp = rawMax ?? 18.0;

      final summitMax = adjustTempByLapseRate(
        rawMax ?? fallbackModelTemp,
        refElevationM: modelElev,
        targetElevationM: summitElevationM,
      );
      final summitMin = adjustTempByLapseRate(
        rawMin ?? (fallbackModelTemp - 6.0),
        refElevationM: modelElev,
        targetElevationM: summitElevationM,
      );
      final basecampMax = adjustTempByLapseRate(
        rawMax ?? fallbackModelTemp,
        refElevationM: modelElev,
        targetElevationM: basecampElevationM,
      );

      final rainPct =
          (d < dailyRainMax.length ? (dailyRainMax[d] ?? 0) : 0).clamp(0, 100);
      final code = d < dailyCodes.length ? dailyCodes[d] : null;
      final condition = WeatherConditionLabel.fromWmoCode(code);
      final windMax = d < dailyWindMax.length ? dailyWindMax[d] : null;
      final uvMax = d < dailyUvMax.length ? dailyUvMax[d] : null;
      final sunrise =
          d < dailySunrises.length ? DateTime.tryParse(dailySunrises[d]) : null;
      final sunset =
          d < dailySunsets.length ? DateTime.tryParse(dailySunsets[d]) : null;

      final humidities = [
        for (final h in dayHoursFull)
          if (h.humidityPercent != null) h.humidityPercent!,
      ];
      final avgHumidity = humidities.isEmpty
          ? null
          : (humidities.reduce((a, b) => a + b) / humidities.length).round();

      final effectiveChartHours = chartHours.isNotEmpty
          ? chartHours
          : (dayHoursFull.isNotEmpty
              ? dayHoursFull.take(8).toList(growable: false)
              : <RouteWeatherHour>[
                  RouteWeatherHour(
                    timeLocal: dayDate.add(const Duration(hours: 9)),
                    temperatureC: _round1(summitMax),
                    rainPercent: rainPct,
                    condition: condition,
                    windSpeedKmh: windMax != null ? _round1(windMax) : null,
                  ),
                ]);

      final dayPosts = <RouteWeatherPost>[
        for (var pIdx = 0; pIdx < posts.length; pIdx++)
          RouteWeatherPost(
            name: posts[pIdx].name,
            altitudeM: posts[pIdx].elevationM,
            temperatureC: _round1(
              adjustTempByLapseRate(
                rawMax ?? fallbackModelTemp,
                refElevationM: modelElev,
                targetElevationM: posts[pIdx].elevationM,
              ),
            ),
            rainPercent:
                (rainPct + (pIdx == posts.length - 1 ? 5 : 0)).clamp(0, 100),
            condition: condition,
          ),
      ];

      days.add(
        RouteWeatherDay(
          dateLocal: dayDate,
          peakTemperatureC: _round1(summitMax),
          peakRainPercent: rainPct,
          condition: condition,
          hours: List<RouteWeatherHour>.unmodifiable(effectiveChartHours),
          posts: List<RouteWeatherPost>.unmodifiable(dayPosts),
          basecampTemperatureC: _round1(basecampMax),
          minTemperatureC: _round1(summitMin),
          maxTemperatureC: _round1(summitMax),
          windSpeedKmh: windMax != null ? _round1(windMax) : null,
          humidityPercent: avgHumidity,
          uvIndexMax: uvMax != null ? _round1(uvMax) : null,
          sunriseLocal: sunrise,
          sunsetLocal: sunset,
          weatherCode: code,
        ),
      );
    }

    if (days.isEmpty) {
      throw const RouteWeatherUnavailable(
        'Data prakiraan harian Open-Meteo kosong.',
      );
    }

    final rawCurrentTemp = _asDouble(currentMap?['temperature_2m']);
    final currentBasecamp = rawCurrentTemp != null
        ? _round1(
            adjustTempByLapseRate(
              rawCurrentTemp,
              refElevationM: modelElev,
              targetElevationM: basecampElevationM,
            ),
          )
        : days.first.basecampTemperatureC;
    final currentSummit = rawCurrentTemp != null
        ? _round1(
            adjustTempByLapseRate(
              rawCurrentTemp,
              refElevationM: modelElev,
              targetElevationM: summitElevationM,
            ),
          )
        : days.first.peakTemperatureC;
    final currentWind =
        _asDouble(currentMap?['wind_speed_10m']) ?? days.first.windSpeedKmh;
    final currentHum = _asInt(currentMap?['relative_humidity_2m']) ??
        days.first.humidityPercent;
    final currentRain = _asInt(currentMap?['precipitation_probability']) ??
        days.first.peakRainPercent;
    final currentCode = _asInt(currentMap?['weather_code']);
    final currentUv = next24Hours.isNotEmpty
        ? next24Hours.first.uvIndex ?? days.first.uvIndexMax
        : days.first.uvIndexMax;

    return RouteWeatherForecast(
      routeName: routeName,
      source: openMeteoSource,
      fetchedAtUtc: nowLocal.toUtc(),
      days: List<RouteWeatherDay>.unmodifiable(days),
      basecampElevationM: basecampElevationM,
      summitElevationM: summitElevationM,
      currentBasecampTempC: currentBasecamp,
      currentSummitTempC: currentSummit,
      currentRainPercent: currentRain.clamp(0, 100),
      currentWindSpeedKmh: currentWind != null ? _round1(currentWind) : null,
      currentHumidityPercent: currentHum?.clamp(0, 100),
      currentUvIndex: currentUv != null ? _round1(currentUv) : null,
      currentCondition: currentCode != null
          ? WeatherConditionLabel.fromWmoCode(currentCode)
          : days.first.condition,
      next24Hours: List<RouteWeatherHour>.unmodifiable(next24Hours),
    );
  }
}

double _round1(double v) => (v * 10.0).round() / 10.0;

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const <String>[];
  return <String>[
    for (final item in value)
      if (item != null) item.toString(),
  ];
}

List<double?> _asDoubleList(Object? value) {
  if (value is! List) return const <double?>[];
  return <double?>[for (final item in value) _asDouble(item)];
}

List<int?> _asIntList(Object? value) {
  if (value is! List) return const <int?>[];
  return <int?>[for (final item in value) _asInt(item)];
}
