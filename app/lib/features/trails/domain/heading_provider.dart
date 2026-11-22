import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../../compass/domain/compass_calibration.dart';
import '../../tracking/domain/track_point.dart';

/// Sumber data arah hadap perangkat.
enum HeadingSource {
  /// Diambil dari lintasan GPS (course) saat bergerak (> ambang kecepatan).
  gpsCourse,

  /// Diambil dari sensor magnetometer kompas saat diam atau berkecepatan rendah.
  compass,
}

/// Bacaan arah hadap perangkat saat ini.
class HeadingReading {
  const HeadingReading({
    required this.headingDeg,
    required this.source,
    this.accuracyDeg,
    this.needsCalibration = false,
  });

  /// Arah hadap dalam derajat (0 - 360 derajat searah jarum jam dari utara).
  final double headingDeg;

  /// Dari mana bacaan arah hadap berasal.
  final HeadingSource source;

  /// Akurasi bacaan sensor kompas (derajat), jika tersedia.
  final double? accuracyDeg;

  /// Apakah kompas terdeteksi belum terkalibrasi dengan baik (akurasi > 30° atau tidak diketahui).
  final bool needsCalibration;

  @override
  String toString() =>
      'HeadingReading(${headingDeg.toStringAsFixed(1)}°, source: $source, '
      'needsCalibration: $needsCalibration)';
}

/// Penyedia arah hadap gabungan: memilih course GPS saat bergerak
/// (> [headingSpeedThresholdMps]) dan sensor kompas dengan low-pass filter saat diam.
class HeadingProvider {
  HeadingProvider({
    Stream<CompassEvent>? compassStream,
    this.headingSpeedThresholdMps = 1.0,
    this.lowPassAlpha = 0.25,
  }) {
    final stream = compassStream ?? _defaultCompassStream();
    if (stream != null) {
      _compassSubscription = stream.listen(_onCompassEvent);
    }
  }

  static Stream<CompassEvent>? _defaultCompassStream() {
    if (kIsWeb) return null;
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        return FlutterCompass.events;
      }
    } catch (_) {}
    return null;
  }

  final double headingSpeedThresholdMps;
  final double lowPassAlpha;

  final StreamController<HeadingReading> _controller =
      StreamController<HeadingReading>.broadcast();
  StreamSubscription<CompassEvent>? _compassSubscription;

  HeadingReading? _currentReading;
  TrackPoint? _lastFix;
  double? _filteredCompassHeading;
  double? _lastCompassAccuracy;
  bool _lastNeedsCalibration = false;

  Stream<HeadingReading> get readings => _controller.stream;
  HeadingReading? get currentReading => _currentReading;

  /// Memperbarui arah hadap berdasarkan fix GPS terbaru.
  void updateGpsFix(TrackPoint fix) {
    _lastFix = fix;
    final speed = fix.speedMps;
    final heading = fix.heading;

    // Jika kecepatan melebihi ambang dan heading GPS valid, gunakan GPS course
    if (speed != null &&
        speed > headingSpeedThresholdMps &&
        heading != null &&
        heading.isFinite) {
      final reading = HeadingReading(
        headingDeg: normalizeHeading(heading),
        source: HeadingSource.gpsCourse,
        accuracyDeg: fix.accuracyM,
        needsCalibration: false,
      );
      _publish(reading);
      return;
    }

    // Jika diam atau lambat, gunakan kompas
    _emitCompassReading();
  }

  /// Memperbarui arah hadap kompas secara manual (mis. untuk pengujian / injeksi).
  void updateCompassRaw(double rawHeadingDeg, {double? accuracyDeg}) {
    _applyCompassReading(rawHeadingDeg, accuracyDeg);
  }

  void _onCompassEvent(CompassEvent event) {
    final heading = event.heading;
    if (heading == null || !heading.isFinite) return;
    _applyCompassReading(heading, event.accuracy);
  }

  void _applyCompassReading(double rawHeading, double? accuracy) {
    _lastCompassAccuracy = accuracy;
    // Ambang kalibrasi: jika akurasi negatif, null, atau > 30 derajat, tandai butuh kalibrasi
    _lastNeedsCalibration =
        accuracy == null || accuracy < 0 || accuracy > 30.0;

    final normRaw = normalizeHeading(rawHeading);
    if (_filteredCompassHeading == null) {
      _filteredCompassHeading = normRaw;
    } else {
      // Circular low-pass filter untuk menangani batas 0/360° secara mulus
      final diff = ((normRaw - _filteredCompassHeading! + 540) % 360) - 180;
      _filteredCompassHeading =
          normalizeHeading(_filteredCompassHeading! + lowPassAlpha * diff);
    }

    // Jika sedang tidak bergerak cepat dengan GPS, publikasikan bacaan kompas
    final fix = _lastFix;
    final speed = fix?.speedMps;
    if (speed == null || speed <= headingSpeedThresholdMps) {
      _emitCompassReading();
    }
  }

  void _emitCompassReading() {
    if (_filteredCompassHeading == null) return;
    final reading = HeadingReading(
      headingDeg: _filteredCompassHeading!,
      source: HeadingSource.compass,
      accuracyDeg: _lastCompassAccuracy,
      needsCalibration: _lastNeedsCalibration,
    );
    _publish(reading);
  }

  void _publish(HeadingReading reading) {
    _currentReading = reading;
    if (!_controller.isClosed) {
      _controller.add(reading);
    }
  }

  void dispose() {
    _compassSubscription?.cancel();
    _compassSubscription = null;
    _controller.close();
  }
}
