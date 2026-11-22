import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'off_grid_transport_adapter.dart';

/// Implementasi [OffGridTransportAdapter] untuk Android (API 26..36+, Android 12-15+)
/// yang berkomunikasi dengan [HiqeoOffGridPlugin] via MethodChannel & EventChannel,
/// serta menangani runtime permissions BLE, Wi-Fi Direct (`NEARBY_WIFI_DEVICES`),
/// lokasi, dan mikrofon (`RECORD_AUDIO`).
class AndroidOffGridAdapter implements OffGridTransportAdapter {
  AndroidOffGridAdapter({
    MethodChannel? methodChannel,
    EventChannel? packetsChannel,
    EventChannel? audioChannel,
    EventChannel? peersChannel,
  })  : _method = methodChannel ??
            const MethodChannel('id.nama.nama_app/offgrid_method'),
        _packetsChannel = packetsChannel ??
            const EventChannel('id.nama.nama_app/offgrid_packets'),
        _audioChannel = audioChannel ??
            const EventChannel('id.nama.nama_app/offgrid_audio'),
        _peersChannel = peersChannel ??
            const EventChannel('id.nama.nama_app/offgrid_peers');

  final MethodChannel _method;
  final EventChannel _packetsChannel;
  final EventChannel _audioChannel;
  final EventChannel _peersChannel;

  Stream<Uint8List>? _packetStream;
  Stream<OffGridAudioPacket>? _audioStream;
  Stream<int>? _peerStream;

  /// Meminta seluruh izin runtime Android 12–15+ untuk BLE Mesh, Wi-Fi Direct,
  /// lokasi GPS, notifikasi Foreground Service, dan rekaman suara.
  static Future<bool> ensureAndroidOffGridPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final statuses = await <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.nearbyWifiDevices,
        Permission.locationWhenInUse,
        Permission.microphone,
        Permission.notification,
      ].request();

      final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
      final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
      final locOk = statuses[Permission.locationWhenInUse]?.isGranted ?? false;
      return scanOk || connectOk || locOk;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start({
    required String groupHashHex,
    required bool highDuty,
    bool useForegroundService = false,
  }) async {
    await ensureAndroidOffGridPermissions();
    try {
      await _method.invokeMethod<void>(
        'start',
        <String, dynamic>{
          'groupHashHex': groupHashHex,
          'highDuty': highDuty,
          'useForegroundService': useForegroundService,
        },
      );
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } catch (_) {}
  }

  @override
  Future<void> setDutyMode({required bool highDuty}) async {
    try {
      await _method.invokeMethod<void>(
        'setDutyMode',
        <String, dynamic>{'highDuty': highDuty},
      );
    } catch (_) {}
  }

  @override
  Future<void> sendPacket(Uint8List payload) async {
    try {
      await _method.invokeMethod<void>(
        'sendPacket',
        <String, dynamic>{'payload': payload},
      );
    } catch (_) {}
  }

  @override
  Future<bool> sendAudioFile(
    String peerId,
    File audioFile,
    Map<String, dynamic> meta,
  ) async {
    final ok = await _method.invokeMethod<bool>(
      'sendAudioFile',
      <String, dynamic>{
        'peerId': peerId,
        'filePath': audioFile.path,
        'meta': meta,
      },
    );
    return ok ?? false;
  }

  @override
  Stream<Uint8List> get onPacketReceived {
    return _packetStream ??= _packetsChannel
        .receiveBroadcastStream()
        .where((event) => event is Uint8List)
        .cast<Uint8List>();
  }

  @override
  Stream<OffGridAudioPacket> get onAudioFileReceived {
    return _audioStream ??= _audioChannel
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((raw) {
          final map = (raw as Map).map((k, v) => MapEntry(k.toString(), v));
          final localPath = (map['localPath'] as String?) ?? '';
          final rawMeta = map['meta'];
          final meta = rawMeta is Map
              ? rawMeta.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          return OffGridAudioPacket(
            audioFile: File(localPath),
            meta: meta,
            fromPeerId: map['fromPeerId'] as String?,
          );
        });
  }

  @override
  Stream<int> get onConnectedPeersChanged {
    return _peerStream ??= _peersChannel
        .receiveBroadcastStream()
        .where((event) => event is num)
        .map((n) => (n as num).toInt());
  }
}
