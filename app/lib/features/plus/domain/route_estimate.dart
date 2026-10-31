import 'package:geo_utils/geo_utils.dart';

import 'hike_analytics.dart';
import 'plus_format.dart';

/// Satu baris garis waktu D3.
class ItineraryPoint {
  const ItineraryPoint({
    required this.label,
    required this.timeLocal,
    required this.detail,
    this.warning = false,
  });

  final String label;
  final DateTime timeLocal;
  final String detail;
  final bool warning;
}

/// Estimasi perjalanan yang dihitung di perangkat dari kecepatan pribadi.
///
/// Angka tidak pernah dikirim ke server. Bila belum ada sesi selesai yang
/// cukup, estimasi tidak dibuat sama sekali (null) alih-alih memakai angka
/// kecepatan umum yang tidak mewakili pengguna.
class RouteEstimate {
  const RouteEstimate({
    required this.routeName,
    required this.distanceM,
    required this.paceKmh,
    required this.startLocal,
    required this.arrivalLocal,
    required this.turnAroundLocal,
    required this.sunsetLocal,
    required this.fitsBeforeSunset,
    required this.ascent,
    required this.breaks,
    required this.summitRest,
    required this.descent,
    required this.timeline,
    required this.gear,
  });

  final String routeName;
  final double distanceM;

  /// Kecepatan jelajah pribadi (median) dalam km/jam.
  final double paceKmh;

  final DateTime startLocal;
  final DateTime arrivalLocal;

  /// Batas aman berbalik arah: matahari terbenam dikurangi waktu turun dan
  /// cadangan 60 menit. Null bila posisi rute tidak diketahui.
  final DateTime? turnAroundLocal;
  final DateTime? sunsetLocal;

  /// Null bila [sunsetLocal] tidak dapat dihitung.
  final bool? fitsBeforeSunset;

  final Duration ascent;
  final Duration breaks;
  final Duration summitRest;
  final Duration descent;

  final List<ItineraryPoint> timeline;
  final List<String> gear;

  static const Duration safetyBuffer = Duration(minutes: 60);
  static const Duration summitRestDefault = Duration(minutes: 45);

  /// Null bila rute kurang dari dua titik, atau [paceKmh] tidak tersedia.
  static RouteEstimate? build({
    required String routeName,
    required List<LatLng> points,
    required DateTime nowLocal,
    required double? paceKmh,
    Duration summitRest = summitRestDefault,
  }) {
    if (points.length < 2 || paceKmh == null || paceKmh <= 0) return null;
    final distanceM = routeDistanceM(points);
    if (distanceM < 100) return null;

    final ascent = Duration(
      seconds: (distanceM / 1000 / paceKmh * 3600).round(),
    );
    final breakMinutes = (ascent.inSeconds / 3600 * 10).round();
    final breaks = Duration(minutes: breakMinutes);
    final descent = Duration(seconds: (ascent.inSeconds * 0.75).round());
    final start = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      nowLocal.hour,
      nowLocal.minute,
    );
    final arrival = start.add(ascent).add(breaks);
    final center = routeCenter(points);
    final sunset = center == null
        ? null
        : estimatedSunset(
            dateLocal: start,
            latitude: center.lat,
            longitude: center.lon,
          );
    final turnAround = sunset?.subtract(descent).subtract(safetyBuffer);
    final fits = turnAround == null ? null : !turnAround.isBefore(arrival);

    final timeline = <ItineraryPoint>[
      ItineraryPoint(
        label: 'Mulai naik',
        timeLocal: start,
        detail: 'Dari titik awal rute',
      ),
      ItineraryPoint(
        label: 'Perkiraan tiba di puncak',
        timeLocal: arrival,
        detail: 'Termasuk istirahat ${breaks.inMinutes} menit di jalan',
        warning: fits == false,
      ),
      if (turnAround != null)
        ItineraryPoint(
          label: 'Batas putar balik',
          timeLocal: turnAround,
          detail: 'Supaya turun sebelum gelap dengan cadangan 60 menit',
          warning: fits == false,
        ),
      if (sunset != null)
        ItineraryPoint(
          label: 'Matahari terbenam',
          timeLocal: sunset,
          detail: 'Perkiraan; cuaca dapat mempercepat gelap',
        ),
    ];

    final waterLitres = _waterLitres(
      ascent + breaks + summitRest + descent,
    );
    final gear = <String>[
      'Headlamp dan baterai cadangan',
      'Jaket hujan',
      'Air $waterLitres liter',
      'P3K dan peluit',
      'Makanan cadangan satu porsi',
      'Pakaian hangat lapis kedua',
      if (distanceM >= 8000) 'Trekking pole',
      if (fits == false) 'Lampu cadangan untuk turun gelap',
    ];

    return RouteEstimate(
      routeName: routeName,
      distanceM: distanceM,
      paceKmh: paceKmh,
      startLocal: start,
      arrivalLocal: arrival,
      turnAroundLocal: turnAround,
      sunsetLocal: sunset,
      fitsBeforeSunset: fits,
      ascent: ascent,
      breaks: breaks,
      summitRest: summitRest,
      descent: descent,
      timeline: timeline,
      gear: gear,
    );
  }

  static int _waterLitres(Duration total) {
    final litres = (total.inMinutes / 120).ceil();
    return litres < 1 ? 1 : litres;
  }

  String get summaryText {
    final buffer = StringBuffer()
      ..writeln('Estimasi $routeName (Hiqeo)')
      ..writeln('Jarak rute: ${(distanceM / 1000).toStringAsFixed(1)} km')
      ..writeln('Kecepatan jelajah pribadi: '
          '${paceKmh.toStringAsFixed(1)} km/jam')
      ..writeln('Mulai: ${formatClock(startLocal)}')
      ..writeln('Perkiraan tiba di puncak: ${formatClock(arrivalLocal)}');
    final turn = turnAroundLocal;
    if (turn != null) {
      buffer.writeln('Batas putar balik: ${formatClock(turn)}');
    }
    final sunset = sunsetLocal;
    if (sunset != null) {
      buffer.writeln(
        'Matahari terbenam (perkiraan): ${formatClock(sunset)}',
      );
    }
    buffer
      ..writeln()
      ..writeln('Estimasi dihitung di HP ini, bukan jadwal resmi.');
    return buffer.toString();
  }
}
