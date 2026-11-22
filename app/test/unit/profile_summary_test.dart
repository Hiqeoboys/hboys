import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/profile/domain/profile_summary.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';

TrackingSession _session({
  required String id,
  double distanceM = 0,
  double elevationGainM = 0,
  TrackingSessionStatus status = TrackingSessionStatus.completed,
}) {
  return TrackingSession(
    id: id,
    startedAtUtc: DateTime.utc(2026, 1, 1),
    distanceM: distanceM,
    elevationGainM: elevationGainM,
    status: status,
  );
}

void main() {
  group('ProfileSummary.fromSessions', () {
    test('hanya menghitung sesi selesai', () {
      final summary = ProfileSummary.fromSessions(<TrackingSession>[
        _session(id: 'a', distanceM: 12000, elevationGainM: 800),
        _session(id: 'b', distanceM: 5000, elevationGainM: 200),
        _session(
          id: 'c',
          distanceM: 90000,
          elevationGainM: 5000,
          status: TrackingSessionStatus.active,
        ),
      ]);

      expect(summary.hikeCount, 2);
      expect(summary.distanceM, 17000);
      expect(summary.elevationGainM, 1000);
    });

    test('tanpa sesi berarti nol, bukan angka contoh', () {
      final summary = ProfileSummary.fromSessions(const <TrackingSession>[]);

      expect(summary.hikeCountLabel, '0');
      expect(summary.distanceLabel, '0 km');
      expect(summary.elevationGainLabel, '0 m');
    });

    test('label jarak memakai koma di bawah 10 km dan pembulatan di atasnya',
        () {
      expect(formatProfileDistance(500), '0,5 km');
      expect(formatProfileDistance(9500), '9,5 km');
      expect(formatProfileDistance(31400), '31 km');
      expect(formatProfileDistance(148400), '148 km');
      expect(formatProfileDistance(14876000), '14.876 km');
      expect(formatProfileDistance(0), '0 km');
    });

    test('jarak negatif atau tidak terhingga tidak ditampilkan sebagai minus',
        () {
      expect(formatProfileDistance(-1200), '0 km');
      expect(formatProfileDistance(double.nan), '0 km');
      expect(formatProfileDistance(double.infinity), '0 km');
    });

    test('tanjakan memakai titik ribuan dan tanda minus tipografis', () {
      expect(
        const ProfileSummary(
          hikeCount: 1,
          distanceM: 1000,
          elevationGainM: 1234.4,
        ).elevationGainLabel,
        '1.234 m',
      );
      expect(
        const ProfileSummary(
          hikeCount: 1,
          distanceM: 1000,
          elevationGainM: 1234.6,
        ).elevationGainLabel,
        '1.235 m',
      );
      expect(
        const ProfileSummary(
          hikeCount: 1,
          distanceM: 1000,
          elevationGainM: -1234,
        ).elevationGainLabel,
        '−1.234 m',
      );
    });
  });
}
