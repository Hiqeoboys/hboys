/// Satu paket Plus sebagaimana dikirim konfigurasi jarak jauh.
///
/// Harga, periode, catatan, dan kuota selalu berasal dari konfigurasi; tidak
/// ada angka yang ditanam di UI. [durationDays] null berarti berlaku seumur
/// hidup. [quotaRemaining] dan [quotaTotal] hanya diisi untuk paket berkuota
/// seperti Founding Member.
class PlusPlan {
  const PlusPlan({
    required this.id,
    required this.title,
    required this.priceLabel,
    required this.periodLabel,
    this.note,
    this.durationDays,
    this.badge,
    this.quotaRemaining,
    this.quotaTotal,
  });

  final String id;
  final String title;
  final String priceLabel;
  final String periodLabel;
  final String? note;
  final int? durationDays;
  final String? badge;
  final int? quotaRemaining;
  final int? quotaTotal;

  bool get isLifetime => durationDays == null;
  bool get hasQuota => quotaRemaining != null || quotaTotal != null;

  /// Mengembalikan null untuk entri yang tidak lengkap agar satu paket rusak
  /// dari server tidak menjatuhkan seluruh paywall.
  static PlusPlan? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    final priceLabel = json['priceLabel'];
    final periodLabel = json['periodLabel'];
    if (id is! String || id.trim().isEmpty) return null;
    if (title is! String || title.trim().isEmpty) return null;
    if (priceLabel is! String || priceLabel.trim().isEmpty) return null;
    if (periodLabel is! String || periodLabel.trim().isEmpty) return null;

    final durationRaw = json['durationDays'];
    int? durationDays;
    if (durationRaw is num) {
      durationDays = durationRaw.toInt();
      if (durationDays <= 0) return null;
    } else if (durationRaw != null) {
      return null;
    }

    final quotaRemaining = _optionalNonNegativeInt(json['quotaRemaining']);
    final quotaTotal = _optionalNonNegativeInt(json['quotaTotal']);
    if (json['quotaRemaining'] != null && quotaRemaining == null) return null;
    if (json['quotaTotal'] != null && quotaTotal == null) return null;

    return PlusPlan(
      id: id,
      title: title,
      priceLabel: priceLabel,
      periodLabel: periodLabel,
      note: _optionalNonEmptyString(json['note']),
      durationDays: durationDays,
      badge: _optionalNonEmptyString(json['badge']),
      quotaRemaining: quotaRemaining,
      quotaTotal: quotaTotal,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'priceLabel': priceLabel,
        'periodLabel': periodLabel,
        if (note != null) 'note': note,
        'durationDays': durationDays,
        if (badge != null) 'badge': badge,
        if (quotaRemaining != null) 'quotaRemaining': quotaRemaining,
        if (quotaTotal != null) 'quotaTotal': quotaTotal,
      };

  static String? _optionalNonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _optionalNonNegativeInt(Object? value) {
    if (value is! num) return null;
    final parsed = value.toInt();
    return parsed < 0 ? null : parsed;
  }
}
