import 'package:geo_utils/geo_utils.dart';

class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lon,
    required this.timestampUtc,
    required this.accuracyM,
    this.altitudeM,
    this.speedMps,
    this.heading,
    this.speedAccuracyMps,
    this.altitudeAccuracyM,
    this.isMocked = false,
    this.receivedAtUtc,
  });

  final double lat;
  final double lon;
  final DateTime timestampUtc;

  /// Perkiraan galat horizontal dari GPS, meter.
  final double accuracyM;
  final double? altitudeM;
  final double? speedMps;

  /// Arah hadap/gerak (bearing) dalam derajat 0..360 searah jarum jam dari utara.
  final double? heading;

  /// Galat kecepatan GPS (m/s) dan galat ketinggian (m), bila tersedia.
  /// Hanya dipakai untuk diagnosa dan pembobotan; tidak disimpan ke database.
  final double? speedAccuracyMps;
  final double? altitudeAccuracyM;
  final bool isMocked;

  /// Waktu jam dinding perangkat saat fix diterima aplikasi. Dipakai untuk
  /// menilai apakah fix masih segar. `null` pada titik hasil pemutaran ulang
  /// dari database.
  final DateTime? receivedAtUtc;

  LatLng get position => LatLng(lat, lon);

  TrackPoint copyWith({
    double? lat,
    double? lon,
    DateTime? timestampUtc,
    double? accuracyM,
    double? altitudeM,
    double? speedMps,
    double? heading,
    double? speedAccuracyMps,
    double? altitudeAccuracyM,
    bool? isMocked,
    DateTime? receivedAtUtc,
  }) =>
      TrackPoint(
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        timestampUtc: timestampUtc ?? this.timestampUtc,
        accuracyM: accuracyM ?? this.accuracyM,
        altitudeM: altitudeM ?? this.altitudeM,
        speedMps: speedMps ?? this.speedMps,
        heading: heading ?? this.heading,
        speedAccuracyMps: speedAccuracyMps ?? this.speedAccuracyMps,
        altitudeAccuracyM: altitudeAccuracyM ?? this.altitudeAccuracyM,
        isMocked: isMocked ?? this.isMocked,
        receivedAtUtc: receivedAtUtc ?? this.receivedAtUtc,
      );
}
