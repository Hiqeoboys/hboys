import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Ketinggian relatif dari barometer (bila perangkat punya sensornya).
///
/// Tekanan diubah ke ketinggian dengan atmosfer standar, lalu digeser (offset)
/// satu kali memakai altitude GPS pertama yang cukup akurat. Hanya selisih
/// ketinggian yang dipakai aplikasi, jadi kesalahan offset tidak berpengaruh
/// pada tanjakan. Bila sensor tidak ada atau tidak mengirim data, [altitudeFor]
/// mengembalikan `null` dan pemanggil memakai altitude GPS.
class BarometerAltitude {
  StreamSubscription<BarometerEvent>? _subscription;
  final List<double> _pressureWindow = <double>[];
  double? _pressureHpa;
  double? _offset;

  /// Galat vertikal yang dilaporkan untuk sampel barometer (meter).
  static const double reportedAccuracyM = 1.5;

  bool get hasReading => _pressureHpa != null;

  void start() {
    try {
      _subscription = barometerEventStream(
        samplingPeriod: const Duration(seconds: 1),
      ).listen(
        (event) {
          if (!event.pressure.isFinite || event.pressure <= 0) return;
          _pressureWindow.add(event.pressure);
          if (_pressureWindow.length > 3) _pressureWindow.removeAt(0);
          var sum = 0.0;
          for (final p in _pressureWindow) {
            sum += p;
          }
          _pressureHpa = sum / _pressureWindow.length;
        },
        onError: (Object _) => _pressureHpa = null,
        cancelOnError: false,
      );
    } catch (_) {
      _pressureHpa = null;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Ketinggian dari barometer untuk fix [position], atau `null`.
  double? altitudeFor(Position position) {
    final pressure = _pressureHpa;
    if (pressure == null || pressure <= 0) return null;
    final barometric = 44330.0 * (1.0 - math.pow(pressure / 1013.25, 0.1903));
    final offset = _offset;
    if (offset == null) {
      final horizontalOk =
          position.accuracy.isFinite && position.accuracy <= 30.0;
      final gpsOk = position.hasAltitude &&
          horizontalOk &&
          (!position.hasAltitudeAccuracy || position.altitudeAccuracy <= 25.0);
      if (!gpsOk) return null;
      _offset = position.altitude - barometric;
      return position.altitude;
    }
    return barometric + offset;
  }
}

