/// Menghitung total tanjakan/turunan dengan ambang histeresis supaya noise
/// altitude (GPS/barometer) tidak menggelembungkan angka.
class ElevationProcessor {
  ElevationProcessor({this.thresholdM = 4});

  final double thresholdM;
  double? _reference;
  double _gain = 0;
  double _loss = 0;

  double get gainMeters => _gain;
  double get lossMeters => _loss;

  void add(double altitudeM) {
    final ref = _reference;
    if (ref == null) {
      _reference = altitudeM;
      return;
    }
    final diff = altitudeM - ref;
    if (diff >= thresholdM) {
      _gain += diff;
      _reference = altitudeM;
    } else if (diff <= -thresholdM) {
      _loss += -diff;
      _reference = altitudeM;
    }
  }
}
