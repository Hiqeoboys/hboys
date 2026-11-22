enum TrackingSessionStatus { active, completed }

class TrackingSession {
  static const String activityHiking = 'hiking';
  static const String activityJogging = 'jogging';

  static String normalizeActivityType(String? value) =>
      value == activityJogging ? activityJogging : activityHiking;

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
    this.reachedSummit = false,
    this.mountainName,
    this.trailName,
    this.activityType = activityHiking,
    this.ownerUserId,
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
  final bool reachedSummit;
  final String? mountainName;
  final String? trailName;
  final String activityType;
  final String? ownerUserId;

  bool get isJogging => activityType == activityJogging;

  TrackingSession copyWith({
    DateTime? endedAtUtc,
    String? trailId,
    double? distanceM,
    int? movingSeconds,
    double? elevationGainM,
    double? elevationLossM,
    TrackingSessionStatus? status,
    bool? reachedSummit,
    String? mountainName,
    String? trailName,
    String? activityType,
    String? ownerUserId,
  }) =>
      TrackingSession(
        id: id,
        startedAtUtc: startedAtUtc,
        endedAtUtc: endedAtUtc ?? this.endedAtUtc,
        groupId: groupId,
        trailId: trailId ?? this.trailId,
        distanceM: distanceM ?? this.distanceM,
        movingSeconds: movingSeconds ?? this.movingSeconds,
        elevationGainM: elevationGainM ?? this.elevationGainM,
        elevationLossM: elevationLossM ?? this.elevationLossM,
        status: status ?? this.status,
        reachedSummit: reachedSummit ?? this.reachedSummit,
        mountainName: mountainName ?? this.mountainName,
        trailName: trailName ?? this.trailName,
        activityType: activityType ?? this.activityType,
        ownerUserId: ownerUserId ?? this.ownerUserId,
      );
}
