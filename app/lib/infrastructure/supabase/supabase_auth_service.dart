import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../core/config/supabase_config.dart';
import '../../features/auth/domain/auth_service.dart';

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client);

  final SupabaseClient _client;

  @override
  bool get isConfigured => true;

  @override
  AuthUser? get currentUser => _toUser(_client.auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges => _client.auth.onAuthStateChange
      .map((state) => _toUser(state.session?.user));

  @override
  Future<void> signIn(AuthProviderKind provider) async {
    try {
      final launched = await _client.auth.signInWithOAuth(
        provider == AuthProviderKind.google
            ? OAuthProvider.google
            : OAuthProvider.apple,
        redirectTo: SupabaseConfig.oauthRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const AccountException(
          'AUTH_LAUNCH_FAILED',
          'Browser login tidak dapat dibuka.',
        );
      }
    } on AuthException catch (error) {
      throw AccountException(
        'AUTH_FAILED',
        'Login gagal: ${error.message}',
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (error) {
      throw AccountException(
        'SIGN_OUT_FAILED',
        'Keluar gagal: ${error.message}',
      );
    }
  }

  AuthUser? _toUser(User? user) {
    if (user == null) return null;
    return AuthUser(id: user.id, email: user.email);
  }
}
