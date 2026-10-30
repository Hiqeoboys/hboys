import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/domain/auth_service.dart';
import '../../features/auth/domain/profile_repository.dart';
import '../../features/groups/domain/username.dart';

/// Profil publik dan direktori kunci. Keduanya memakai fungsi server agar
/// tabel profiles tidak bisa dibaca bebas oleh klien.
class SupabaseIdentityRepository implements ProfileRepository, KeyDirectory {
  SupabaseIdentityRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<UserProfile?> currentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('id, username, public_key')
          .eq('id', user.id)
          .maybeSingle();
      return row == null ? null : _profileFromMap(row);
    } on PostgrestException catch (error) {
      throw _profileError(error);
    }
  }

  @override
  Future<UserProfile> registerProfile({
    required String username,
    required String publicKeyBase64,
  }) async {
    final normalized = normalizeUsername(username);
    if (!isValidUsername(normalized)) {
      throw const AccountException(
        'USERNAME_INVALID',
        'Username harus 3-20 karakter: huruf kecil, angka, titik, garis bawah.',
      );
    }
    try {
      final data = await _client.rpc(
        'register_profile',
        params: {
          'p_username': normalized,
          'p_public_key': publicKeyBase64,
        },
      );
      return _profileFromMap(_firstRow(data));
    } on PostgrestException catch (error) {
      throw _profileError(error);
    }
  }

  @override
  Future<DirectoryEntry?> findByUsername(String username) async {
    final normalized = normalizeUsername(username);
    if (!isValidUsername(normalized)) return null;
    try {
      final data = await _client.rpc(
        'lookup_user',
        params: {'p_username': normalized},
      );
      final rows = _rows(data);
      if (rows.isEmpty) return null;
      final row = rows.first;
      return DirectoryEntry(
        userId: row['id'] as String,
        username: row['username'] as String,
        publicKeyBase64: row['public_key'] as String,
      );
    } on PostgrestException catch (error) {
      throw _profileError(error);
    }
  }

  UserProfile _profileFromMap(Map<String, dynamic> row) => UserProfile(
        userId: row['id'] as String,
        username: row['username'] as String,
        publicKeyBase64: row['public_key'] as String,
      );

  Map<String, dynamic> _firstRow(dynamic data) {
    final rows = _rows(data);
    if (rows.isEmpty) {
      throw const AccountException(
        'PROFILE_EMPTY',
        'Server tidak mengembalikan profil.',
      );
    }
    return rows.first;
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    if (data is Map) {
      return [Map<String, dynamic>.from(data)];
    }
    return const [];
  }

  AccountException _profileError(PostgrestException error) {
    final text = '${error.message} ${error.details ?? ''}';
    if (text.contains('USERNAME_TAKEN')) {
      return const AccountException(
        'USERNAME_TAKEN',
        'Username sudah dipakai. Pilih username lain.',
      );
    }
    if (text.contains('USERNAME_IMMUTABLE')) {
      return const AccountException(
        'USERNAME_IMMUTABLE',
        'Username tidak dapat diubah setelah terdaftar.',
      );
    }
    if (text.contains('USERNAME_INVALID')) {
      return const AccountException(
        'USERNAME_INVALID',
        'Username harus 3-20 karakter: huruf kecil, angka, titik, garis bawah.',
      );
    }
    if (text.contains('PUBLIC_KEY_INVALID')) {
      return const AccountException(
        'PUBLIC_KEY_INVALID',
        'Kunci publik perangkat tidak valid.',
      );
    }
    if (text.contains('AUTH_REQUIRED')) {
      return const AccountException(
        'AUTH_REQUIRED',
        'Sesi login sudah berakhir. Masuk kembali.',
      );
    }
    if (text.contains('PROFILE_REQUIRED')) {
      return const AccountException(
        'PROFILE_REQUIRED',
        'Daftarkan username sebelum mencari pengguna lain.',
      );
    }
    return const AccountException(
      'PROFILE_SERVER_ERROR',
      'Permintaan profil ditolak server. Coba lagi.',
    );
  }
}
