import 'track_point.dart';
import 'gps_filter.dart';

/// Hitungan dan data fix terakhir untuk diagnosa pipeline lokasi. Murni data:
/// bisa dikirim lintas isolate lewat [toMap]/[TrackingDiagnostics.fromMap].
class TrackingDiagnostics {
  TrackingDiagnostics();

  int received = 0;
  int accepted = 0;
  int rejectedAccuracy = 0;
  int rejectedDuplicateTime = 0;
  int rejectedJump = 0;
  int rejectedJitter = 0;

  /// Rata-rata bergerak (10 fix) akurasi horizontal, meter.
  double? avgAccuracyM;

  FixRejectReason? lastReject;

  double? lastLat;
  double? lastLon;
  double? lastAccuracyM;
  double? lastSpeedMps;
  double? lastSpeedAccuracyMps;
  double? lastAltitudeM;
  double? lastAltitudeAccuracyM;
  bool lastIsMocked = false;
  DateTime? lastReceivedAtUtc;
  String provider = 'geolocator/FusedLocation';

  int get rejected =>
      rejectedAccuracy + rejectedDuplicateTime + rejectedJump + rejectedJitter;

  double? lastFixAgeSeconds(DateTime nowUtc) {
    final at = lastReceivedAtUtc;
    if (at == null) return null;
    return nowUtc.difference(at).inMilliseconds / 1000.0;
  }

  void record(TrackPoint p, FixRejectReason? reason) {
    received++;
    switch (reason) {
      case null:
        accepted++;
      case FixRejectReason.accuracy:
        rejectedAccuracy++;
      case FixRejectReason.duplicateTime:
        rejectedDuplicateTime++;
      case FixRejectReason.jump:
        rejectedJump++;
      case FixRejectReason.jitter:
        rejectedJitter++;
    }
    lastReject = reason;
    lastLat = p.lat;
    lastLon = p.lon;
    lastAccuracyM = p.accuracyM;
    lastSpeedMps = p.speedMps;
    lastSpeedAccuracyMps = p.speedAccuracyMps;
    lastAltitudeM = p.altitudeM;
    lastAltitudeAccuracyM = p.altitudeAccuracyM;
    lastIsMocked = p.isMocked;
    lastReceivedAtUtc = p.receivedAtUtc ?? p.timestampUtc;
    final previous = avgAccuracyM;
    avgAccuracyM =
        previous == null ? p.accuracyM : previous + (p.accuracyM - previous) / 10;
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'received': received,
        'accepted': accepted,
        'rejectedAccuracy': rejectedAccuracy,
        'rejectedDuplicateTime': rejectedDuplicateTime,
        'rejectedJump': rejectedJump,
        'rejectedJitter': rejectedJitter,
        'avgAccuracyM': avgAccuracyM,
        'lastReject': lastReject?.name,
        'lastLat': lastLat,
        'lastLon': lastLon,
        'lastAccuracyM': lastAccuracyM,
        'lastSpeedMps': lastSpeedMps,
        'lastSpeedAccuracyMps': lastSpeedAccuracyMps,
        'lastAltitudeM': lastAltitudeM,
        'lastAltitudeAccuracyM': lastAltitudeAccuracyM,
        'lastIsMocked': lastIsMocked,
        'lastReceivedAtUtc': lastReceivedAtUtc?.toUtc().toIso8601String(),
      };

  factory TrackingDiagnostics.fromMap(Map<Object?, Object?> map) {
    double? d(String key) => (map[key] as num?)?.toDouble();
    int i(String key) => (map[key] as num?)?.toInt() ?? 0;
    final diag = TrackingDiagnostics()
      ..received = i('received')
      ..accepted = i('accepted')
      ..rejectedAccuracy = i('rejectedAccuracy')
      ..rejectedDuplicateTime = i('rejectedDuplicateTime')
      ..rejectedJump = i('rejectedJump')
      ..rejectedJitter = i('rejectedJitter')
      ..avgAccuracyM = d('avgAccuracyM')
      ..lastLat = d('lastLat')
      ..lastLon = d('lastLon')
      ..lastAccuracyM = d('lastAccuracyM')
      ..lastSpeedMps = d('lastSpeedMps')
      ..lastSpeedAccuracyMps = d('lastSpeedAccuracyMps')
      ..lastAltitudeM = d('lastAltitudeM')
      ..lastAltitudeAccuracyM = d('lastAltitudeAccuracyM')
      ..lastIsMocked = map['lastIsMocked'] == true;
    final reject = map['lastReject'];
    if (reject is String) {
      for (final reason in FixRejectReason.values) {
        if (reason.name == reject) diag.lastReject = reason;
      }
    }
    final at = map['lastReceivedAtUtc'];
    if (at is String) diag.lastReceivedAtUtc = DateTime.tryParse(at)?.toUtc();
    return diag;
  }

  /// Satu baris ringkas untuk log konsol.
  String summary() {
    String f(double? v, [int digits = 1]) =>
        v == null ? '-' : v.toStringAsFixed(digits);
    return 'fix=$received ok=$accepted '
        'tolak(akurasi=$rejectedAccuracy,waktu=$rejectedDuplicateTime,'
        'loncat=$rejectedJump,jitter=$rejectedJitter) '
        'acc=${f(lastAccuracyM)}m avg=${f(avgAccuracyM)}m '
        'spd=${f(lastSpeedMps, 2)} alt=${f(lastAltitudeM)} '
        'mock=$lastIsMocked terakhir=${lastReject?.name ?? 'diterima'}';
  }
}

