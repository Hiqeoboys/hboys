import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../infrastructure/supabase/supabase_services.dart';
import '../../chat/domain/group_chat_models.dart';

@immutable
class PendingSosSyncItem {
  const PendingSosSyncItem({
    required this.sosUuid,
    required this.authorId,
    required this.categoryIndex,
    required this.lat,
    required this.lon,
    required this.message,
    required this.createdAtUtc,
    required this.queuedAtUtc,
    this.groupId,
    this.accuracyM,
    this.altitudeM,
    this.batteryPercent,
    this.mountainName,
    this.senderName,
    this.status = 'active',
    this.cancelledAtUtc,
  });

  final String sosUuid;
  final String authorId;
  final String? groupId;
  final int categoryIndex;
  final double lat;
  final double lon;
  final int? accuracyM;
  final double? altitudeM;
  final int? batteryPercent;
  final String? mountainName;
  final String? senderName;
  final String message;
  final DateTime createdAtUtc;
  final DateTime queuedAtUtc;
  final String status;
  final DateTime? cancelledAtUtc;

  PendingSosSyncItem copyWith({
    String? status,
    DateTime? cancelledAtUtc,
  }) =>
      PendingSosSyncItem(
        sosUuid: sosUuid,
        authorId: authorId,
        groupId: groupId,
        categoryIndex: categoryIndex,
        lat: lat,
        lon: lon,
        accuracyM: accuracyM,
        altitudeM: altitudeM,
        batteryPercent: batteryPercent,
        mountainName: mountainName,
        senderName: senderName,
        message: message,
        createdAtUtc: createdAtUtc,
        queuedAtUtc: queuedAtUtc,
        status: status ?? this.status,
        cancelledAtUtc: cancelledAtUtc ?? this.cancelledAtUtc,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sosUuid': sosUuid,
        'authorId': authorId,
        'groupId': groupId,
        'categoryIndex': categoryIndex,
        'lat': lat,
        'lon': lon,
        'accuracyM': accuracyM,
        'altitudeM': altitudeM,
        'batteryPercent': batteryPercent,
        'mountainName': mountainName,
        'senderName': senderName,
        'message': message,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'queuedAtUtc': queuedAtUtc.toUtc().toIso8601String(),
        'status': status,
        'cancelledAtUtc': cancelledAtUtc?.toUtc().toIso8601String(),
      };

  static PendingSosSyncItem? fromJson(Map<String, dynamic> map) {
    final id = map['sosUuid']?.toString().trim() ?? '';
    final lat = (map['lat'] as num?)?.toDouble();
    final lon = (map['lon'] as num?)?.toDouble();
    if (id.isEmpty || lat == null || lon == null) return null;
    return PendingSosSyncItem(
      sosUuid: id,
      authorId: map['authorId']?.toString() ?? 'perangkat-lokal',
      groupId: map['groupId']?.toString(),
      categoryIndex: (map['categoryIndex'] as num?)?.toInt() ?? 4,
      lat: lat,
      lon: lon,
      accuracyM: (map['accuracyM'] as num?)?.toInt(),
      altitudeM: (map['altitudeM'] as num?)?.toDouble(),
      batteryPercent: (map['batteryPercent'] as num?)?.toInt(),
      mountainName: map['mountainName']?.toString(),
      senderName: map['senderName']?.toString(),
      message: map['message']?.toString() ?? '',
      createdAtUtc:
          DateTime.tryParse(map['createdAtUtc']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      queuedAtUtc:
          DateTime.tryParse(map['queuedAtUtc']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      status: map['status']?.toString() ?? 'active',
      cancelledAtUtc:
          DateTime.tryParse(map['cancelledAtUtc']?.toString() ?? '')?.toUtc(),
    );
  }
}

/// Antrean sinkronisasi SOS otomatis berbasis `SharedPreferences`.
///
/// Menyimpan kejadian SOS yang dipicu saat perangkat offline, lalu segera
/// mengunggahnya ke Supabase `sos_events` begitu sinyal internet kembali agar
/// kontak darurat online segera menerima push notification prioritas tinggi.
class SosOfflineQueueService extends ChangeNotifier {
  SosOfflineQueueService._({bool persist = true}) : _persist = persist;

  static final SosOfflineQueueService instance = SosOfflineQueueService._();

  @visibleForTesting
  factory SosOfflineQueueService.forTesting({bool persist = false}) =>
      SosOfflineQueueService._(persist: persist);

  static const String _storageKey = 'hiqeo_pending_sos_queue_v1';

  final bool _persist;
  List<PendingSosSyncItem> _items = <PendingSosSyncItem>[];
  final Set<String> _recentlySyncedIds = <String>{};
  bool _loaded = false;
  bool _flushing = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  List<PendingSosSyncItem> get pendingItems =>
      List<PendingSosSyncItem>.unmodifiable(_items);

  bool isPending(String sosUuid) =>
      _items.any((item) => item.sosUuid == sosUuid);

  bool wasSynced(String sosUuid) => _recentlySyncedIds.contains(sosUuid);

  Future<void> load() async {
    if (_loaded || !_persist) {
      _loaded = true;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _items = decoded
              .whereType<Map>()
              .map(
                (m) => PendingSosSyncItem.fromJson(Map<String, dynamic>.from(m)),
              )
              .whereType<PendingSosSyncItem>()
              .toList();
        }
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    if (!_persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(
        _items.map((e) => e.toJson()).toList(growable: false),
      );
      await prefs.setString(_storageKey, payload);
    } catch (_) {}
  }

  Future<void> enqueue(PendingSosSyncItem item) async {
    await load();
    _recentlySyncedIds.remove(item.sosUuid);
    _items.removeWhere((e) => e.sosUuid == item.sosUuid);
    _items.add(item);
    notifyListeners();
    await _save();
  }

  Future<void> markCancelled(String sosUuid, DateTime cancelledAtUtc) async {
    await load();
    var updated = false;
    _items = _items.map((item) {
      if (item.sosUuid != sosUuid) return item;
      updated = true;
      return item.copyWith(
        status: 'cancelled',
        cancelledAtUtc: cancelledAtUtc.toUtc(),
      );
    }).toList();
    if (updated) {
      notifyListeners();
      await _save();
    }
  }

  void startConnectivityAutoSync() {
    if (_connectivitySub != null) return;
    try {
      _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
        if (results.any((r) => r != ConnectivityResult.none)) {
          unawaited(flushPending());
        }
      });
    } catch (_) {}
  }

  Future<int> flushPending({
    Future<bool> Function(PendingSosSyncItem item)? uploaderOverride,
    Future<bool> Function()? connectivityCheckOverride,
  }) async {
    await load();
    if (_flushing || _items.isEmpty) return 0;
    _flushing = true;
    var syncedCount = 0;

    try {
      final online = connectivityCheckOverride != null
          ? await connectivityCheckOverride()
          : await _hasNetwork();
      if (!online) return 0;

      final remaining = <PendingSosSyncItem>[];
      for (final item in List<PendingSosSyncItem>.of(_items)) {
        final ok = uploaderOverride != null
            ? await uploaderOverride(item)
            : await _uploadToSupabase(item);
        if (ok) {
          syncedCount++;
          _recentlySyncedIds.add(item.sosUuid);
        } else {
          remaining.add(item);
        }
      }
      _items = remaining;
      if (syncedCount > 0) {
        await _save();
        notifyListeners();
      }
    } finally {
      _flushing = false;
    }
    return syncedCount;
  }

  Future<bool> _hasNetwork() async {
    try {
      final res = await Connectivity().checkConnectivity();
      return res.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _uploadToSupabase(PendingSosSyncItem item) async {
    final client = SupabaseServices.clientOrNull;
    final authUser = client?.auth.currentUser;
    if (client == null || authUser == null) return false;
    final groupId = item.groupId;
    final hasValidGroup = groupId != null && isValidUuid(groupId);
    try {
      await client.from('sos_events').upsert(
        <String, dynamic>{
          'id': item.sosUuid,
          'author_id': authUser.id,
          if (hasValidGroup) 'group_id': groupId,
          'category': item.categoryIndex,
          'lat': item.lat,
          'lon': item.lon,
          if (item.accuracyM != null) 'accuracy_m': item.accuracyM,
          if (item.altitudeM != null) 'altitude_m': item.altitudeM,
          if (item.batteryPercent != null) 'battery_pct': item.batteryPercent,
          if (item.mountainName != null && item.mountainName!.trim().isNotEmpty)
            'mountain_name': item.mountainName!.trim(),
          'message': item.message,
          'created_at': item.createdAtUtc.toUtc().toIso8601String(),
          'status': item.status,
          if (item.cancelledAtUtc != null)
            'cancelled_at': item.cancelledAtUtc!.toUtc().toIso8601String(),
        },
        onConflict: 'id',
      ).timeout(const Duration(seconds: 8));

      if (hasValidGroup && item.status == 'active') {
        try {
          final chatRemote = SupabaseServices.createGroupChatRemoteService();
          if (chatRemote != null) {
            await chatRemote
                .upsertMessage(
                  GroupMessageRecord(
                    clientMsgId: normalizeToUuid('sos-${item.sosUuid}'),
                    groupId: groupId,
                    senderId: authUser.id,
                    senderName: item.senderName ?? 'Pendaki',
                    messageType: GroupMessageType.text,
                    content: item.message,
                    originTransport: ChatTransportOrigin.bleMesh,
                    syncStatus: ChatSyncStatus.sent,
                    clientCreatedAtUtc: item.createdAtUtc,
                  ),
                )
                .timeout(const Duration(seconds: 8));
          }
        } catch (_) {}
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disposeListener() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }
}
