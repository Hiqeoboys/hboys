import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../infrastructure/auth/active_account_scope.dart';
import '../domain/group_remote_service.dart';

/// Grup terbaru dipakai sebagai helper kompatibilitas lama.
RemoteGroup? nextHikeOf(List<RemoteGroup> groups) {
  if (groups.isEmpty) return null;
  return groups.reduce(
    (a, b) => a.group.createdAtUtc.isAfter(b.group.createdAtUtc) ? a : b,
  );
}

/// Sumber kebenaran tunggal untuk daftar grup yang sinkron antara tab
/// Sosial -> Grup dan halaman Siapkan Pendakian (termasuk grup baru lokal
/// dan tombstone grup yang baru dihapus/keluar).
class SocialGroupsStore extends ChangeNotifier {
  SocialGroupsStore({SharedPreferences? prefs}) : _prefs = prefs;

  static SocialGroupsStore? _instance;
  static SocialGroupsStore get instance => _instance ??= SocialGroupsStore();

  @visibleForTesting
  static void setInstanceForTesting(SocialGroupsStore? store) {
    _instance = store;
  }

  static const String deletedGroupsPrefsKey =
      'hiqeo_deleted_group_tombstones_v1';
  static const String legacyDeletedGroupsPrefsKey =
      'hiqeo_deleted_group_ids_v1';

  SharedPreferences? _prefs;
  bool _loaded = false;
  String? _loadedNamespace;
  final Set<String> _deletedGroupIds = <String>{};
  final List<RemoteGroup> _localGroups = <RemoteGroup>[];

  Set<String> get deletedGroupIds => Set<String>.unmodifiable(_deletedGroupIds);
  List<RemoteGroup> get localGroups =>
      List<RemoteGroup>.unmodifiable(_localGroups);

  String _scopedDeletedKey() {
    final uid = ActiveAccountScope.currentUserId();
    return uid == null
        ? deletedGroupsPrefsKey
        : ActiveAccountScope.namespacedKey(deletedGroupsPrefsKey,
            userIdOverride: uid);
  }

  Future<SharedPreferences?> _tryGetPrefs() async {
    try {
      return _prefs ??= await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistDeletedIds([SharedPreferences? prefs]) async {
    final target = prefs ?? await _tryGetPrefs();
    if (target == null) return;
    try {
      await target.setStringList(
        _scopedDeletedKey(),
        _deletedGroupIds.toList(growable: false),
      );
      if (ActiveAccountScope.currentUserId() == null) {
        await target.remove(legacyDeletedGroupsPrefsKey);
      }
    } catch (_) {}
  }

  Future<void> load({bool force = false}) async {
    final ns = ActiveAccountScope.storageNamespace();
    if (_loaded && !force && _loadedNamespace == ns) return;
    _loadedNamespace = ns;
    _deletedGroupIds.clear();
    final prefs = await _tryGetPrefs();
    var migratedLegacy = false;
    if (prefs != null) {
      try {
        final ids = prefs.getStringList(_scopedDeletedKey());
        if (ids != null && ids.isNotEmpty) {
          _deletedGroupIds.addAll(ids);
        }
        final legacyIds = prefs.getStringList(legacyDeletedGroupsPrefsKey);
        if (legacyIds != null) {
          if (legacyIds.isNotEmpty) {
            _deletedGroupIds.addAll(legacyIds);
          }
          migratedLegacy = true;
        }
      } catch (_) {}
    }
    _localGroups.removeWhere((g) => _deletedGroupIds.contains(g.group.id));
    if (migratedLegacy) {
      await _persistDeletedIds(prefs);
      try {
        await prefs?.remove(legacyDeletedGroupsPrefsKey);
      } catch (_) {}
    }
    _loaded = true;
    notifyListeners();
  }

  /// Mengosongkan state grup & tombstone saat pengguna berganti akun.
  Future<void> resetForAccountChange() async {
    _deletedGroupIds.clear();
    _localGroups.clear();
    _loaded = false;
    _loadedNamespace = null;
    notifyListeners();
    await load();
  }

  void addLocalGroup(RemoteGroup remote) {
    _deletedGroupIds.remove(remote.group.id);
    _localGroups.removeWhere((g) => g.group.id == remote.group.id);
    _localGroups.insert(0, remote);
    notifyListeners();
  }

  void clearLocalGroups() {
    if (_localGroups.isEmpty) return;
    _localGroups.clear();
    notifyListeners();
  }

  Future<void> markGroupDeleted(String groupId) async {
    _deletedGroupIds.add(groupId);
    _localGroups.removeWhere((g) => g.group.id == groupId);
    notifyListeners();
    await _persistDeletedIds();
  }

  /// Menyelaraskan daftar grup lokal dan tombstone terhadap hasil aktif dari server:
  /// - Grup ber-UUID server yang sudah tidak dikembalikan server dihapus total.
  /// - Hanya grup baru offline (`grup-lokal-*`) yang dipertahankan sampai tersinkron.
  /// - Tombstone yang sudah terkonfirmasi hilang di server dibersihkan permanen.
  Future<void> reconcileWithServer(Iterable<RemoteGroup> serverGroups) async {
    final serverIds = serverGroups.map((g) => g.group.id).toSet();
    final prevLocalLen = _localGroups.length;
    final prevDeletedLen = _deletedGroupIds.length;

    _localGroups.removeWhere(
      (g) =>
          serverIds.contains(g.group.id) ||
          !g.group.id.startsWith('grup-lokal-'),
    );
    _deletedGroupIds.removeWhere((id) => !serverIds.contains(id));

    final deletedChanged = _deletedGroupIds.length != prevDeletedLen;
    final localChanged = _localGroups.length != prevLocalLen;
    if (deletedChanged) {
      await _persistDeletedIds();
    }
    if (deletedChanged || localChanged) {
      notifyListeners();
    }
  }

  /// Menggabungkan grup dari server (`AccountController.groups`) dan grup baru
  /// lokal sambil membuang semua grup yang sudah dihapus/keluar.
  List<RemoteGroup> resolveGroups(Iterable<RemoteGroup> remoteGroups) {
    final seen = <String>{};
    final merged = <RemoteGroup>[];
    for (final g in remoteGroups) {
      if (_deletedGroupIds.contains(g.group.id)) continue;
      if (seen.add(g.group.id)) merged.add(g);
    }
    for (final g in _localGroups) {
      if (_deletedGroupIds.contains(g.group.id)) continue;
      if (seen.add(g.group.id)) merged.add(g);
    }
    return merged;
  }
}
