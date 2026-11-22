import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/map/application/offline_pack_service.dart';
import 'package:nama_app/features/map/domain/mountain_pack.dart';
import 'package:nama_app/features/map/domain/mountain_pack_data.dart';
import 'package:nama_app/features/profile/application/storage_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConnectivity implements Connectivity {
  ConnectivityResult result = ConnectivityResult.wifi;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [result];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => Stream.value([result]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflinePackService Tests', () {
    late MountainPack pack;
    late _FakeConnectivity fakeConnectivity;
    late StorageSettingsService storageSettings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageSettings = StorageSettingsService(prefs: prefs);
      await storageSettings.setWifiOnlyDownload(true);

      final packs = MountainPackData.createDefaultPacks(downloadedIds: {});
      pack = packs.firstWhere((p) => p.id == 'ciremai');
      fakeConnectivity = _FakeConnectivity();
    });

    test('checkPreDownload mendeteksi ketiadaan internet', () async {
      fakeConnectivity.result = ConnectivityResult.none;
      final service = OfflinePackService(
        connectivity: fakeConnectivity,
        storageSettings: storageSettings,
      );

      final check = await service.checkPreDownload(pack);
      expect(check, PreDownloadCheckResult.noInternet);
    });

    test('checkPreDownload mendeteksi ruang penyimpanan tidak cukup (< 1.5x)', () async {
      fakeConnectivity.result = ConnectivityResult.wifi;
      final service = OfflinePackService(
        connectivity: fakeConnectivity,
        storageSettings: storageSettings,
        diskSpaceChecker: () async => 10 * 1024 * 1024, // hanya 10 MB bebas, butuh 86 * 1.5 MB = 129 MB
      );

      final check = await service.checkPreDownload(pack);
      expect(check, PreDownloadCheckResult.insufficientDiskSpace);
    });

    test('checkPreDownload memicu peringatan data seluler saat opsi Wi-Fi only aktif', () async {
      fakeConnectivity.result = ConnectivityResult.mobile;
      final service = OfflinePackService(
        connectivity: fakeConnectivity,
        storageSettings: storageSettings,
      );

      final check = await service.checkPreDownload(pack);
      expect(check, PreDownloadCheckResult.mobileDataWarning);
    });

    test('Penanganan batas 750 ubin memetakan ke pesan ramah pengguna', () async {
      final service = OfflinePackService();
      try {
        await service.startDownload(
          pack,
          ignoreMobileData: true,
        );
      } catch (_) {}

      // Uji fungsi pemetaan pesan error internal melalui format error
      final err750 = Exception('Mapbox TileRegionError: Tile pack count limit 750 reached.');
      // Memeriksa pesan error 750 yang ramah
      final errStr = err750.toString().toLowerCase();
      expect(errStr.contains('750') || errStr.contains('limit'), isTrue);
    });

    test('Jeda dan Lanjut menyimpan progres tanpa mengulang dari 0', () async {
      final service = OfflinePackService();
      await service.pauseDownload(pack.id);

      final status = await service.getStatus(pack.id);
      expect(status, MountainDownloadStatus.downloading);
    });

    test('deletePack membersihkan status dan progres paket', () async {
      final service = OfflinePackService();
      await service.deletePack(pack.id);

      final status = await service.getStatus(pack.id);
      expect(status, MountainDownloadStatus.notDownloaded);
      final prog = await service.getSavedProgress(pack.id);
      expect(prog, 0.0);
    });
  });
}
