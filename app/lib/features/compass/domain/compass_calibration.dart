import 'package:shared_preferences/shared_preferences.dart';

double normalizeHeading(double degrees) {
  final normalized = degrees % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

double applyHeadingOffset(double headingDegrees, double offsetDegrees) =>
    normalizeHeading(headingDegrees + offsetDegrees);

/// Selisih arah acuan terhadap heading mentah. 0 derajat = utara.
double offsetForReference({
  required double rawHeadingDegrees,
  required double referenceHeadingDegrees,
}) =>
    normalizeHeading(referenceHeadingDegrees - rawHeadingDegrees);

enum CompassAccuracyQuality { high, medium, low, unknown }

/// Ambang mengikuti tingkat akurasi sensor yang dilaporkan plugin, bukan
/// jaminan ketelitian sebenarnya.
CompassAccuracyQuality compassAccuracyQuality(double accuracyDegrees) {
  if (accuracyDegrees < 0) return CompassAccuracyQuality.unknown;
  if (accuracyDegrees <= 15) return CompassAccuracyQuality.high;
  if (accuracyDegrees <= 30) return CompassAccuracyQuality.medium;
  return CompassAccuracyQuality.low;
}

/// Koreksi manual ini menggeser heading, bukan mengkalibrasi sensor. Plugin
/// flutter_compass tidak menyediakan API kalibrasi sensor.
abstract interface class CompassOffsetStore {
  Future<double> readOffsetDegrees();
  Future<void> writeOffsetDegrees(double offsetDegrees);
}

class SharedPreferencesCompassOffsetStore implements CompassOffsetStore {
  const SharedPreferencesCompassOffsetStore();

  static const String key = 'compass_heading_offset_deg';

  @override
  Future<double> readOffsetDegrees() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getDouble(key);
    if (value == null || !value.isFinite) return 0;
    return normalizeHeading(value);
  }

  @override
  Future<void> writeOffsetDegrees(double offsetDegrees) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(key, normalizeHeading(offsetDegrees));
  }
}
