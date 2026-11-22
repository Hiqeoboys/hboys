/// Menghitung total tanjakan/turunan dengan Hysteresis Anchor berstandar Strava:
/// * `3,0 m` untuk perangkat dengan sensor barometer terkalibrasi;
/// * `8,0 m` untuk perangkat GPS murni (tanpa barometer);
/// serta syarat perpindahan horizontal nyata (`minHorizontalStepM >= 4,0 m`)
/// agar mengangkat/menggoyang HP saat diam selalu menghasilkan `0 m`.
class ElevationProcessor {
  ElevationProcessor({
    double? thresholdM,
    this.minHorizontalStepM = 4.0,
    this.useBarometer = false,
  }) : thresholdM =
            thresholdM ?? (useBarometer ? barometerThresholdM : gpsThresholdM);

  static const double barometerThresholdM = 3.0;
  static const double gpsThresholdM = 8.0;

  final double thresholdM;
  final double minHorizontalStepM;
  final bool useBarometer;

  double? _reference;
  double? _refDistanceM;
  double _gain = 0;
  double _loss = 0;

  double get gainMeters => _gain;
  double get lossMeters => _loss;

  void add(double altitudeM, {double? cumulativeDistanceM}) {
    final ref = _reference;
    if (ref == null) {
      _reference = altitudeM;
      _refDistanceM = cumulativeDistanceM;
      return;
    }
    if (cumulativeDistanceM != null && _refDistanceM != null) {
      final horizontalDelta = cumulativeDistanceM - _refDistanceM!;
      if (horizontalDelta < minHorizontalStepM) {
        return;
      }
    }
    final diff = altitudeM - ref;
    if (diff >= thresholdM) {
      _gain += diff;
      _reference = altitudeM;
      if (cumulativeDistanceM != null) _refDistanceM = cumulativeDistanceM;
    } else if (diff <= -thresholdM) {
      _loss += -diff;
      _reference = altitudeM;
      if (cumulativeDistanceM != null) _refDistanceM = cumulativeDistanceM;
    }
  }
}
