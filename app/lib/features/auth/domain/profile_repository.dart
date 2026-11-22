import 'package:flutter/foundation.dart';

@immutable
class UsernameAvailabilityResult {
  const UsernameAvailabilityResult({
    required this.available,
    this.reason,
  });

  final bool available;
  final String? reason;
}

class UserProfile {
  const UserProfile({
    required this.userId,
    this.username,
    this.publicKeyBase64,
    this.fullName,
    this.avatarUrl,
    this.localAvatarPath,
    this.email,
    this.usernameChangedAtUtc,
    bool? isProfileComplete,
    this.isPlus = false,
    this.plusPlanId,
    this.plusStartedAtUtc,
    this.plusExpiresAtUtc,
    this.isOfficial = false,
  }) : _isProfileCompleteOverride = isProfileComplete;

  final String userId;
  final String? username;

  /// Kunci publik X25519 perangkat, base64. Bukan kunci rahasia.
  final String? publicKeyBase64;

  final String? fullName;
  final String? avatarUrl;

  /// Path berkas avatar lokal yang disimpan untuk tampilan offline.
  final String? localAvatarPath;

  final String? email;

  /// Waktu terakhir username diganti lewat RPC `set_username` (null jika belum
  /// pernah mengganti).
  final DateTime? usernameChangedAtUtc;

  final bool? _isProfileCompleteOverride;

  /// Menandakan pengguna sudah melengkapi profil (memiliki username) sehingga
  /// saat offline banner/teks "Username belum dibuat" / "Lengkapi akun" tidak
  /// muncul keliru.
  bool get isProfileComplete =>
      _isProfileCompleteOverride ??
      (username != null && username!.trim().isNotEmpty);

  /// Status Hiqeo Plus yang disinkronkan dari server & dicache lokal.
  final bool isPlus;
  final String? plusPlanId;
  final DateTime? plusStartedAtUtc;
  final DateTime? plusExpiresAtUtc;
  final bool isOfficial;

  bool get isUltima {
    if (!isPlus) return false;
    final normalized = plusPlanId?.trim().toLowerCase();
    return plusExpiresAtUtc == null ||
        normalized == 'lifetime' ||
        normalized == 'founding' ||
        normalized == 'ultima';
  }

  UserProfile copyWith({
    String? userId,
    String? username,
    String? publicKeyBase64,
    String? fullName,
    String? avatarUrl,
    String? localAvatarPath,
    String? email,
    DateTime? usernameChangedAtUtc,
    bool? isProfileComplete,
    bool? isPlus,
    String? plusPlanId,
    DateTime? plusStartedAtUtc,
    DateTime? plusExpiresAtUtc,
    bool? isOfficial,
    bool clearPlusExpiresAt = false,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      publicKeyBase64: publicKeyBase64 ?? this.publicKeyBase64,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      localAvatarPath: localAvatarPath ?? this.localAvatarPath,
      email: email ?? this.email,
      usernameChangedAtUtc: usernameChangedAtUtc ?? this.usernameChangedAtUtc,
      isProfileComplete: isProfileComplete ?? _isProfileCompleteOverride,
      isPlus: isPlus ?? this.isPlus,
      plusPlanId: plusPlanId ?? this.plusPlanId,
      plusStartedAtUtc: plusStartedAtUtc ?? this.plusStartedAtUtc,
      plusExpiresAtUtc:
          clearPlusExpiresAt ? null : (plusExpiresAtUtc ?? this.plusExpiresAtUtc),
      isOfficial: isOfficial ?? this.isOfficial,
    );
  }
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

  /// Mengecek ketersediaan username secara realtime di server (`check_username_available`).
  Future<UsernameAvailabilityResult> checkUsernameAvailability(String username);

  /// Mendaftarkan username publik dan kunci publik perangkat.
  Future<UserProfile> registerProfile({
    required String username,
    required String publicKeyBase64,
  });

  /// Mengubah username lewat RPC server `set_username` yang menegakkan format,
  /// moderasi `blocked_terms`, keunikan case-insensitive, dan jeda 7 hari.
  Future<UserProfile> setUsername(String newUsername);

  /// Memperbarui URL foto profil publik via RPC `update_my_avatar`.
  Future<UserProfile> updateAvatarUrl(String avatarUrl);

  /// Memperbarui nama tampilan / nama akun (`profiles.full_name`).
  Future<UserProfile> updateFullName(String fullName);
}

/// Pencarian direktori kunci selalu dengan kecocokan persis, bukan pencarian
/// bebas. Server membatasi hasil ke satu profil.
abstract interface class KeyDirectory {
  Future<DirectoryEntry?> findByUsername(String username);
}
