import '../../../infrastructure/power/power_profile_manager.dart';
import '../domain/tracking_diagnostics.dart';
import '../domain/tracking_session.dart';
import 'tracking_runtime.dart';

/// Potret datar sesi rekaman untuk UI dan pesan lintas isolate.
class TrackingStatus {
  const TrackingStatus({
    required this.sessionId,
    required this.sessionStatus,
    required this.startedAtUtc,
    required this.distanceM,
    required this.movingSeconds,
    required this.elapsedSeconds,
    required this.elevationGainM,
    required this.elevationLossM,
    required this.isMoving,
    required this.pointCount,
    required this.profile,
    this.paceSecPerKm,
    this.verticalSpeedMph,
    this.batteryPercent,
    this.isPaused = false,
    this.stepCount,
    this.kcalPerKg = 0,
    this.lastValidFixAtUtc,
    this.diagnostics,
    this.activityType = TrackingSession.activityHiking,
  });

  final String sessionId;
  final TrackingSessionStatus sessionStatus;
  final DateTime startedAtUtc;
  final double distanceM;
  final int movingSeconds;
  final int elapsedSeconds;
  final double elevationGainM;
  final double elevationLossM;
  final bool isMoving;
  final int pointCount;
  final PowerProfile profile;
  final double? paceSecPerKm;
  final double? verticalSpeedMph;
  final int? batteryPercent;
  final bool isPaused;

  /// Langkah sejak rekaman dimulai dari sensor langkah; `null` bila tidak ada.
  /// Diisi di sisi UI, tidak dikirim dari layanan latar.
  final int? stepCount;

  /// Energi terkumpul per kg berat badan (ACSM). Kalikan dengan berat badan.
  final double kcalPerKg;

  /// Waktu jam dinding saat fix valid terakhir diterima. `null` bila belum
  /// pernah ada fix valid (status "Mencari sinyal GPS").
  final DateTime? lastValidFixAtUtc;

  /// Hitungan diagnosa pipeline lokasi.
  final TrackingDiagnostics? diagnostics;

  /// Jenis aktivitas sesi: `'hiking'` atau `'jogging'`.
  final String activityType;

  bool get isJogging => activityType == TrackingSession.activityJogging;

  bool get hasValidFix => lastValidFixAtUtc != null;

  TrackingStatus copyWith({
    String? sessionId,
    TrackingSessionStatus? sessionStatus,
    DateTime? startedAtUtc,
    double? distanceM,
    int? movingSeconds,
    int? elapsedSeconds,
    double? elevationGainM,
    double? elevationLossM,
    bool? isMoving,
    int? pointCount,
    PowerProfile? profile,
    double? paceSecPerKm,
    double? verticalSpeedMph,
    int? batteryPercent,
    bool? isPaused,
    int? stepCount,
    double? kcalPerKg,
    DateTime? lastValidFixAtUtc,
    TrackingDiagnostics? diagnostics,
    String? activityType,
  }) {
    return TrackingStatus(
      sessionId: sessionId ?? this.sessionId,
      sessionStatus: sessionStatus ?? this.sessionStatus,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      distanceM: distanceM ?? this.distanceM,
      movingSeconds: movingSeconds ?? this.movingSeconds,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      elevationGainM: elevationGainM ?? this.elevationGainM,
      elevationLossM: elevationLossM ?? this.elevationLossM,
      isMoving: isMoving ?? this.isMoving,
      pointCount: pointCount ?? this.pointCount,
      profile: profile ?? this.profile,
      paceSecPerKm: paceSecPerKm ?? this.paceSecPerKm,
      verticalSpeedMph: verticalSpeedMph ?? this.verticalSpeedMph,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      isPaused: isPaused ?? this.isPaused,
      stepCount: stepCount ?? this.stepCount,
      kcalPerKg: kcalPerKg ?? this.kcalPerKg,
      lastValidFixAtUtc: lastValidFixAtUtc ?? this.lastValidFixAtUtc,
      diagnostics: diagnostics ?? this.diagnostics,
      activityType: activityType ?? this.activityType,
    );
  }

  factory TrackingStatus.fromRuntimeUpdate(TrackingRuntimeUpdate update) {
    final snapshot = update.snapshot;
    final point = snapshot?.lastPoint;
    return TrackingStatus(
      sessionId: update.session.id,
      sessionStatus: update.session.status,
      startedAtUtc: update.session.startedAtUtc,
      distanceM: snapshot?.distanceM ?? update.session.distanceM,
      movingSeconds:
          snapshot?.movingTime.inSeconds ?? update.session.movingSeconds,
      elapsedSeconds: snapshot?.elapsed.inSeconds ?? 0,
      elevationGainM: snapshot?.gainM ?? update.session.elevationGainM,
      elevationLossM: snapshot?.lossM ?? update.session.elevationLossM,
      isMoving: snapshot?.isMoving ?? false,
      pointCount: update.pointCount,
      profile: update.profile,
      paceSecPerKm: snapshot?.paceSecPerKm,
      verticalSpeedMph: snapshot?.verticalSpeedMph,
      batteryPercent: update.batteryPercent,
      isPaused: update.isPaused,
      kcalPerKg: snapshot?.kcalPerKg ?? 0,
      lastValidFixAtUtc: point == null
          ? null
          : (point.receivedAtUtc ?? point.timestampUtc),
      diagnostics: update.diagnostics,
      activityType: update.session.activityType,
    );
  }

  Map<String, Object?> toMap(String type) => {
        'type': type,
        'sessionId': sessionId,
        'sessionStatus': sessionStatus.name,
        'startedAtUtc': startedAtUtc.toUtc().toIso8601String(),
        'distanceM': distanceM,
        'movingSeconds': movingSeconds,
        'elapsedSeconds': elapsedSeconds,
        'elevationGainM': elevationGainM,
        'elevationLossM': elevationLossM,
        'isMoving': isMoving,
        'pointCount': pointCount,
        'profile': profile.name,
        'paceSecPerKm': paceSecPerKm,
        'verticalSpeedMph': verticalSpeedMph,
        'batteryPercent': batteryPercent,
        'isPaused': isPaused,
        'kcalPerKg': kcalPerKg,
        'lastValidFixAtUtc': lastValidFixAtUtc?.toUtc().toIso8601String(),
        'diagnostics': diagnostics?.toMap(),
        'activityType': activityType,
      };

  factory TrackingStatus.fromMap(Map<Object?, Object?> map) {
    String string(String key) {
      final value = map[key];
      if (value is String) return value;
      throw FormatException('Pesan tracking tanpa $key');
    }

    num number(String key) {
      final value = map[key];
      if (value is num) return value;
      throw FormatException('Pesan tracking tanpa angka $key');
    }

    num? optionalNumber(String key) => map[key] as num?;

    final profileName = string('profile');
    final profile = PowerProfile.values.firstWhere(
      (p) => p.name == profileName,
      orElse: () =>
          throw FormatException('Profil daya tidak dikenal: $profileName'),
    );
    final statusName = string('sessionStatus');
    final sessionStatus = TrackingSessionStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () =>
          throw FormatException('Status sesi tidak dikenal: $statusName'),
    );
    final fixAt = map['lastValidFixAtUtc'];
    final diag = map['diagnostics'];

    return TrackingStatus(
      sessionId: string('sessionId'),
      sessionStatus: sessionStatus,
      startedAtUtc: DateTime.parse(string('startedAtUtc')).toUtc(),
      distanceM: number('distanceM').toDouble(),
      movingSeconds: number('movingSeconds').toInt(),
      elapsedSeconds: number('elapsedSeconds').toInt(),
      elevationGainM: number('elevationGainM').toDouble(),
      elevationLossM: number('elevationLossM').toDouble(),
      isMoving: map['isMoving'] == true,
      pointCount: number('pointCount').toInt(),
      profile: profile,
      paceSecPerKm: optionalNumber('paceSecPerKm')?.toDouble(),
      verticalSpeedMph: optionalNumber('verticalSpeedMph')?.toDouble(),
      batteryPercent: optionalNumber('batteryPercent')?.toInt(),
      isPaused: map['isPaused'] == true,
      kcalPerKg: optionalNumber('kcalPerKg')?.toDouble() ?? 0,
      lastValidFixAtUtc:
          fixAt is String ? DateTime.tryParse(fixAt)?.toUtc() : null,
      diagnostics: diag is Map ? TrackingDiagnostics.fromMap(diag) : null,
      activityType: TrackingSession.normalizeActivityType(
        map['activityType'] as String?,
      ),
    );
  }
}
