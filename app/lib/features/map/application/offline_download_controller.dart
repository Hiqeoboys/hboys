import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/map_package.dart';
import 'offline_map_service.dart';

enum OfflineDownloadPhase {
  idle,
  estimating,
  estimated,
  downloading,
  downloaded,
  error,
}

/// Mengatur estimasi dan unduhan satu paket. Hasil callback dari SDK yang sudah
/// kedaluwarsa (pengguna memilih paket lain) diabaikan.
class OfflineDownloadController extends ChangeNotifier {
  OfflineDownloadController({required this.service});

  final OfflineMapService service;

  MountainMapPackage? _package;
  OfflinePlan? _plan;
  OfflineEstimate? _estimate;
  OfflineProgress? _progress;
  OfflineRegionStatus? _status;
  OfflineDownloadPhase _phase = OfflineDownloadPhase.idle;
  String? _error;
  bool _disposed = false;
  int _generation = 0;

  MountainMapPackage? get package => _package;
  OfflinePlan? get plan => _plan;
  OfflineEstimate? get estimate => _estimate;
  OfflineProgress? get progress => _progress;
  OfflineRegionStatus? get status => _status;
  OfflineDownloadPhase get phase => _phase;
  String? get error => _error;

  bool get isReady => _status?.ready ?? false;

  bool get isBusy =>
      _phase == OfflineDownloadPhase.estimating ||
      _phase == OfflineDownloadPhase.downloading;

  bool get canDownload =>
      _package != null &&
      (_plan?.canDownload ?? false) &&
      !isBusy &&
      !isReady &&
      _phase != OfflineDownloadPhase.downloaded;

  void select(MountainMapPackage? package) {
    if (_disposed) return;
    _generation++;
    _package = package;
    _plan = package == null ? null : OfflinePlan.evaluate(package.offline);
    _estimate = null;
    _progress = null;
    _status = null;
    _error = null;
    _phase = OfflineDownloadPhase.idle;
    notifyListeners();
    if (package != null) {
      unawaited(refreshStatus());
      if (_plan?.canDownload ?? false) {
        unawaited(estimateDownload());
      }
    }
  }

  /// Membaca keadaan region dari penyimpanan SDK. Status siap tidak disimpan
  /// di memori aplikasi sehingga tetap benar setelah aplikasi dibuka ulang.
  Future<void> refreshStatus() async {
    final package = _package;
    if (_disposed || package == null) return;
    // Memakai identitas paket, bukan [_generation]: estimasi yang dimulai
    // setelah pemilihan tidak boleh membatalkan pembacaan status.
    try {
      final status = await service.regionStatus(package);
      if (_disposed || !identical(_package, package)) return;
      _status = status;
    } catch (_) {
      if (_disposed || !identical(_package, package)) return;
      _status = null;
    }
    notifyListeners();
  }

  Future<void> estimateDownload() async {
    final package = _package;
    final plan = _plan;
    if (_disposed || package == null || plan == null) return;
    if (!plan.canDownload || isBusy) return;

    final generation = ++_generation;
    _phase = OfflineDownloadPhase.estimating;
    _estimate = null;
    _error = null;
    notifyListeners();
    try {
      final estimate = await service.estimate(package);
      if (_disposed || generation != _generation) return;
      _estimate = estimate;
      _phase = OfflineDownloadPhase.estimated;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('OfflineDownloadController.estimate failed: $error');
      }
      if (_disposed || generation != _generation) return;
      _phase = OfflineDownloadPhase.error;
      _error =
          'Ukuran unduhan belum bisa dihitung. Periksa koneksi lalu coba lagi.';
    }
    notifyListeners();
  }

  Future<void> download() async {
    final package = _package;
    final plan = _plan;
    if (_disposed || package == null || plan == null) return;
    if (!plan.canDownload ||
        isBusy ||
        _phase == OfflineDownloadPhase.downloaded) {
      return;
    }

    final generation = ++_generation;
    _error = null;
    if (_estimate == null) {
      _phase = OfflineDownloadPhase.estimating;
      notifyListeners();
      try {
        final estimate = await service.estimate(package);
        if (_disposed || generation != _generation) return;
        _estimate = estimate;
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
              'OfflineDownloadController.download estimate failed: $error');
        }
        if (_disposed || generation != _generation) return;
        _phase = OfflineDownloadPhase.error;
        _error =
            'Ukuran unduhan belum bisa dihitung. Periksa koneksi lalu coba lagi.';
        notifyListeners();
        return;
      }
    }

    _phase = OfflineDownloadPhase.downloading;
    _progress = null;
    notifyListeners();
    try {
      await service.download(
        package,
        onProgress: (progress) {
          if (_disposed || generation != _generation) return;
          _progress = progress;
          notifyListeners();
        },
      );
      if (_disposed || generation != _generation) return;
      _phase = OfflineDownloadPhase.downloaded;
      notifyListeners();
      await refreshStatus();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('OfflineDownloadController.download failed: $error');
      }
      if (_disposed || generation != _generation) return;
      _phase = OfflineDownloadPhase.error;
      _error =
          'Unduhan terhenti. Periksa koneksi internet dan ruang penyimpanan.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
