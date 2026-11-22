import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/domain/auth_service.dart';
import '../../features/auth/domain/profile_repository.dart';
import '../../features/auth/domain/username_policy.dart';
import '../../features/groups/domain/username.dart';

/// Profil publik dan direktori kunci. Keduanya memakai fungsi server agar
/// tabel profiles tidak bisa dibaca atau diubah kolom username-nya bebas oleh klien.
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
          .select('*')
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
    final validation = UsernamePolicy.validate(username);
    if (!validation.isValid) {
      throw AccountException(
        validation.isReserved ? 'blocked' : 'invalid_format',
        validation.errorMessage ??
            'Username harus 3–20 karakter: huruf kecil, angka, titik, garis bawah.',
      );
    }
    try {
      final data = await _client.rpc(
        'register_profile',
        params: {
          'p_username': validation.normalized,
          'p_public_key': publicKeyBase64,
        },
      );
      final registered = _profileFromMap(_firstRow(data));
      final current = await currentProfile();
      return current ?? registered;
    } on PostgrestException catch (error) {
      throw _profileError(error);
    }
  }

  @override
  Future<UserProfile> setUsername(String newUsername) async {
    final validation = UsernamePolicy.validate(newUsername);
    if (!validation.isValid) {
      throw AccountException(
        validation.isReserved ? 'blocked' : 'invalid_format',
        validation.errorMessage ??
            'Format username tidak sesuai aturan.',
      );
    }
    try {
      final data = await _client.rpc(
        'set_username',
        params: {'new_username': validation.normalized},
      );
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final ok = map['ok'];
        if (ok == false) {
          final code = (map['error'] ?? 'server_error').toString();
          final mapped = UsernamePolicy.mapServerError(code);
          throw AccountException(mapped.code, mapped.message);
        }
      }
      final refreshed = await currentProfile();
      if (refreshed != null) return refreshed;
      final user = _client.auth.currentUser;
      if (user == null) {
        throw const AccountException(
          'AUTH_REQUIRED',
          'Sesi login sudah berakhir. Masuk kembali.',
        );
      }
      return UserProfile(
        userId: user.id,
        username: validation.normalized,
        email: user.email,
        usernameChangedAtUtc: DateTime.now().toUtc(),
      );
    } on AccountException {
      rethrow;
    } on PostgrestException catch (error) {
      final text = '${error.message} ${error.details ?? ''}';
      final mapped = UsernamePolicy.mapServerError(text);
      if (mapped.code != 'server_error') {
        throw AccountException(mapped.code, mapped.message);
      }
      throw _profileError(error);
    }
  }

  @override
  Future<UserProfile> updateAvatarUrl(String avatarUrl) async {
    try {
      await _client.rpc(
        'update_my_avatar',
        params: {'p_avatar_url': avatarUrl},
      );
      final refreshed = await currentProfile();
      if (refreshed != null) return refreshed;
      final user = _client.auth.currentUser;
      if (user == null) {
        throw const AccountException(
          'AUTH_REQUIRED',
          'Sesi login sudah berakhir. Masuk kembali.',
        );
      }
      return UserProfile(userId: user.id, avatarUrl: avatarUrl);
    } on AccountException {
      rethrow;
    } on PostgrestException catch (error) {
      throw _profileError(error);
    }
  }

  @override
  Future<UserProfile> updateFullName(String fullName) async {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) {
      throw const AccountException(
        'FULL_NAME_EMPTY',
        'Nama akun tidak boleh kosong.',
      );
    }
    if (trimmed.length > 40) {
      throw const AccountException(
        'FULL_NAME_TOO_LONG',
        'Nama akun maksimal 40 karakter.',
      );
    }
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AccountException(
        'AUTH_REQUIRED',
        'Sesi login sudah berakhir. Masuk kembali.',
      );
    }
    try {
      try {
        await _client.rpc(
          'update_my_full_name',
          params: {'p_full_name': trimmed},
        );
      } on PostgrestException catch (rpcError) {
        final msgLower = rpcError.message.toLowerCase();
        if (rpcError.code == 'PGRST202' ||
            rpcError.code == '42883' ||
            msgLower.contains('update_my_full_name')) {
          await _client
              .from('profiles')
              .update(<String, dynamic>{'full_name': trimmed})
              .eq('id', user.id);
        } else {
          rethrow;
        }
      }
      try {
        await _client.auth.updateUser(
          UserAttributes(
            data: <String, dynamic>{
              'full_name': trimmed,
              'name': trimmed,
            },
          ),
        );
      } catch (_) {}
      final refreshed = await currentProfile();
      if (refreshed != null) {
        return refreshed.copyWith(fullName: trimmed);
      }
      return UserProfile(
        userId: user.id,
        fullName: trimmed,
        email: user.email,
      );
    } on AccountException {
      rethrow;
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

  UserProfile _profileFromMap(Map<String, dynamic> row) {
    DateTime? changedAt;
    final rawChanged = row['username_changed_at'];
    if (rawChanged is String && rawChanged.isNotEmpty) {
      changedAt = DateTime.tryParse(rawChanged)?.toUtc();
    }
    DateTime? plusExpiresAt;
    final rawPlusExp = row['plus_expires_at'];
    if (rawPlusExp is String && rawPlusExp.isNotEmpty) {
      plusExpiresAt = DateTime.tryParse(rawPlusExp)?.toUtc();
    }
    final rawIsPlus = row['is_plus'];
    final isPlus = rawIsPlus is bool ? rawIsPlus : false;
    return UserProfile(
      userId: row['id'] as String,
      username: row['username'] as String?,
      publicKeyBase64: row['public_key'] as String?,
      fullName: row['full_name'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      email: row['email'] as String?,
      usernameChangedAtUtc: changedAt,
      isPlus: isPlus,
      plusPlanId: row['plus_plan_id'] as String?,
      plusExpiresAtUtc: plusExpiresAt,
    );
  }

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
    final mapped = UsernamePolicy.mapServerError(text);
    if (mapped.code != 'server_error') {
      return AccountException(mapped.code, mapped.message);
    }
    if (text.contains('PUBLIC_KEY_INVALID')) {
      return const AccountException(
        'PUBLIC_KEY_INVALID',
        'Kunci publik perangkat tidak valid.',
      );
    }
    if (text.contains('FULL_NAME_EMPTY')) {
      return const AccountException(
        'FULL_NAME_EMPTY',
        'Nama akun tidak boleh kosong.',
      );
    }
    if (text.contains('FULL_NAME_TOO_LONG')) {
      return const AccountException(
        'FULL_NAME_TOO_LONG',
        'Nama akun maksimal 40 karakter.',
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
