import 'dart:math' as math;

import 'track_point.dart';
import 'package:geo_utils/geo_utils.dart';

/// Membuat deret ketinggian untuk grafik profil dari titik-titik tersimpan.
///
/// 1. Hanya titik yang punya altitude.
/// 2. Ambil sampel tiap [distanceStepM] meter ATAU tiap [timeStep] (mana yang
///    tercapai lebih dulu), bukan tiap fix.
/// 3. Haluskan dengan rata-rata bergerak [smoothing] titik.
/// 4. Kurangi ke paling banyak [maxSamples] titik (ujung-ujung dipertahankan).
List<double> buildElevationProfile(
  List<TrackPoint> points, {
  double distanceStepM = 10,
  Duration timeStep = const Duration(seconds: 5),
  int smoothing = 5,
  int maxSamples = 120,
}) {
  final samples = <double>[];
  TrackPoint? lastKept;
  var distanceSinceKept = 0.0;
  TrackPoint? previous;
  for (final point in points) {
    final altitude = point.altitudeM;
    if (altitude == null) continue;
    if (previous != null) {
      distanceSinceKept += distanceMeters(previous.position, point.position);
    }
    previous = point;
    if (lastKept == null) {
      samples.add(altitude);
      lastKept = point;
      distanceSinceKept = 0;
      continue;
    }
    final elapsed = point.timestampUtc.difference(lastKept.timestampUtc);
    if (distanceSinceKept >= distanceStepM || elapsed >= timeStep) {
      samples.add(altitude);
      lastKept = point;
      distanceSinceKept = 0;
    }
  }
  final smoothed = movingAverage(samples, smoothing);
  return downsample(smoothed, maxSamples);
}

/// Rata-rata bergerak dengan jendela [window] (ganjil). Di tepi jendela
/// menyempit simetris sehingga titik ujung tidak ditarik keluar rentang.
List<double> movingAverage(List<double> values, int window) {
  if (values.length < 3 || window <= 1) return List<double>.of(values);
  final half = window ~/ 2;
  return <double>[
    for (var i = 0; i < values.length; i++)
      () {
        final reach = math.min(half, math.min(i, values.length - 1 - i));
        var sum = 0.0;
        for (var j = i - reach; j <= i + reach; j++) {
          sum += values[j];
        }
        return sum / (2 * reach + 1);
      }(),
  ];
}

/// Mengurangi [values] menjadi paling banyak [maxSamples] titik berjarak rata.
List<double> downsample(List<double> values, int maxSamples) {
  if (values.length <= maxSamples || maxSamples < 2) return values;
  return <double>[
    for (var i = 0; i < maxSamples; i++)
      values[(i * (values.length - 1) / (maxSamples - 1)).round()],
  ];
}

/// Kemiringan tangen interpolasi kubik monoton Fritsch-Carlson untuk titik
/// berjarak sama [h]. Menjamin kurva tidak melampaui nilai minimum/maksimum
/// kedua titik di tiap ruas (tanpa overshoot).
List<double> monotoneTangents(List<double> y, double h) {
  final n = y.length;
  if (n < 2) return List<double>.filled(n, 0);
  final d = <double>[for (var k = 0; k < n - 1; k++) (y[k + 1] - y[k]) / h];
  final m = List<double>.filled(n, 0);
  m[0] = d.first;
  m[n - 1] = d.last;
  for (var k = 1; k < n - 1; k++) {
    m[k] = d[k - 1] * d[k] <= 0 ? 0 : (d[k - 1] + d[k]) / 2;
  }
  for (var k = 0; k < n - 1; k++) {
    if (d[k] == 0) {
      m[k] = 0;
      m[k + 1] = 0;
      continue;
    }
    final alpha = m[k] / d[k];
    final beta = m[k + 1] / d[k];
    final s = alpha * alpha + beta * beta;
    if (s > 9) {
      final tau = 3 / math.sqrt(s);
      m[k] = tau * alpha * d[k];
      m[k + 1] = tau * beta * d[k];
    }
  }
  return m;
}

/// Nilai kurva kubik Hermite monoton pada posisi [x] (satuan indeks * [h]).
double evaluateMonotone(List<double> y, List<double> m, double h, double x) {
  final n = y.length;
  final clamped = x.clamp(0.0, (n - 1) * h).toDouble();
  var k = (clamped / h).floor();
  if (k >= n - 1) k = n - 2;
  final t = (clamped - k * h) / h;
  final t2 = t * t;
  final t3 = t2 * t;
  return (2 * t3 - 3 * t2 + 1) * y[k] +
      (t3 - 2 * t2 + t) * h * m[k] +
      (-2 * t3 + 3 * t2) * y[k + 1] +
      (t3 - t2) * h * m[k + 1];
}

