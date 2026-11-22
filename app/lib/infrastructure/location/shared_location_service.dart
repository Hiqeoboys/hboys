import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/utils/clock.dart';
import '../../features/tracking/application/tracking_controller.dart';
import '../../features/tracking/application/tracking_runtime.dart'
    show TrackingAccess;
import '../../features/tracking/domain/track_point.dart';
import '../power/power_profile_manager.dart';
import 'geolocator_tracking_source.dart';

/// Status layanan lokasi bersama untuk layar yang butuh posisi pengguna saat
/// tidak merekam (mis. Peta).
enum LiveLocationStatus {
  /// Belum ada yang berlangganan atau belum diperiksa.
  idle,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,

  /// Izin dan layanan siap, belum ada fix yang bisa dipakai.
  searching,

  /// Fix terbaru tersedia.
  active,
  error,
}

/// Dari mana titik terakhir berasal.
enum LiveLocationSource { none, ownStream, recordingSession }

@immutable
class LiveLocationState {
  const LiveLocationState({
    this.status = LiveLocationStatus.idle,
    this.point,
    this.source = LiveLocationSource.none,
    this.errorMessage,
  });

  final LiveLocationStatus status;
  final TrackPoint? point;
  final LiveLocationSource source;
  final String? errorMessage;

  LiveLocationState copyWith({
    LiveLocationStatus? status,
    TrackPoint? point,
    bool clearPoint = false,
    LiveLocationSource? source,
    String? errorMessage,
    bool clearError = false,
  }) =>
      LiveLocationState(
        status: status ?? this.status,
        point: clearPoint ? null : (point ?? this.point),
        source: source ?? this.source,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// Pintu ke platform lokasi untuk pemakaian latar depan.
abstract interface class ForegroundLocationBackend {
  Future<TrackingAccess> checkAccess();

  /// Memunculkan dialog izin sistem (hanya izin "saat dipakai" yang perlu).
  Future<TrackingAccess> requestAccess();

  Stream<TrackPoint> positions();
  Future<bool> openLocationSettings();
  Future<bool> openAppSettings();
}

/// Sumber titik dari sesi rekaman yang sedang berjalan. Selama merekam,
/// layanan bersama TIDAK membuka aliran GPS sendiri; ia hanya membaca titik
/// terakhir yang ditulis rekaman supaya tidak ada dua aliran yang berebut.
abstract interface class RecordingLocationFeed {
  bool get isRecording;
  Listenable get changes;
  Future<TrackPoint?> latestPoint();
}

class TrackingControllerRecordingFeed implements RecordingLocationFeed {
  const TrackingControllerRecordingFeed();

  @override
  bool get isRecording => TrackingController.instance.isRecording;

  @override
  Listenable get changes => TrackingController.instance;

  @override
  Future<TrackPoint?> latestPoint() =>
      TrackingController.instance.latestRecordedPoint();
}

class GeolocatorForegroundBackend implements ForegroundLocationBackend {
  const GeolocatorForegroundBackend();

  @override
  Future<TrackingAccess> checkAccess() =>
      const GeolocatorTrackingSource().checkAccess();

  @override
  Future<TrackingAccess> requestAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return TrackingAccess.serviceDisabled;
    }
    final permission = await Geolocator.requestPermission();
    return _fromPermission(permission);
  }

  static TrackingAccess _fromPermission(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always => TrackingAccess.granted,
        LocationPermission.whileInUse => TrackingAccess.whileInUse,
        LocationPermission.denied => TrackingAccess.denied,
        LocationPermission.deniedForever => TrackingAccess.deniedForever,
        LocationPermission.unableToDetermine =>
          TrackingAccess.unableToDetermine,
      };

  @override
  Stream<TrackPoint> positions() {
    // Latar depan dengan Activity: penyedia gabungan boleh dipakai (jatuh ke
    // LocationManager otomatis bila Google Play Services tidak ada). Interval
    // 2 detik dan filter jarak kecil cukup untuk "posisi saya" di peta tanpa
    // menguras baterai seperti rekaman.
    final LocationSettings settings = defaultTargetPlatform ==
            TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2,
            intervalDuration: const Duration(seconds: 2),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2,
            activityType: ActivityType.fitness,
            pauseLocationUpdatesAutomatically: true,
          );
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (position) => TrackPoint(
        lat: position.latitude,
        lon: position.longitude,
        timestampUtc: position.timestamp.toUtc(),
        accuracyM: position.accuracy,
        altitudeM: position.hasAltitude ? position.altitude : null,
        speedMps:
            position.hasSpeed && position.speed >= 0 ? position.speed : null,
        heading: position.heading.isFinite &&
                position.heading >= 0 &&
                position.heading <= 360
            ? position.heading
            : null,
        isMocked: position.isMocked,
        receivedAtUtc: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }
}

/// Bukti langganan. Panggil [release] saat layar tidak lagi membutuhkan
/// lokasi; aman dipanggil berulang.
class LocationLease {
  LocationLease._(this._service);

  final SharedLocationService _service;
  bool _released = false;

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _service._releaseLease();
  }
}

/// Layanan lokasi latar depan yang dipakai bersama dengan hitung referensi.
///
/// - Aliran GPS sendiri hanya hidup selama ada minimal satu [LocationLease]
///   dan TIDAK sedang merekam.
/// - Selama merekam, titik dibaca dari sesi rekaman (satu-satunya aliran GPS
///   aktif milik layanan latar tracking), lalu diteruskan ke pelanggan.
/// - Ketika lease terakhir dilepas, semua aliran dihentikan.
class SharedLocationService extends ChangeNotifier {
  SharedLocationService({
    ForegroundLocationBackend backend = const GeolocatorForegroundBackend(),
    RecordingLocationFeed? recordingFeed,
    Clock clock = const SystemClock(),
    this.maxFixAge = const Duration(minutes: 2),
  })  : _backend = backend,
        _feed = recordingFeed,
        _clock = clock;

  /// Instansi aplikasi. Uji memakai konstruktor sendiri.
  static final SharedLocationService instance = SharedLocationService(
    recordingFeed: const TrackingControllerRecordingFeed(),
  );

  final ForegroundLocationBackend _backend;
  final RecordingLocationFeed? _feed;
  final Clock _clock;

  /// Fix lebih tua dari ini tidak dianggap posisi saat ini.
  final Duration maxFixAge;

  LiveLocationState _state = const LiveLocationState();
  int _leases = 0;
  bool _accessOk = false;
  StreamSubscription<TrackPoint>? _ownSub;
  bool _ownStreamIsSimulated = false;
  bool _feedAttached = false;
  bool _feedListening = false;
  bool _pullingRecorded = false;
  bool _disposed = false;
  int _generation = 0;

  LiveLocationState get state => _state;
  Clock get clock => _clock;
  int get leaseCount => _leases;

  /// Benar bila aliran GPS milik layanan ini sedang terbuka.
  bool get hasOwnStream => _ownSub != null;

  /// Benar bila layanan sedang membaca titik dari sesi rekaman.
  bool get followsRecording => _feedAttached;

  /// Titik terakhir bila masih segar.
  TrackPoint? get freshPoint {
    final point = _state.point;
    if (point == null) return null;
    final age = _clock.nowUtc().difference(point.timestampUtc);
    return age > maxFixAge ? null : point;
  }

  LocationLease acquire() {
    _leases++;
    _attachFeed();
    if (_leases == 1) unawaited(refresh());
    return LocationLease._(this);
  }

  void _releaseLease() {
    if (_leases == 0) return;
    _leases--;
    if (_leases == 0) {
      _generation++;
      _detachFeed();
      unawaited(_stopAll());
      _setState(_state.copyWith(
        status: LiveLocationStatus.idle,
        source: LiveLocationSource.none,
        clearError: true,
      ));
    }
  }

  /// Memeriksa ulang layanan lokasi dan izin, lalu menyelaraskan sumber titik.
  /// Dipanggil saat berlangganan, saat aplikasi kembali aktif, dan saat
  /// tombol ditekan.
  Future<void> refresh() async {
    if (_disposed || _leases == 0) return;
    final generation = _generation;
    final TrackingAccess access;
    try {
      if (kDebugMode && TrackingController.instance.simulationEnabled) {
        access = TrackingAccess.granted;
      } else {
        access = await _backend.checkAccess();
      }
    } catch (error) {
      if (generation != _generation) return;
      _setError('Gagal memeriksa izin lokasi: $error');
      return;
    }
    if (_disposed || generation != _generation || _leases == 0) return;
    await _applyAccess(access);
  }

  /// Meminta izin lewat dialog sistem lalu menyelaraskan sumber titik.
  Future<void> requestPermission() async {
    if (_disposed) return;
    final TrackingAccess access;
    try {
      access = await _backend.requestAccess();
    } catch (error) {
      _setError('Gagal meminta izin lokasi: $error');
      return;
    }
    await _applyAccess(access);
  }

  Future<bool> openLocationSettings() => _backend.openLocationSettings();
  Future<bool> openAppSettings() => _backend.openAppSettings();

  Future<void> _applyAccess(TrackingAccess access) async {
    switch (access) {
      case TrackingAccess.serviceDisabled:
        _accessOk = false;
        await _stopAll();
        _setState(_state.copyWith(
          status: LiveLocationStatus.serviceDisabled,
          source: LiveLocationSource.none,
          clearError: true,
        ));
      case TrackingAccess.denied:
      case TrackingAccess.unableToDetermine:
        _accessOk = false;
        await _stopAll();
        _setState(_state.copyWith(
          status: LiveLocationStatus.permissionDenied,
          source: LiveLocationSource.none,
          clearError: true,
        ));
      case TrackingAccess.deniedForever:
        _accessOk = false;
        await _stopAll();
        _setState(_state.copyWith(
          status: LiveLocationStatus.permissionDeniedForever,
          source: LiveLocationSource.none,
          clearError: true,
        ));
      case TrackingAccess.granted:
      case TrackingAccess.whileInUse:
        _accessOk = true;
        if (_state.status != LiveLocationStatus.active) {
          _setState(_state.copyWith(
            status: freshPoint == null
                ? LiveLocationStatus.searching
                : LiveLocationStatus.active,
            clearError: true,
          ));
        }
        await _syncSource();
    }
  }

  /// Memilih tepat satu sumber: sesi rekaman bila sedang merekam, bila tidak
  /// aliran GPS sendiri (atau lokasi simulasi saat debug).
  Future<void> _syncSource() async {
    if (_disposed || _leases == 0) {
      await _stopAll();
      return;
    }
    final isSim = kDebugMode && TrackingController.instance.simulationEnabled;
    if (isSim) {
      _accessOk = true;
    } else if (!_accessOk) {
      await _stopAll();
      return;
    }

    final feed = _feed;
    if (feed != null && feed.isRecording) {
      await _stopOwnStream();
      _feedAttached = true;
      await _pullRecorded();
      return;
    }
    _feedAttached = false;

    if (_ownSub != null && _ownStreamIsSimulated != isSim) {
      await _stopOwnStream();
    }
    _startOwnStream(isSimulated: isSim);
  }

  void _startOwnStream({bool isSimulated = false}) {
    if (_ownSub != null) return;
    final generation = _generation;
    _ownStreamIsSimulated = isSimulated;
    final Stream<TrackPoint> stream;
    if (isSimulated) {
      final simSource = TrackingController.instance.simulatedLocationSource;
      if (simSource != null) {
        stream = simSource.positions(PowerProfileConfig.normal);
      } else {
        stream = _backend.positions();
      }
    } else {
      stream = _backend.positions();
    }

    _ownSub = stream.listen(
      (point) {
        if (generation != _generation || _leases == 0) return;
        _publish(point, LiveLocationSource.ownStream);
      },
      onError: (Object error) {
        if (generation != _generation) return;
        // Aliran gagal (mis. layanan dimatikan di tengah jalan): hentikan lalu
        // periksa ulang agar status akhir akurat.
        unawaited(_stopOwnStream());
        unawaited(_recoverFromStreamError(error));
      },
      cancelOnError: true,
    );
  }

  Future<void> _recoverFromStreamError(Object error) async {
    if (_disposed || _leases == 0) return;
    try {
      final access = await _backend.checkAccess();
      if (access == TrackingAccess.granted ||
          access == TrackingAccess.whileInUse) {
        _setError('Aliran lokasi berhenti: $error');
      } else {
        await _applyAccess(access);
      }
    } catch (_) {
      _setError('Aliran lokasi berhenti: $error');
    }
  }

  void _onFeedChanged() {
    final feed = _feed;
    if (feed == null || _disposed || _leases == 0) return;
    unawaited(_syncSource());
  }

  Future<void> _pullRecorded() async {
    final feed = _feed;
    if (feed == null || _pullingRecorded) return;
    _pullingRecorded = true;
    final generation = _generation;
    try {
      final point = await feed.latestPoint();
      if (_disposed || generation != _generation || _leases == 0) return;
      if (point != null) {
        _publish(point, LiveLocationSource.recordingSession);
      } else if (_state.status != LiveLocationStatus.active) {
        _setState(_state.copyWith(
          status: LiveLocationStatus.searching,
          source: LiveLocationSource.recordingSession,
        ));
      }
    } catch (_) {
      // Pembacaan gagal sekali tidak boleh menjatuhkan layanan; percobaan
      // berikutnya terjadi pada perubahan rekaman berikutnya.
    } finally {
      _pullingRecorded = false;
    }
  }

  void _publish(TrackPoint point, LiveLocationSource source) {
    final current = _state.point;
    // Jangan mundur ke titik yang lebih lama.
    if (current != null && point.timestampUtc.isBefore(current.timestampUtc)) {
      return;
    }
    _setState(LiveLocationState(
      status: LiveLocationStatus.active,
      point: point,
      source: source,
    ));
  }

  void _setError(String message) {
    _setState(_state.copyWith(
      status: LiveLocationStatus.error,
      errorMessage: message,
    ));
  }

  void _setState(LiveLocationState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  void _attachFeed() {
    final feed = _feed;
    if (_feedListening || feed == null) return;
    feed.changes.addListener(_onFeedChanged);
    _feedListening = true;
  }

  void _detachFeed() {
    final feed = _feed;
    if (!_feedListening || feed == null) return;
    feed.changes.removeListener(_onFeedChanged);
    _feedListening = false;
    _feedAttached = false;
  }

  Future<void> _stopOwnStream() async {
    final sub = _ownSub;
    _ownSub = null;
    await sub?.cancel();
  }

  Future<void> _stopAll() async {
    _detachFeed();
    await _stopOwnStream();
  }

  @override
  void dispose() {
    _disposed = true;
    _detachFeed();
    unawaited(_stopOwnStream());
    super.dispose();
  }
}

