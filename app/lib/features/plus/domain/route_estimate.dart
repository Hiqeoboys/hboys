import 'dart:math' as math;

import 'package:geo_utils/geo_utils.dart' show LatLng;

import '../../trails/domain/track_route.dart';
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

/// Kecepatan tim untuk kalkulator estimasi pendakian lokal.
enum HikingPace {
  santai('Santai', 0.78),
  normal('Normal', 1.00),
  cepat('Cepat', 1.25);

  const HikingPace(this.label, this.speedFactor);

  final String label;
  final double speedFactor;
}

/// Beban carrier yang memengaruhi laju jalan, kebutuhan air, dan kalori.
enum CarrierLoad {
  ringan('Ringan (Tektok / < 8 kg)', 1.00, 1.00, 1.00),
  sedang('Sedang (8–14 kg)', 0.88, 1.08, 1.18),
  berat('Berat (> 14 kg)', 0.76, 1.16, 1.38);

  const CarrierLoad(
    this.label,
    this.speedMultiplier,
    this.waterMultiplier,
    this.calorieMultiplier,
  );

  final String label;
  final double speedMultiplier;
  final double waterMultiplier;
  final double calorieMultiplier;
}

/// Titik estimasi waktu tiba per pos pada jalur pendakian.
class PostEtaItem {
  const PostEtaItem({
    required this.name,
    required this.distanceFromStartM,
    required this.etaLocal,
    this.elevationM,
    this.isSummit = false,
    this.isReturn = false,
  });

  final String name;
  final double distanceFromStartM;
  final double? elevationM;
  final DateTime etaLocal;
  final bool isSummit;
  final bool isReturn;
}

/// Hasil kalkulator estimasi waktu & logistik pendakian berbasis Naismith's Rule
/// + fungsi kemiringan Tobler (100% dihitung lokal tanpa beban database).
class HikingPlanEstimate {
  const HikingPlanEstimate({
    required this.routeName,
    required this.trailName,
    required this.distanceM,
    required this.elevationGainM,
    required this.basecampElevationM,
    required this.summitElevationM,
    required this.pace,
    required this.load,
    required this.startLocal,
    required this.ascentMoving,
    required this.ascentBreaks,
    required this.ascentTotal,
    required this.summitRest,
    required this.descent,
    required this.totalRoundTrip,
    required this.summitArrivalLocal,
    required this.returnBasecampLocal,
    required this.sunsetLocal,
    required this.turnAroundLocal,
    required this.fitsBeforeSunset,
    required this.waterLiters,
    required this.caloriesKcal,
    required this.postEtas,
    required this.gear,
  });

  final String routeName;
  final String? trailName;
  final double distanceM;
  final double elevationGainM;
  final double basecampElevationM;
  final double summitElevationM;
  final HikingPace pace;
  final CarrierLoad load;
  final DateTime startLocal;
  final Duration ascentMoving;
  final Duration ascentBreaks;
  final Duration ascentTotal;
  final Duration summitRest;
  final Duration descent;
  final Duration totalRoundTrip;
  final DateTime summitArrivalLocal;
  final DateTime returnBasecampLocal;
  final DateTime? sunsetLocal;
  final DateTime? turnAroundLocal;
  final bool? fitsBeforeSunset;
  final double waterLiters;
  final int caloriesKcal;
  final List<PostEtaItem> postEtas;
  final List<String> gear;

  static HikingPlanEstimate calculate({
    required String routeName,
    String? trailName,
    required double distanceM,
    required double elevationGainM,
    required double basecampElevationM,
    required double summitElevationM,
    required DateTime startLocal,
    required HikingPace pace,
    required CarrierLoad load,
    LatLng? centerCoord,
    List<TrackWaypoint> waypoints = const <TrackWaypoint>[],
    Duration summitRest = const Duration(minutes: 45),
  }) {
    final safeDistM = distanceM < 100 ? 100.0 : distanceM;
    final effectiveGainM = elevationGainM > 0
        ? elevationGainM
        : math.max(100.0, summitElevationM - basecampElevationM);
    final distanceKm = safeDistM / 1000.0;
    final grade = (effectiveGainM / safeDistM).clamp(0.0, 0.6);

    // Kombinasi Naismith's Rule + Tobler Hiking Function:
    // Naismith: distanceKm/5 + gainM/600 jam
    // Tobler uphill: 6 * exp(-3.5 * |grade + 0.05|) km/jam
    final naismithHours = (distanceKm / 5.0) + (effectiveGainM / 600.0);
    final toblerSpeedKmh = 6.0 * math.exp(-3.5 * (grade + 0.05).abs());
    final toblerHours =
        toblerSpeedKmh > 0.2 ? distanceKm / toblerSpeedKmh : naismithHours;
    final baseAscentHours = (naismithHours * 0.5) + (toblerHours * 0.5);

    final effectiveFactor = pace.speedFactor * load.speedMultiplier;
    final ascentMovingSec =
        (baseAscentHours / effectiveFactor * 3600).round().clamp(600, 86400);
    final ascentMoving = Duration(seconds: ascentMovingSec);
    final breakMins = ((ascentMovingSec / 3600.0) * 10).round().clamp(5, 180);
    final ascentBreaks = Duration(minutes: breakMins);
    final ascentTotal = ascentMoving + ascentBreaks;

    // Turun sedikit lebih lambat pada jalur sangat terjal atau carrier berat.
    final descentRatio = ((0.62 + grade.clamp(0.0, 0.35) * 0.30) /
            load.speedMultiplier.clamp(0.80, 1.0))
        .clamp(0.55, 0.85);
    final descent = Duration(seconds: (ascentMovingSec * descentRatio).round());
    final totalRoundTrip = ascentTotal + summitRest + descent;

    final start = DateTime(
      startLocal.year,
      startLocal.month,
      startLocal.day,
      startLocal.hour,
      startLocal.minute,
    );
    final summitArrival = start.add(ascentTotal);
    final returnBasecamp = start.add(totalRoundTrip);

    final sunset = centerCoord == null
        ? null
        : estimatedSunset(
            dateLocal: start,
            latitude: centerCoord.lat,
            longitude: centerCoord.lon,
          );
    final turnAround =
        sunset?.subtract(descent).subtract(const Duration(minutes: 45));
    final fits = sunset == null
        ? null
        : !returnBasecamp.isAfter(sunset.add(const Duration(minutes: 15)));

    // Kebutuhan air (liter dibulatkan ke 0,5 L terdekat) & kalori (kkal kelipatan 50)
    final activeHours = (ascentTotal.inMinutes + descent.inMinutes) / 60.0;
    final rawLiters = (activeHours * 0.55 * load.waterMultiplier) +
        (effectiveGainM / 1000.0 * 0.30);
    final waterLiters = ((rawLiters * 2.0).ceil() / 2.0).clamp(1.5, 12.0);
    final rawKcal =
        (activeHours * 340.0 + effectiveGainM * 0.42) * load.calorieMultiplier;
    final caloriesKcal = ((rawKcal / 50.0).round() * 50).clamp(300, 12000);

    // Susun estimasi waktu per pos dari GPX waypoints jika tersedia.
    final postEtas = <PostEtaItem>[
      PostEtaItem(
        name: 'Basecamp',
        distanceFromStartM: 0,
        elevationM: basecampElevationM,
        etaLocal: start,
      ),
    ];

    if (waypoints.isNotEmpty) {
      var lastFrac = 0.0;
      var hasSummitWp = false;
      final totalAscentSec = ascentTotal.inSeconds;
      final gainDenom = math.max(1.0, summitElevationM - basecampElevationM);

      for (var i = 0; i < waypoints.length; i++) {
        final wp = waypoints[i];
        final isLast = i == waypoints.length - 1;
        final lowerName = wp.name.toLowerCase();
        final looksLikeSummit = lowerName.contains('puncak') ||
            lowerName.contains('summit') ||
            (wp.symbol?.toLowerCase().contains('summit') ?? false);
        final dFrac = (wp.distanceFromStartM / safeDistM).clamp(0.0, 1.0);
        final eFrac = wp.elevationM != null
            ? ((wp.elevationM! - basecampElevationM) / gainDenom)
                .clamp(0.0, 1.0)
            : dFrac;
        var combined = (dFrac * 0.45 + eFrac * 0.55).clamp(0.05, 1.0);
        if (combined <= lastFrac) {
          combined = math.min(1.0, lastFrac + 0.05);
        }
        if (isLast && looksLikeSummit) {
          combined = 1.0;
          hasSummitWp = true;
        }
        lastFrac = combined;
        postEtas.add(
          PostEtaItem(
            name: wp.name,
            distanceFromStartM: wp.distanceFromStartM,
            elevationM: wp.elevationM,
            etaLocal: start.add(
              Duration(seconds: (totalAscentSec * combined).round()),
            ),
            isSummit: looksLikeSummit,
          ),
        );
      }
      if (!hasSummitWp) {
        postEtas.add(
          PostEtaItem(
            name: 'Puncak',
            distanceFromStartM: safeDistM,
            elevationM: summitElevationM,
            etaLocal: summitArrival,
            isSummit: true,
          ),
        );
      }
    } else {
      postEtas.addAll(<PostEtaItem>[
        PostEtaItem(
          name: 'Pos Tengah',
          distanceFromStartM: safeDistM * 0.55,
          elevationM: (basecampElevationM + summitElevationM) / 2.0,
          etaLocal: start.add(
            Duration(seconds: (ascentTotal.inSeconds * 0.55).round()),
          ),
        ),
        PostEtaItem(
          name: 'Puncak',
          distanceFromStartM: safeDistM,
          elevationM: summitElevationM,
          etaLocal: summitArrival,
          isSummit: true,
        ),
      ]);
    }

    postEtas.add(
      PostEtaItem(
        name: 'Kembali ke Basecamp',
        distanceFromStartM: safeDistM * 2,
        elevationM: basecampElevationM,
        etaLocal: returnBasecamp,
        isReturn: true,
      ),
    );

    final formattedWater = formatDecimal(waterLiters);
    final gear = <String>[
      'Air minum min. $formattedWater liter & elektrolit',
      'Bekal logistik ±${groupDigits(caloriesKcal)} kkal',
      'Headlamp + baterai cadangan',
      'Jaket insulasi & jas hujan',
      'P3K pribadi & peluit darurat',
      if (safeDistM >= 7000)
        'Trekking pole untuk kurangi beban lutut saat turun',
      if (fits == false) 'Senter cadangan (perkiraan turun mendekati gelap)',
    ];

    return HikingPlanEstimate(
      routeName: routeName,
      trailName: trailName,
      distanceM: safeDistM,
      elevationGainM: effectiveGainM,
      basecampElevationM: basecampElevationM,
      summitElevationM: summitElevationM,
      pace: pace,
      load: load,
      startLocal: start,
      ascentMoving: ascentMoving,
      ascentBreaks: ascentBreaks,
      ascentTotal: ascentTotal,
      summitRest: summitRest,
      descent: descent,
      totalRoundTrip: totalRoundTrip,
      summitArrivalLocal: summitArrival,
      returnBasecampLocal: returnBasecamp,
      sunsetLocal: sunset,
      turnAroundLocal: turnAround,
      fitsBeforeSunset: fits,
      waterLiters: waterLiters,
      caloriesKcal: caloriesKcal,
      postEtas: List<PostEtaItem>.unmodifiable(postEtas),
      gear: List<String>.unmodifiable(gear),
    );
  }

  String get summaryText {
    final buffer = StringBuffer()
      ..writeln('Estimasi $routeName (Hiqeo)')
      ..writeln(
        'Jarak naik: ${formatKm(distanceM)} · Tanjakan: +${groupDigits(elevationGainM.round())} m',
      )
      ..writeln('Kecepatan: ${pace.label} · Beban: ${load.label}')
      ..writeln('Mulai: ${formatClock(startLocal)}')
      ..writeln(
          'Tiba puncak: ${formatClock(summitArrivalLocal)} (${formatDuration(ascentTotal.inSeconds)})')
      ..writeln('Turun: ${formatDuration(descent.inSeconds)}')
      ..writeln(
          'Total pulang-pergi: ${formatDuration(totalRoundTrip.inSeconds)} (kembali ${formatClock(returnBasecampLocal)})')
      ..writeln(
          'Kebutuhan air: ${formatDecimal(waterLiters)} liter · Kalori: ${groupDigits(caloriesKcal)} kkal');
    if (sunsetLocal != null) {
      buffer
          .writeln('Perkiraan matahari terbenam: ${formatClock(sunsetLocal!)}');
    }
    return buffer.toString();
  }
}

/// Estimasi perjalanan yang dihitung di perangkat dari kecepatan pribadi (legacy).
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
