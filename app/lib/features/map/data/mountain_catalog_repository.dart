import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/offline_pack_service.dart';
import '../domain/mountain_pack.dart';
import '../domain/mountain_pack_data.dart';

/// Repository tunggal katalog paket gunung lokal (`assets/gpx`) yang
/// disinkronkan penuh dengan [OfflinePackService] untuk ubin peta offline Mapbox.
class MountainCatalogRepository extends ChangeNotifier {
  MountainCatalogRepository({
    SharedPreferences? prefs,
    OfflinePackService? offlineService,
    bool? mockOnline,
  })  : _prefs = prefs,
        _offlineService = offlineService,
        _mockOnline = mockOnline;

  static MountainCatalogRepository? _instance;
  static MountainCatalogRepository get instance =>
      _instance ??= MountainCatalogRepository();

  @visibleForTesting
  static void setMockInstance(MountainCatalogRepository? mock) {
    _instance = mock;
  }

  static const String _downloadedKey = OfflinePackService.keyDownloadedIds;
  static const String _trailKeyPrefix = 'hiqeo_selected_trail_';

  SharedPreferences? _prefs;
  final OfflinePackService? _offlineService;
  bool? _mockOnline;
  List<MountainPack> _packs = <MountainPack>[];
  bool _isLoading = false;
  String? _error;
  final Map<String, double> _downloadProgress = <String, double>{};

  OfflinePackService get _effectiveOfflineService =>
      _offlineService ?? OfflinePackService.instance;

  List<MountainPack> get packs => List.unmodifiable(_packs);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<bool> isOnline() async {
    if (_mockOnline != null) return _mockOnline!;
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  void setMockOnline(bool? online) {
    _mockOnline = online;
    notifyListeners();
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<Set<String>> _readSyncedDownloadedIds(SharedPreferences prefs) async {
    final ids = (prefs.getStringList(_downloadedKey) ?? const <String>[]).toSet();
    final baseIds = <String>{
      for (final pack in MountainPackData.createDefaultPacks()) pack.id,
      for (final key in prefs.getKeys())
        if (key.startsWith(OfflinePackService.keyStatusPrefix))
          key.substring(OfflinePackService.keyStatusPrefix.length),
    };
    for (final packId in baseIds) {
      final status = await _effectiveOfflineService.getStatus(
        packId,
        remoteVersion: 1,
      );
      if (status == MountainDownloadStatus.downloaded ||
          status == MountainDownloadStatus.updateAvailable) {
        ids.add(packId);
      } else if (prefs.getString('${OfflinePackService.keyStatusPrefix}$packId') ==
          MountainDownloadStatus.notDownloaded.name) {
        ids.remove(packId);
      }
    }
    return ids;
  }

  Future<void> _saveDownloadedIds(Set<String> ids) async {
    final prefs = await _getPrefs();
    await prefs.setStringList(_downloadedKey, ids.toList());
  }

  /// Memuat katalog gunung dari berkas GPX lokal (`assets/gpx`) sekaligus
  /// menyinkronkan status unduhan Mapbox Offline.
  Future<List<MountainPack>> loadPacks({bool forceRefresh = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final prefs = await _getPrefs();
      final downloaded = await _readSyncedDownloadedIds(prefs);

      // Pastikan status di OfflinePackService & SharedPreferences konsisten.
      for (final id in downloaded) {
        if (prefs.getString('${OfflinePackService.keyStatusPrefix}$id') == null) {
          await prefs.setString(
            '${OfflinePackService.keyStatusPrefix}$id',
            MountainDownloadStatus.downloaded.name,
          );
          await prefs.setDouble('${OfflinePackService.keyProgressPrefix}$id', 1.0);
        }
      }

      _packs = await MountainPackData.loadHydratedPacks(
        downloadedIds: downloaded,
      );

      // Terapkan progres unduhan yang sedang berjalan bila ada.
      _packs = _packs.map((p) {
        if (_downloadProgress.containsKey(p.id)) {
          final prog = _downloadProgress[p.id]!;
          return p.copyWith(
            status: prog >= 1.0
                ? MountainDownloadStatus.downloaded
                : MountainDownloadStatus.downloading,
            progress: prog,
          );
        }
        return p;
      }).toList();

      _isLoading = false;
      notifyListeners();
      return _packs;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MountainCatalogRepository load failed: $e');
      }
      _isLoading = false;
      _error = 'Daftar gunung belum bisa dimuat saat ini. Coba muat ulang.';
      notifyListeners();
      return _packs;
    }
  }

  /// Memulai unduhan ubin peta Mapbox Offline (khusus bounding box gunung
  /// terkait) dan berkas GPX lokal secara reaktif.
  Future<void> startDownload(
    String mountainId, {
    void Function(double progress)? onProgress,
  }) async {
    final online = await isOnline();
    if (!online) {
      throw StateError('Butuh internet untuk mengunduh');
    }

    final index = _packs.indexWhere((p) => p.id == mountainId);
    if (index < 0) return;
    final pack = _packs[index];

    _downloadProgress[mountainId] = 0.05;
    _packs[index] = pack.copyWith(
      status: MountainDownloadStatus.downloading,
      progress: 0.05,
    );
    notifyListeners();
    onProgress?.call(0.05);

    StreamSubscription<OfflineDownloadProgress>? sub;
    try {
      sub = _effectiveOfflineService.progressStream(mountainId).listen((event) {
        _downloadProgress[mountainId] = event.fraction;
        final curIdx = _packs.indexWhere((p) => p.id == mountainId);
        if (curIdx >= 0) {
          _packs[curIdx] = _packs[curIdx].copyWith(
            status: event.fraction >= 1.0
                ? MountainDownloadStatus.downloaded
                : MountainDownloadStatus.downloading,
            progress: event.fraction,
          );
          notifyListeners();
          onProgress?.call(event.fraction);
        }
      });

      await _effectiveOfflineService.startDownload(
        pack,
        ignoreMobileData: true,
      );
      await markDownloaded(mountainId);
    } catch (e) {
      _downloadProgress.remove(mountainId);
      final curIdx = _packs.indexWhere((p) => p.id == mountainId);
      if (curIdx >= 0) {
        _packs[curIdx] = _packs[curIdx].copyWith(
          status: MountainDownloadStatus.failed,
          failureReason: e.toString(),
        );
        notifyListeners();
      }
      rethrow;
    } finally {
      await sub?.cancel();
    }
  }

  /// Menandai gunung sudah terunduh di seluruh repo & preferences.
  Future<void> markDownloaded(String mountainId) async {
    final prefs = await _getPrefs();
    final downloaded = (prefs.getStringList(_downloadedKey) ?? const <String>[]).toSet();
    downloaded.add(mountainId);
    await _saveDownloadedIds(downloaded);
    await prefs.setString(
      '${OfflinePackService.keyStatusPrefix}$mountainId',
      MountainDownloadStatus.downloaded.name,
    );
    await prefs.setDouble('${OfflinePackService.keyProgressPrefix}$mountainId', 1.0);

    _downloadProgress.remove(mountainId);
    final idx = _packs.indexWhere((p) => p.id == mountainId);
    if (idx >= 0) {
      _packs[idx] = _packs[idx].copyWith(
        status: MountainDownloadStatus.downloaded,
        progress: 1.0,
      );
      notifyListeners();
    }
  }

  /// Menghapus status unduhan gunung agar daftar & halaman detail langsung sinkron.
  Future<void> markDeleted(String mountainId) async {
    final prefs = await _getPrefs();
    final downloaded = (prefs.getStringList(_downloadedKey) ?? const <String>[]).toSet();
    downloaded.remove(mountainId);
    await _saveDownloadedIds(downloaded);

    _downloadProgress.remove(mountainId);
    final idx = _packs.indexWhere((p) => p.id == mountainId);
    if (idx >= 0) {
      _packs[idx] = _packs[idx].copyWith(
        status: MountainDownloadStatus.notDownloaded,
        progress: 0.0,
      );
      notifyListeners();
    }
  }

  Future<String?> getLastSelectedTrailId(String mountainId) async {
    final prefs = await _getPrefs();
    return prefs.getString('$_trailKeyPrefix$mountainId');
  }

  Future<void> saveSelectedTrailId(String mountainId, String trailId) async {
    final prefs = await _getPrefs();
    await prefs.setString('$_trailKeyPrefix$mountainId', trailId);
  }
}
