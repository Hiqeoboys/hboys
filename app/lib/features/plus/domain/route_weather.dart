/// Model cuaca rute dan antarmuka sumbernya.
///
/// Aplikasi tidak pernah memanggil BMKG langsung. Repositori ini nantinya
/// diisi backend yang menyimpan cache prakiraan; tahap ini hanya punya
/// implementasi demo (debug) dan keadaan tidak tersedia (rilis).
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
}

/// Label sumber resmi. Implementasi demo memakai label lain supaya tidak
/// mengaku sebagai prakiraan BMKG.
const String bmkgSource = 'BMKG';

class RouteWeatherHour {
  const RouteWeatherHour({
    required this.timeLocal,
    required this.temperatureC,
    required this.rainPercent,
    required this.condition,
  });

  final DateTime timeLocal;
  final double temperatureC;
  final int rainPercent;
  final WeatherCondition condition;

  Map<String, Object?> toJson() => <String, Object?>{
        'time': timeLocal.toIso8601String(),
        'temperatureC': temperatureC,
        'rainPercent': rainPercent,
        'condition': condition.name,
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
  });

  final DateTime dateLocal;
  final double peakTemperatureC;
  final int peakRainPercent;
  final WeatherCondition condition;
  final List<RouteWeatherHour> hours;
  final List<RouteWeatherPost> posts;

  Map<String, Object?> toJson() => <String, Object?>{
        'date': dateLocal.toIso8601String(),
        'peakTemperatureC': peakTemperatureC,
        'peakRainPercent': peakRainPercent,
        'condition': condition.name,
        'hours': <Object?>[for (final hour in hours) hour.toJson()],
        'posts': <Object?>[for (final post in posts) post.toJson()],
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
    );
  }
}

class RouteWeatherForecast {
  const RouteWeatherForecast({
    required this.routeName,
    required this.source,
    required this.fetchedAtUtc,
    required this.days,
  });

  final String routeName;

  /// [bmkgSource] untuk data resmi lewat backend; label lain berarti demo.
  final String source;
  final DateTime fetchedAtUtc;
  final List<RouteWeatherDay> days;

  bool get isOfficial => source == bmkgSource;

  Map<String, Object?> toJson() => <String, Object?>{
        'routeName': routeName,
        'source': source,
        'fetchedAtUtc': fetchedAtUtc.toIso8601String(),
        'days': <Object?>[for (final day in days) day.toJson()],
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
    return RouteWeatherForecast(
      routeName: routeName,
      source: source,
      fetchedAtUtc: fetchedAt,
      days: List<RouteWeatherDay>.unmodifiable(days),
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
