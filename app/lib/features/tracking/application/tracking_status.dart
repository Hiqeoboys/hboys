import '../../../infrastructure/power/power_profile_manager.dart';
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

  factory TrackingStatus.fromRuntimeUpdate(TrackingRuntimeUpdate update) {
    final snapshot = update.snapshot;
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
    );
  }
}
