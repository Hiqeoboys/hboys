import 'sos_category.dart';

enum SosEventStatus { active, cancelled, resolved }

class SosEvent {
  const SosEvent({
    required this.id,
    required this.authorId,
    required this.category,
    required this.lat,
    required this.lon,
    required this.createdAtUtc,
    required this.receivedAtUtc,
    this.groupId,
    this.accuracyM,
    this.batteryPercent,
    this.status = SosEventStatus.active,
    this.cancelledAtUtc,
  });

  final String id;
  final String authorId;
  final String? groupId;
  final SosCategory category;
  final double lat;
  final double lon;
  final int? accuracyM;
  final int? batteryPercent;

  /// Waktu di perangkat pembuat, bukan waktu server.
  final DateTime createdAtUtc;
  final DateTime receivedAtUtc;
  final SosEventStatus status;
  final DateTime? cancelledAtUtc;
}
