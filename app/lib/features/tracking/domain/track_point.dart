import 'package:geo_utils/geo_utils.dart';

class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lon,
    required this.timestampUtc,
    required this.accuracyM,
    this.altitudeM,
    this.speedMps,
  });

  final double lat;
  final double lon;
  final DateTime timestampUtc;

  /// Perkiraan galat horizontal dari GPS, meter.
  final double accuracyM;
  final double? altitudeM;
  final double? speedMps;

  LatLng get position => LatLng(lat, lon);
}
