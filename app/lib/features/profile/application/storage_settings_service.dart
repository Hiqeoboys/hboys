import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Layanan preferensi pengaturan penyimpanan dan unduhan peta offline.
class StorageSettingsService extends ChangeNotifier {
  StorageSettingsService({SharedPreferences? prefs}) : _prefs = prefs;

  static StorageSettingsService? _instance;
  static StorageSettingsService get instance =>
      _instance ??= StorageSettingsService();

  @visibleForTesting
  static void setMockInstance(StorageSettingsService? mock) {
    _instance = mock;
  }

  static const String keyWifiOnlyDownload = 'hiqeo_wifi_only_download';

  SharedPreferences? _prefs;
  bool _wifiOnlyDownload = true;
  bool _isLoaded = false;

  bool get wifiOnlyDownload => _wifiOnlyDownload;
  bool get isLoaded => _isLoaded;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Memuat preferensi dari penyimpanan lokal.
  Future<bool> loadSettings() async {
    final prefs = await _getPrefs();
    _wifiOnlyDownload = prefs.getBool(keyWifiOnlyDownload) ?? true;
    _isLoaded = true;
    notifyListeners();
    return _wifiOnlyDownload;
  }

  /// Mengubah opsi unduh hanya lewat Wi-Fi.
  Future<void> setWifiOnlyDownload(bool value) async {
    _wifiOnlyDownload = value;
    final prefs = await _getPrefs();
    await prefs.setBool(keyWifiOnlyDownload, value);
    notifyListeners();
  }
}
