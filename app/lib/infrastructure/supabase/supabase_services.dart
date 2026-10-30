import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../core/config/supabase_config.dart';
import '../../features/auth/application/account_controller.dart';
import '../../features/auth/domain/auth_service.dart';
import '../../features/auth/domain/profile_repository.dart';
import '../../features/groups/application/group_key_manager.dart';
import '../crypto/crypto_interfaces.dart';
import '../crypto/cryptography_identity_service.dart';
import '../crypto/flutter_secure_value_store.dart';
import '../crypto/secure_group_key_store.dart';
import 'secure_supabase_storage.dart';
import 'supabase_auth_service.dart';
import 'supabase_group_remote_service.dart';
import 'supabase_identity_repository.dart';

/// Titik rakit Supabase. Tidak ada panggilan jaringan saat dibuat; panggilan
/// hanya terjadi setelah pengguna menekan tombol.
class SupabaseServices {
  SupabaseServices._();

  static String? initializationError;

  static bool get isAvailable {
    if (!SupabaseConfig.isConfigured || initializationError != null) {
      return false;
    }
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> initialize() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      const store = FlutterSecureValueStore();
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.effectiveKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          localStorage: SecureSupabaseLocalStorage(store),
          pkceAsyncStorage: SecureGotrueAsyncStorage(store),
          detectSessionInUriPredicate: SupabaseConfig.isOAuthCallback,
        ),
      );
    } catch (error) {
      initializationError =
          'Inisialisasi Supabase gagal: ${error.runtimeType}';
    }
  }

  static AccountController createAccountController() {
    if (!isAvailable) return _disabledController();
    final client = Supabase.instance.client;
    const store = FlutterSecureValueStore();
    final identity = CryptographyIdentityService(store: store);
    final repository = SupabaseIdentityRepository(client);
    final remote = SupabaseGroupRemoteService(client);
    final groupKeys = GroupKeyManager(
      remote: remote,
      crypto: identity,
      store: const SecureGroupKeyStore(store: store),
    );
    return AccountController(
      authService: SupabaseAuthService(client),
      profileRepository: repository,
      keyDirectory: repository,
      identity: identity,
      groupRemote: remote,
      groupKeyManager: groupKeys,
    );
  }

  static AccountController _disabledController() {
    return AccountController(
      authService: _DisabledAuthService(),
      profileRepository: _DisabledProfileRepository(),
      keyDirectory: _DisabledKeyDirectory(),
      identity: _DisabledIdentity(),
    );
  }
}

class _DisabledAuthService implements AuthService {
  @override
  bool get isConfigured => false;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get authStateChanges => const Stream.empty();

  @override
  Future<void> signIn(AuthProviderKind provider) async {
    throw const AccountException(
      'AUTH_DISABLED',
      'Supabase belum dikonfigurasi.',
    );
  }

  @override
  Future<void> signOut() async {}
}

class _DisabledProfileRepository implements ProfileRepository {
  @override
  Future<UserProfile?> currentProfile() async => null;

  @override
  Future<UserProfile> registerProfile({
    required String username,
    required String publicKeyBase64,
  }) async {
    throw const AccountException(
      'AUTH_DISABLED',
      'Supabase belum dikonfigurasi.',
    );
  }
}

class _DisabledKeyDirectory implements KeyDirectory {
  @override
  Future<DirectoryEntry?> findByUsername(String username) async => null;
}

class _DisabledIdentity implements IdentityService {
  @override
  Future<Uint8List> publicKey() async => Uint8List(0);
}
