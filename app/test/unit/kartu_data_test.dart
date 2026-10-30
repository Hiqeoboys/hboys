import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/kartu/domain/kartu_data.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';

final t0 = DateTime.utc(2026, 10, 30, 1);

TrackingSession _session({
  TrackingSessionStatus status = TrackingSessionStatus.completed,
  double distanceM = 12840,
  int movingSeconds = 25920,
  double elevationGainM = 1140,
  DateTime? startedAtUtc,
}) =>
    TrackingSession(
      id: 'sesi-1',
      startedAtUtc: startedAtUtc ?? t0,
      endedAtUtc: t0.add(const Duration(hours: 8)),
      distanceM: distanceM,
      movingSeconds: movingSeconds,
      elevationGainM: elevationGainM,
      status: status,
    );

TrackPoint _point(
  int minute,
  double lat,
  double lon, {
  double? altitudeM,
}) =>
    TrackPoint(
      lat: lat,
      lon: lon,
      timestampUtc: t0.add(Duration(minutes: minute)),
      accuracyM: 8,
      altitudeM: altitudeM,
    );

void main() {
  group('KartuData.fromSession', () {
    test('menolak sesi yang belum selesai', () {
      final data = KartuData.fromSession(
        _session(status: TrackingSessionStatus.active),
        <TrackPoint>[_point(0, -6.8, 106.8)],
      );
      expect(data, isNull);
    });

    test('memakai angka sesi apa adanya dan memformat label Indonesia', () {
      final startedAtUtc = DateTime(2026, 10, 30, 7, 12).toUtc();
      final data = KartuData.fromSession(
        _session(startedAtUtc: startedAtUtc),
        <TrackPoint>[
          _point(0, -6.800, 106.800, altitudeM: 1500),
          _point(30, -6.799, 106.800, altitudeM: 1600),
          _point(60, -6.798, 106.800, altitudeM: 1570),
        ],
      );

      expect(data, isNotNull);
      expect(data!.distanceLabel, '12,8 km');
      expect(data.rightAxisLabel, '12,8 km');
      expect(data.gainLabel, '+1.140 m');
      expect(data.timeLabel, '07:12');
      expect(data.dateLabel, '30 OKT 2026');
    });

    test('memformat tanjakan nol dan negatif tanpa tanda palsu', () {
      final zero = KartuData.fromSession(
        _session(elevationGainM: 0),
        <TrackPoint>[_point(0, -6.8, 106.8)],
      );
      final negative = KartuData.fromSession(
        _session(elevationGainM: -420),
        <TrackPoint>[_point(0, -6.8, 106.8)],
      );
      expect(zero!.gainLabel, '0 m');
      expect(negative!.gainLabel, '−420 m');
    });

    test('profil elevasi memakai jarak tempuh dan puncak sebenarnya', () {
      final data = KartuData.fromSession(
        _session(),
        <TrackPoint>[
          _point(0, -6.800, 106.800, altitudeM: 1500),
          _point(30, -6.799, 106.800, altitudeM: 1800),
          _point(60, -6.798, 106.800, altitudeM: 1600),
        ],
      );

      final profile = data!.profile;
      expect(profile, isNotNull);
      expect(profile, hasLength(3));
      expect(profile!.first.fraction, closeTo(0, 0.001));
      expect(profile[1].fraction, closeTo(0.5, 0.02));
      expect(profile.last.fraction, closeTo(1, 0.001));
      expect(data.peakFraction, closeTo(0.5, 0.02));
    });

    test('tanpa dua titik ber-altitude, profil dan puncak dibiarkan kosong',
        () {
      final data = KartuData.fromSession(
        _session(),
        <TrackPoint>[
          _point(0, -6.800, 106.800, altitudeM: 1500),
          _point(30, -6.799, 106.800),
          _point(60, -6.798, 106.800),
        ],
      );
      expect(data!.profile, isNull);
      expect(data.peakFraction, isNull);
    });

    test('rute ternormalisasi di dalam kotak dan menjaga bentuk', () {
      final data = KartuData.fromSession(
        _session(),
        <TrackPoint>[
          _point(0, 0, 0),
          _point(10, 0, 0.001),
          _point(20, 0.002, 0.001),
        ],
      );

      final route = data!.route;
      expect(route, isNotNull);
      expect(route, hasLength(3));
      for (final point in route!) {
        expect(point.dx, inInclusiveRange(0, 1));
        expect(point.dy, inInclusiveRange(0, 1));
      }
      final spanX = route[1].dx - route.first.dx;
      final spanY = route.last.dy - route.first.dy;
      expect(spanX, closeTo(0.5, 0.001));
      expect(spanY, closeTo(-1, 0.001));
      expect((spanX / spanY).abs(), closeTo(0.5, 0.001));
    });

    test('satu titik tidak menghasilkan rute', () {
      final data = KartuData.fromSession(
        _session(),
        <TrackPoint>[_point(0, -6.8, 106.8, altitudeM: 1500)],
      );
      expect(data!.route, isNull);
      expect(data.profile, isNull);
    });

    test('profil memakai posisi indeks bila semua titik menumpuk', () {
      final data = KartuData.fromSession(
        _session(),
        <TrackPoint>[
          _point(0, -6.8, 106.8, altitudeM: 1500),
          _point(10, -6.8, 106.8, altitudeM: 1700),
        ],
      );
      expect(data!.route, isEmpty);
      expect(data.profile, isNotNull);
      expect(data.profile![1].fraction, 1);
    });
  });

  group('KartuProfilePoint', () {
    test('menyimpan fraction dan altitude tanpa perubahan', () {
      const point = KartuProfilePoint(0.42, 2130);
      expect(point.fraction, 0.42);
      expect(point.altitudeM, 2130);
    });
  });

  test('route berupa Offset sehingga bisa digambar langsung', () {
    final data = KartuData.fromSession(
      _session(),
      <TrackPoint>[
        _point(0, -6.8, 106.8),
        _point(10, -6.79, 106.81),
      ],
    );
    expect(data!.route, isA<List<Offset>>());
  });
}
