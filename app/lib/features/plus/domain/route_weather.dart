/// Model cuaca rute, evaluasi peringatan keselamatan, & antarmuka sumbernya.
///
/// Prakiraan real diambil langsung dari perangkat via Open-Meteo API tanpa
/// kueri Supabase, lalu disimpan di cache lokal agar tetap bisa dibaca saat
/// offline di gunung.
library;

enum WeatherCondition { clear, partlyCloudy, lightRain, rain, heavyRain }

extension WeatherConditionLabel on WeatherCondition {
  String get label => switch (this) {
        WeatherCondition.clear => 'Cerah',
        WeatherCondition.partlyCloudy => 'Berawan',
        WeatherCondition.lightRain => 'Hujan ringan',
        WeatherCondition.rain => 'Hujan',
        WeatherCondition.heavyRain => 'Hujan lebat',
      };

  static WeatherCondition fromName(String? name) {
    for (final value in WeatherCondition.values) {
      if (value.name == name) return value;
    }
    return WeatherCondition.partlyCloudy;
  }

  /// Memetakan kode cuaca WMO Open-Meteo ke [WeatherCondition].
  static WeatherCondition fromWmoCode(int? code) {
    if (code == null) return WeatherCondition.partlyCloudy;
    if (code == 0 || code == 1) return WeatherCondition.clear;
    if (code == 2 || code == 3 || code == 45 || code == 48) {
      return WeatherCondition.partlyCloudy;
    }
    if (code == 51 || code == 53 || code == 56 || code == 61 || code == 80) {
      return WeatherCondition.lightRain;
    }
    if (code == 55 ||
        code == 57 ||
        code == 63 ||
        code == 66 ||
        code == 71 ||
        code == 73 ||
        code == 81) {
      return WeatherCondition.rain;
    }
    return WeatherCondition.heavyRain;
  }
}

/// Label sumber resmi BMKG (kompatibilitas lama).
const String bmkgSource = 'BMKG';

/// Label sumber prakiraan langsung perangkat via Open-Meteo.
const String openMeteoSource = 'Open-Meteo';

/// Laju penurunan suhu udara standar di gunung: -0,65 °C setiap naik 100 m.
const double kStandardLapseRatePer100m = 0.65;

/// Menghitung suhu perkiraan pada ketinggian tujuan menggunakan lapse rate
/// atmosfer standar (-0,65 °C per 100 m kenaikan elevasi).
double adjustTempByLapseRate(
  double refTempC, {
  required double refElevationM,
  required double targetElevationM,
}) =>
    refTempC -
    ((targetElevationM - refElevationM) / 100.0) * kStandardLapseRatePer100m;

/// Memformat usia cache cuaca menjadi keterangan relatif ("Diperbarui ... lalu").
String formatRelativeUpdatedAgo(DateTime fetchedAtUtc, DateTime nowUtc) {
  final diff = nowUtc.difference(fetchedAtUtc);
  if (diff.isNegative || diff.inMinutes < 1) {
    return 'Diperbarui baru saja';
  }
  if (diff.inMinutes < 60) {
    return 'Diperbarui ${diff.inMinutes} menit lalu';
  }
  if (diff.inHours < 24) {
    return 'Diperbarui ${diff.inHours} jam lalu';
  }
  return 'Diperbarui ${diff.inDays} hari lalu';
}

enum WeatherAlertSeverity { medium, high }

class RouteWeatherAlert {
  const RouteWeatherAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
  });

  final String id;
  final String title;
  final String message;
  final WeatherAlertSeverity severity;
}

/// Mengevaluasi peringatan keselamatan otomatis untuk pendaki berdasarkan
/// suhu puncak (< 8 °C -> risiko hipotermia), badai/hujan lebat, angin kencang,
/// dan UV ekstrem.
List<RouteWeatherAlert> evaluateWeatherSafetyWarnings(
  RouteWeatherDay day, {
  double? currentSummitTempC,
  double? currentWindKmh,
}) {
  final alerts = <RouteWeatherAlert>[];
  final coldestSummitC =
      currentSummitTempC ?? day.minTemperatureC ?? day.peakTemperatureC;
  if (coldestSummitC < 8.0) {
    alerts.add(
      RouteWeatherAlert(
        id: 'hypothermia',
        title: 'Peringatan suhu dingin / hipotermia',
        message:
            'Suhu puncak dapat turun ke ${coldestSummitC.round()}°C (< 8°C). '
            'Wajib bawa jaket insulasi, sarung tangan, kupluk, dan emergency blanket.',
        severity: WeatherAlertSeverity.high,
      ),
    );
  }

  final isThunderstorm = day.weatherCode != null && day.weatherCode! >= 95;
  if (day.condition == WeatherCondition.heavyRain ||
      isThunderstorm ||
      day.peakRainPercent >= 75) {
    alerts.add(
      RouteWeatherAlert(
        id: 'storm',
        title: isThunderstorm
            ? 'Peringatan badai petir & hujan lebat'
            : 'Potensi hujan tinggi di jalur',
        message:
            'Peluang hujan mencapai ${day.peakRainPercent}%. Hindari area terbuka '
            'punggung gunung saat awan gelap dan siapkan jas hujan waterproof.',
        severity: WeatherAlertSeverity.high,
      ),
    );
  }

  final peakWind = currentWindKmh ?? day.windSpeedKmh ?? 0.0;
  if (peakWind >= 35.0) {
    alerts.add(
      RouteWeatherAlert(
        id: 'wind',
        title: 'Peringatan angin kencang puncak',
        message:
            'Kecepatan angin mencapai ${peakWind.round()} km/jam. Waspadai terpaan '
            'wind chill di punggungan terbuka dan pertimbangkan menunda summit attack.',
        severity: WeatherAlertSeverity.high,
      ),
    );
  }

  if ((day.uvIndexMax ?? 0.0) >= 8.0) {
    alerts.add(
      RouteWeatherAlert(
        id: 'uv',
        title: 'Paparan UV tinggi',
        message:
            'Indeks UV maks ${day.uvIndexMax!.round()}. Gunakan tabir surya, '
            'topi, dan kacamata hitam di area terbuka.',
        severity: WeatherAlertSeverity.medium,
      ),
    );
  }

  return List<RouteWeatherAlert>.unmodifiable(alerts);
}

class RouteWeatherHour {
  const RouteWeatherHour({
    required this.timeLocal,
    required this.temperatureC,
    required this.rainPercent,
    required this.condition,
    this.windSpeedKmh,
    this.humidityPercent,
    this.uvIndex,
    this.weatherCode,
  });

  final DateTime timeLocal;
  final double temperatureC;
  final int rainPercent;
  final WeatherCondition condition;
  final double? windSpeedKmh;
  final int? humidityPercent;
  final double? uvIndex;
  final int? weatherCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'time': timeLocal.toIso8601String(),
        'temperatureC': temperatureC,
        'rainPercent': rainPercent,
        'condition': condition.name,
        if (windSpeedKmh != null) 'windSpeedKmh': windSpeedKmh,
        if (humidityPercent != null) 'humidityPercent': humidityPercent,
        if (uvIndex != null) 'uvIndex': uvIndex,
        if (weatherCode != null) 'weatherCode': weatherCode,
      };

  static RouteWeatherHour? tryParse(Object? json) {
    if (json is! Map) return null;
    final time = DateTime.tryParse(json['time']?.toString() ?? '');
    final temperature = _toDouble(json['temperatureC']);
    final rain = _toInt(json['rainPercent']);
    if (time == null || temperature == null || rain == null) return null;
    return RouteWeatherHour(
      timeLocal: time,
      temperatureC: temperature,
      rainPercent: rain.clamp(0, 100),
      condition: WeatherConditionLabel.fromName(json['condition']?.toString()),
      windSpeedKmh: _toDouble(json['windSpeedKmh']),
      humidityPercent: _toInt(json['humidityPercent']),
      uvIndex: _toDouble(json['uvIndex']),
      weatherCode: _toInt(json['weatherCode']),
    );
  }
}

class RouteWeatherPost {
  const RouteWeatherPost({
    required this.name,
    required this.temperatureC,
    required this.rainPercent,
    required this.condition,
    this.altitudeM,
  });

  final String name;
  final double? altitudeM;
  final double temperatureC;
  final int rainPercent;
  final WeatherCondition condition;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'altitudeM': altitudeM,
        'temperatureC': temperatureC,
        'rainPercent': rainPercent,
        'condition': condition.name,
      };

  static RouteWeatherPost? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name']?.toString();
    final temperature = _toDouble(json['temperatureC']);
    final rain = _toInt(json['rainPercent']);
    if (name == null || name.isEmpty || temperature == null || rain == null) {
      return null;
    }
    return RouteWeatherPost(
      name: name,
      altitudeM: _toDouble(json['altitudeM']),
      temperatureC: temperature,
      rainPercent: rain.clamp(0, 100),
      condition: WeatherConditionLabel.fromName(json['condition']?.toString()),
    );
  }
}

class RouteWeatherDay {
  const RouteWeatherDay({
    required this.dateLocal,
    required this.peakTemperatureC,
    required this.peakRainPercent,
    required this.condition,
    required this.hours,
    required this.posts,
    this.basecampTemperatureC,
    this.minTemperatureC,
    this.maxTemperatureC,
    this.windSpeedKmh,
    this.humidityPercent,
    this.uvIndexMax,
    this.sunriseLocal,
    this.sunsetLocal,
    this.weatherCode,
  });

  final DateTime dateLocal;
  final double peakTemperatureC;
  final int peakRainPercent;
  final WeatherCondition condition;
  final List<RouteWeatherHour> hours;
  final List<RouteWeatherPost> posts;
  final double? basecampTemperatureC;
  final double? minTemperatureC;
  final double? maxTemperatureC;
  final double? windSpeedKmh;
  final int? humidityPercent;
  final double? uvIndexMax;
  final DateTime? sunriseLocal;
  final DateTime? sunsetLocal;
  final int? weatherCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'date': dateLocal.toIso8601String(),
        'peakTemperatureC': peakTemperatureC,
        'peakRainPercent': peakRainPercent,
        'condition': condition.name,
        'hours': <Object?>[for (final hour in hours) hour.toJson()],
        'posts': <Object?>[for (final post in posts) post.toJson()],
        if (basecampTemperatureC != null)
          'basecampTemperatureC': basecampTemperatureC,
        if (minTemperatureC != null) 'minTemperatureC': minTemperatureC,
        if (maxTemperatureC != null) 'maxTemperatureC': maxTemperatureC,
        if (windSpeedKmh != null) 'windSpeedKmh': windSpeedKmh,
        if (humidityPercent != null) 'humidityPercent': humidityPercent,
        if (uvIndexMax != null) 'uvIndexMax': uvIndexMax,
        if (sunriseLocal != null)
          'sunriseLocal': sunriseLocal!.toIso8601String(),
        if (sunsetLocal != null) 'sunsetLocal': sunsetLocal!.toIso8601String(),
        if (weatherCode != null) 'weatherCode': weatherCode,
      };

  static RouteWeatherDay? tryParse(Object? json) {
    if (json is! Map) return null;
    final date = DateTime.tryParse(json['date']?.toString() ?? '');
    final peak = _toDouble(json['peakTemperatureC']);
    final rain = _toInt(json['peakRainPercent']);
    if (date == null || peak == null || rain == null) return null;
    final hours = <RouteWeatherHour>[
      for (final item
          in json['hours'] is List ? json['hours'] as List : const [])
        if (RouteWeatherHour.tryParse(item) case final hour?) hour,
    ];
    final posts = <RouteWeatherPost>[
      for (final item
          in json['posts'] is List ? json['posts'] as List : const [])
        if (RouteWeatherPost.tryParse(item) case final post?) post,
    ];
    if (hours.isEmpty || posts.isEmpty) return null;
    return RouteWeatherDay(
      dateLocal: date,
      peakTemperatureC: peak,
      peakRainPercent: rain.clamp(0, 100),
      condition: WeatherConditionLabel.fromName(json['condition']?.toString()),
      hours: List<RouteWeatherHour>.unmodifiable(hours),
      posts: List<RouteWeatherPost>.unmodifiable(posts),
      basecampTemperatureC: _toDouble(json['basecampTemperatureC']),
      minTemperatureC: _toDouble(json['minTemperatureC']),
      maxTemperatureC: _toDouble(json['maxTemperatureC']),
      windSpeedKmh: _toDouble(json['windSpeedKmh']),
      humidityPercent: _toInt(json['humidityPercent']),
      uvIndexMax: _toDouble(json['uvIndexMax']),
      sunriseLocal: DateTime.tryParse(json['sunriseLocal']?.toString() ?? ''),
      sunsetLocal: DateTime.tryParse(json['sunsetLocal']?.toString() ?? ''),
      weatherCode: _toInt(json['weatherCode']),
    );
  }
}

class RouteWeatherForecast {
  const RouteWeatherForecast({
    required this.routeName,
    required this.source,
    required this.fetchedAtUtc,
    required this.days,
    this.basecampElevationM,
    this.summitElevationM,
    this.currentBasecampTempC,
    this.currentSummitTempC,
    this.currentRainPercent,
    this.currentWindSpeedKmh,
    this.currentHumidityPercent,
    this.currentUvIndex,
    this.currentCondition,
    this.next24Hours = const <RouteWeatherHour>[],
  });

  final String routeName;

  /// [bmkgSource] untuk BMKG, [openMeteoSource] untuk Open-Meteo perangkat,
  /// atau label lain untuk data demo.
  final String source;
  final DateTime fetchedAtUtc;
  final List<RouteWeatherDay> days;
  final double? basecampElevationM;
  final double? summitElevationM;
  final double? currentBasecampTempC;
  final double? currentSummitTempC;
  final int? currentRainPercent;
  final double? currentWindSpeedKmh;
  final int? currentHumidityPercent;
  final double? currentUvIndex;
  final WeatherCondition? currentCondition;
  final List<RouteWeatherHour> next24Hours;

  bool get isOfficial => source == bmkgSource;
  bool get isOpenMeteo => source == openMeteoSource;

  Map<String, Object?> toJson() => <String, Object?>{
        'routeName': routeName,
        'source': source,
        'fetchedAtUtc': fetchedAtUtc.toIso8601String(),
        'days': <Object?>[for (final day in days) day.toJson()],
        if (basecampElevationM != null)
          'basecampElevationM': basecampElevationM,
        if (summitElevationM != null) 'summitElevationM': summitElevationM,
        if (currentBasecampTempC != null)
          'currentBasecampTempC': currentBasecampTempC,
        if (currentSummitTempC != null)
          'currentSummitTempC': currentSummitTempC,
        if (currentRainPercent != null)
          'currentRainPercent': currentRainPercent,
        if (currentWindSpeedKmh != null)
          'currentWindSpeedKmh': currentWindSpeedKmh,
        if (currentHumidityPercent != null)
          'currentHumidityPercent': currentHumidityPercent,
        if (currentUvIndex != null) 'currentUvIndex': currentUvIndex,
        if (currentCondition != null)
          'currentCondition': currentCondition!.name,
        if (next24Hours.isNotEmpty)
          'next24Hours': <Object?>[for (final h in next24Hours) h.toJson()],
      };

  static RouteWeatherForecast? tryParse(Object? json) {
    if (json is! Map) return null;
    final routeName = json['routeName']?.toString();
    final source = json['source']?.toString();
    final fetchedAt = DateTime.tryParse(json['fetchedAtUtc']?.toString() ?? '');
    if (routeName == null ||
        routeName.isEmpty ||
        source == null ||
        fetchedAt == null) {
      return null;
    }
    final days = <RouteWeatherDay>[
      for (final item in json['days'] is List ? json['days'] as List : const [])
        if (RouteWeatherDay.tryParse(item) case final day?) day,
    ];
    if (days.isEmpty) return null;
    final next24 = <RouteWeatherHour>[
      for (final item in json['next24Hours'] is List
          ? json['next24Hours'] as List
          : const [])
        if (RouteWeatherHour.tryParse(item) case final hour?) hour,
    ];
    final currentCondName = json['currentCondition']?.toString();
    return RouteWeatherForecast(
      routeName: routeName,
      source: source,
      fetchedAtUtc: fetchedAt,
      days: List<RouteWeatherDay>.unmodifiable(days),
      basecampElevationM: _toDouble(json['basecampElevationM']),
      summitElevationM: _toDouble(json['summitElevationM']),
      currentBasecampTempC: _toDouble(json['currentBasecampTempC']),
      currentSummitTempC: _toDouble(json['currentSummitTempC']),
      currentRainPercent: _toInt(json['currentRainPercent']),
      currentWindSpeedKmh: _toDouble(json['currentWindSpeedKmh']),
      currentHumidityPercent: _toInt(json['currentHumidityPercent']),
      currentUvIndex: _toDouble(json['currentUvIndex']),
      currentCondition: currentCondName != null
          ? WeatherConditionLabel.fromName(currentCondName)
          : null,
      next24Hours: List<RouteWeatherHour>.unmodifiable(next24),
    );
  }
}

class RouteWeatherUnavailable implements Exception {
  const RouteWeatherUnavailable([this.message = 'Cuaca rute belum tersedia.']);

  final String message;

  @override
  String toString() => message;
}

abstract interface class RouteWeatherRepository {
  Future<RouteWeatherForecast> fetch({
    required String routeName,
    required DateTime nowLocal,
  });
}

abstract interface class RouteWeatherCache {
  Future<RouteWeatherForecast?> read(String routeName);
  Future<void> write(RouteWeatherForecast forecast);
}

double? _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}
