import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../infrastructure/auth/active_account_scope.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/offgrid/off_grid_chat_local_store.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../chat/domain/group_chat_models.dart';

/// Satu item perlengkapan pendakian (termasuk gunung tinggi / salju ekstrem).
@immutable
class PackingItem {
  const PackingItem({
    required this.id,
    required this.name,
    required this.category,
    this.isCustom = false,
  });

  final String id;
  final String name;
  final String category;
  final bool isCustom;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'category': category,
        'is_custom': isCustom,
      };

  static PackingItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    final category = raw['category']?.toString().trim() ?? 'Lainnya';
    if (id.isEmpty || name.isEmpty) return null;
    return PackingItem(
      id: id,
      name: name,
      category: category,
      isCustom: raw['is_custom'] == true,
    );
  }
}

/// Katalog lengkap perlengkapan pendakian (tropis hingga gunung bersalju/ekstrem).
const List<PackingItem> kDefaultPackingCatalog = <PackingItem>[
  // Tas & Tidur
  PackingItem(id: 'carrier', name: 'Carrier / Daypack + Rain Cover', category: 'Tas & Tidur'),
  PackingItem(id: 'tenda', name: 'Tenda 3–4 Musim & Footprint', category: 'Tas & Tidur'),
  PackingItem(id: 'sleeping_bag', name: 'Sleeping Bag (Termal / Ekstrem)', category: 'Tas & Tidur'),
  PackingItem(id: 'matras', name: 'Matras Insulasi / Sleeping Pad', category: 'Tas & Tidur'),
  PackingItem(id: 'bivvy', name: 'Bivvy Bag / Emergency Shelter', category: 'Tas & Tidur'),

  // Pakaian & Suhu Ekstrem
  PackingItem(id: 'base_layer', name: 'Thermal Base Layer (Atasan & Celana)', category: 'Pakaian & Dingin'),
  PackingItem(id: 'fleece', name: 'Mid Layer Fleece / Polar', category: 'Pakaian & Dingin'),
  PackingItem(id: 'down_jacket', name: 'Jaket Bulu Angsa (Down Jacket)', category: 'Pakaian & Dingin'),
  PackingItem(id: 'hardshell', name: 'Jaket Hardshell / Windproof Waterproof', category: 'Pakaian & Dingin'),
  PackingItem(id: 'raincoat', name: 'Jas Hujan / Ponco Darurat', category: 'Pakaian & Dingin'),
  PackingItem(id: 'pants', name: 'Celana Gunung Quick-Dry', category: 'Pakaian & Dingin'),
  PackingItem(id: 'extra_clothes', name: 'Baju & Kaus Kaki Ganti Kering (Dry Bag)', category: 'Pakaian & Dingin'),
  PackingItem(id: 'insulated_gloves', name: 'Sarung Tangan Tahan Air / Insulated', category: 'Pakaian & Dingin'),
  PackingItem(id: 'beanie_buff', name: 'Kupluk / Balaclava / Buff', category: 'Pakaian & Dingin'),

  // Alas Kaki & Salju / Medan Ekstrem
  PackingItem(id: 'hiking_boots', name: 'Sepatu Gunung / Mountaineering Boots', category: 'Kaki & Ekstrem'),
  PackingItem(id: 'gaiters', name: 'Gaiter Lumpur / Salju', category: 'Kaki & Ekstrem'),
  PackingItem(id: 'trekking_pole', name: 'Trekking Pole (Sepasang)', category: 'Kaki & Ekstrem'),
  PackingItem(id: 'crampon', name: 'Crampon / Microspikes Es & Salju', category: 'Kaki & Ekstrem'),
  PackingItem(id: 'ice_axe', name: 'Ice Axe / Kapak Es & Helm Gunung', category: 'Kaki & Ekstrem'),
  PackingItem(id: 'snow_goggles', name: 'Kacamata UV / Snow Goggles', category: 'Kaki & Ekstrem'),

  // Logistik & Memasak
  PackingItem(id: 'water', name: 'Air Minum / Water Bladder + Filter', category: 'Logistik & Masak'),
  PackingItem(id: 'food', name: 'Makanan Utama & Camilan Berkalori Tinggi', category: 'Logistik & Masak'),
  PackingItem(id: 'stove_gas', name: 'Kompor & Gas High-Altitude + Korek', category: 'Logistik & Masak'),
  PackingItem(id: 'nesting', name: 'Nesting, Sendok & Mug', category: 'Logistik & Masak'),
  PackingItem(id: 'electrolyte', name: 'Oralit / Minuman Elektrolit', category: 'Logistik & Masak'),

  // Navigasi, Penerangan & Keselamatan
  PackingItem(id: 'headlamp', name: 'Headlamp + Baterai Cadangan', category: 'Navigasi & P3K'),
  PackingItem(id: 'powerbank', name: 'Powerbank + Kabel Charger', category: 'Navigasi & P3K'),
  PackingItem(id: 'first_aid', name: 'Kotak P3K & Obat Pribadi', category: 'Navigasi & P3K'),
  PackingItem(id: 'thermal_blanket', name: 'Emergency Foil Blanket', category: 'Navigasi & P3K'),
  PackingItem(id: 'whistle', name: 'Peluit Darurat & Pisau Lipat', category: 'Navigasi & P3K'),
  PackingItem(id: 'trash_bag', name: 'Trash Bag (Bawa Turun Sampah)', category: 'Navigasi & P3K'),
  PackingItem(id: 'id_permit', name: 'Identitas Diri (KTP) & SIMAKSI', category: 'Navigasi & P3K'),
];

/// Penyimpanan 2 tahap Packing List (Tahap 1: pilih barang, Tahap 2: ceklis barang
/// yang sudah masuk tas) yang terhubung ke halaman Siapkan Pendakian & Peta.
class PackingListStore extends ChangeNotifier {
  PackingListStore({SharedPreferences? prefs}) : _prefs = prefs;

  static PackingListStore? _instance;
  static PackingListStore get instance => _instance ??= PackingListStore();

  @visibleForTesting
  static void setInstanceForTesting(PackingListStore? store) {
    _instance = store;
  }

  static const String _keySelected = 'hiqeo_packing_selected_v2';
  static const String _keyPacked = 'hiqeo_packing_packed_v2';
  static const String _keyStage1Done = 'hiqeo_packing_stage1_done_v2';
  static const String _keyCustomItems = 'hiqeo_packing_custom_items_v2';

  SharedPreferences? _prefs;
  bool _loaded = false;
  String? _loadedNamespace;
  Set<String> _selectedIds = <String>{};
  Set<String> _packedIds = <String>{};
  bool _stage1Done = false;
  List<PackingItem> _customItems = <PackingItem>[];

  String _scopedKey(String base) => ActiveAccountScope.namespacedKey(base);

  bool get isLoaded => _loaded;
  bool get stage1Done => _stage1Done;
  Set<String> get selectedIds => Set<String>.unmodifiable(_selectedIds);
  Set<String> get packedIds => Set<String>.unmodifiable(_packedIds);
  List<PackingItem> get customItems => List<PackingItem>.unmodifiable(_customItems);

  List<PackingItem> get catalog => <PackingItem>[
        ...kDefaultPackingCatalog,
        ..._customItems,
      ];

  bool get hasPackingList => _selectedIds.isNotEmpty;

  List<PackingItem> get selectedItems => catalog
      .where((item) => _selectedIds.contains(item.id))
      .toList(growable: false);

  List<PackingItem> get missingItems => selectedItems
      .where((item) => !_packedIds.contains(item.id))
      .toList(growable: false);

  bool get allPacked => hasPackingList && missingItems.isEmpty;

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> load({bool force = false}) async {
    final ns = ActiveAccountScope.storageNamespace();
    if (_loaded && !force && _loadedNamespace == ns) return;
    _loadedNamespace = ns;
    final prefs = await _getPrefs();
    _selectedIds =
        (prefs.getStringList(_scopedKey(_keySelected)) ?? const <String>[])
            .toSet();
    _packedIds =
        (prefs.getStringList(_scopedKey(_keyPacked)) ?? const <String>[])
            .where(_selectedIds.contains)
            .toSet();
    _stage1Done = prefs.getBool(_scopedKey(_keyStage1Done)) ?? false;
    if (_selectedIds.isEmpty) {
      _stage1Done = false;
    }
    _customItems = <PackingItem>[];
    final rawCustom = prefs.getString(_scopedKey(_keyCustomItems));
    if (rawCustom != null && rawCustom.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCustom);
        if (decoded is List) {
          _customItems = decoded
              .map(PackingItem.fromJson)
              .whereType<PackingItem>()
              .toList();
        }
      } catch (_) {
        _customItems = <PackingItem>[];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    _loadedNamespace = ActiveAccountScope.storageNamespace();
    final prefs = await _getPrefs();
    await prefs.setStringList(_scopedKey(_keySelected), _selectedIds.toList());
    await prefs.setStringList(_scopedKey(_keyPacked), _packedIds.toList());
    await prefs.setBool(_scopedKey(_keyStage1Done), _stage1Done);
    await prefs.setString(
      _scopedKey(_keyCustomItems),
      jsonEncode(_customItems.map((e) => e.toJson()).toList()),
    );
  }

  /// Mengosongkan daftar perlengkapan di memori dan memuat milik akun aktif.
  Future<void> resetForAccountChange() async {
    _selectedIds.clear();
    _packedIds.clear();
    _stage1Done = false;
    _customItems = <PackingItem>[];
    _loaded = false;
    _loadedNamespace = null;
    notifyListeners();
    try {
      await load();
    } catch (_) {}
  }

  Future<void> toggleSelectItem(String id) async {
    if (!_loaded) await load();
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
      _packedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    if (_selectedIds.isEmpty) {
      _stage1Done = false;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> addCustomItem(String name, {String category = 'Tambahan'}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (!_loaded) await load();
    final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    final item = PackingItem(
      id: id,
      name: trimmed,
      category: category,
      isCustom: true,
    );
    _customItems = <PackingItem>[..._customItems, item];
    _selectedIds.add(id);
    await _persist();
    notifyListeners();
  }

  Future<void> finishStage1() async {
    if (!_loaded) await load();
    if (_selectedIds.isEmpty) return;
    _stage1Done = true;
    _packedIds = _packedIds.intersection(_selectedIds);
    await _persist();
    notifyListeners();
  }

  Future<void> editStage1() async {
    if (!_loaded) await load();
    _stage1Done = false;
    await _persist();
    notifyListeners();
  }

  Future<void> togglePackedItem(String id) async {
    if (!_loaded) await load();
    if (!_selectedIds.contains(id)) return;
    if (_packedIds.contains(id)) {
      _packedIds.remove(id);
    } else {
      _packedIds.add(id);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _selectedIds.clear();
    _packedIds.clear();
    _stage1Done = false;
    try {
      await _persist();
    } catch (_) {}
    notifyListeners();
  }
}

/// Status persiapan pendakian bersama grup (menghubungkan Siapkan Pendakian & Chat Grup).
@immutable
class GroupHikePlan {
  const GroupHikePlan({
    required this.inviteId,
    required this.groupId,
    required this.groupName,
    required this.mountainId,
    required this.mountainName,
    this.trailId,
    this.trailName,
    required this.organizerUserId,
    required this.organizerName,
    required this.readyUserIds,
    required this.memberCount,
    this.status = 'active',
    this.inviteMessageClientId,
    this.startedAtUtc,
    this.startedByUserId,
  });

  final String inviteId;
  final String groupId;
  final String groupName;
  final String mountainId;
  final String mountainName;
  final String? trailId;
  final String? trailName;
  final String organizerUserId;
  final String organizerName;
  final Set<String> readyUserIds;
  final int memberCount;
  final String status;
  final String? inviteMessageClientId;
  final DateTime? startedAtUtc;
  final String? startedByUserId;

  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed';
  bool get isStarted => status == 'started';
  bool get isActive => status == 'active';
  bool get isOngoing => isActive || isStarted;

  /// Parses `ready_user_ids` from either a Dart `List` or Postgres array literal (`{uuid1,uuid2}`).
  static Set<String> parseReadyUserIds(Object? raw) {
    final result = <String>{};
    if (raw is Iterable) {
      for (final entry in raw) {
        final s = entry?.toString().trim() ?? '';
        if (s.isNotEmpty) result.add(s);
      }
      return result;
    }
    if (raw is String) {
      var trimmed = raw.trim();
      if (trimmed.isEmpty) return result;
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        trimmed = trimmed.substring(1, trimmed.length - 1);
      } else if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List) return parseReadyUserIds(decoded);
        } catch (_) {}
      }
      for (final part in trimmed.split(',')) {
        final cleaned = part.replaceAll('"', '').replaceAll("'", '').trim();
        if (cleaned.isNotEmpty) result.add(cleaned);
      }
    }
    return result;
  }

  /// Minimal ada anggota lain selain pembuat yang sudah menekan "Siap"
  /// (atau semua anggota grup sudah siap jika grup hanya 1 orang).
  bool get hasOtherMemberReady {
    if (memberCount <= 1) return true;
    final othersReady =
        readyUserIds.where((id) => id != organizerUserId).length;
    return othersReady > 0 || readyUserIds.length >= memberCount;
  }

  /// Seluruh anggota grup sudah menekan "Siap".
  bool get allMembersReady =>
      memberCount <= 1 || readyUserIds.length >= memberCount;

  int get readyCount => readyUserIds.length;

  /// Masih ada anggota grup yang belum menekan tombol "Siap".
  bool get isWaitingForOthers => !allMembersReady;

  int get pendingMemberCount =>
      (memberCount - readyCount).clamp(0, memberCount);

  String get waitingLockMessage =>
      'Menunggu anggota grup lain menekan Siap ($readyCount/$memberCount siap)';

  GroupHikePlan copyWith({
    String? groupName,
    String? mountainId,
    String? mountainName,
    String? trailId,
    String? trailName,
    Set<String>? readyUserIds,
    int? memberCount,
    String? status,
    String? inviteMessageClientId,
    DateTime? startedAtUtc,
    String? startedByUserId,
  }) =>
      GroupHikePlan(
        inviteId: inviteId,
        groupId: groupId,
        groupName: groupName ?? this.groupName,
        mountainId: mountainId ?? this.mountainId,
        mountainName: mountainName ?? this.mountainName,
        trailId: trailId ?? this.trailId,
        trailName: trailName ?? this.trailName,
        organizerUserId: organizerUserId,
        organizerName: organizerName,
        readyUserIds: readyUserIds ?? this.readyUserIds,
        memberCount: memberCount ?? this.memberCount,
        status: status ?? this.status,
        inviteMessageClientId:
            inviteMessageClientId ?? this.inviteMessageClientId,
        startedAtUtc: startedAtUtc ?? this.startedAtUtc,
        startedByUserId: startedByUserId ?? this.startedByUserId,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'invite_id': inviteId,
        'group_id': groupId,
        'group_name': groupName,
        'mountain_id': mountainId,
        'mountain_name': mountainName,
        'trail_id': trailId,
        'trail_name': trailName,
        'organizer_user_id': organizerUserId,
        'organizer_name': organizerName,
        'ready_user_ids': readyUserIds.toList(),
        'member_count': memberCount,
        'status': status,
        if (inviteMessageClientId != null)
          'invite_message_id': inviteMessageClientId,
        if (startedAtUtc != null)
          'started_at': startedAtUtc!.toUtc().toIso8601String(),
        if (startedByUserId != null) 'started_by': startedByUserId,
      };

  static GroupHikePlan? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final inviteId = raw['invite_id']?.toString() ?? '';
    final groupId = raw['group_id']?.toString() ?? '';
    final groupName = raw['group_name']?.toString() ?? '';
    final mountainId = raw['mountain_id']?.toString() ?? '';
    final mountainName = raw['mountain_name']?.toString() ?? '';
    if (inviteId.isEmpty || groupId.isEmpty || mountainId.isEmpty) return null;
    final ready = parseReadyUserIds(raw['ready_user_ids']);
    final startedRaw = raw['started_at']?.toString();
    return GroupHikePlan(
      inviteId: inviteId,
      groupId: groupId,
      groupName: groupName,
      mountainId: mountainId,
      mountainName: mountainName,
      trailId: raw['trail_id']?.toString(),
      trailName: raw['trail_name']?.toString(),
      organizerUserId: raw['organizer_user_id']?.toString() ?? '',
      organizerName: raw['organizer_name']?.toString() ?? '',
      readyUserIds: ready,
      memberCount: (raw['member_count'] as num?)?.toInt() ?? 1,
      status: raw['status']?.toString() ?? 'active',
      inviteMessageClientId: raw['invite_message_id']?.toString(),
      startedAtUtc:
          startedRaw != null ? DateTime.tryParse(startedRaw)?.toUtc() : null,
      startedByUserId: raw['started_by']?.toString(),
    );
  }

  static GroupHikePlan? fromPrepRow(
    Map<String, dynamic> row, {
    String? groupName,
  }) {
    final groupId = row['group_id']?.toString() ?? '';
    final inviteId = row['invite_id']?.toString() ?? '';
    final mountainId = row['mountain_id']?.toString() ?? '';
    final mountainName = row['mountain_name']?.toString() ?? '';
    if (groupId.isEmpty || inviteId.isEmpty || mountainId.isEmpty) return null;
    final ready = parseReadyUserIds(row['ready_user_ids']);
    final rawStatus = row['status']?.toString() ?? 'active';
    final effectiveStatus =
        row['is_cancelled'] == true ? 'cancelled' : rawStatus;
    final startedRaw = row['started_at']?.toString();
    return GroupHikePlan(
      inviteId: inviteId,
      groupId: groupId,
      groupName: groupName ?? row['group_name']?.toString() ?? 'Grup Pendakian',
      mountainId: mountainId,
      mountainName: mountainName,
      trailId: row['trail_id']?.toString(),
      trailName: row['trail_name']?.toString(),
      organizerUserId: row['organizer_user_id']?.toString() ?? '',
      organizerName: row['organizer_name']?.toString() ?? 'Ketua Rombongan',
      readyUserIds: ready,
      memberCount: (row['member_count'] as num?)?.toInt() ?? 1,
      status: effectiveStatus,
      inviteMessageClientId: row['invite_message_id']?.toString(),
      startedAtUtc:
          startedRaw != null ? DateTime.tryParse(startedRaw)?.toUtc() : null,
      startedByUserId: row['started_by']?.toString(),
    );
  }
}

/// Protokol pesan ajakan pendakian grup di dalam chat grup (tanpa tabel tambahan).
class GroupHikeInviteMessage {
  const GroupHikeInviteMessage._();

  static const String invitePrefix = '[HIQEO_HIKE_INVITE]';
  static const String readyPrefix = '[HIQEO_HIKE_READY]';
  static const String cancelPrefix = '[HIQEO_HIKE_CANCEL]';

  static String encodeInvite(GroupHikePlan plan) =>
      '$invitePrefix${jsonEncode(plan.toJson())}';

  static String encodeReady({
    required String inviteId,
    required String userId,
    required String userName,
  }) =>
      '$readyPrefix${jsonEncode(<String, Object?>{
        'invite_id': inviteId,
        'user_id': userId,
        'user_name': userName,
      })}';

  static String encodeCancel({
    required String inviteId,
    required String groupId,
  }) =>
      '$cancelPrefix${jsonEncode(<String, Object?>{
        'invite_id': inviteId,
        'group_id': groupId,
      })}';

  static GroupHikePlan? tryDecodeInvite(String? content) {
    if (content == null || !content.startsWith(invitePrefix)) return null;
    try {
      return GroupHikePlan.fromJson(
        jsonDecode(content.substring(invitePrefix.length)),
      );
    } catch (_) {
      return null;
    }
  }

  static ({String inviteId, String userId, String userName})? tryDecodeReady(
    String? content,
  ) {
    if (content == null || !content.startsWith(readyPrefix)) return null;
    try {
      final map = jsonDecode(content.substring(readyPrefix.length));
      if (map is! Map) return null;
      final inviteId = map['invite_id']?.toString() ?? '';
      final userId = map['user_id']?.toString() ?? '';
      final userName = map['user_name']?.toString() ?? '';
      if (inviteId.isEmpty || userId.isEmpty) return null;
      return (inviteId: inviteId, userId: userId, userName: userName);
    } catch (_) {
      return null;
    }
  }

  static ({String inviteId, String groupId})? tryDecodeCancel(
    String? content,
  ) {
    if (content == null || !content.startsWith(cancelPrefix)) return null;
    try {
      final map = jsonDecode(content.substring(cancelPrefix.length));
      if (map is! Map) return null;
      final inviteId = map['invite_id']?.toString() ?? '';
      final groupId = map['group_id']?.toString() ?? '';
      if (inviteId.isEmpty || groupId.isEmpty) return null;
      return (inviteId: inviteId, groupId: groupId);
    } catch (_) {
      return null;
    }
  }
}

/// Status persiapan pendakian solo (tanpa grup).
@immutable
class SoloHikePlan {
  const SoloHikePlan({
    required this.mountainId,
    required this.mountainName,
    this.trailId,
    this.trailName,
    this.isStarted = false,
  });

  final String mountainId;
  final String mountainName;
  final String? trailId;
  final String? trailName;
  final bool isStarted;

  SoloHikePlan copyWith({
    String? trailId,
    String? trailName,
    bool? isStarted,
  }) =>
      SoloHikePlan(
        mountainId: mountainId,
        mountainName: mountainName,
        trailId: trailId ?? this.trailId,
        trailName: trailName ?? this.trailName,
        isStarted: isStarted ?? this.isStarted,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'mountain_id': mountainId,
        'mountain_name': mountainName,
        'trail_id': trailId,
        'trail_name': trailName,
        'is_started': isStarted,
      };

  static SoloHikePlan? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final mountainId = raw['mountain_id']?.toString().trim() ?? '';
    final mountainName = raw['mountain_name']?.toString().trim() ?? '';
    if (mountainId.isEmpty || mountainName.isEmpty) return null;
    return SoloHikePlan(
      mountainId: mountainId,
      mountainName: mountainName,
      trailId: raw['trail_id']?.toString(),
      trailName: raw['trail_name']?.toString(),
      isStarted: raw['is_started'] == true,
    );
  }
}

/// Store global untuk rencana pendakian grup/solo aktif (mengunci gunung & grup
/// saat anggota menekan "Siap" agar tidak terjadi ajakan ganda).
class GroupHikePlanStore extends ChangeNotifier {
  GroupHikePlanStore({SharedPreferences? prefs}) : _prefs = prefs;

  static GroupHikePlanStore? _instance;
  static GroupHikePlanStore get instance => _instance ??= GroupHikePlanStore();

  @visibleForTesting
  static void setInstanceForTesting(GroupHikePlanStore? store) {
    _instance = store;
  }

  static const String _keyPlan = 'hiqeo_active_group_hike_plan_v1';
  static const String _keySoloPlan = 'hiqeo_active_solo_hike_plan_v1';
  static const String _keyCompletedInvites = 'hiqeo_completed_hike_invites_v1';

  SharedPreferences? _prefs;
  bool _loaded = false;
  String? _loadedNamespace;
  GroupHikePlan? _activePlan;
  SoloHikePlan? _soloPlan;
  final Map<String, GroupHikePlan> _activePlansByGroupId =
      <String, GroupHikePlan>{};
  final Map<String, String> _groupNamesById = <String, String>{};
  final Set<String> _cancelledInviteIds = <String>{};
  final Set<String> _completedInviteIds = <String>{};
  final Set<String> _handledStartedKeys = <String>{};
  final StreamController<GroupHikePlan> _hikeStartedCtrl =
      StreamController<GroupHikePlan>.broadcast();
  RealtimeChannel? _globalPrepChannel;

  String _scopedPlanKey(String base) => ActiveAccountScope.namespacedKey(base);

  GroupHikePlan? get activePlan => _activePlan;
  SoloHikePlan? get soloPlan => _soloPlan;
  Stream<GroupHikePlan> get onHikeStarted => _hikeStartedCtrl.stream;

  /// Mengembalikan ajakan pendakian aktif untuk [groupId], atau `null` bila
  /// belum ada ajakan / ajakan sudah dibatalkan atau selesai.
  GroupHikePlan? activePlanForGroup(String groupId) {
    final plan = _activePlansByGroupId[groupId];
    if (plan != null &&
        plan.isOngoing &&
        !plan.isCancelled &&
        !_cancelledInviteIds.contains(plan.inviteId)) {
      return plan;
    }
    final active = _activePlan;
    if (active != null &&
        active.groupId == groupId &&
        active.isOngoing &&
        !active.isCancelled &&
        !_cancelledInviteIds.contains(active.inviteId)) {
      return active;
    }
    return null;
  }

  bool isInviteCancelled(String inviteId) =>
      _cancelledInviteIds.contains(inviteId);

  void markInviteCancelledLocally(String inviteId, {String? groupId}) {
    if (inviteId.isEmpty) return;
    final added = _cancelledInviteIds.add(inviteId);
    if (groupId != null) {
      final cached = _activePlansByGroupId[groupId];
      if (cached?.inviteId == inviteId) {
        _activePlansByGroupId.remove(groupId);
      }
    } else {
      _activePlansByGroupId.removeWhere((_, p) => p.inviteId == inviteId);
    }
    if (_activePlan?.inviteId == inviteId) {
      unawaited(setPlan(null));
    } else if (added) {
      notifyListeners();
    }
  }

  /// Memastikan langganan Realtime `public.group_hike_prep` aktif secara global
  /// sehingga kesiapan anggota ("Saya Siap" / batal) dan event `hike_started`
  /// selalu diterima instan di layar mana pun tanpa berpindah halaman.
  void ensureRealtimeSubscribed({
    Map<String, String> groupNamesById = const <String, String>{},
  }) {
    for (final entry in groupNamesById.entries) {
      final name = entry.value.trim();
      if (name.isNotEmpty) _groupNamesById[entry.key] = name;
    }
    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null) return;
    if (_globalPrepChannel != null) return;

    _globalPrepChannel = client
        .channel('hiqeo_group_hike_prep_global')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_hike_prep',
          callback: (payload) => unawaited(_handlePrepRealtime(payload)),
        )
        .subscribe();
  }

  void subscribeGroupPrep(String groupId) {
    ensureRealtimeSubscribed();
  }

  /// Langganan `group_hike_prep` dijaga tetap hidup lintas layar selama sesi
  /// login aktif agar pembaruan status siap & auto-start grup tidak terputus.
  Future<void> unsubscribeGroupPrep() async {}

  Future<void> unsubscribeAllRealtime() async {
    final global = _globalPrepChannel;
    _globalPrepChannel = null;
    if (global != null) {
      try {
        await SupabaseServices.clientOrNull?.removeChannel(global);
      } catch (_) {}
    }
  }

  Future<void> _handlePrepRealtime(PostgresChangePayload payload) async {
    final isDelete = payload.eventType == PostgresChangeEvent.delete;
    final row = payload.newRecord.isNotEmpty
        ? Map<String, dynamic>.from(payload.newRecord)
        : Map<String, dynamic>.from(payload.oldRecord);
    if (row.isEmpty) return;
    await _processPrepRow(row, isDelete: isDelete);
  }

  @visibleForTesting
  Future<void> handlePrepRowForTesting(
    Map<String, dynamic> row, {
    bool isDelete = false,
    String? currentUserIdOverride,
  }) =>
      _processPrepRow(
        row,
        isDelete: isDelete,
        currentUserIdOverride: currentUserIdOverride,
      );

  Future<void> _processPrepRow(
    Map<String, dynamic> row, {
    bool isDelete = false,
    String? currentUserIdOverride,
  }) async {
    if (isDelete) {
      final groupId = row['group_id']?.toString() ?? '';
      if (groupId.isEmpty) return;
      _activePlansByGroupId.remove(groupId);
      if (_activePlan?.groupId == groupId) {
        await setPlan(null);
      } else {
        notifyListeners();
      }
      return;
    }

    final rawGroupId = row['group_id']?.toString() ?? '';
    final knownName = _groupNamesById[rawGroupId] ??
        _activePlansByGroupId[rawGroupId]?.groupName ??
        (_activePlan?.groupId == rawGroupId ? _activePlan?.groupName : null);
    final parsed = GroupHikePlan.fromPrepRow(row, groupName: knownName);
    if (parsed == null) return;

    if (parsed.isCancelled ||
        parsed.isCompleted ||
        _completedInviteIds.contains(parsed.inviteId)) {
      if (parsed.isCancelled) {
        _cancelledInviteIds.add(parsed.inviteId);
      }
      _activePlansByGroupId.remove(parsed.groupId);
      if (_activePlan?.groupId == parsed.groupId) {
        await setPlan(null);
      } else {
        notifyListeners();
      }
      if (parsed.isCancelled &&
          parsed.inviteMessageClientId != null &&
          parsed.inviteMessageClientId!.isNotEmpty) {
        await _markLocalInviteMessageCancelled(
          groupId: parsed.groupId,
          clientMsgId: parsed.inviteMessageClientId!,
        );
      }
    } else if (parsed.isOngoing) {
      _cancelledInviteIds.remove(parsed.inviteId);
      _activePlansByGroupId[parsed.groupId] = parsed;
      await setPlan(parsed);
      if (parsed.isStarted) {
        _maybeEmitHikeStarted(
          parsed,
          currentUserIdOverride: currentUserIdOverride,
        );
      }
    } else {
      _activePlansByGroupId.remove(parsed.groupId);
      if (_activePlan?.groupId == parsed.groupId) {
        await setPlan(null);
      } else {
        notifyListeners();
      }
    }
  }

  void _maybeEmitHikeStarted(
    GroupHikePlan plan, {
    String? currentUserIdOverride,
  }) {
    if (!plan.isStarted || plan.isCancelled) return;
    final key =
        '${plan.groupId}:${plan.inviteId}:${plan.startedAtUtc?.millisecondsSinceEpoch ?? 0}';
    final currentUid = currentUserIdOverride ??
        SupabaseServices.sharedAccountController?.user?.id ??
        SupabaseServices.clientOrNull?.auth.currentUser?.id;
    if (currentUid != null &&
        currentUid.isNotEmpty &&
        plan.startedByUserId == currentUid) {
      _handledStartedKeys.add(key);
      return;
    }
    if (plan.startedAtUtc != null) {
      final age = DateTime.now().toUtc().difference(plan.startedAtUtc!).abs();
      if (age > const Duration(hours: 6)) return;
    }
    if (_handledStartedKeys.add(key) && !_hikeStartedCtrl.isClosed) {
      _hikeStartedCtrl.add(plan);
    }
  }

  void emitHikeStartedFromPush(
    Map<String, String> rawData, {
    String? currentUserIdOverride,
  }) {
    final groupId = (rawData['group_id'] ?? rawData['target_id'] ?? '').trim();
    final mountainId = (rawData['mountain_id'] ?? '').trim();
    if (groupId.isEmpty || mountainId.isEmpty) return;
    final existing = activePlanForGroup(groupId);
    final inviteId = (rawData['invite_id'] ?? '').trim().isNotEmpty
        ? rawData['invite_id']!.trim()
        : (existing?.inviteId ?? 'push_$groupId');
    final trailIdRaw = (rawData['route_id'] ?? rawData['trail_id'] ?? '').trim();
    final trailNameRaw = (rawData['trail_name'] ?? '').trim();
    final mountainNameRaw = (rawData['mountain_name'] ?? '').trim();
    final groupNameRaw = (rawData['room_name'] ?? '').trim();
    final startedAt = rawData['started_at'] != null
        ? DateTime.tryParse(rawData['started_at']!)?.toUtc()
        : null;
    final startedBy =
        (rawData['started_by'] ?? rawData['sender_id'] ?? '').trim();

    final plan = GroupHikePlan(
      inviteId: inviteId,
      groupId: groupId,
      groupName: groupNameRaw.isNotEmpty
          ? groupNameRaw
          : (_groupNamesById[groupId] ?? existing?.groupName ?? 'Grup Pendakian'),
      mountainId: mountainId,
      mountainName: mountainNameRaw.isNotEmpty
          ? mountainNameRaw
          : (existing?.mountainName ?? mountainId),
      trailId: trailIdRaw.isNotEmpty ? trailIdRaw : existing?.trailId,
      trailName: trailNameRaw.isNotEmpty ? trailNameRaw : existing?.trailName,
      organizerUserId: existing?.organizerUserId ?? startedBy,
      organizerName: existing?.organizerName ??
          (rawData['sender_name']?.trim().isNotEmpty == true
              ? rawData['sender_name']!.trim()
              : 'Ketua Rombongan'),
      readyUserIds: existing?.readyUserIds ?? const <String>{},
      memberCount: existing?.memberCount ?? 2,
      status: 'started',
      inviteMessageClientId: existing?.inviteMessageClientId,
      startedAtUtc: startedAt ?? DateTime.now().toUtc(),
      startedByUserId: startedBy.isNotEmpty ? startedBy : null,
    );
    _activePlansByGroupId[groupId] = plan;
    unawaited(setPlan(plan));
    _maybeEmitHikeStarted(
      plan,
      currentUserIdOverride: currentUserIdOverride,
    );
  }

  Future<void> _markLocalInviteMessageCancelled({
    required String groupId,
    required String clientMsgId,
  }) async {
    AppDatabase? db;
    try {
      db = openAppDatabase(await defaultAppDatabaseFile());
      final store = OffGridChatLocalStore(database: db);
      await store.markMessageCancelled(
        groupId: groupId,
        clientMsgId: clientMsgId,
      );
    } catch (_) {
    } finally {
      await db?.close();
    }
  }

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> load({bool force = false}) async {
    final ns = ActiveAccountScope.storageNamespace();
    if (_loaded && !force && _loadedNamespace == ns) return;
    _loadedNamespace = ns;
    _activePlan = null;
    _soloPlan = null;
    final prefs = await _getPrefs();
    _completedInviteIds
      ..clear()
      ..addAll(
        prefs.getStringList(_scopedPlanKey(_keyCompletedInvites)) ??
            const <String>[],
      );
    final raw = prefs.getString(_scopedPlanKey(_keyPlan));
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = GroupHikePlan.fromJson(jsonDecode(raw));
        if (decoded != null &&
            decoded.isOngoing &&
            !_completedInviteIds.contains(decoded.inviteId)) {
          _activePlan = decoded;
        }
      } catch (_) {
        _activePlan = null;
      }
    }
    final rawSolo = prefs.getString(_scopedPlanKey(_keySoloPlan));
    if (rawSolo != null && rawSolo.isNotEmpty) {
      try {
        _soloPlan = SoloHikePlan.fromJson(jsonDecode(rawSolo));
      } catch (_) {
        _soloPlan = null;
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// Mengosongkan rencana pendakian & langganan realtime saat berganti akun.
  Future<void> resetForAccountChange() async {
    await unsubscribeAllRealtime();
    _activePlan = null;
    _soloPlan = null;
    _activePlansByGroupId.clear();
    _groupNamesById.clear();
    _cancelledInviteIds.clear();
    _handledStartedKeys.clear();
    _loaded = false;
    _loadedNamespace = null;
    notifyListeners();
    try {
      await load();
    } catch (_) {}
  }

  Future<void> setPlan(GroupHikePlan? plan) async {
    _loadedNamespace = ActiveAccountScope.storageNamespace();
    final prev = _activePlan;
    _activePlan = plan;
    if (plan != null) {
      _soloPlan = null;
      if (plan.isOngoing && !plan.isCancelled) {
        _activePlansByGroupId[plan.groupId] = plan;
      } else {
        _activePlansByGroupId.remove(plan.groupId);
      }
    } else if (prev != null) {
      _activePlansByGroupId.remove(prev.groupId);
    }
    final prefs = await _getPrefs();
    if (plan == null) {
      await prefs.remove(_scopedPlanKey(_keyPlan));
    } else {
      await prefs.setString(_scopedPlanKey(_keyPlan), jsonEncode(plan.toJson()));
      await prefs.remove(_scopedPlanKey(_keySoloPlan));
    }
    notifyListeners();
  }

  Future<void> setSoloPlan(SoloHikePlan? plan) async {
    _loadedNamespace = ActiveAccountScope.storageNamespace();
    _soloPlan = plan;
    final prefs = await _getPrefs();
    if (plan == null) {
      await prefs.remove(_scopedPlanKey(_keySoloPlan));
    } else {
      await prefs.setString(
        _scopedPlanKey(_keySoloPlan),
        jsonEncode(plan.toJson()),
      );
    }
    notifyListeners();
  }

  Future<void> clearSoloPlan() => setSoloPlan(null);

  /// Membersihkan rencana grup lokal bila grupnya sudah tercatat terhapus.
  Future<void> pruneDeletedGroups(Set<String> deletedGroupIds) async {
    for (final gid in deletedGroupIds) {
      _activePlansByGroupId.remove(gid);
    }
    final current = _activePlan;
    if (current == null || !deletedGroupIds.contains(current.groupId)) return;
    await setPlan(null);
  }

  /// Dipanggil otomatis saat sesi tracking pendakian berakhir (baik sampai
  /// puncak maupun dihentikan manual) untuk mereset status persiapan Beranda.
  Future<void> completeAndResetAfterHike() async {
    final current = _activePlan;
    final affectedGroupIds = <String>{};
    if (current != null) {
      _completedInviteIds.add(current.inviteId);
      affectedGroupIds.add(current.groupId);
    }
    for (final entry in _activePlansByGroupId.entries) {
      if (entry.value.isStarted || entry.key == current?.groupId) {
        _completedInviteIds.add(entry.value.inviteId);
        affectedGroupIds.add(entry.key);
      }
    }
    _activePlansByGroupId.clear();
    _activePlan = null;
    _soloPlan = null;
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_scopedPlanKey(_keyPlan));
      await prefs.remove(_scopedPlanKey(_keySoloPlan));
      final capped = _completedInviteIds.length > 50
          ? _completedInviteIds
              .skip(_completedInviteIds.length - 50)
              .toList(growable: false)
          : _completedInviteIds.toList(growable: false);
      await prefs.setStringList(_scopedPlanKey(_keyCompletedInvites), capped);
    } catch (_) {}
    notifyListeners();
    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    for (final gid in affectedGroupIds.where(isValidUuid)) {
      try {
        await client
            .from('group_hike_prep')
            .update(<String, dynamic>{
              'status': 'completed',
              'updated_at': nowIso,
            })
            .eq('group_id', gid)
            .timeout(const Duration(seconds: 9));
      } catch (_) {}
    }
  }

  Future<void> markUserReady(String inviteId, String userId) async {
    var changed = false;
    final byGroupEntry = _activePlansByGroupId.entries
        .where((e) => e.value.inviteId == inviteId)
        .toList(growable: false);
    for (final entry in byGroupEntry) {
      if (!entry.value.readyUserIds.contains(userId)) {
        _activePlansByGroupId[entry.key] = entry.value.copyWith(
          readyUserIds: <String>{...entry.value.readyUserIds, userId},
        );
        changed = true;
      }
    }

    final current = _activePlan;
    if (current != null &&
        current.inviteId == inviteId &&
        !current.readyUserIds.contains(userId)) {
      final updated = current.copyWith(
        readyUserIds: <String>{...current.readyUserIds, userId},
      );
      await setPlan(updated);
      return;
    }
    if (changed) notifyListeners();
  }

  /// Menyimpan 1 baris status persiapan aktif per `group_id` di tabel
  /// `group_hike_prep` (mencegah duplikasi ajakan "Siap").
  Future<GroupHikePlan> upsertRemotePlan(GroupHikePlan plan) async {
    _completedInviteIds.remove(plan.inviteId);
    await setPlan(plan);
    final client = SupabaseServices.clientOrNull;
    if (client == null ||
        client.auth.currentUser == null ||
        !isValidUuid(plan.groupId)) {
      return plan;
    }
    try {
      await client
          .from('group_hike_prep')
          .upsert(
            <String, dynamic>{
              'group_id': plan.groupId,
              'invite_id': plan.inviteId,
              if (isValidUuid(plan.inviteMessageClientId))
                'invite_message_id': plan.inviteMessageClientId,
              'mountain_id': plan.mountainId,
              'mountain_name': plan.mountainName,
              'trail_id': plan.trailId,
              'trail_name': plan.trailName,
              'organizer_user_id': plan.organizerUserId,
              'organizer_name': plan.organizerName,
              'ready_user_ids': plan.readyUserIds.where(isValidUuid).toList(),
              'member_count': plan.memberCount,
              'status': 'active',
              'is_cancelled': false,
              'cancelled_at': null,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'group_id',
          )
          .timeout(const Duration(seconds: 9));
    } catch (_) {
      // Tetap tersimpan secara lokal bila offline atau migrasi belum diterapkan.
    }
    return plan;
  }

  /// Memperbarui kesiapan anggota pada baris `group_hike_prep` yang SAMA
  /// (atomik via RPC `mark_group_hike_ready`) dan mengunci gunung+grup lokal
  /// tanpa mengirim ulang tombol "Siap".
  Future<GroupHikePlan> markReadyRemote(
    GroupHikePlan plan,
    String userId,
  ) async {
    final existing = _activePlan;
    final mergedReady = <String>{
      ...plan.readyUserIds,
      if (existing != null && existing.groupId == plan.groupId)
        ...existing.readyUserIds,
      userId,
    };
    final localUpdated = plan.copyWith(readyUserIds: mergedReady);
    await setPlan(localUpdated);

    final client = SupabaseServices.clientOrNull;
    if (client == null ||
        client.auth.currentUser == null ||
        !isValidUuid(plan.groupId)) {
      return localUpdated;
    }
    try {
      final res = await client.rpc(
        'mark_group_hike_ready',
        params: <String, dynamic>{'p_group_id': plan.groupId},
      ).timeout(const Duration(seconds: 9));
      if (res is Map) {
        final parsed = GroupHikePlan.fromPrepRow(
          Map<String, dynamic>.from(res),
          groupName: plan.groupName,
        );
        if (parsed != null) {
          if (parsed.isCancelled) {
            _cancelledInviteIds.add(parsed.inviteId);
            _activePlansByGroupId.remove(plan.groupId);
            await setPlan(null);
          } else {
            await setPlan(parsed);
          }
          return parsed;
        }
      }
    } catch (_) {
      // Fallback: update langsung jika RPC belum dimigrasi.
      try {
        await client
            .from('group_hike_prep')
            .update(<String, dynamic>{
              'ready_user_ids':
                  localUpdated.readyUserIds.where(isValidUuid).toList(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('group_id', plan.groupId)
            .timeout(const Duration(seconds: 9));
      } catch (_) {}
    }
    return localUpdated;
  }

  /// Membatalkan kesiapan diri sendiri pada baris `group_hike_prep` secara atomik.
  Future<GroupHikePlan> unmarkReadyRemote(
    GroupHikePlan plan,
    String userId,
  ) async {
    final existing = _activePlan;
    final nextReady = <String>{
      ...plan.readyUserIds,
      if (existing != null && existing.groupId == plan.groupId)
        ...existing.readyUserIds,
    }..remove(userId);
    final localUpdated = plan.copyWith(readyUserIds: nextReady);
    _activePlansByGroupId[plan.groupId] = localUpdated;
    await setPlan(localUpdated);

    final client = SupabaseServices.clientOrNull;
    if (client == null ||
        client.auth.currentUser == null ||
        !isValidUuid(plan.groupId)) {
      return localUpdated;
    }
    try {
      final res = await client.rpc(
        'unmark_group_hike_ready',
        params: <String, dynamic>{'p_group_id': plan.groupId},
      ).timeout(const Duration(seconds: 9));
      if (res is Map) {
        final parsed = GroupHikePlan.fromPrepRow(
          Map<String, dynamic>.from(res),
          groupName: plan.groupName,
        );
        if (parsed != null && !parsed.isCancelled) {
          await setPlan(parsed);
          return parsed;
        }
      }
    } catch (_) {
      try {
        await client
            .from('group_hike_prep')
            .update(<String, dynamic>{
              'ready_user_ids':
                  localUpdated.readyUserIds.where(isValidUuid).toList(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('group_id', plan.groupId)
            .timeout(const Duration(seconds: 9));
      } catch (_) {}
    }
    return localUpdated;
  }

  /// Menandai pendakian grup resmi dimulai (`status = 'started'`) agar seluruh
  /// anggota rombongan langsung terbawa ke layar Peta Jalur dalam mode tracking.
  Future<GroupHikePlan> startGroupHikeRemote(
    GroupHikePlan plan, {
    required String startedByUserId,
    String? mountainId,
    String? trailId,
  }) async {
    final now = DateTime.now().toUtc();
    final resolvedMountainId = mountainId?.trim().isNotEmpty == true
        ? mountainId!.trim()
        : plan.mountainId;
    final resolvedTrailId =
        trailId?.trim().isNotEmpty == true ? trailId!.trim() : plan.trailId;
    final startedLocal = plan.copyWith(
      mountainId: resolvedMountainId,
      trailId: resolvedTrailId,
      status: 'started',
      startedAtUtc: now,
      startedByUserId: startedByUserId,
    );
    _handledStartedKeys.add(
      '${plan.groupId}:${plan.inviteId}:${now.millisecondsSinceEpoch}',
    );
    _activePlansByGroupId[plan.groupId] = startedLocal;
    await setPlan(startedLocal);

    final client = SupabaseServices.clientOrNull;
    if (client == null ||
        client.auth.currentUser == null ||
        !isValidUuid(plan.groupId)) {
      return startedLocal;
    }
    try {
      final res = await client
          .rpc(
            'start_group_hike_prep',
            params: <String, dynamic>{
              'p_group_id': plan.groupId,
              if (resolvedMountainId.isNotEmpty)
                'p_mountain_id': resolvedMountainId,
              if (resolvedTrailId != null && resolvedTrailId.isNotEmpty)
                'p_trail_id': resolvedTrailId,
            },
          )
          .timeout(const Duration(seconds: 9));
      if (res is Map) {
        final parsed = GroupHikePlan.fromPrepRow(
          Map<String, dynamic>.from(res),
          groupName: plan.groupName,
        );
        if (parsed != null) {
          _handledStartedKeys.add(
            '${parsed.groupId}:${parsed.inviteId}:${parsed.startedAtUtc?.millisecondsSinceEpoch ?? 0}',
          );
          await setPlan(parsed);
          return parsed;
        }
      }
    } catch (_) {
      try {
        await client
            .from('group_hike_prep')
            .update(<String, dynamic>{
              'status': 'started',
              'started_at': now.toIso8601String(),
              if (isValidUuid(startedByUserId)) 'started_by': startedByUserId,
              'mountain_id': resolvedMountainId,
              if (resolvedTrailId != null) 'trail_id': resolvedTrailId,
              'updated_at': now.toIso8601String(),
            })
            .eq('group_id', plan.groupId)
            .timeout(const Duration(seconds: 9));
      } catch (_) {}
    }
    return startedLocal;
  }

  /// Memuat 1 baris persiapan aktif dari `group_hike_prep` untuk grup tertentu.
  Future<GroupHikePlan?> refreshForGroup(
    String groupId, {
    String? groupName,
  }) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null ||
        client.auth.currentUser == null ||
        !isValidUuid(groupId)) {
      return _activePlan?.groupId == groupId ? _activePlan : null;
    }
    try {
      final row = await client
          .from('group_hike_prep')
          .select()
          .eq('group_id', groupId)
          .maybeSingle()
          .timeout(const Duration(seconds: 9));
      if (row == null) {
        _activePlansByGroupId.remove(groupId);
        if (_activePlan?.groupId == groupId) {
          await setPlan(null);
        } else {
          notifyListeners();
        }
        return null;
      }
      final parsed = GroupHikePlan.fromPrepRow(
        Map<String, dynamic>.from(row),
        groupName: groupName ?? _activePlan?.groupName,
      );
      if (parsed == null) return null;
      if (parsed.isCancelled) {
        _cancelledInviteIds.add(parsed.inviteId);
        _activePlansByGroupId.remove(groupId);
        if (_activePlan?.groupId == groupId) {
          await setPlan(null);
        } else {
          notifyListeners();
        }
        if (parsed.inviteMessageClientId != null &&
            parsed.inviteMessageClientId!.isNotEmpty) {
          await _markLocalInviteMessageCancelled(
            groupId: parsed.groupId,
            clientMsgId: parsed.inviteMessageClientId!,
          );
        }
        return null;
      }
      if (!parsed.isOngoing || _completedInviteIds.contains(parsed.inviteId)) {
        _activePlansByGroupId.remove(groupId);
        if (_activePlan?.groupId == groupId) {
          await setPlan(null);
        } else {
          notifyListeners();
        }
        return null;
      }
      _cancelledInviteIds.remove(parsed.inviteId);
      _activePlansByGroupId[groupId] = parsed;
      await setPlan(parsed);
      if (parsed.isStarted) {
        _maybeEmitHikeStarted(parsed);
      }
      return parsed;
    } catch (_) {
      return _activePlan;
    }
  }

  /// Menyinkronkan status persiapan aktif dari `group_hike_prep` untuk seluruh
  /// grup pengguna (mis. saat User B membuka Siapkan Pendakian atau tab Grup).
  Future<void> refreshForGroups(
    List<String> groupIds, {
    Map<String, String> groupNamesById = const <String, String>{},
  }) async {
    for (final entry in groupNamesById.entries) {
      final name = entry.value.trim();
      if (name.isNotEmpty) _groupNamesById[entry.key] = name;
    }
    final client = SupabaseServices.clientOrNull;
    final uuids = groupIds.where(isValidUuid).toList(growable: false);
    if (client == null || client.auth.currentUser == null || uuids.isEmpty) {
      return;
    }
    try {
      final rows = await client
          .from('group_hike_prep')
          .select()
          .inFilter('group_id', uuids)
          .inFilter('status', const <String>['active', 'started'])
          .order('updated_at', ascending: false)
          .timeout(const Duration(seconds: 9));

      final nextByGroup = <String, GroupHikePlan>{};
      GroupHikePlan? newest;
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final gid = row['group_id']?.toString() ?? '';
        final parsed = GroupHikePlan.fromPrepRow(
          row,
          groupName: groupNamesById[gid] ?? _groupNamesById[gid] ?? _activePlan?.groupName,
        );
        if (parsed != null &&
            parsed.isOngoing &&
            !parsed.isCancelled &&
            !_completedInviteIds.contains(parsed.inviteId)) {
          nextByGroup[gid] = parsed;
          newest ??= parsed;
        }
      }

      for (final gid in uuids) {
        if (nextByGroup.containsKey(gid)) {
          _activePlansByGroupId[gid] = nextByGroup[gid]!;
        } else {
          _activePlansByGroupId.remove(gid);
        }
      }

      if (newest == null) {
        if (_activePlan != null && uuids.contains(_activePlan!.groupId)) {
          await setPlan(null);
          return;
        }
      } else {
        await setPlan(newest);
        if (newest.isStarted) {
          _maybeEmitHikeStarted(newest);
        }
        return;
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Membatalkan rencana pendakian grup aktif pada server dan lokal, sekaligus
  /// memperbarui kartu ajakan di `group_messages` menjadi status dibatalkan.
  Future<void> cancelActivePlanRemote() async {
    final current = _activePlan;
    if (current != null) {
      _cancelledInviteIds.add(current.inviteId);
      _activePlansByGroupId.remove(current.groupId);
    }
    await setPlan(null);
    if (current == null || !isValidUuid(current.groupId)) return;

    if (current.inviteMessageClientId != null &&
        current.inviteMessageClientId!.isNotEmpty) {
      unawaited(
        _markLocalInviteMessageCancelled(
          groupId: current.groupId,
          clientMsgId: current.inviteMessageClientId!,
        ),
      );
    }

    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      await client
          .rpc(
            'cancel_group_hike_prep',
            params: <String, dynamic>{
              'p_group_id': current.groupId,
              'p_invite_id': current.inviteId,
            },
          )
          .timeout(const Duration(seconds: 9));
    } on PostgrestException catch (error) {
      final msg = '${error.message} ${error.details ?? ''}';
      if (error.code == 'PGRST202' ||
          error.code == '42883' ||
          msg.contains('cancel_group_hike_prep')) {
        try {
          await client
              .from('group_hike_prep')
              .update(<String, dynamic>{
                'status': 'cancelled',
                'is_cancelled': true,
                'cancelled_at': nowIso,
                'updated_at': nowIso,
              })
              .eq('group_id', current.groupId)
              .timeout(const Duration(seconds: 9));
        } catch (_) {
          try {
            await client
                .from('group_hike_prep')
                .update(<String, dynamic>{
                  'status': 'cancelled',
                  'updated_at': nowIso,
                })
                .eq('group_id', current.groupId)
                .timeout(const Duration(seconds: 9));
          } catch (_) {}
        }
        if (isValidUuid(current.inviteMessageClientId)) {
          try {
            await client
                .from('group_messages')
                .update(<String, dynamic>{
                  'is_cancelled': true,
                  'cancelled_at': nowIso,
                })
                .eq('group_id', current.groupId)
                .eq('client_id', current.inviteMessageClientId!)
                .timeout(const Duration(seconds: 9));
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
