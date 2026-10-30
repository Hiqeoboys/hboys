import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/compass/domain/compass_calibration.dart';

void main() {
  group('normalisasi heading', () {
    test('nilai negatif dibungkus ke 0..360', () {
      expect(normalizeHeading(-10), 350);
      expect(normalizeHeading(-370), 350);
    });

    test('nilai lebih dari 360 dibungkus', () {
      expect(normalizeHeading(360), 0);
      expect(normalizeHeading(725), 5);
    });

    test('offset diterapkan lalu dinormalisasi', () {
      expect(applyHeadingOffset(350, 20), 10);
      expect(applyHeadingOffset(10, -20), 350);
    });
  });

  test('offset acuan adalah selisih acuan terhadap heading mentah', () {
    expect(
      offsetForReference(rawHeadingDegrees: 350, referenceHeadingDegrees: 10),
      20,
    );
    expect(
      offsetForReference(rawHeadingDegrees: 100, referenceHeadingDegrees: 90),
      350,
    );
    expect(
      offsetForReference(rawHeadingDegrees: 45, referenceHeadingDegrees: 45),
      0,
    );
  });

  group('kualitas akurasi kompas', () {
    test('ambang mengikuti nilai derajat yang dilaporkan', () {
      expect(compassAccuracyQuality(-1), CompassAccuracyQuality.unknown);
      expect(compassAccuracyQuality(0), CompassAccuracyQuality.high);
      expect(compassAccuracyQuality(15), CompassAccuracyQuality.high);
      expect(compassAccuracyQuality(16), CompassAccuracyQuality.medium);
      expect(compassAccuracyQuality(30), CompassAccuracyQuality.medium);
      expect(compassAccuracyQuality(31), CompassAccuracyQuality.low);
    });
  });
}
