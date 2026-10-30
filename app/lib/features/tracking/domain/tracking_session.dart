enum TrackingSessionStatus { active, completed }

class TrackingSession {
  const TrackingSession({
    required this.id,
    required this.startedAtUtc,
    this.endedAtUtc,
    this.groupId,
    this.trailId,
    this.distanceM = 0,
    this.movingSeconds = 0,
    this.elevationGainM = 0,
    this.elevationLossM = 0,
    this.status = TrackingSessionStatus.active,
  });

  final String id;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;
  final String? groupId;
  final String? trailId;
  final double distanceM;
  final int movingSeconds;
  final double elevationGainM;
  final double elevationLossM;
  final TrackingSessionStatus status;

  TrackingSession copyWith({
    DateTime? endedAtUtc,
    double? distanceM,
    int? movingSeconds,
    double? elevationGainM,
    double? elevationLossM,
    TrackingSessionStatus? status,
  }) =>
      TrackingSession(
        id: id,
        startedAtUtc: startedAtUtc,
        endedAtUtc: endedAtUtc ?? this.endedAtUtc,
        groupId: groupId,
        trailId: trailId,
        distanceM: distanceM ?? this.distanceM,
        movingSeconds: movingSeconds ?? this.movingSeconds,
        elevationGainM: elevationGainM ?? this.elevationGainM,
        elevationLossM: elevationLossM ?? this.elevationLossM,
        status: status ?? this.status,
      );
}
