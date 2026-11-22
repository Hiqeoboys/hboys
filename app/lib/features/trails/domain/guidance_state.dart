import 'package:geo_utils/geo_utils.dart';

/// Alasan mengapa pemanduan tidak tersedia.
enum GuidanceUnavailableReason {
  /// Layanan lokasi pada sistem dimatikan.
  needsLocation,

  /// Izin lokasi belum diberikan.
  needsPermission,

  /// Belum ada rute utama yang dipilih.
  noRoute,

  /// Belum ada sinyal GPS atau fix terakhir basi (> 10 dtk).
  waitingGps,
}

/// Status panduan rute kembali ke jalur.
sealed class GuidanceState {
  const GuidanceState();
}

/// Pemanduan belum bisa bekerja karena salah satu prasyarat [reason] belum terpenuhi.
class GuidanceUnavailable extends GuidanceState {
  const GuidanceUnavailable(this.reason);
  final GuidanceUnavailableReason reason;

  @override
  String toString() => 'GuidanceUnavailable($reason)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuidanceUnavailable && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// Status sementara saat pengguna meminta petunjuk secara eksplisit dan sistem
/// sedang memeriksa posisi atau menunggu fix GPS dalam batas waktu singkat (maksimal 3 detik).
class GuidanceCheckingPosition extends GuidanceState {
  const GuidanceCheckingPosition();

  @override
  String toString() => 'GuidanceCheckingPosition()';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GuidanceCheckingPosition;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Pengguna berada di dalam batas toleransi jalur utama.
class GuidanceOnRoute extends GuidanceState {
  const GuidanceOnRoute(this.distanceToRouteM);

  /// Jarak tegak lurus pengguna ke jalur utama saat ini (dalam meter).
  final double distanceToRouteM;

  @override
  String toString() =>
      'GuidanceOnRoute(${distanceToRouteM.toStringAsFixed(1)} m)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuidanceOnRoute &&
          (other.distanceToRouteM - distanceToRouteM).abs() < 1e-3;

  @override
  int get hashCode => distanceToRouteM.hashCode;
}

/// Pengguna sedang dipandu mundur menyusuri jejak rekaman menuju jalur utama.
class GuidanceFollowingTrail extends GuidanceState {
  const GuidanceFollowingTrail({
    required this.bearingDeg,
    required this.distToNextM,
    required this.remainingTrailM,
    required this.offRouteM,
    required this.progress,
    required this.targetPoint,
    required this.guidePath,
  });

  /// Arah MUTLAK dari utara (0-360 derajat). UI yang mengurangi dengan arah hadap HP.
  final double bearingDeg;

  /// Jarak langsung dari posisi pengguna ke titik target berikutnya (meter).
  final double distToNextM;

  /// Total sisa panjang jejak panduan mundur sampai ke anchor di jalur utama (meter).
  final double remainingTrailM;

  /// Jarak lurus saat ini dari posisi pengguna ke jalur utama (meter).
  final double offRouteM;

  /// Progres kembali ke jalur (rentang 0.0 - 1.0).
  final double progress;

  /// Titik target aktif saat ini pada lintasan panduan.
  final LatLng targetPoint;

  /// Titik-titik lintasan pemanduan dari posisi pengguna mundur ke anchor.
  final List<LatLng> guidePath;

  @override
  String toString() =>
      'GuidanceFollowingTrail(bearing: ${bearingDeg.toStringAsFixed(1)}°, '
      'distToNext: ${distToNextM.toStringAsFixed(1)} m, '
      'remaining: ${remainingTrailM.toStringAsFixed(1)} m, '
      'offRoute: ${offRouteM.toStringAsFixed(1)} m, '
      'progress: ${(progress * 100).toStringAsFixed(0)}%)';
}

/// Pemanduan garis lurus ke titik jalur terdekat saat tidak ada jejak rekaman yang bisa diikuti.
class GuidanceStraightLine extends GuidanceState {
  const GuidanceStraightLine({
    required this.bearingDeg,
    required this.distToRouteM,
    required this.progress,
    required this.targetPoint,
    this.accuracyM,
  });

  /// Arah MUTLAK dari utara (0-360 derajat).
  final double bearingDeg;

  /// Jarak lurus ke titik target di jalur utama (meter).
  final double distToRouteM;

  /// Progres pemanduan garis lurus (0.0 - 1.0).
  final double progress;

  /// Titik terdekat pada jalur utama sebagai target garis lurus.
  final LatLng targetPoint;

  /// Akurasi GPS pada saat kalkulasi (meter), jika tersedia.
  final double? accuracyM;

  @override
  String toString() =>
      'GuidanceStraightLine(bearing: ${bearingDeg.toStringAsFixed(1)}°, '
      'distToRoute: ${distToRouteM.toStringAsFixed(1)} m, '
      'progress: ${(progress * 100).toStringAsFixed(0)}%, '
      'accuracy: ${accuracyM?.toStringAsFixed(1)} m)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuidanceStraightLine &&
          (other.bearingDeg - bearingDeg).abs() < 1e-3 &&
          (other.distToRouteM - distToRouteM).abs() < 1e-3 &&
          (other.progress - progress).abs() < 1e-3 &&
          (other.targetPoint.lat - targetPoint.lat).abs() < 1e-6 &&
          (other.targetPoint.lon - targetPoint.lon).abs() < 1e-6;

  @override
  int get hashCode => Object.hash(
        bearingDeg.round(),
        distToRouteM.round(),
        targetPoint.lat,
        targetPoint.lon,
      );
}

/// Pengguna telah terdeteksi berhasil kembali ke dalam batas toleransi jalur utama.
class GuidanceReturned extends GuidanceState {
  const GuidanceReturned();

  @override
  String toString() => 'GuidanceReturned()';

  @override
  bool operator ==(Object other) => other is GuidanceReturned;

  @override
  int get hashCode => 42;
}

