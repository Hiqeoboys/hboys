import 'plus_plan.dart';

/// Saklar rilis untuk fitur yang boleh menyala bertahap.
///
/// Saklar yang tidak dikirim server dianggap mati, sehingga build lama tidak
/// pernah menampilkan fitur yang belum disetujui.
class PlusFeatureFlags {
  const PlusFeatureFlags({
    this.leaderboard = false,
    this.peakBadges = false,
  });

  static const PlusFeatureFlags disabled = PlusFeatureFlags();

  final bool leaderboard;
  final bool peakBadges;

  static PlusFeatureFlags fromJson(Object? json) {
    if (json is! Map) return disabled;
    return PlusFeatureFlags(
      leaderboard: json['leaderboard'] == true,
      peakBadges: json['peakBadges'] == true,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'leaderboard': leaderboard,
        'peakBadges': peakBadges,
      };
}

/// Konfigurasi Plus yang datang dari server dan disimpan sebagai cache lokal.
///
/// Harga, kuota, dan tenggang tidak pernah ditulis di UI. Bila server belum
/// bisa dihubungi, cache terakhir tetap dipakai; bila belum ada cache sama
/// sekali, aplikasi memakai masa tenggang 3 hari supaya fitur inti Plus
/// tetap dapat diakses sementara sebelum terkunci.
class PlusRemoteConfig {
  const PlusRemoteConfig({
    required this.plans,
    required this.graceDays,
    required this.flags,
    required this.fetchedAtUtc,
  });

  static const int minGraceDays = 3;
  static const int maxGraceDays = 3;
  static const int fallbackGraceDays = minGraceDays;

  /// Batas umur cache sebelum konfigurasi diambil ulang saat aplikasi dibuka.
  /// Status Plus sendiri tetap diperiksa offline dari token bertanda tangan.
  static const Duration refreshInterval = Duration(hours: 12);

  final List<PlusPlan> plans;
  final int graceDays;
  final PlusFeatureFlags flags;
  final DateTime fetchedAtUtc;

  int get effectiveGraceDays => graceDays.clamp(minGraceDays, maxGraceDays);

  static PlusRemoteConfig fromJson(
    Map<String, Object?> json, {
    DateTime? fetchedAtUtc,
  }) {
    final plans = <PlusPlan>[];
    final seen = <String>{};
    final rawPlans = json['plans'];
    if (rawPlans is List) {
      for (final rawPlan in rawPlans) {
        final plan = PlusPlan.tryParse(rawPlan);
        if (plan == null || !seen.add(plan.id)) continue;
        plans.add(plan);
      }
    }

    final rawGrace = json['graceDays'];
    final graceDays = rawGrace is num
        ? rawGrace.toInt().clamp(minGraceDays, maxGraceDays)
        : fallbackGraceDays;

    final rawFetchedAt = json['fetchedAtUtc'];
    final parsedFetchedAt = fetchedAtUtc ??
        (rawFetchedAt is String
            ? DateTime.tryParse(rawFetchedAt)?.toUtc()
            : null) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    return PlusRemoteConfig(
      plans: List<PlusPlan>.unmodifiable(plans),
      graceDays: graceDays,
      flags: PlusFeatureFlags.fromJson(json['flags']),
      fetchedAtUtc: parsedFetchedAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'plans': <Object?>[for (final plan in plans) plan.toJson()],
        'graceDays': graceDays,
        'flags': flags.toJson(),
        'fetchedAtUtc': fetchedAtUtc.toUtc().toIso8601String(),
      };
}
