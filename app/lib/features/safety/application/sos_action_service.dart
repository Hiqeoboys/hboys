import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/utils/safe_url_launcher.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/offgrid/android_off_grid_adapter.dart';
import '../../../infrastructure/offgrid/mesh_packet_codec.dart';
import '../../../infrastructure/offgrid/off_grid_chat_local_store.dart';
import '../../../infrastructure/power/device_battery_reader.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../chat/domain/group_chat_models.dart';
import '../../preparation/application/packing_list_store.dart';
import '../../tracking/application/tracking_controller.dart';
import '../domain/emergency_contact.dart';
import '../domain/safety_repository.dart';
import '../domain/sos_category.dart';
import 'sos_location.dart';
import 'sos_offline_queue_service.dart';
import 'sos_sms_service.dart';

/// Satu langkah pulsa Morse SOS (`· · · — — — · · ·`).
class SosMorseStep {
  const SosMorseStep({required this.on, required this.duration});

  final bool on;
  final Duration duration;
}

/// Pola standar ITU Morse SOS: `· · · — — — · · ·` lalu jeda sebelum berulang.
const List<SosMorseStep> kSosMorsePattern = <SosMorseStep>[
  // S (· · ·)
  SosMorseStep(on: true, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: false, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: true, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: false, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: true, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: false, duration: Duration(milliseconds: 450)),
  // O (— — —)
  SosMorseStep(on: true, duration: Duration(milliseconds: 600)),
  SosMorseStep(on: false, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: true, duration: Duration(milliseconds: 600)),
  SosMorseStep(on: false, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: true, duration: Duration(milliseconds: 600)),
  SosMorseStep(on: false, duration: Duration(milliseconds: 450)),
  // S (· · ·)
  SosMorseStep(on: true, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: false, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: true, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: false, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: true, duration: Duration(milliseconds: 200)),
  SosMorseStep(on: false, duration: Duration(milliseconds: 1200)),
];

/// Format pesan darurat SOS yang dikirim ke kontak darurat, SMS & grup.
String formatSosEmergencyMessage({
  required String senderName,
  required SosFix? fix,
  required String? mountainName,
  required int? batteryPercent,
  required SosCategory category,
}) {
  final categoryLabel = switch (category) {
    SosCategory.injury => 'Cedera',
    SosCategory.lost => 'Tersesat',
    SosCategory.weather => 'Cuaca ekstrem',
    SosCategory.medical => 'Medis',
    SosCategory.other => 'Darurat',
  };
  final mountain =
      (mountainName != null && mountainName.trim().isNotEmpty)
          ? mountainName.trim()
          : 'Lokasi saat ini';
  final coords = fix != null
      ? '${fix.lat.toStringAsFixed(5)}, ${fix.lon.toStringAsFixed(5)} '
          '(https://maps.google.com/?q=${fix.lat.toStringAsFixed(5)},${fix.lon.toStringAsFixed(5)})'
      : 'Koordinat GPS belum tersedia';
  final elev = fix?.altitudeM != null
      ? '${fix!.altitudeM!.round()} mdpl'
      : 'Tidak diketahui';
  final bat = batteryPercent != null ? '$batteryPercent%' : 'Tidak diketahui';
  return '🚨 DARURAT SOS HIQEO\n'
      'Pendaki: $senderName\n'
      'Gunung: $mountain\n'
      'Koordinat: $coords\n'
      'Elevasi: $elev\n'
      'Baterai: $bat\n'
      'Kategori: $categoryLabel';
}

/// URI SMS darurat untuk iOS atau fallback ketika izin `SEND_SMS` belum aktif.
Uri buildEmergencySmsUri(List<String> phones, String body) {
  final phonePattern = RegExp(r'^\+?[0-9]{6,16}$');
  final cleaned = phones
      .map((p) => p.trim())
      .where((p) => phonePattern.hasMatch(p))
      .toList(growable: false);
  return Uri(
    scheme: 'sms',
    path: cleaned.join(','),
    queryParameters: <String, String>{'body': body},
  );
}

class SosDispatchOutcome {
  const SosDispatchOutcome({
    this.flashlightActive = false,
    this.sirenActive = false,
    this.isOnline = false,
    this.savedRemoteUpsert = false,
    this.queuedForServerSync = false,
    this.sentGroupMessage = false,
    this.sentMeshBroadcast = false,
    this.notifiedEmergencyContacts = false,
    this.sentDirectSms = false,
    this.directSmsSentCount = 0,
    this.directSmsTargetCount = 0,
    this.smsPermissionDenied = false,
    this.openedOfflineSms = false,
    this.whatsappConfigured = false,
    this.whatsappAutoSent = false,
    this.hasPhoneEmergencyContacts = false,
    this.remoteSosId,
    this.batteryPercent,
    this.mountainName,
    this.emergencyMessage,
  });

  final bool flashlightActive;
  final bool sirenActive;
  final bool isOnline;
  final bool savedRemoteUpsert;
  final bool queuedForServerSync;
  final bool sentGroupMessage;
  final bool sentMeshBroadcast;
  final bool notifiedEmergencyContacts;
  final bool sentDirectSms;
  final int directSmsSentCount;
  final int directSmsTargetCount;
  final bool smsPermissionDenied;
  final bool openedOfflineSms;
  final bool whatsappConfigured;
  final bool whatsappAutoSent;
  final bool hasPhoneEmergencyContacts;
  final String? remoteSosId;
  final int? batteryPercent;
  final String? mountainName;
  final String? emergencyMessage;
}

abstract interface class SosActionRunner {
  /// Menjalankan seluruh aksi SOS secara paralel: senter Morse, sirene volume
  /// maksimal, 1 UPSERT atau antrean sinkronisasi server, grup/Mesh, & SMS/WA.
  Future<SosDispatchOutcome> activate({
    required String sosUuid,
    required SosFix? fix,
    required SosCategory category,
    required DateTime triggeredAtUtc,
    SafetyRepository? safetyRepository,
  });

  /// Mematikan senter, sirene, menandai batal di antrean, & memperbarui server.
  Future<void> deactivate({String? remoteSosId});
}

/// Implementasi produksi perangkat (Android/iOS) untuk aksi SOS penuh
/// dengan dukungan zero-click SMS (`SmsManager`), antrean sinkronisasi offline,
/// siaran Hiqeo Mesh, dan hook WhatsApp Business Cloud API.
class DeviceSosActionRunner implements SosActionRunner {
  DeviceSosActionRunner({
    SosSmsSender? smsSender,
    SosOfflineQueueService? offlineQueue,
    Future<bool> Function()? onlineChecker,
    Future<bool> Function(Uri uri)? urlLauncher,
    Future<({bool configured, bool sent})> Function(
      String sosUuid,
      String message,
      List<String> phones,
    )? whatsappInvoker,
    Future<bool> Function(Map<String, dynamic> payload)? remoteSosUpserter,
    Future<bool> Function(GroupMessageRecord message)? groupMessageSender,
    Future<bool> Function({
      required String groupId,
      required MeshSosPayload payload,
    })? meshBroadcaster,
    Future<int?> Function()? batteryLevelReader,
    String Function()? senderNameResolver,
    String Function()? ownerIdResolver,
    String? Function()? activeGroupIdResolver,
    String? Function()? mountainNameResolver,
    bool enableDeviceHardware = true,
  })  : _smsSender = smsSender ?? const MethodChannelSosSmsSender(),
        _offlineQueue = offlineQueue ?? SosOfflineQueueService.instance,
        _onlineChecker = onlineChecker,
        _urlLauncher = urlLauncher ?? launchSafeExternalUrl,
        _whatsappInvoker = whatsappInvoker,
        _remoteSosUpserter = remoteSosUpserter,
        _groupMessageSender = groupMessageSender,
        _meshBroadcaster = meshBroadcaster,
        _batteryLevelReader = batteryLevelReader,
        _senderNameResolver = senderNameResolver,
        _ownerIdResolver = ownerIdResolver,
        _activeGroupIdResolver = activeGroupIdResolver,
        _mountainNameResolver = mountainNameResolver,
        _enableDeviceHardware = enableDeviceHardware;

  static const MethodChannel _hardwareChannel =
      MethodChannel('id.nama.nama_app/sos_hardware');
  static const String _sirenAssetPath = 'assets/audio/sos_siren.wav';
  static const String _fallbackMeshGroupId = 'hiqeo-sos-public';

  final SosSmsSender _smsSender;
  final SosOfflineQueueService _offlineQueue;
  final Future<bool> Function()? _onlineChecker;
  final Future<bool> Function(Uri uri) _urlLauncher;
  final Future<({bool configured, bool sent})> Function(
    String sosUuid,
    String message,
    List<String> phones,
  )? _whatsappInvoker;
  final Future<bool> Function(Map<String, dynamic> payload)? _remoteSosUpserter;
  final Future<bool> Function(GroupMessageRecord message)? _groupMessageSender;
  final Future<bool> Function({
    required String groupId,
    required MeshSosPayload payload,
  })? _meshBroadcaster;
  final Future<int?> Function()? _batteryLevelReader;
  final String Function()? _senderNameResolver;
  final String Function()? _ownerIdResolver;
  final String? Function()? _activeGroupIdResolver;
  final String? Function()? _mountainNameResolver;
  final bool _enableDeviceHardware;

  AudioPlayer? _sirenPlayer;
  int _morseRunId = 0;
  bool _morseRunning = false;

  bool get _supportsHardwareChannel =>
      _enableDeviceHardware &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<SosDispatchOutcome> activate({
    required String sosUuid,
    required SosFix? fix,
    required SosCategory category,
    required DateTime triggeredAtUtc,
    SafetyRepository? safetyRepository,
  }) async {
    // 1. Senter Morse & Sirene 100% offline selalu langsung berjalan pertama.
    final flashlightFuture = _enableDeviceHardware
        ? _startMorseFlashlight()
        : Future<bool>.value(false);
    final sirenFuture = _enableDeviceHardware
        ? _startMaxVolumeSiren()
        : Future<bool>.value(false);

    // 2. Kumpulkan konteks nyata (baterai, gunung, nama pendaki, grup, koneksi).
    int? batteryPercent;
    try {
      batteryPercent = _batteryLevelReader != null
          ? await _batteryLevelReader()
          : await DeviceBatteryReader().levelPercent();
    } catch (_) {}

    final planStore = GroupHikePlanStore.instance;
    final mountainName = _mountainNameResolver != null
        ? _mountainNameResolver()
        : (TrackingController.instance.activeMountainName ??
            planStore.activePlan?.mountainName ??
            planStore.soloPlan?.mountainName);

    final account = SupabaseServices.sharedAccountController;
    final client = SupabaseServices.clientOrNull;
    final authUser = client?.auth.currentUser;
    final senderId = _ownerIdResolver != null
        ? _ownerIdResolver()
        : (authUser?.id ?? account?.user?.id ?? 'perangkat-lokal');

    final String senderName;
    if (_senderNameResolver != null) {
      senderName = _senderNameResolver();
    } else if (account?.profile?.fullName?.trim().isNotEmpty == true) {
      senderName = account!.profile!.fullName!.trim();
    } else if (account?.profile?.username?.trim().isNotEmpty == true) {
      senderName = '@${account!.profile!.username!.trim()}';
    } else if (account?.user?.displayName?.trim().isNotEmpty == true) {
      senderName = account!.user!.displayName!.trim();
    } else {
      senderName = 'Pendaki';
    }

    final activeGroupId = _activeGroupIdResolver != null
        ? _activeGroupIdResolver()
        : (planStore.activePlan?.groupId ??
            (account != null && account.groups.isNotEmpty
                ? account.groups.first.group.id
                : null));

    final emergencyMessage = formatSosEmergencyMessage(
      senderName: senderName,
      fix: fix,
      mountainName: mountainName,
      batteryPercent: batteryPercent,
      category: category,
    );

    final isOnline = _onlineChecker != null
        ? await _onlineChecker()
        : await _checkOnline();

    final phoneContacts = await _loadActivePhoneContacts(
      ownerId: authUser?.id ?? senderId,
      safetyRepository: safetyRepository,
    );
    final phones = phoneContacts
        .map((c) => c.phoneE164.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);

    // 3. Jalankan seluruh kanal darurat paralel tanpa menahan senter & sirene.
    var savedRemoteUpsert = false;
    var queuedForServerSync = false;
    var sentGroupMessage = false;
    var sentMeshBroadcast = false;
    var notifiedEmergencyContacts = false;
    var sentDirectSms = false;
    var directSmsSentCount = 0;
    var smsPermissionDenied = false;
    var openedOfflineSms = false;
    var whatsappConfigured = false;
    var whatsappAutoSent = false;

    final dispatchFutures = <Future<void>>[
      // (a) Server `sos_events` UPSERT (online) atau masuk antrean sinkronisasi lokal.
      () async {
        if (fix == null) return;
        final canAttemptUpsert = _remoteSosUpserter != null ||
            (client != null && authUser != null);

        if (isOnline && canAttemptUpsert) {
          final payload = <String, dynamic>{
            'id': sosUuid,
            'author_id': authUser?.id ?? senderId,
            if (activeGroupId != null && isValidUuid(activeGroupId))
              'group_id': activeGroupId,
            'category': category.index,
            'lat': fix.lat,
            'lon': fix.lon,
            if (fix.accuracyM != null) 'accuracy_m': fix.accuracyM,
            if (fix.altitudeM != null) 'altitude_m': fix.altitudeM,
            if (batteryPercent != null) 'battery_pct': batteryPercent,
            if (mountainName != null && mountainName.trim().isNotEmpty)
              'mountain_name': mountainName.trim(),
            'message': emergencyMessage,
            'created_at': triggeredAtUtc.toUtc().toIso8601String(),
            'status': 'active',
          };
          try {
            if (_remoteSosUpserter != null) {
              savedRemoteUpsert = await _remoteSosUpserter(payload);
            } else if (client != null) {
              await client
                  .from('sos_events')
                  .upsert(payload, onConflict: 'id')
                  .timeout(const Duration(seconds: 8));
              savedRemoteUpsert = true;
            }
          } catch (_) {
            savedRemoteUpsert = false;
          }
          if (savedRemoteUpsert) {
            notifiedEmergencyContacts = true;
            return;
          }
        }

        // Offline atau unggah server gagal -> simpan ke antrean sinkronisasi lokal.
        await _offlineQueue.enqueue(
          PendingSosSyncItem(
            sosUuid: sosUuid,
            authorId: authUser?.id ?? senderId,
            groupId: activeGroupId,
            categoryIndex: category.index,
            lat: fix.lat,
            lon: fix.lon,
            accuracyM: fix.accuracyM,
            altitudeM: fix.altitudeM,
            batteryPercent: batteryPercent,
            mountainName: mountainName?.trim(),
            senderName: senderName,
            message: emergencyMessage,
            createdAtUtc: triggeredAtUtc.toUtc(),
            queuedAtUtc: DateTime.now().toUtc(),
          ),
        );
        queuedForServerSync = true;
      }(),

      // (b) Ruang Obrolan Grup (online) & Siaran Hiqeo Mesh (offline/fallback).
      () async {
        final sosChatClientMsgId = normalizeToUuid('sos-$sosUuid');
        if (activeGroupId != null && activeGroupId.isNotEmpty) {
          final msgRecord = GroupMessageRecord(
            clientMsgId: sosChatClientMsgId,
            groupId: activeGroupId,
            senderId: senderId,
            senderName: senderName,
            messageType: GroupMessageType.text,
            content: emergencyMessage,
            originTransport: isOnline
                ? ChatTransportOrigin.online
                : ChatTransportOrigin.bleMesh,
            syncStatus: ChatSyncStatus.pending,
            clientCreatedAtUtc: triggeredAtUtc,
          );

          if (_groupMessageSender == null) {
            AppDatabase? db;
            try {
              db = openAppDatabase(await defaultAppDatabaseFile());
              final localStore = OffGridChatLocalStore(database: db);
              await localStore.insertMessageIfAbsent(msgRecord);
            } catch (_) {
            } finally {
              await db?.close();
            }
          }

          if (isOnline) {
            try {
              if (_groupMessageSender != null) {
                sentGroupMessage = await _groupMessageSender(msgRecord);
              } else {
                final chatRemote =
                    SupabaseServices.createGroupChatRemoteService();
                if (chatRemote != null && isValidUuid(activeGroupId)) {
                  await chatRemote
                      .upsertMessage(msgRecord)
                      .timeout(const Duration(seconds: 6));
                  sentGroupMessage = true;
                }
              }
            } catch (_) {
              sentGroupMessage = false;
            }
          }
        }

        if ((!isOnline || !sentGroupMessage) && fix != null) {
          final targetMeshGroup =
              (activeGroupId != null && activeGroupId.isNotEmpty)
                  ? activeGroupId
                  : _fallbackMeshGroupId;
          final sosPayload = MeshSosPayload(
            clientMsgId: sosChatClientMsgId,
            groupId: targetMeshGroup,
            senderId: senderId,
            senderName: senderName,
            lat: fix.lat,
            lon: fix.lon,
            altitudeMdpl: fix.altitudeM?.round(),
            batteryPercent: batteryPercent,
            category: category.name,
            createdAtUtc: triggeredAtUtc,
          );

          try {
            if (_meshBroadcaster != null) {
              sentMeshBroadcast = await _meshBroadcaster(
                groupId: targetMeshGroup,
                payload: sosPayload,
              );
            } else if (!kIsWeb && Platform.isAndroid) {
              final adapter = AndroidOffGridAdapter();
              final codec = MeshPacketCodec();
              final groupHash =
                  await MeshPacketCodec.groupHashHexFor(targetMeshGroup);
              await adapter.start(
                groupHashHex: groupHash,
                highDuty: true,
                useForegroundService: true,
              );
              final envelope = MeshEnvelope(
                kind: MeshPayloadKind.sosSignal,
                clientMsgId: sosChatClientMsgId,
                groupId: targetMeshGroup,
                keyVersion: 1,
                ttl: MeshPacketCodec.maxTtl,
                sosSignal: sosPayload,
              );
              final chunks = await codec.encodeAndChunk(envelope);
              for (final chunk in chunks) {
                await adapter.sendPacket(chunk);
              }
              sentMeshBroadcast = true;
            }
          } catch (_) {
            sentMeshBroadcast = false;
          }
        }
      }(),

      // (c) Zero-Click Native SMS (Android SmsManager, online & offline) + iOS fallback.
      () async {
        if (phones.isEmpty) return;
        if (_smsSender.isSupported) {
          try {
            final batch = await _smsSender.sendSmsBatch(
              phones: phones,
              message: emergencyMessage,
            );
            if (batch.anySent) {
              sentDirectSms = true;
              directSmsSentCount = batch.sentCount;
              notifiedEmergencyContacts = true;
              return;
            }
            smsPermissionDenied = batch.permissionDenied;
          } catch (_) {}

          // Fallback bila izin SEND_SMS ditolak saat offline.
          if (!isOnline) {
            try {
              final launched = await _urlLauncher(
                buildEmergencySmsUri(phones, emergencyMessage),
              );
              if (launched) {
                openedOfflineSms = true;
                notifiedEmergencyContacts = true;
              }
            } catch (_) {}
          }
        } else if (!isOnline) {
          // iOS melarang SMS senyap: buka sheet SMS otomatis berisi isi lengkap.
          try {
            final launched = await _urlLauncher(
              buildEmergencySmsUri(phones, emergencyMessage),
            );
            if (launched) {
              openedOfflineSms = true;
              notifiedEmergencyContacts = true;
            }
          } catch (_) {}
        }
      }(),

      // (d) Hook WhatsApp otomatis non-blocking (hanya saat online).
      () async {
        if (!isOnline || phones.isEmpty) return;
        try {
          if (_whatsappInvoker != null) {
            final res = await _whatsappInvoker(
              sosUuid,
              emergencyMessage,
              phones,
            ).timeout(const Duration(seconds: 4));
            whatsappConfigured = res.configured;
            if (res.sent) {
              whatsappAutoSent = true;
              notifiedEmergencyContacts = true;
            }
            return;
          }
          if (client != null && authUser != null) {
            final response = await client.functions
                .invoke(
                  'send-sos-whatsapp',
                  body: <String, dynamic>{
                    'sos_id': sosUuid,
                    'message': emergencyMessage,
                  },
                )
                .timeout(const Duration(seconds: 4));
            final data = response.data;
            if (data is Map && data['configured'] == true) {
              whatsappConfigured = true;
              final sent = (data['sent'] as num?)?.toInt() ?? 0;
              if (sent > 0) {
                whatsappAutoSent = true;
                notifiedEmergencyContacts = true;
              }
            }
          }
        } catch (_) {
          // Tidak pernah memblokir SMS zero-click atau perangkat keras SOS.
        }
      }(),
    ];

    final results = await Future.wait<Object?>(<Future<Object?>>[
      flashlightFuture,
      sirenFuture,
      Future.wait<void>(dispatchFutures),
    ]);

    return SosDispatchOutcome(
      flashlightActive: results[0] == true,
      sirenActive: results[1] == true,
      isOnline: isOnline,
      savedRemoteUpsert: savedRemoteUpsert,
      queuedForServerSync: queuedForServerSync,
      sentGroupMessage: sentGroupMessage,
      sentMeshBroadcast: sentMeshBroadcast,
      notifiedEmergencyContacts: notifiedEmergencyContacts,
      sentDirectSms: sentDirectSms,
      directSmsSentCount: directSmsSentCount,
      directSmsTargetCount: phones.length,
      smsPermissionDenied: smsPermissionDenied,
      openedOfflineSms: openedOfflineSms,
      whatsappConfigured: whatsappConfigured,
      whatsappAutoSent: whatsappAutoSent,
      hasPhoneEmergencyContacts: phones.isNotEmpty,
      remoteSosId: savedRemoteUpsert ? sosUuid : null,
      batteryPercent: batteryPercent,
      mountainName: mountainName,
      emergencyMessage: emergencyMessage,
    );
  }

  @override
  Future<void> deactivate({String? remoteSosId}) async {
    _morseRunning = false;
    _morseRunId++;
    if (_enableDeviceHardware) {
      await _setTorch(false);
      try {
        await _sirenPlayer?.stop();
        await _sirenPlayer?.dispose();
      } catch (_) {}
      _sirenPlayer = null;
      try {
        if (_supportsHardwareChannel) {
          await _hardwareChannel.invokeMethod<void>('restoreVolume');
        }
      } catch (_) {}
    }

    if (remoteSosId != null && remoteSosId.isNotEmpty) {
      final nowUtc = DateTime.now().toUtc();
      await _offlineQueue.markCancelled(remoteSosId, nowUtc);
      if (isValidUuid(remoteSosId)) {
        final client = SupabaseServices.clientOrNull;
        if (client != null && client.auth.currentUser != null) {
          try {
            await client.from('sos_events').update(<String, dynamic>{
              'status': 'cancelled',
              'cancelled_at': nowUtc.toIso8601String(),
            }).eq('id', remoteSosId);
          } catch (_) {}
        }
      }
    }
  }

  Future<bool> _checkOnline() async {
    try {
      final res = await Connectivity().checkConnectivity();
      return res.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<List<EmergencyContact>> _loadActivePhoneContacts({
    required String ownerId,
    SafetyRepository? safetyRepository,
  }) async {
    if (safetyRepository == null) return const <EmergencyContact>[];
    bool isPhoneGranted(EmergencyContact c) =>
        !c.isHiqeoAccount &&
        c.consentStatus == EmergencyContactConsentStatus.granted &&
        c.phoneE164.trim().isNotEmpty;

    try {
      final list = await safetyRepository.contactsOf(ownerId);
      final granted = list.where(isPhoneGranted).toList(growable: false);
      if (granted.isNotEmpty || ownerId == 'perangkat-lokal') return granted;
      final localList = await safetyRepository.contactsOf('perangkat-lokal');
      return localList.where(isPhoneGranted).toList(growable: false);
    } catch (_) {
      return const <EmergencyContact>[];
    }
  }

  Future<bool> _setTorch(bool enabled) async {
    if (!_supportsHardwareChannel) return false;
    try {
      return await _hardwareChannel.invokeMethod<bool>(
            'setTorch',
            <String, dynamic>{'enabled': enabled},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _startMorseFlashlight() async {
    final ok = await _setTorch(true);
    if (!ok) return false;
    _morseRunning = true;
    final runId = ++_morseRunId;
    unawaited(_runMorseLoop(runId));
    return true;
  }

  Future<void> _runMorseLoop(int runId) async {
    try {
      while (_morseRunning && _morseRunId == runId) {
        for (final step in kSosMorsePattern) {
          if (!_morseRunning || _morseRunId != runId) break;
          await _setTorch(step.on);
          await Future<void>.delayed(step.duration);
        }
      }
    } finally {
      await _setTorch(false);
    }
  }

  Future<bool> _startMaxVolumeSiren() async {
    try {
      if (_supportsHardwareChannel) {
        await _hardwareChannel.invokeMethod<void>('setMaxVolume');
      }
      // On iOS, keep SosHardwareHandler's .playback AVAudioSession active so the silent switch stays bypassed.
      final player = AudioPlayer(
        handleAudioSessionActivation: defaultTargetPlatform != TargetPlatform.iOS,
      );
      _sirenPlayer = player;
      await player.setAsset(_sirenAssetPath);
      await player.setLoopMode(LoopMode.one);
      await player.setVolume(1.0);
      unawaited(player.play());
      return true;
    } catch (_) {
      return false;
    }
  }
}
