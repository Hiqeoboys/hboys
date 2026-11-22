import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Paket audio `.m4a` beserta metadata yang diterima melalui transport P2P offline
/// (Wi-Fi Direct / TCP socket lokal).
class OffGridAudioPacket {
  const OffGridAudioPacket({
    required this.audioFile,
    required this.meta,
    this.fromPeerId,
  });

  final File audioFile;
  final Map<String, dynamic> meta;
  final String? fromPeerId;

  dynamic operator [](String key) {
    switch (key) {
      case 'audioFile':
        return audioFile;
      case 'meta':
        return meta;
      case 'fromPeerId':
        return fromPeerId;
      default:
        return meta[key];
    }
  }
}

/// Kontrak abstrak lintas platform untuk komunikasi off-grid (BLE Mesh & Wi-Fi Direct).
/// Implementasi Android memakai MethodChannel/EventChannel ke Kotlin native;
/// implementasi iOS di masa depan cukup mengimplementasikan kontrak ini lewat CoreBluetooth.
abstract interface class OffGridTransportAdapter {
  Future<void> start({
    required String groupHashHex,
    required bool highDuty,
    bool useForegroundService = false,
  });

  Future<void> stop();

  Future<void> setDutyMode({required bool highDuty});

  Future<void> sendPacket(Uint8List payload);

  Future<bool> sendAudioFile(
    String peerId,
    File audioFile,
    Map<String, dynamic> meta,
  );

  Stream<Uint8List> get onPacketReceived;

  Stream<OffGridAudioPacket> get onAudioFileReceived;

  Stream<int> get onConnectedPeersChanged;
}

/// Bus topologi dalam memori untuk pengujian multi-hop BLE Mesh & Wi-Fi Direct.
class LoopbackOffGridMeshBus {
  final Map<String, InMemoryOffGridTransportAdapter> _nodes =
      <String, InMemoryOffGridTransportAdapter>{};
  final Map<String, Set<String>> _links = <String, Set<String>>{};

  void register(InMemoryOffGridTransportAdapter node) {
    _nodes[node.nodeId] = node;
    _links.putIfAbsent(node.nodeId, () => <String>{});
  }

  /// Menghubungkan dua node secara dua arah untuk simulasi jangkauan radio.
  void connect(String aId, String bId) {
    _links.putIfAbsent(aId, () => <String>{}).add(bId);
    _links.putIfAbsent(bId, () => <String>{}).add(aId);
    _nodes[aId]?._notifyPeerCount();
    _nodes[bId]?._notifyPeerCount();
  }

  /// Memutuskan tautan radio antara dua node (untuk uji store-and-forward).
  void disconnect(String aId, String bId) {
    _links[aId]?.remove(bId);
    _links[bId]?.remove(aId);
    _nodes[aId]?._notifyPeerCount();
    _nodes[bId]?._notifyPeerCount();
  }

  Set<String> neighborsOf(String nodeId) =>
      _links[nodeId] ?? const <String>{};

  void broadcastPacket(String fromNodeId, Uint8List payload) {
    final sender = _nodes[fromNodeId];
    if (sender == null || !sender.isStarted) return;
    for (final targetId in neighborsOf(fromNodeId)) {
      final target = _nodes[targetId];
      if (target != null && target.isStarted) {
        target._deliverPacket(Uint8List.fromList(payload));
      }
    }
  }

  Future<bool> transferAudioFile({
    required String fromNodeId,
    required String targetPeerId,
    required File audioFile,
    required Map<String, dynamic> meta,
  }) async {
    final sender = _nodes[fromNodeId];
    if (sender == null || !sender.isStarted) return false;

    final neighbors = neighborsOf(fromNodeId)
        .map((id) => _nodes[id])
        .where((n) => n != null && n.isStarted)
        .cast<InMemoryOffGridTransportAdapter>()
        .toList(growable: false);
    if (neighbors.isEmpty) return false;

    final targets = targetPeerId == 'broadcast'
        ? neighbors
        : neighbors
            .where((n) => n.nodeId == targetPeerId)
            .toList(growable: false);
    if (targets.isEmpty) return false;

    final bytes = await audioFile.readAsBytes();
    final msgId = (meta['client_msg_id'] as String?) ??
        DateTime.now().microsecondsSinceEpoch.toString();

    for (final target in targets) {
      final outDir = target.receivedAudioDirectory ?? Directory.systemTemp;
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
      final copiedFile = File(
        '${outDir.path}${Platform.pathSeparator}rx_${target.nodeId}_$msgId.m4a',
      );
      await copiedFile.writeAsBytes(bytes, flush: true);
      target._deliverAudio(
        OffGridAudioPacket(
          audioFile: copiedFile,
          meta: Map<String, dynamic>.from(meta),
          fromPeerId: fromNodeId,
        ),
      );
    }
    return true;
  }
}

/// Implementasi [OffGridTransportAdapter] dalam memori (juga fallback non-Android
/// dan harness unit test).
class InMemoryOffGridTransportAdapter implements OffGridTransportAdapter {
  InMemoryOffGridTransportAdapter({
    this.nodeId = 'local-node',
    LoopbackOffGridMeshBus? bus,
    this.receivedAudioDirectory,
  }) : _bus = bus {
    _bus?.register(this);
  }

  final String nodeId;
  final LoopbackOffGridMeshBus? _bus;
  final Directory? receivedAudioDirectory;

  final StreamController<Uint8List> _packetCtrl =
      StreamController<Uint8List>.broadcast();
  final StreamController<OffGridAudioPacket> _audioCtrl =
      StreamController<OffGridAudioPacket>.broadcast();
  final StreamController<int> _peersCtrl = StreamController<int>.broadcast();

  bool _started = false;
  bool _highDuty = false;
  bool _foregroundServiceActive = false;
  String? _groupHashHex;
  final List<bool> dutyModeHistory = <bool>[];
  final List<Uint8List> sentPackets = <Uint8List>[];

  bool get isStarted => _started;
  bool get isHighDuty => _highDuty;
  bool get isForegroundServiceActive => _foregroundServiceActive;
  String? get activeGroupHashHex => _groupHashHex;

  @override
  Future<void> start({
    required String groupHashHex,
    required bool highDuty,
    bool useForegroundService = false,
  }) async {
    _started = true;
    _groupHashHex = groupHashHex;
    _highDuty = highDuty;
    _foregroundServiceActive = useForegroundService;
    dutyModeHistory.add(highDuty);
    _notifyPeerCount();
  }

  @override
  Future<void> stop() async {
    _started = false;
    _foregroundServiceActive = false;
    if (!_peersCtrl.isClosed) {
      _peersCtrl.add(0);
    }
  }

  @override
  Future<void> setDutyMode({required bool highDuty}) async {
    _highDuty = highDuty;
    dutyModeHistory.add(highDuty);
  }

  @override
  Future<void> sendPacket(Uint8List payload) async {
    sentPackets.add(Uint8List.fromList(payload));
    _bus?.broadcastPacket(nodeId, payload);
  }

  @override
  Future<bool> sendAudioFile(
    String peerId,
    File audioFile,
    Map<String, dynamic> meta,
  ) async {
    final bus = _bus;
    if (bus == null) return false;
    return bus.transferAudioFile(
      fromNodeId: nodeId,
      targetPeerId: peerId,
      audioFile: audioFile,
      meta: meta,
    );
  }

  void _deliverPacket(Uint8List payload) {
    if (!_packetCtrl.isClosed) {
      _packetCtrl.add(payload);
    }
  }

  void _deliverAudio(OffGridAudioPacket packet) {
    if (!_audioCtrl.isClosed) {
      _audioCtrl.add(packet);
    }
  }

  void _notifyPeerCount() {
    if (_peersCtrl.isClosed || !_started) return;
    final bus = _bus;
    if (bus == null) {
      _peersCtrl.add(0);
      return;
    }
    final activeNeighbors = bus
        .neighborsOf(nodeId)
        .where((id) => bus._nodes[id]?.isStarted ?? false)
        .length;
    _peersCtrl.add(activeNeighbors);
  }

  @override
  Stream<Uint8List> get onPacketReceived => _packetCtrl.stream;

  @override
  Stream<OffGridAudioPacket> get onAudioFileReceived => _audioCtrl.stream;

  @override
  Stream<int> get onConnectedPeersChanged => _peersCtrl.stream;

  Future<void> dispose() async {
    await stop();
    await _packetCtrl.close();
    await _audioCtrl.close();
    await _peersCtrl.close();
  }
}
