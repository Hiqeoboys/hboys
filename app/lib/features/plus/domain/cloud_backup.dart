/// Keadaan cadangan cloud yang disimpan lokal pada tahap ini.
///
/// Server cadangan belum tersambung, jadi [connected] selalu false untuk
/// implementasi sekarang. Antarmuka ini sudah siap diganti implementasi
/// backend tanpa mengubah layar D6.
library;

class BackupDevice {
  const BackupDevice({
    required this.name,
    required this.lastActiveUtc,
    this.current = false,
  });

  final String name;
  final DateTime lastActiveUtc;
  final bool current;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'lastActiveUtc': lastActiveUtc.toIso8601String(),
        'current': current,
      };

  static BackupDevice? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name']?.toString();
    final lastActive =
        DateTime.tryParse(json['lastActiveUtc']?.toString() ?? '');
    if (name == null || name.isEmpty || lastActive == null) return null;
    return BackupDevice(
      name: name,
      lastActiveUtc: lastActive,
      current: json['current'] == true,
    );
  }
}

class CloudBackupState {
  const CloudBackupState({
    required this.autoBackup,
    required this.recoveryCode,
    required this.devices,
    required this.connected,
    this.lastBackupAtUtc,
  });

  final bool autoBackup;
  final String recoveryCode;
  final List<BackupDevice> devices;
  final bool connected;
  final DateTime? lastBackupAtUtc;

  CloudBackupState copyWith({
    bool? autoBackup,
    String? recoveryCode,
    List<BackupDevice>? devices,
    bool? connected,
    DateTime? lastBackupAtUtc,
  }) =>
      CloudBackupState(
        autoBackup: autoBackup ?? this.autoBackup,
        recoveryCode: recoveryCode ?? this.recoveryCode,
        devices: devices ?? this.devices,
        connected: connected ?? this.connected,
        lastBackupAtUtc: lastBackupAtUtc ?? this.lastBackupAtUtc,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'autoBackup': autoBackup,
        'recoveryCode': recoveryCode,
        'connected': connected,
        'lastBackupAtUtc': lastBackupAtUtc?.toIso8601String(),
        'devices': <Object?>[for (final device in devices) device.toJson()],
      };

  static CloudBackupState? tryParse(Object? json,
      {required String fallbackCode}) {
    if (json is! Map) return null;
    final code = json['recoveryCode']?.toString();
    final devices = <BackupDevice>[
      for (final item
          in json['devices'] is List ? json['devices'] as List : const [])
        if (BackupDevice.tryParse(item) case final device?) device,
    ];
    return CloudBackupState(
      autoBackup: json['autoBackup'] == true,
      recoveryCode: code == null || code.isEmpty ? fallbackCode : code,
      devices: List<BackupDevice>.unmodifiable(devices),
      connected: json['connected'] == true,
      lastBackupAtUtc: DateTime.tryParse(
        json['lastBackupAtUtc']?.toString() ?? '',
      ),
    );
  }
}

abstract interface class CloudBackupRepository {
  Future<CloudBackupState> load();

  /// Menyimpan pilihan saklar. Tidak mengubah [CloudBackupState.lastBackupAtUtc]
  /// karena belum ada server yang menerima cadangan.
  Future<CloudBackupState> setAutoBackup(bool enabled);
}
