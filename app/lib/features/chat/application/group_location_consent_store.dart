import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Menyimpan persetujuan lokasi per grup (aktif secara bawaan untuk
/// mendukung pembaruan otomatis lokasi terakhir anggota).
class GroupLocationConsentStore extends ChangeNotifier {
  GroupLocationConsentStore._();

  static final GroupLocationConsentStore instance =
      GroupLocationConsentStore._();

  static const String _keyPrefix = 'hiqeo_group_share_loc_v1_';

  final Map<String, bool> _cache = <String, bool>{};

  bool isEnabled(String groupId) => _cache[groupId] ?? true;

  Future<bool> load(String groupId) async {
    if (_cache.containsKey(groupId)) return _cache[groupId]!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getBool('$_keyPrefix$groupId') ?? true;
      _cache[groupId] = val;
      notifyListeners();
      return val;
    } catch (_) {
      return true;
    }
  }

  Future<void> setEnabled(String groupId, bool enabled) async {
    if (_cache[groupId] == enabled) return;
    _cache[groupId] = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_keyPrefix$groupId', enabled);
    } catch (_) {}
  }

  Future<void> clearGroup(String groupId) async {
    _cache.remove(groupId);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$groupId');
    } catch (_) {}
  }
}
