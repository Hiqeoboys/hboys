import '../domain/group_remote_service.dart';

/// Grup terbaru dipakai sebagai "pendakian berikutnya" karena aplikasi belum
/// punya model jadwal pendakian.
RemoteGroup? nextHikeOf(List<RemoteGroup> groups) {
  if (groups.isEmpty) return null;
  return groups.reduce(
    (a, b) => a.group.createdAtUtc.isAfter(b.group.createdAtUtc) ? a : b,
  );
}
