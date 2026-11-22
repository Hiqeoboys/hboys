import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/presentation/tracking_view_data.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

final t0 = DateTime.utc(2027, 6, 1, 8);

TrackPoint point(int second, double? altitude) => TrackPoint(
      lat: -6.9,
      lon: 107.6,
      timestampUtc: t0.add(Duration(seconds: second)),
      accuracyM: 5,
      altitudeM: altitude,
    );

void main() {
  test('timer memakai jam:menit:detik dua digit', () {
    expect(formatTimer(0), '00:00:00');
    expect(formatTimer(9710), '02:41:50');
    expect(formatTimer(-4), '00:00:00');
  });

  test('angka memakai koma desimal dan titik ribuan', () {
    expect(formatDistanceValue(6420), '6,4');
    expect(formatDistanceValue(0), '0,0');
    expect(formatDistanceValue(12500), '12,5');
    expect(formatElevationValue(842.4), '842');
    expect(formatElevationValue(8420), '8.420');
  });

  test('pace dan kecepatan vertikal kosong ditulis em dash', () {
    expect(formatPaceValue(null), '—');
    expect(formatPaceValue(0), '—');
    expect(formatPaceValue(1450), '24:10');
    expect(formatVerticalSpeedValue(null), '—');
    expect(formatVerticalSpeedValue(312.2), '312');
    expect(formatVerticalSpeedValue(1234), '1.234');
    expect(formatVerticalSpeedValue(-120.4), '-120');
  });

  test('langkah dan kalori tanpa sumber tidak dikarang', () {
    expect(formatStepCount(null), '—');
    expect(formatStepCount(11230), '11.230');
    expect(formatStepCount(1204, estimated: true), '~1.204');
    expect(formatCaloriesValue(null), '—');
    expect(formatCaloriesValue(980.4), '980');
  });

  test('deteksi fix kedaluwarsa (> 10 detik)', () {
    expect(isFixStale(null, t0), isFalse);
    expect(isFixStale(t0, t0.add(const Duration(seconds: 10))), isFalse);
    expect(isFixStale(t0, t0.add(const Duration(seconds: 11))), isTrue);
  });

  test('label profil daya sesuai mode', () {
    expect(profileLabel(PowerProfile.normal), 'Normal');
    expect(profileLabel(PowerProfile.saver), 'Hemat');
    expect(profileLabel(PowerProfile.critical), 'Kritis');
  });

  test('deret ketinggian melewati titik tanpa altitud', () {
    expect(
      elevationSeries(<TrackPoint>[
        point(0, 1000),
        point(5, null),
        point(10, 1006),
      ]),
      <double>[1000, 1006],
    );
    expect(elevationSeries(<TrackPoint>[point(0, null)]), isEmpty);
  });

  test('deret ketinggian dipangkas tetap memuat ujung-ujungnya', () {
    final points = <TrackPoint>[
      for (var i = 0; i <= 200; i++) point(i * 5, 1000 + i.toDouble()),
    ];
    final series = elevationSeries(points, maxSamples: 64);
    expect(series, hasLength(64));
    expect(series.first, 1000);
    expect(series.last, 1200);
    expect(series[32], closeTo(1100, 8));
  });
}
