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
  OfflineDownloadPhase _phase = OfflineDownloadPhase.idle;
  String? _error;
  bool _disposed = false;
  int _generation = 0;

  MountainMapPackage? get package => _package;
  OfflinePlan? get plan => _plan;
  OfflineEstimate? get estimate => _estimate;
  OfflineProgress? get progress => _progress;
  OfflineDownloadPhase get phase => _phase;
  String? get error => _error;

  bool get isBusy =>
      _phase == OfflineDownloadPhase.estimating ||
      _phase == OfflineDownloadPhase.downloading;

  bool get canDownload =>
      _package != null &&
      (_plan?.canDownload ?? false) &&
      !isBusy &&
      _phase != OfflineDownloadPhase.downloaded;

  void select(MountainMapPackage? package) {
    if (_disposed) return;
    _generation++;
    _package = package;
    _plan = package == null ? null : OfflinePlan.evaluate(package.offline);
    _estimate = null;
    _progress = null;
    _error = null;
    _phase = OfflineDownloadPhase.idle;
    notifyListeners();
    if (package != null && (_plan?.canDownload ?? false)) {
      unawaited(estimateDownload());
    }
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
      if (_disposed || generation != _generation) return;
      _phase = OfflineDownloadPhase.error;
      _error = 'Gagal memperkirakan unduhan: $error';
    }
    notifyListeners();
  }

  Future<void> download() async {
    final package = _package;
    final plan = _plan;
    if (_disposed || package == null || plan == null) return;
    if (!plan.canDownload || isBusy || _phase == OfflineDownloadPhase.downloaded) {
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
        if (_disposed || generation != _generation) return;
        _phase = OfflineDownloadPhase.error;
        _error = 'Gagal memperkirakan unduhan: $error';
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
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _phase = OfflineDownloadPhase.error;
      _error = 'Unduhan gagal: $error';
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
