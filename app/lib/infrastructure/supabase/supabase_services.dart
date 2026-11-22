import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../core/config/supabase_config.dart';
import '../../features/auth/application/account_controller.dart';
import '../../features/auth/domain/auth_service.dart';
import '../../features/auth/domain/profile_repository.dart';
import '../../features/chat/application/group_chat_crypto.dart';
import '../../features/chat/domain/group_chat_remote_service.dart';
import '../../features/groups/application/group_key_manager.dart';
import '../../features/plus/plus_dependencies.dart';
import '../cache/offline_account_cache.dart';
import '../crypto/crypto_interfaces.dart';
import '../crypto/cryptography_identity_service.dart';
import '../crypto/flutter_secure_value_store.dart';
import '../crypto/secure_group_key_store.dart';
import 'secure_supabase_storage.dart';
import 'supabase_auth_service.dart';
import 'supabase_group_chat_remote_service.dart';
import 'supabase_group_realtime_service.dart';
import 'supabase_group_remote_service.dart';
import 'supabase_identity_repository.dart';

/// Titik rakit Supabase. Tidak ada panggilan jaringan saat dibuat; panggilan
/// hanya terjadi setelah pengguna menekan tombol atau sesi aktif dipulihkan.
class SupabaseServices {
  SupabaseServices._();

  static String? initializationError;
  static AccountController? _sharedAccountController;
  static SqliteOfflineAccountCache? _sharedCache;

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

  static SupabaseClient? get clientOrNull =>
      isAvailable ? Supabase.instance.client : null;

  /// Cek sesi tersimpan lokal saja (tanpa panggilan jaringan ke server).
  static bool get hasLocalSession =>
      clientOrNull?.auth.currentSession != null ||
      _sharedAccountController?.profile != null;

  static Future<void> initialize() async {
    await SupabaseConfig.loadEnv();
    if (!SupabaseConfig.isConfigured) return;
    try {
      const store = FlutterSecureValueStore();
      await Supabase.initialize(
        url: SupabaseConfig.url,
        // ignore: deprecated_member_use
        anonKey: SupabaseConfig.effectiveKey,
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

  /// Menghidrasi profil, grup, dan pembersihan grup terhapus dari cache SQLite
  /// lokal TANPA memicu panggilan jaringan online.
  static Future<void> warmUpLocalAccountCache() async {
    if (!isAvailable) return;
    final controller = _sharedAccountController ??= createAccountController();
    await controller.hydrateLocalCacheOnly();
  }

  /// Menyalakan listener auth, sinkronisasi server, dan Realtime di latar
  /// setelah pengguna masuk ke Beranda.
  static void startBackgroundAccountSync() {
    sharedAccountController?.initialize();
  }

  /// Mengembalikan instance tunggal [AccountController] bila Supabase aktif
  /// agar Beranda, Grup, Profil, dan HiqeoShell berbagi cache lokal SQLite dan
  /// langganan Supabase Realtime yang sama tanpa duplikasi koneksi.
  ///
  /// Bila Supabase tidak aktif (mis. build tanpa kredensial atau widget test),
  /// mengembalikan `null` sehingga pemanggil dapat membuat controller terisolasi.
  static AccountController? get sharedAccountController {
    if (!isAvailable) return null;
    final existing = _sharedAccountController;
    if (existing != null) return existing;
    final created = createAccountController();
    created.initialize();
    _sharedAccountController = created;
    return created;
  }

  static OfflineAccountCache get sharedCache =>
      _sharedCache ??= SqliteOfflineAccountCache();

  static AccountController createAccountController() {
    if (!isAvailable) return _disabledController();
    final client = Supabase.instance.client;
    const store = FlutterSecureValueStore();
    final identity = CryptographyIdentityService(store: store);
    final repository = SupabaseIdentityRepository(client);
    final remote = SupabaseGroupRemoteService(client);
    final realtime = SupabaseGroupRealtimeService(client);
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
      cache: sharedCache,
      realtimeService: realtime,
      plusController: PlusDependencies.controller,
    );
  }

  static GroupChatRemoteService? createGroupChatRemoteService() {
    if (!isAvailable) return null;
    const store = FlutterSecureValueStore();
    return SupabaseGroupChatRemoteService(
      Supabase.instance.client,
      crypto: GroupChatCrypto(
        keyStore: const SecureGroupKeyStore(store: store),
        allowDeterministicFallback: true,
      ),
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
  Future<void> switchAccount(AuthProviderKind provider) async {
    throw const AccountException(
      'AUTH_DISABLED',
      'Supabase belum dikonfigurasi.',
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
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

  @override
  Future<UserProfile> setUsername(String newUsername) async {
    throw const AccountException(
      'AUTH_DISABLED',
      'Supabase belum dikonfigurasi.',
    );
  }

  @override
  Future<UserProfile> updateAvatarUrl(String avatarUrl) async {
    throw const AccountException(
      'AUTH_DISABLED',
      'Supabase belum dikonfigurasi.',
    );
  }

  @override
  Future<UserProfile> updateFullName(String fullName) async {
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
