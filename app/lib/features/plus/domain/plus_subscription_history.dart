import 'package:flutter/foundation.dart';

enum PlusSubscriptionHistoryStatus {
  active,
  lifetime,
  grace,
  expired,
  cancelled,
}

extension PlusSubscriptionHistoryStatusX on PlusSubscriptionHistoryStatus {
  String get label => switch (this) {
        PlusSubscriptionHistoryStatus.active => 'Aktif',
        PlusSubscriptionHistoryStatus.lifetime => 'Seumur hidup',
        PlusSubscriptionHistoryStatus.grace => 'Masa tenggang',
        PlusSubscriptionHistoryStatus.expired => 'Berakhir',
        PlusSubscriptionHistoryStatus.cancelled => 'Dibatalkan',
      };

  static PlusSubscriptionHistoryStatus parse(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'active' => PlusSubscriptionHistoryStatus.active,
        'lifetime' => PlusSubscriptionHistoryStatus.lifetime,
        'grace' => PlusSubscriptionHistoryStatus.grace,
        'cancelled' => PlusSubscriptionHistoryStatus.cancelled,
        _ => PlusSubscriptionHistoryStatus.expired,
      };
}

String plusPlanTitleForId(String? planId) {
  switch (planId?.trim().toLowerCase()) {
    case 'student_annual':
    case 'mahasiswa':
      return 'Paket Mahasiswa';
    case 'annual':
    case 'tahunan':
      return 'Hiqeo Plus Tahunan';
    case 'trip_pass_3d':
    case 'trip3d':
    case 'trip7d':
      return 'Tiket 1x Naik';
    case 'founding':
      return 'Founding Member';
    case 'lifetime':
    case 'ultima':
      return 'Hiqeo Plus Ultima';
    default:
      return 'Hiqeo Plus';
  }
}

@immutable
class PlusSubscriptionHistoryEntry {
  const PlusSubscriptionHistoryEntry({
    required this.id,
    required this.planId,
    required this.planTitle,
    required this.status,
    required this.startedAtUtc,
    this.expiresAtUtc,
  });

  final String id;
  final String planId;
  final String planTitle;
  final PlusSubscriptionHistoryStatus status;
  final DateTime startedAtUtc;
  final DateTime? expiresAtUtc;

  bool get isLifetime => status == PlusSubscriptionHistoryStatus.lifetime;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'plan_id': planId,
        'plan_title': planTitle,
        'status': status.name,
        'started_at': startedAtUtc.toUtc().toIso8601String(),
        'expires_at': expiresAtUtc?.toUtc().toIso8601String(),
      };

  static PlusSubscriptionHistoryEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final id = map['id']?.toString() ?? '';
    final planId = map['plan_id']?.toString() ?? 'annual';
    final startedRaw = map['started_at']?.toString();
    final startedAt =
        startedRaw != null ? DateTime.tryParse(startedRaw)?.toUtc() : null;
    if (id.isEmpty || startedAt == null) return null;
    final expiresRaw = map['expires_at']?.toString();
    final expiresAt =
        expiresRaw != null ? DateTime.tryParse(expiresRaw)?.toUtc() : null;
    final title = map['plan_title']?.toString().trim();
    return PlusSubscriptionHistoryEntry(
      id: id,
      planId: planId,
      planTitle:
          (title != null && title.isNotEmpty) ? title : plusPlanTitleForId(planId),
      status: PlusSubscriptionHistoryStatusX.parse(map['status']?.toString()),
      startedAtUtc: startedAt,
      expiresAtUtc: expiresAt,
    );
  }
}
