/// Isi token hak akses Plus yang sudah diverifikasi tanda tangannya.
///
/// [expiresAtUtc] null berarti berlaku seumur hidup. Semua waktu UTC.
class EntitlementPayload {
  const EntitlementPayload({
    required this.version,
    required this.subject,
    required this.planId,
    required this.issuedAtUtc,
    this.expiresAtUtc,
  });

  static const int currentVersion = 1;

  final int version;
  final String subject;
  final String planId;
  final DateTime issuedAtUtc;
  final DateTime? expiresAtUtc;

  bool get isLifetime => expiresAtUtc == null;

  /// Mengembalikan null bila payload tidak lengkap atau versinya tidak dikenal.
  static EntitlementPayload? tryParse(Object? json) {
    if (json is! Map) return null;
    if (json['v'] != currentVersion) return null;
    final subject = json['sub'];
    final planId = json['plan'];
    if (subject is! String || subject.trim().isEmpty) return null;
    if (planId is! String || planId.trim().isEmpty) return null;
    final issuedAt = _parseUtc(json['iat']);
    if (issuedAt == null) return null;
    final rawExpiresAt = json['exp'];
    final expiresAt = rawExpiresAt == null ? null : _parseUtc(rawExpiresAt);
    if (rawExpiresAt != null && expiresAt == null) return null;
    if (expiresAt != null && expiresAt.isBefore(issuedAt)) return null;
    return EntitlementPayload(
      version: currentVersion,
      subject: subject,
      planId: planId,
      issuedAtUtc: issuedAt,
      expiresAtUtc: expiresAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'v': version,
        'sub': subject,
        'plan': planId,
        'iat': issuedAtUtc.toUtc().toIso8601String(),
        'exp': expiresAtUtc?.toUtc().toIso8601String(),
      };

  static DateTime? _parseUtc(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

enum PlusAccessState { free, active, grace, expired }

/// Status akses Plus pada satu titik waktu.
///
/// Selama [PlusAccessState.grace], seluruh fitur Plus masih dapat dipakai.
class PlusAccess {
  const PlusAccess({
    required this.state,
    this.planId,
    this.expiresAtUtc,
    this.graceEndsAtUtc,
    this.lifetime = false,
  });

  static const PlusAccess free = PlusAccess(state: PlusAccessState.free);

  final PlusAccessState state;
  final String? planId;
  final DateTime? expiresAtUtc;
  final DateTime? graceEndsAtUtc;
  final bool lifetime;

  bool get hasPlus =>
      state == PlusAccessState.active || state == PlusAccessState.grace;

  bool get isGrace => state == PlusAccessState.grace;

  /// Hanya Paket Mahasiswa, Paket Tahunan, dan Founding/Lifetime yang memiliki
  /// akses penuh fitur sosial (buat komunitas, kirim pesan komunitas, tambah
  /// teman, peringkat Leaderboard, dan lencana Plus di profil).
  /// Pengguna Gratis dan Tiket 1x Naik (`trip_pass_3d`) tidak termasuk.
  bool get hasFullSocialAccess => hasPlus && isFullSocialPlan(planId);

  static bool isFullSocialPlan(String? planId) {
    if (planId == null) return false;
    final normalized = planId.trim().toLowerCase();
    return normalized == 'student_annual' ||
        normalized == 'mahasiswa' ||
        normalized == 'annual' ||
        normalized == 'tahunan' ||
        normalized == 'lifetime' ||
        normalized == 'founding';
  }

  @override
  bool operator ==(Object other) =>
      other is PlusAccess &&
      other.state == state &&
      other.planId == planId &&
      other.expiresAtUtc == expiresAtUtc &&
      other.graceEndsAtUtc == graceEndsAtUtc &&
      other.lifetime == lifetime;

  @override
  int get hashCode =>
      Object.hash(state, planId, expiresAtUtc, graceEndsAtUtc, lifetime);
}

/// Menghitung status akses murni dari token dan waktu; tidak memanggil jaringan.
PlusAccess evaluatePlusAccess({
  required EntitlementPayload? payload,
  required DateTime nowUtc,
  required int graceDays,
}) {
  if (payload == null) return PlusAccess.free;

  final expiresAt = payload.expiresAtUtc;
  if (expiresAt == null) {
    return PlusAccess(
      state: PlusAccessState.active,
      planId: payload.planId,
      lifetime: true,
    );
  }

  final graceEndsAt = expiresAt.add(Duration(days: graceDays));
  if (nowUtc.isBefore(expiresAt)) {
    return PlusAccess(
      state: PlusAccessState.active,
      planId: payload.planId,
      expiresAtUtc: expiresAt,
      graceEndsAtUtc: graceEndsAt,
    );
  }
  if (nowUtc.isBefore(graceEndsAt)) {
    return PlusAccess(
      state: PlusAccessState.grace,
      planId: payload.planId,
      expiresAtUtc: expiresAt,
      graceEndsAtUtc: graceEndsAt,
    );
  }
  return PlusAccess(
    state: PlusAccessState.expired,
    planId: payload.planId,
    expiresAtUtc: expiresAt,
    graceEndsAtUtc: graceEndsAt,
  );
}
