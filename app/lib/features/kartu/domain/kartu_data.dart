import 'dart:math' as math;
import 'dart:ui';

import 'package:geo_utils/geo_utils.dart';

import '../../tracking/domain/track_point.dart';
import '../../tracking/domain/tracking_session.dart';

/// Ringkasan satu pendakian yang selesai, dipakai layar Kartu Pendakian.
///
/// Semua angka berasal dari sesi dan titik yang benar-benar tersimpan. Tidak
/// ada nilai contoh; bagian yang datanya tidak ada dibiarkan kosong.
class KartuData {
  const KartuData({
    required this.sessionId,
    required this.startedAtUtc,
    required this.distanceM,
    required this.movingSeconds,
    required this.elevationGainM,
    required this.profile,
    required this.peakFraction,
    required this.route,
  });

  final String sessionId;
  final DateTime startedAtUtc;
  final double distanceM;
  final int movingSeconds;
  final double elevationGainM;

  /// Titik grafik elevasi dengan x 0..1 menurut jarak tempuh. Null bila titik
  /// ber-altitude kurang dari dua, sehingga kurva tidak bisa digambar jujur.
  final List<KartuProfilePoint>? profile;

  /// Posisi puncak pada sumbu x grafik elevasi; null bila tidak ada profil.
  final double? peakFraction;

  /// Rute ternormalisasi 0..1 untuk gaya Peta. Null bila titik kurang dari dua.
  final List<Offset>? route;

  static KartuData? fromSession(
    TrackingSession session,
    List<TrackPoint> points,
  ) {
    if (session.status != TrackingSessionStatus.completed) return null;
    final altitudes = <({double fraction, double altitude})>[];
    var cumulativeM = 0.0;
    TrackPoint? previous;
    final fractions = <double>[];
    for (final point in points) {
      if (previous != null) {
        cumulativeM += distanceMeters(previous.position, point.position);
      }
      fractions.add(cumulativeM);
      previous = point;
    }
    final totalM = cumulativeM > 0 ? cumulativeM : null;
    for (var i = 0; i < points.length; i++) {
      final altitude = points[i].altitudeM;
      if (altitude == null) continue;
      final fraction = totalM == null
          ? (points.length == 1 ? 0.0 : i / (points.length - 1))
          : fractions[i] / totalM;
      altitudes.add((fraction: fraction, altitude: altitude));
    }

    List<KartuProfilePoint>? profile;
    double? peakFraction;
    if (altitudes.length >= 2) {
      profile = <KartuProfilePoint>[
        for (final entry in altitudes)
          KartuProfilePoint(entry.fraction, entry.altitude),
      ];
      var peak = altitudes.first;
      for (final entry in altitudes) {
        if (entry.altitude > peak.altitude) peak = entry;
      }
      peakFraction = peak.fraction;
    }

    List<Offset>? route;
    if (points.length >= 2) {
      route = _normalizeRoute(points);
    }

    return KartuData(
      sessionId: session.id,
      startedAtUtc: session.startedAtUtc,
      distanceM: session.distanceM,
      movingSeconds: session.movingSeconds,
      elevationGainM: session.elevationGainM,
      profile: profile,
      peakFraction: peakFraction,
      route: route,
    );
  }

  static List<Offset> _normalizeRoute(List<TrackPoint> points) {
    final midLat =
        points.map((point) => point.lat).reduce((a, b) => a + b) /
            points.length;
    final cosLat = math.cos(midLat * math.pi / 180).abs();
    final xs = <double>[
      for (final point in points) point.lon * cosLat,
    ];
    final ys = <double>[for (final point in points) point.lat];
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final spanX = maxX - minX;
    final spanY = maxY - minY;
    if (spanX <= 0 && spanY <= 0) return const <Offset>[];
    // Satu skala untuk kedua sumbu agar bentuk rute tidak gepeng.
    final span = math.max(spanX, spanY);
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    return <Offset>[
      for (var i = 0; i < points.length; i++)
        Offset(
          0.5 + (xs[i] - centerX) / span,
          0.5 - (ys[i] - centerY) / span,
        ),
    ];
  }

  String get distanceLabel =>
      '${_decimal(distanceM / 1000)} km';

  String get gainLabel {
    final meters = elevationGainM.round();
    final digits = meters.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    final sign = meters > 0 ? '+' : (meters < 0 ? '−' : '');
    return '$sign$buffer m';
  }

  String get timeLabel {
    final total = movingSeconds < 0 ? 0 : movingSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  String get rightAxisLabel => distanceLabel;

  String get dateLabel {
    final local = startedAtUtc.toLocal();
    const months = <String>[
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MEI',
      'JUN',
      'JUL',
      'AGU',
      'SEP',
      'OKT',
      'NOV',
      'DES',
    ];
    return '${local.day.toString().padLeft(2, '0')} '
        '${months[local.month - 1]} ${local.year}';
  }

  static String _decimal(double value) =>
      value.toStringAsFixed(1).replaceAll('.', ',');
}

class KartuProfilePoint {
  const KartuProfilePoint(this.fraction, this.altitudeM);

  final double fraction;
  final double altitudeM;
}
