import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../core/config/supabase_config.dart';
import '../../features/auth/domain/auth_service.dart' as domain;
import '../../services/auth_service.dart' as standalone;

class SupabaseAuthService implements domain.AuthService {
  SupabaseAuthService(this._client, {standalone.AuthService? authService})
      : _service = authService ?? standalone.AuthService(client: _client);

  final SupabaseClient _client;
  final standalone.AuthService _service;

  @override
  bool get isConfigured => true;

  @override
  domain.AuthUser? get currentUser => _toUser(_client.auth.currentUser);

  @override
  Stream<domain.AuthUser?> get authStateChanges => _client.auth.onAuthStateChange
      .map((state) => _toUser(state.session?.user));

  @override
  Future<void> signIn(domain.AuthProviderKind provider) async {
    if (provider == domain.AuthProviderKind.google) {
      await _service.signInWithGoogle();
      return;
    }

    try {
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: SupabaseConfig.oauthRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const domain.AccountException(
          'AUTH_LAUNCH_FAILED',
          'Browser login tidak dapat dibuka',
        );
      }
    } on AuthException catch (error) {
      throw domain.AccountException(
        'AUTH_FAILED',
        'Login gagal: ${error.message}',
      );
    }
  }

  @override
  Future<void> switchAccount(domain.AuthProviderKind provider) async {
    if (provider == domain.AuthProviderKind.google) {
      await _service.switchGoogleAccount();
      return;
    }
    await signOut();
    await signIn(provider);
  }

  @override
  Future<List<domain.LinkedIdentity>> linkedIdentities() async {
    final current = _client.auth.currentUser;
    if (current == null) return const <domain.LinkedIdentity>[];
    List<UserIdentity> rawIdentities = current.identities ?? const <UserIdentity>[];
    try {
      rawIdentities = await _client.auth.getUserIdentities();
    } catch (_) {
      // Offline / cache fallback menggunakan identities pada sesi saat ini.
    }
    final result = <domain.LinkedIdentity>[];
    final seen = <domain.AuthProviderKind>{};
    for (final identity in rawIdentities) {
      final kind = _kindFromProviderName(identity.provider);
      if (kind == null || !seen.add(kind)) continue;
      final email = identity.identityData?['email']?.toString();
      result.add(
        domain.LinkedIdentity(
          provider: kind,
          email: (email != null && email.trim().isNotEmpty) ? email.trim() : null,
          identityId: identity.identityId,
        ),
      );
    }
    return List<domain.LinkedIdentity>.unmodifiable(result);
  }

  @override
  Future<void> linkProvider(domain.AuthProviderKind provider) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const domain.AuthFailure(
        domain.AuthFailureCode.server,
        'Masuk ke akun terlebih dahulu sebelum menautkan akun.',
      );
    }
    final label = provider == domain.AuthProviderKind.apple ? 'Apple' : 'Google';
    try {
      final oauthProvider = provider == domain.AuthProviderKind.apple
          ? OAuthProvider.apple
          : OAuthProvider.google;
      final launched = await _client.auth.linkIdentity(
        oauthProvider,
        redirectTo: SupabaseConfig.oauthRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
        queryParams: provider == domain.AuthProviderKind.google
            ? const <String, String>{'prompt': 'select_account'}
            : null,
      );
      if (!launched) {
        throw const domain.AuthFailure(
          domain.AuthFailureCode.notConfigured,
          'Browser login tidak dapat dibuka untuk menautkan akun.',
        );
      }
    } on domain.AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      final lower = error.message.toLowerCase();
      final code = (error.code ?? '').toLowerCase();
      if (code.contains('identity_already_exists') ||
          lower.contains('identity_already_exists') ||
          lower.contains('already exists') ||
          lower.contains('already linked') ||
          lower.contains('already registered') ||
          lower.contains('already associated')) {
        throw domain.AuthFailure(
          domain.AuthFailureCode.identityAlreadyLinked,
          'Akun $label ini sudah terdaftar di akun Hiqeo lain. '
          'Data akun aktifmu tetap aman.',
        );
      }
      if (code.contains('manual_linking_disabled') ||
          lower.contains('manual linking is disabled') ||
          lower.contains('manual_linking_disabled')) {
        throw const domain.AuthFailure(
          domain.AuthFailureCode.manualLinkingDisabled,
          'Fitur tautkan akun belum diaktifkan di server autentikasi.',
        );
      }
      if (lower.contains('cancel')) {
        throw const domain.AuthFailure(
          domain.AuthFailureCode.cancelled,
          'Penautan akun dibatalkan.',
        );
      }
      if (lower.contains('provider is not enabled') ||
          lower.contains('unsupported provider')) {
        throw domain.AuthFailure(
          domain.AuthFailureCode.notConfigured,
          'Login $label belum diaktifkan di server.',
        );
      }
      throw domain.AuthFailure(
        domain.AuthFailureCode.server,
        'Gagal menautkan akun $label: ${error.message}',
      );
    } catch (_) {
      throw domain.AuthFailure(
        domain.AuthFailureCode.network,
        'Gagal menautkan akun $label. Periksa koneksi internetmu.',
      );
    }
  }

  domain.AuthProviderKind? _kindFromProviderName(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'google' => domain.AuthProviderKind.google,
        'apple' => domain.AuthProviderKind.apple,
        _ => null,
      };

  @override
  Future<void> signOut() async {
    await _service.signOut();
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await _client.rpc<void>('delete_my_account');
      await signOut();
    } on PostgrestException catch (error) {
      throw domain.AccountException(
        'DELETE_ACCOUNT_FAILED',
        'Gagal menghapus akun di server: ${error.message}',
      );
    } on AuthException catch (error) {
      throw domain.AccountException(
        'DELETE_ACCOUNT_FAILED',
        'Gagal menghapus akun: ${error.message}',
      );
    }
  }

  domain.AuthUser? _toUser(User? user) {
    if (user == null) return null;
    return domain.AuthUser(
      id: user.id,
      email: user.email,
      displayName: _displayName(user),
      avatarUrl: _avatarUrl(user),
      provider: _provider(user),
    );
  }

  String? _displayName(User user) {
    final metadata = user.userMetadata;
    if (metadata == null) return null;
    for (final key in const <String>['full_name', 'name']) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String? _avatarUrl(User user) {
    final metadata = user.userMetadata;
    if (metadata == null) return null;
    for (final key in const <String>['avatar_url', 'picture']) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  domain.AuthProviderKind? _provider(User user) {
    return switch (user.appMetadata['provider']) {
      'google' => domain.AuthProviderKind.google,
      'apple' => domain.AuthProviderKind.apple,
      _ => null,
    };
  }
}
