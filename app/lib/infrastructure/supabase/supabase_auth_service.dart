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
