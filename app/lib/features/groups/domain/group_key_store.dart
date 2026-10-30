import 'dart:typed_data';

/// Penyimpanan kunci grup dan tanda tangan distribusi. Implementasi produksi
/// memakai keystore/Keychain; kunci tidak disimpan di database aplikasi.
abstract interface class GroupKeyStore {
  Future<Uint8List?> readGroupKey(String groupId, int keyVersion);

  Future<void> writeGroupKey(
    String groupId,
    int keyVersion,
    Uint8List groupKey,
  );

  Future<void> deleteGroupKey(String groupId, int keyVersion);

  Future<String?> readDistributionSignature(String groupId, int keyVersion);

  Future<void> writeDistributionSignature(
    String groupId,
    int keyVersion,
    String signature,
  );

  Future<void> deleteDistributionSignature(String groupId, int keyVersion);
}
