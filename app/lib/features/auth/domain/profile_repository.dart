class UserProfile {
  const UserProfile({
    required this.userId,
    required this.username,
    required this.publicKeyBase64,
  });

  final String userId;
  final String username;

  /// Kunci publik X25519 perangkat, base64. Bukan kunci rahasia.
  final String publicKeyBase64;
}

class DirectoryEntry {
  const DirectoryEntry({
    required this.userId,
    required this.username,
    required this.publicKeyBase64,
  });

  final String userId;
  final String username;
  final String publicKeyBase64;
}

abstract interface class ProfileRepository {
  Future<UserProfile?> currentProfile();

  /// Mendaftarkan username publik dan kunci publik perangkat. Server menolak
  /// username yang sudah dipakai atau diubah setelah terdaftar.
  Future<UserProfile> registerProfile({
    required String username,
    required String publicKeyBase64,
  });
}

/// Pencarian direktori kunci selalu dengan kecocokan persis, bukan pencarian
/// bebas. Server membatasi hasil ke satu profil.
abstract interface class KeyDirectory {
  Future<DirectoryEntry?> findByUsername(String username);
}
