import '../features/plus/domain/plus_plan.dart';
import '../features/plus/domain/plus_remote_config.dart';
import '../features/plus/domain/plus_repositories.dart';

const int kPlusTripPassPriceIdr = 7900;
const int kPlusStudentAnnualPriceIdr = 79000;
const int kPlusAnnualPriceIdr = 149000;

/// Alias kompatibilitas untuk pengujian lama.
const int kPlusMonthlyPriceIdr = 29000;

/// Menghitung persentase penghematan paket Tahunan dibanding 12x paket Bulanan.
int calculateAnnualSavingsPercent({
  int monthlyPriceIdr = kPlusMonthlyPriceIdr,
  int annualPriceIdr = kPlusAnnualPriceIdr,
}) {
  final yearlyFromMonthly = monthlyPriceIdr * 12;
  if (yearlyFromMonthly <= 0 || annualPriceIdr >= yearlyFromMonthly) return 0;
  return (((yearlyFromMonthly - annualPriceIdr) / yearlyFromMonthly) * 100)
      .round();
}

/// Format Rupiah (mis. 7900 -> "Rp7.900").
String formatRupiah(int amountIdr) {
  final digits = amountIdr.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return 'Rp$buffer';
}

/// Tiga paket resmi Paywall Hiqeo Plus:
/// 1. Tiket 1x Naik — Rp7.900 · 3 hari tanpa berlangganan (tanpa label "fitur terbatas").
/// 2. Paket Mahasiswa — Rp79.000 / tahun.
/// 3. Paket Tahunan — Rp149.000 / tahun.
List<PlusPlan> buildDefaultPlusPlans({
  int tripPassPriceIdr = kPlusTripPassPriceIdr,
  int studentAnnualPriceIdr = kPlusStudentAnnualPriceIdr,
  int annualPriceIdr = kPlusAnnualPriceIdr,
}) {
  return <PlusPlan>[
    PlusPlan(
      id: 'trip_pass_3d',
      title: 'Tiket 1x Naik',
      priceLabel: formatRupiah(tripPassPriceIdr),
      periodLabel: '3 hari tanpa berlangganan',
      durationDays: 3,
    ),
    PlusPlan(
      id: 'student_annual',
      title: 'Paket Mahasiswa',
      priceLabel: formatRupiah(studentAnnualPriceIdr),
      periodLabel: '/ tahun',
      note: 'Akses penuh untuk pelajar & mahasiswa',
      durationDays: 365,
      badge: 'Hemat',
    ),
    PlusPlan(
      id: 'annual',
      title: 'Paket Tahunan',
      priceLabel: formatRupiah(annualPriceIdr),
      periodLabel: '/ tahun',
      note: 'Akses penuh seluruh fitur Hiqeo Plus',
      durationDays: 365,
      badge: 'Populer',
    ),
  ];
}

/// Abstraksi repositori langganan untuk dihubungkan ke RevenueCat / Play Billing.
abstract interface class SubscriptionRepository
    implements PlusBillingRepository, PlusRemoteConfigRepository {
  List<PlusPlan> get availablePlans;
}

/// Implementasi mock sebelum payment gateway aktif.
class MockSubscriptionRepository implements SubscriptionRepository {
  const MockSubscriptionRepository();

  @override
  List<PlusPlan> get availablePlans => buildDefaultPlusPlans();

  @override
  Future<PlusRemoteConfig> fetch({required DateTime fetchedAtUtc}) async {
    return PlusRemoteConfig(
      plans: availablePlans,
      graceDays: PlusRemoteConfig.fallbackGraceDays,
      flags: const PlusFeatureFlags(leaderboard: true, peakBadges: false),
      fetchedAtUtc: fetchedAtUtc,
    );
  }

  @override
  Future<PlusBillingResult> purchase(String planId) async {
    return const PlusBillingResult.unavailable('Pembayaran belum tersedia');
  }

  @override
  Future<PlusBillingResult> restore() async {
    return const PlusBillingResult.nothingToRestore(
      'Pembayaran belum tersedia',
    );
  }
}
