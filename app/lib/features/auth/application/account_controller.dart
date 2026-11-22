import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/clock.dart';
import '../../../infrastructure/auth/active_account_scope.dart';
import '../../../infrastructure/cache/hiqeo_media_cache_service.dart';
import '../../../infrastructure/cache/offline_account_cache.dart';
import '../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../../infrastructure/crypto/crypto_interfaces.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../../infrastructure/notifications/device_notification_group_store.dart';
import '../../../infrastructure/notifications/push_notification_service.dart';
import '../../../infrastructure/storage/media_url_normalizer.dart';
import '../../../infrastructure/storage/r2_media_service.dart';
import '../../../infrastructure/storage/r2_uploader.dart';
import '../../../infrastructure/supabase/app_presence_service.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../chat/application/group_auto_location_service.dart';
import '../../groups/application/group_key_manager.dart';
import '../../groups/application/group_selection.dart';
import '../../groups/domain/group.dart';
import '../../groups/domain/group_remote_service.dart';
import '../../groups/domain/invitation.dart';
import '../../groups/domain/username.dart';
import '../../home/beranda_page.dart';
import '../../notifications/data/user_notifications_service.dart';
import '../../plus/application/plus_controller.dart';
import '../../plus/infrastructure/supabase_cloud_backup_service.dart';
import '../../preparation/application/packing_list_store.dart';
import '../../profile/application/body_metrics_store.dart';
import '../../safety/application/emergency_contact_sync_service.dart';
import '../../social/data/chat_mute_service.dart';
import '../../social/data/community_service.dart';
import '../../social/data/friends_service.dart';
import '../../social/data/social_unread_store.dart';
import '../../tracking/application/tracking_controller.dart';
import '../domain/auth_service.dart';
import '../domain/profile_repository.dart';
import '../domain/username_policy.dart';

class AccountController extends ChangeNotifier {
  AccountController({
    required AuthService authService,
    required ProfileRepository profileRepository,
    required KeyDirectory keyDirectory,
    required IdentityService identity,
    GroupRemoteService? groupRemote,
    GroupKeyManager? groupKeyManager,
    OfflineAccountCache? cache,
    GroupRealtimeService? realtimeService,
    PlusController? plusController,
    SocialGroupsStore? groupsStore,
    Stream<bool>? connectivityStream,
    Clock clock = const SystemClock(),
  })  : _auth = authService,
        _profiles = profileRepository,
        _directory = keyDirectory,
        _identity = identity,
        _groupRemote = groupRemote,
        _groupKeys = groupKeyManager,
        _cache = cache,
        _realtimeService = realtimeService,
        _plusController = plusController,
        _injectedGroupsStore = groupsStore,
        _injectedConnectivityStream = connectivityStream,
        _clock = clock;

  static const int maxAccountNameLength = 40;
  static final Map<String, bool> _localAvatarExistsCache = <String, bool>{};

  /// Menghindari `File.existsSync()` berulang di dalam widget `build()` saat scroll.
  static File? cachedLocalAvatarFile(String? path) {
    if (kIsWeb || path == null) return null;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    final exists =
        _localAvatarExistsCache[trimmed] ?? File(trimmed).existsSync();
    _localAvatarExistsCache[trimmed] = exists;
    return exists ? File(trimmed) : null;
  }

  static void evictLocalAvatarFileCache([String? path]) {
    if (path == null) {
      _localAvatarExistsCache.clear();
    } else {
      _localAvatarExistsCache.remove(path.trim());
    }
  }

  final AuthService _auth;
  final ProfileRepository _profiles;
  final KeyDirectory _directory;
  final IdentityService _identity;
  final GroupRemoteService? _groupRemote;
  final GroupKeyManager? _groupKeys;
  final OfflineAccountCache? _cache;
  final GroupRealtimeService? _realtimeService;
  final PlusController? _plusController;
  final SocialGroupsStore? _injectedGroupsStore;
  final Stream<bool>? _injectedConnectivityStream;
  final Clock _clock;

  SocialGroupsStore get _groupsStore =>
      _injectedGroupsStore ?? SocialGroupsStore.instance;

  StreamSubscription<AuthUser?>? _authSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<GroupRealtimeEvent>? _realtimeSubscription;
  final StreamController<IncomingInvitation> _incomingInvitationsCtrl =
      StreamController<IncomingInvitation>.broadcast();
  final StreamController<String> _groupKeyReadyCtrl =
      StreamController<String>.broadcast();
  final Set<String> _keySyncInFlight = <String>{};
  final Map<String, Timer> _membershipKeyTimers = <String, Timer>{};
  DateTime? _lastGroupRefreshAtUtc;

  bool _initialized = false;
  bool _disposed = false;
  int _generation = 0;
  bool _hasHydratedInvitations = false;
  bool _hasSyncedGroupsFromServer = false;
  bool _refreshingGroups = false;
  bool _isOnline = true;
  bool _syncingOnReconnect = false;
  String? _realtimeSubscribedUserId;
  String? _realtimeGroupSignature;
  String? _cloudBackupSyncedUserId;

  AuthUser? _user;
  UserProfile? _profile;
  bool _deviceKeyMismatch = false;
  List<IncomingInvitation> _invitations = const <IncomingInvitation>[];
  List<RemoteGroup> _groups = const <RemoteGroup>[];
  Map<String, int> _memberCounts = const <String, int>{};
  Map<String, List<MemberDirectoryEntry>> _membersByGroup =
      const <String, List<MemberDirectoryEntry>>{};
  Map<String, GroupKeyStatus> _keyStatuses = const <String, GroupKeyStatus>{};
  Map<String, String> _keyErrors = const <String, String>{};
  final Set<String> _knownInvitationIds = <String>{};
  bool _loading = false;
  bool _busy = false;
  bool _profileResolved = false;
  List<LinkedIdentity> _linkedIdentities = const <LinkedIdentity>[];
  AuthProviderKind? _linkingProvider;
  String? _linkingError;
  String? _linkingNotice;
  String? _error;
  String? _notice;

  bool get isConfigured => _auth.isConfigured;
  bool get groupsEnabled => _groupRemote != null && _groupKeys != null;
  bool get hasSyncedGroupsFromServer => _hasSyncedGroupsFromServer;
  bool get isLoading => _loading;
  bool get isBusy => _busy;
  bool get isOnline => _isOnline;
  bool get isProfileResolved => _profileResolved;
  AuthUser? get user => _user;
  UserProfile? get profile => _profile;
  String? get localAvatarPath => _profile?.localAvatarPath;
  List<LinkedIdentity> get linkedIdentities => _linkedIdentities;
  AuthProviderKind? get linkingProvider => _linkingProvider;
  String? get linkingError => _linkingError;
  String? get linkingNotice => _linkingNotice;

  bool isProviderLinked(AuthProviderKind provider) {
    if (_linkedIdentities.any((item) => item.provider == provider)) {
      return true;
    }
    return _user?.provider == provider;
  }

  /// True jika user sudah login dan profil belum lengkap (username atau nama
  /// tampilan belum diisi). Pengguna lama yang sudah memiliki keduanya akan
  /// langsung melewati onboarding.
  bool get needsProfileOnboarding {
    if (_user == null || _loading || !_profileResolved) return false;
    final p = _profile;
    final hasUsername = p?.username?.trim().isNotEmpty == true;
    final hasFullName = p?.fullName?.trim().isNotEmpty == true;
    return !hasUsername || !hasFullName;
  }

  bool get needsUsername {
    if (_user == null || _loading) return false;
    final p = _profile;
    if (p == null) return true;
    if (p.isProfileComplete) return false;
    return p.username == null || p.username!.isEmpty;
  }

  bool get hasNonCompliantUsername {
    final current = _profile?.username;
    if (current == null || current.isEmpty) return false;
    return !UsernamePolicy.validate(current, userEmail: _user?.email).isValid;
  }

  int get usernameCooldownDaysRemaining => UsernamePolicy.cooldownDaysRemaining(
        usernameChangedAtUtc: _profile?.usernameChangedAtUtc,
        nowUtc: _clock.nowUtc(),
        currentUsername: _profile?.username,
      );

  bool get deviceKeyMismatch => _deviceKeyMismatch;
  List<IncomingInvitation> get invitations => _invitations;
  int get pendingInvitationCount => _invitations.length;
  List<RemoteGroup> get groups => _groups;
  String? get error => _error;
  String? get notice => _notice;

  /// Stream undangan grup baru yang masuk secara realtime untuk menampilkan
  /// banner melayang di dalam aplikasi (bukan push notification sistem).
  Stream<IncomingInvitation> get onIncomingInvitation =>
      _incomingInvitationsCtrl.stream;

  /// Memancarkan `groupId` segera setelah kunci enkripsi E2EE grup tersedia
  /// atau diperbarui di perangkat (termasuk lewat Realtime `group_key_blobs`)
  /// sehingga ruang obrolan dan layanan lokasi bisa langsung mendekripsi ulang.
  Stream<String> get onGroupKeyReady => _groupKeyReadyCtrl.stream;

  void _emitGroupKeyReady(String groupId) {
    if (_disposed || _groupKeyReadyCtrl.isClosed || groupId.isEmpty) return;
    _groupKeyReadyCtrl.add(groupId);
  }

  GroupKeyStatus? keyStatusFor(String groupId) => _keyStatuses[groupId];
  String? keyErrorFor(String groupId) => _keyErrors[groupId];

  /// Jumlah anggota terbaru untuk [groupId] (dari `group_members` server,
  /// pembaruan Supabase Realtime, atau cache lokal SQLite saat offline).
  int memberCountFor(String groupId) {
    final explicit = _memberCounts[groupId];
    if (explicit != null && explicit > 0) return explicit;
    final cachedList = _membersByGroup[groupId];
    if (cachedList != null && cachedList.isNotEmpty) return cachedList.length;
    final keyCount = _keyStatuses[groupId]?.memberCount ?? 0;
    if (keyCount > 0) return keyCount;
    return 1;
  }

  /// Daftar anggota dari cache memori/lokal secara sinkron (tanpa delay saat offline).
  List<MemberDirectoryEntry> cachedMembersOf(String groupId) =>
      List<MemberDirectoryEntry>.unmodifiable(
        _membersByGroup[groupId] ?? const <MemberDirectoryEntry>[],
      );

  /// Daftar anggota grup: mengambil dari server bila tersedia dan menyimpan ke
  /// cache lokal, atau otomatis jatuh ke cache lokal saat offline/gagal jaringan.
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async {
    if (!groupsEnabled) {
      final cached = _membersByGroup[groupId];
      if (cached != null && cached.isNotEmpty) return cached;
      return (await _cache?.readMembers(groupId)) ??
          const <MemberDirectoryEntry>[];
    }
    try {
      final remote = await _groupRemote!.membersOf(groupId);
      if (remote.isNotEmpty) {
        _seedPublicProfilesFromMembers(remote);
        _membersByGroup = <String, List<MemberDirectoryEntry>>{
          ..._membersByGroup,
          groupId: List<MemberDirectoryEntry>.unmodifiable(remote),
        };
        _memberCounts = <String, int>{
          ..._memberCounts,
          groupId: remote.length,
        };
        unawaited(_cache?.writeMembers(groupId, remote));
        await _persistGroupsToCache();
        _notify();
      }
      return remote;
    } catch (_) {
      final inMem = _membersByGroup[groupId];
      if (inMem != null && inMem.isNotEmpty) return inMem;
      final disk = await _cache?.readMembers(groupId);
      if (disk != null && disk.isNotEmpty) {
        _membersByGroup = <String, List<MemberDirectoryEntry>>{
          ..._membersByGroup,
          groupId: List<MemberDirectoryEntry>.unmodifiable(disk),
        };
        _memberCounts = <String, int>{
          ..._memberCounts,
          groupId: math.max(_memberCounts[groupId] ?? 1, disk.length),
        };
        return disk;
      }
      return const <MemberDirectoryEntry>[];
    }
  }

  /// Hidrasi dari cache SQLite lokal SAJA tanpa panggilan jaringan.
  /// Dipakai saat startup offline-first agar Beranda langsung terisi pada frame pertama.
  Future<void> hydrateLocalCacheOnly() async {
    final current = _auth.currentUser;
    if (current == null || _disposed) return;
    ActiveAccountScope.setActiveUserId(current.id);
    _user ??= current;
    await _hydrateFromLocalCache(current, _generation);
  }

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _startConnectivityListener();
    _authSubscription = _auth.authStateChanges.listen(
      (user) => unawaited(_handleUser(user)),
      onError: (Object error, StackTrace stackTrace) {
        _error = _friendly(error);
        _notify();
      },
    );
    final current = _auth.currentUser;
    ActiveAccountScope.setActiveUserId(current?.id);
    if (current != null) unawaited(_handleUser(current));
  }

  Future<void> _resetLocalAccountState({required String? nextUserId}) async {
    ActiveAccountScope.setActiveUserId(nextUserId);
    BerandaPage.clearAccountCaches();
    SocialUnreadStore.instance.clearForAccountChange();
    CommunityService.instance.clearForAccountChange();
    _groupsStore.clearLocalGroups();
    TrackingController.instance.resetForAccountChange();
    unawaited(DeviceNotificationGroupStore.instance.clearAll());
    await Future.wait<void>(<Future<void>>[
      PackingListStore.instance.resetForAccountChange(),
      GroupHikePlanStore.instance.resetForAccountChange(),
      BodyMetricsStore.instance.resetForAccountChange(),
      _groupsStore.resetForAccountChange(),
    ]);
    DriftTrackingRepository.notifyExternalChange();
  }

  void _startConnectivityListener() {
    final injected = _injectedConnectivityStream;
    if (injected != null) {
      _connectivitySubscription = injected.listen(_handleConnectivityChanged);
      return;
    }
    try {
      // Pada unit test murni Dart tanpa ServicesBinding, lewati plugin
      // connectivity_plus agar tidak melempar galat binding saat listen/cancel.
      ServicesBinding.instance;
      final connectivity = Connectivity();
      unawaited(() async {
        try {
          final current = await connectivity.checkConnectivity();
          if (!_disposed) {
            _isOnline = current.any((r) => r != ConnectivityResult.none);
          }
        } catch (_) {}
      }());
      _connectivitySubscription = connectivity.onConnectivityChanged
          .map((results) => results.any((r) => r != ConnectivityResult.none))
          .listen(_handleConnectivityChanged, onError: (_) {});
    } catch (_) {
      // Abaikan bila plugin connectivity atau binding Flutter belum aktif.
    }
  }

  void _handleConnectivityChanged(bool online) {
    final wasOffline = !_isOnline;
    _isOnline = online;
    if (online && wasOffline) {
      HiqeoMediaCacheService.instance.clearFailureCooldowns();
      if (_user != null && !_syncingOnReconnect) {
        unawaited(_syncAfterReconnect());
      }
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    _notify();
  }

  Future<void> _syncAfterReconnect() async {
    if (_disposed || _user == null || _syncingOnReconnect) return;
    _syncingOnReconnect = true;
    _error = null;
    final gen = _generation;
    try {
      await _fetchProfileFromServer(_user!, gen);
      await _refreshGroupsInternal(gen, allowRealtimeNotify: true);
      _ensureRealtimeSubscribed();
    } finally {
      _syncingOnReconnect = false;
      _notify();
    }
  }

  Future<void> signIn(AuthProviderKind provider) async {
    if (!isConfigured || _busy) return;
    _busy = true;
    _error = null;
    _notice = null;
    _notify();
    try {
      await _auth.signIn(provider);
      if (_auth.currentUser == null) {
        _notice =
            'Selesaikan login di browser. Aplikasi akan terbuka kembali otomatis.';
      }
    } catch (error) {
      if (error is AccountException && error.code == 'AUTH_CANCELLED') {
        // Pengguna membatalkan alur login; jangan tampilkan pesan kesalahan.
      } else {
        _error = _friendly(error);
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Memaksa pemilih akun penyedia identitas muncul agar pengguna bisa beralih
  /// ke akun lain.
  Future<void> switchAccount(AuthProviderKind provider) async {
    if (!isConfigured || _busy) return;
    _busy = true;
    _error = null;
    _notice = null;
    _notify();
    final prevUserId = _user?.id;
    try {
      await _auth.switchAccount(provider);
      final afterUser = _auth.currentUser;
      if (afterUser?.id != prevUserId) {
        if (SupabaseServices.isAvailable) {
          AppPresenceService.instance.stop();
          GroupAutoLocationService.instance.stop();
          unawaited(ChatMuteService.instance.setActiveUser(afterUser?.id));
          UserNotificationsService.instance.clear();
          FriendsService.instance.clear();
        }
        _cloudBackupSyncedUserId = null;
        await _resetLocalAccountState(nextUserId: afterUser?.id);
      }
    } catch (error) {
      if (error is AccountException && error.code == 'AUTH_CANCELLED') {
        // Pengguna membatalkan pemilihan akun; tidak menampilkan galat.
      } else {
        _error = _friendly(error);
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Mengganti username lewat RPC server `set_username`. Mengembalikan `null`
  /// bila berhasil, atau pesan galat bahasa Indonesia bila ditolak.
  Future<String?> changeUsername(String input) async {
    if (_user == null) {
      return 'Masuk ke akun terlebih dahulu.';
    }
    final validation = UsernamePolicy.validate(
      input,
      userEmail: _user?.email,
    );
    if (!validation.isValid) {
      return validation.errorMessage ?? 'Format username tidak sesuai.';
    }
    final remaining = usernameCooldownDaysRemaining;
    if (remaining > 0) {
      return 'Username baru bisa diganti lagi dalam $remaining hari';
    }
    if (_busy) return 'Sedang memproses permintaan lain.';

    final userId = _user!.id;
    _busy = true;
    _error = null;
    _notice = null;
    _notify();
    try {
      // Jika profil belum pernah punya kunci publik, daftarkan sekalian.
      if (_profile == null ||
          _profile!.publicKeyBase64 == null ||
          _profile!.publicKeyBase64!.isEmpty) {
        final publicKey = await _identity.publicKey();
        final registered = await _profiles.registerProfile(
          username: validation.normalized,
          publicKeyBase64: base64Encode(publicKey),
        );
        if (_user?.id != userId) return null;
        _profile = _mergeWithLocalProfile(registered, authUser: _user);
        await _persistProfileAndPlus(_profile!);
        _deviceKeyMismatch = false;
        _notice = 'Username @${registered.username} berhasil disimpan.';
        await _refreshGroupsInternal(_generation);
        return null;
      }

      final updated = await _profiles.setUsername(validation.normalized);
      if (_user?.id != userId) return null;
      _profile = _mergeWithLocalProfile(updated, authUser: _user);
      await _persistProfileAndPlus(_profile!);
      _notice = 'Username berhasil diganti menjadi @${updated.username}.';
      return null;
    } catch (error) {
      final String msg;
      if (error is AccountException) {
        final mapped = UsernamePolicy.mapServerError(error.code);
        msg = mapped.code != 'server_error' ? mapped.message : error.message;
      } else {
        msg = _friendly(error);
      }
      _error = msg;
      return msg;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Mengecek ketersediaan username untuk formulir onboarding / ganti username.
  Future<UsernameAvailabilityResult> checkUsernameAvailability(
    String rawInput,
  ) async {
    final validation = UsernamePolicy.validate(
      rawInput,
      userEmail: _user?.email,
    );
    if (!validation.isValid) {
      return UsernameAvailabilityResult(
        available: false,
        reason: validation.isReserved ? 'blocked' : 'invalid_format',
      );
    }
    try {
      return await _profiles.checkUsernameAvailability(validation.normalized);
    } catch (_) {
      return const UsernameAvailabilityResult(
        available: false,
        reason: 'network_error',
      );
    }
  }

  /// Menyelesaikan onboarding profil pengguna baru (nama tampilan + username +
  /// foto profil opsional).
  Future<String?> completeOnboardingProfile({
    required String fullName,
    required String username,
    Uint8List? avatarWebpBytes,
    R2Uploader? avatarUploader,
  }) async {
    final user = _user;
    if (user == null) return 'Masuk ke akun terlebih dahulu.';
    final nameErr = UsernamePolicy.validateDisplayName(
      fullName,
      userEmail: user.email,
    );
    if (nameErr != null) return nameErr;
    final usernameVal = UsernamePolicy.validate(
      username,
      userEmail: user.email,
    );
    if (!usernameVal.isValid) {
      return usernameVal.errorMessage ?? 'Format username tidak sesuai.';
    }
    if (_busy) return 'Sedang memproses permintaan lain.';

    _busy = true;
    _error = null;
    _notice = null;
    _notify();
    try {
      final publicKey = await _identity.publicKey();
      var savedProfile = await _profiles.registerProfile(
        username: usernameVal.normalized,
        publicKeyBase64: base64Encode(publicKey),
      );
      if (_user?.id != user.id) return null;

      savedProfile = await _profiles.updateFullName(fullName.trim());
      if (_user?.id != user.id) return null;

      String? uploadedUrl = savedProfile.avatarUrl;
      String? localAvatarPath = savedProfile.localAvatarPath;
      if (avatarWebpBytes != null && avatarWebpBytes.isNotEmpty) {
        final publicUrl = avatarUploader != null
            ? await avatarUploader.upload(
                kind: R2Kind.avatar,
                bytes: avatarWebpBytes,
                contentType: 'image/webp',
              )
            : await R2MediaService.instance.uploadPreparedAvatarWebp(
                avatarWebpBytes,
                userId: user.id,
              );
        savedProfile = await _profiles.updateAvatarUrl(publicUrl);
        uploadedUrl = publicUrl;
        localAvatarPath = await _cache?.saveAvatarBytes(
          userId: user.id,
          avatarUrl: publicUrl,
          bytes: avatarWebpBytes,
        );
        if (localAvatarPath != null) {
          evictLocalAvatarFileCache(localAvatarPath);
        }
      }

      if (_user?.id != user.id) return null;
      _profile = _mergeWithLocalProfile(savedProfile, authUser: user).copyWith(
        username: usernameVal.normalized,
        fullName: fullName.trim(),
        avatarUrl: uploadedUrl,
        localAvatarPath: localAvatarPath,
        isProfileComplete: true,
        isOfficial: savedProfile.isOfficial ||
            (UsernamePolicy.isOfficialEmail(user.email) &&
                usernameVal.normalized == UsernamePolicy.officialUsername),
      );
      _profileResolved = true;
      await _persistProfileAndPlus(_profile!);
      await _refreshGroupsInternal(_generation);
      return null;
    } catch (error) {
      final String msg;
      if (error is AccountException) {
        final mapped = UsernamePolicy.mapServerError(error.code);
        msg = mapped.code != 'server_error' ? mapped.message : error.message;
      } else {
        msg = _friendly(error);
      }
      _error = msg;
      return msg;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Memperbarui daftar penyedia login (Google/Apple) yang tertaut ke akun ini.
  Future<void> refreshLinkedIdentities() async {
    if (_user == null) {
      if (_linkedIdentities.isNotEmpty) {
        _linkedIdentities = const <LinkedIdentity>[];
        _notify();
      }
      return;
    }
    try {
      final identities = await _auth.linkedIdentities();
      if (_disposed) return;
      if (!listEquals(identities, _linkedIdentities)) {
        _linkedIdentities = identities;
        _notify();
      }
    } catch (_) {}
  }

  /// Menautkan akun Google atau Apple tambahan ke akun yang sedang masuk tanpa
  /// menghapus data atau mengeluarkan sesi saat ini.
  Future<bool> linkProvider(AuthProviderKind provider) async {
    if (!isConfigured || _user == null || _linkingProvider != null) {
      return false;
    }
    _linkingProvider = provider;
    _linkingError = null;
    _linkingNotice = null;
    _notify();
    try {
      await _auth.linkProvider(provider);
      await refreshLinkedIdentities();
      if (!_disposed) {
        final label = provider == AuthProviderKind.apple ? 'Apple' : 'Google';
        _linkingNotice = isProviderLinked(provider)
            ? 'Akun $label berhasil ditautkan.'
            : 'Selesaikan penautan akun $label di browser. Aplikasi akan terbuka kembali otomatis.';
      }
      return true;
    } on AuthFailure catch (failure) {
      if (failure.code != AuthFailureCode.cancelled && !_disposed) {
        _linkingError = failure.message;
      }
      return false;
    } catch (error) {
      if (!_disposed) {
        _linkingError = _friendly(error);
      }
      return false;
    } finally {
      _linkingProvider = null;
      _notify();
    }
  }

  void clearLinkingMessages() {
    if (_linkingError == null && _linkingNotice == null) return;
    _linkingError = null;
    _linkingNotice = null;
    _notify();
  }

  /// Mengunggah foto profil WebP 1:1 (maks 512px) ke R2 (`avatars/{uid}.webp`)
  /// lalu memperbarui `profiles.avatar_url` & cache lokal.
  Future<String?> updateProfilePhoto(
    Uint8List webpBytes, {
    R2Uploader? uploader,
  }) async {
    final user = _user;
    if (user == null) return 'Masuk ke akun terlebih dahulu.';
    if (_busy) return 'Sedang memproses permintaan lain.';

    _busy = true;
    _error = null;
    _notice = null;
    _notify();
    try {
      final prevAvatarUrl = _profile?.avatarUrl;
      final publicUrl = uploader != null
          ? await uploader.upload(
              kind: R2Kind.avatar,
              bytes: webpBytes,
              contentType: 'image/webp',
            )
          : await R2MediaService.instance.uploadPreparedAvatarWebp(
              webpBytes,
              userId: user.id,
            );
      final updated = await _profiles.updateAvatarUrl(publicUrl);
      if (_user?.id != user.id) return null;
      PublicProfileCacheService.evictAvatarFromImageCache(prevAvatarUrl);
      final localPath = await _cache?.saveAvatarBytes(
        userId: user.id,
        avatarUrl: publicUrl,
        bytes: webpBytes,
      );
      if (localPath != null) evictLocalAvatarFileCache(localPath);
      _profile = _mergeWithLocalProfile(updated, authUser: user).copyWith(
        avatarUrl: publicUrl,
        localAvatarPath: localPath,
      );
      await _persistProfileAndPlus(_profile!);
      _notice = 'Foto profil berhasil diperbarui.';
      return null;
    } catch (error) {
      final msg = error is StateError ? error.message : _friendly(error);
      _error = msg;
      return msg;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Memperbarui nama tampilan / nama akun (`profiles.full_name`) sekaligus
  /// cache lokal & state in-memory agar Beranda, Profil, dan chat langsung
  /// menampilkan nama terbaru tanpa restart.
  Future<String?> updateFullName(String input) async {
    final user = _user;
    if (user == null) return 'Masuk ke akun terlebih dahulu.';
    final trimmed = input.trim();
    final nameErr = UsernamePolicy.validateDisplayName(
      trimmed,
      userEmail: user.email,
    );
    if (nameErr != null) {
      return nameErr;
    }
    if (_busy) return 'Sedang memproses permintaan lain.';

    _busy = true;
    _error = null;
    _notice = null;
    _notify();
    try {
      final updated = await _profiles.updateFullName(trimmed);
      if (_user?.id != user.id) return null;
      _profile = _mergeWithLocalProfile(updated, authUser: user).copyWith(
        fullName: trimmed,
      );
      await _persistProfileAndPlus(_profile!);
      _notice = 'Nama akun berhasil diperbarui.';
      return null;
    } catch (error) {
      final msg = error is AccountException ? error.message : _friendly(error);
      _error = msg;
      return msg;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> signOut() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      final prevUserId = _user?.id;
      if (SupabaseServices.isAvailable) {
        AppPresenceService.instance.stop();
        GroupAutoLocationService.instance.stop();
        unawaited(ChatMuteService.instance.clearLocal(userId: prevUserId));
        UserNotificationsService.instance.clear();
        FriendsService.instance.clear();
      }
      await PushNotificationService.instance.clearTokenForCurrentUser();
      await _auth.signOut();
      await _stopRealtime();
      await EmergencyContactSyncService.instance.disposeChannel();
      _cloudBackupSyncedUserId = null;
      if (prevUserId != null) {
        await _cache?.clearUser(prevUserId);
      }
      await _plusController?.clearAccountPlus();
      _generation++;
      _user = null;
      _profile = null;
      _profileResolved = false;
      _linkedIdentities = const <LinkedIdentity>[];
      _linkingProvider = null;
      _linkingError = null;
      _linkingNotice = null;
      _deviceKeyMismatch = false;
      _invitations = const <IncomingInvitation>[];
      _groups = const <RemoteGroup>[];
      _memberCounts = const <String, int>{};
      _membersByGroup = const <String, List<MemberDirectoryEntry>>{};
      _keyStatuses = const <String, GroupKeyStatus>{};
      _keyErrors = const <String, String>{};
      _knownInvitationIds.clear();
      _hasHydratedInvitations = false;
      _hasSyncedGroupsFromServer = false;
      _groupsStore.clearLocalGroups();
      await _resetLocalAccountState(nextUserId: null);
      _notice = 'Sudah keluar. Kunci identitas tetap tersimpan di perangkat.';
    } catch (error) {
      _error = _friendly(error);
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Menghapus akun dan seluruh datanya di server via RPC `delete_my_account`,
  /// lalu mereset sesi di pengendali akun.
  Future<bool> deleteAccount() async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _notify();
    try {
      final prevUserId = _user?.id;
      if (SupabaseServices.isAvailable) {
        AppPresenceService.instance.stop();
        GroupAutoLocationService.instance.stop();
        unawaited(ChatMuteService.instance.clearLocal(userId: prevUserId));
        UserNotificationsService.instance.clear();
        FriendsService.instance.clear();
      }
      await PushNotificationService.instance.clearTokenForCurrentUser();
      await _auth.deleteAccount();
      await _stopRealtime();
      await EmergencyContactSyncService.instance.disposeChannel();
      _cloudBackupSyncedUserId = null;
      if (prevUserId != null) {
        await _cache?.clearUser(prevUserId);
      }
      await _plusController?.clearAccountPlus();
      _generation++;
      _user = null;
      _profile = null;
      _profileResolved = false;
      _linkedIdentities = const <LinkedIdentity>[];
      _linkingProvider = null;
      _linkingError = null;
      _linkingNotice = null;
      _deviceKeyMismatch = false;
      _invitations = const <IncomingInvitation>[];
      _groups = const <RemoteGroup>[];
      _memberCounts = const <String, int>{};
      _membersByGroup = const <String, List<MemberDirectoryEntry>>{};
      _keyStatuses = const <String, GroupKeyStatus>{};
      _keyErrors = const <String, String>{};
      _knownInvitationIds.clear();
      _hasHydratedInvitations = false;
      _hasSyncedGroupsFromServer = false;
      _groupsStore.clearLocalGroups();
      await _resetLocalAccountState(nextUserId: null);
      _notice = 'Akun dan seluruh data berhasil dihapus.';
      return true;
    } catch (error) {
      _error = _friendly(error);
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> registerUsername(String input) async {
    if (_busy || _user == null) return;
    final normalized = normalizeUsername(input);
    if (!isValidUsername(normalized)) {
      _error =
          'Username harus 3-20 karakter: huruf kecil, angka, titik, garis bawah.';
      _notify();
      return;
    }
    final userId = _user!.id;
    _busy = true;
    _error = null;
    _notify();
    try {
      final publicKey = await _identity.publicKey();
      final profile = await _profiles.registerProfile(
        username: normalized,
        publicKeyBase64: base64Encode(publicKey),
      );
      if (_user?.id != userId) return;
      _profile = _mergeWithLocalProfile(profile);
      await _persistProfileAndPlus(_profile!);
      _deviceKeyMismatch = false;
      _notice = 'Username @${profile.username} terdaftar.';
      await _refreshGroupsInternal(_generation);
    } catch (error) {
      _error = _friendly(error);
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Mendaftarkan ulang kunci perangkat saat kunci lokal berbeda dari direktori.
  /// Kunci grup yang dibungkus untuk kunci lama tidak dapat dipulihkan.
  Future<void> registerCurrentDeviceKey() async {
    final profile = _profile;
    if (_busy || profile == null || profile.username == null) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      final publicKey = await _identity.publicKey();
      final updated = await _profiles.registerProfile(
        username: profile.username!,
        publicKeyBase64: base64Encode(publicKey),
      );
      _profile = _mergeWithLocalProfile(updated);
      await _persistProfileAndPlus(_profile!);
      _deviceKeyMismatch = false;
      _notice =
          'Kunci perangkat diperbarui. Kunci grup lama tidak dapat dibuka.';
      await _refreshGroupsInternal(_generation);
    } catch (error) {
      _error = _friendly(error);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      if (_user != null) {
        await _fetchProfileFromServer(_user!, _generation);
      }
      await _refreshGroupsInternal(_generation, allowRealtimeNotify: true);
      _ensureRealtimeSubscribed();
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Menyinkronkan daftar grup aktif langsung dari server (`my_groups` -> join
  /// `group_members` & `groups`) dan merekonsiliasi cache lokal secara penuh.
  Future<void> refreshGroups({bool force = false}) async {
    if (!groupsEnabled || _user == null || _refreshingGroups) return;
    final nowUtc = _clock.nowUtc();
    if (!force &&
        _lastGroupRefreshAtUtc != null &&
        nowUtc.difference(_lastGroupRefreshAtUtc!) <
            const Duration(seconds: 5)) {
      return;
    }
    _lastGroupRefreshAtUtc = nowUtc;
    _refreshingGroups = true;
    try {
      await _refreshGroupsInternal(_generation, allowRealtimeNotify: true);
      _ensureRealtimeSubscribed();
    } finally {
      _refreshingGroups = false;
      _notify();
    }
  }

  Future<bool> createGroup(String name, {String? mountain}) =>
      createGroupWithOptions(name: name, mountain: mountain);

  Future<bool> createGroupWithOptions({
    required String name,
    String? mountain,
    File? avatarFile,
    Future<String> Function(Uint8List webpBytes, String groupId)?
        avatarUploader,
  }) async {
    if (!groupsEnabled || _busy) return false;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 60) {
      _error = 'Nama grup harus 1-60 karakter.';
      _notify();
      return false;
    }
    _busy = true;
    _error = null;
    _notify();
    var created = false;
    try {
      final prepFuture = avatarFile != null
          ? R2MediaService.instance
              .prepareAvatarWebp(avatarFile)
              .catchError((_) => Uint8List(0))
          : Future<Uint8List?>.value(null);
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _groupRemote!.createGroup(name: trimmed, mountain: mountain),
        prepFuture,
      ]);
      var remoteGroup = results[0] as RemoteGroup;
      final webpBytes = results[1] as Uint8List?;

      if (webpBytes != null && webpBytes.isNotEmpty) {
        try {
          final uploader = avatarUploader ??
              (Uint8List bytes, String gid) => R2MediaService.instance
                  .uploadPreparedGroupAvatarWebp(bytes, groupId: gid);
          final avatarUrl = await uploader(webpBytes, remoteGroup.group.id);
          if (_groupRemote is GroupAvatarUpdater) {
            await (_groupRemote as GroupAvatarUpdater).updateGroupAvatar(
              groupId: remoteGroup.group.id,
              avatarUrl: avatarUrl,
            );
          }
          remoteGroup = remoteGroup.copyWith(
            group: remoteGroup.group.copyWith(avatarUrl: avatarUrl),
          );
        } catch (_) {
          // Kegagalan unggah foto profil grup tidak membatalkan grup yang sudah dibuat.
        }
      }

      // Tampilkan grup baru seketika di daftar (optimistic) tanpa menunggu round-trip penuh.
      _groups = List<RemoteGroup>.unmodifiable(<RemoteGroup>[
        remoteGroup,
        for (final g in _groups)
          if (g.group.id != remoteGroup.group.id) g,
      ]);
      _memberCounts = <String, int>{
        ..._memberCounts,
        remoteGroup.group.id: 1,
      };
      if (_user != null && _profile != null) {
        _membersByGroup = <String, List<MemberDirectoryEntry>>{
          ..._membersByGroup,
          remoteGroup.group.id: <MemberDirectoryEntry>[
            MemberDirectoryEntry(
              userId: _user!.id,
              username: _profile!.username ?? '',
              displayName: _profile!.fullName,
              avatarUrl: _profile!.avatarUrl,
              role: GroupRole.owner,
              publicKeyBase64: _profile!.publicKeyBase64 ?? '',
              joinedAtUtc:
                  remoteGroup.joinedAtUtc ?? remoteGroup.group.createdAtUtc,
            ),
          ],
        };
      }
      _notice = 'Grup "${remoteGroup.group.name}" dibuat.';
      _busy = false;
      _notify();

      unawaited(_persistGroupsToCache());
      _ensureRealtimeSubscribed();
      unawaited(_ensureNewGroupKeyInBackground(remoteGroup));
      created = true;
    } catch (error) {
      _error = _friendly(error);
      _busy = false;
      _notify();
    }
    return created;
  }

  Future<void> _ensureNewGroupKeyInBackground(RemoteGroup group) async {
    if (_disposed || _deviceKeyMismatch || _groupKeys == null) return;
    try {
      final status = await _groupKeys.ensureOwnedGroupKey(group);
      if (_disposed) return;
      _keyStatuses = <String, GroupKeyStatus>{
        ..._keyStatuses,
        group.group.id: status,
      };
      if (status.availability == GroupKeyAvailability.ready) {
        _emitGroupKeyReady(group.group.id);
      }
      _notify();
    } catch (_) {}
  }

  Future<bool> deleteGroup(String groupId) async {
    if (!groupsEnabled || _busy) return false;
    _busy = true;
    _error = null;
    _notify();
    try {
      await _groupRemote!.deleteGroup(groupId);
      await _purgeDeletedOrLeftGroupLocally(groupId);
      _notice = 'Grup dihapus.';
      return true;
    } catch (error) {
      _error = _friendly(error);
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> leaveGroup(String groupId) async {
    if (!groupsEnabled || _busy) return false;
    _busy = true;
    _error = null;
    _notify();
    try {
      await _groupRemote!.leaveGroup(groupId);
      await _purgeDeletedOrLeftGroupLocally(groupId);
      _notice = 'Kamu keluar dari grup.';
      return true;
    } catch (error) {
      _error = _friendly(error);
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _purgeDeletedOrLeftGroupLocally(String groupId) async {
    _groups =
        _groups.where((g) => g.group.id != groupId).toList(growable: false);
    _memberCounts = Map<String, int>.of(_memberCounts)..remove(groupId);
    _membersByGroup =
        Map<String, List<MemberDirectoryEntry>>.of(_membersByGroup)
          ..remove(groupId);
    _keyStatuses = Map<String, GroupKeyStatus>.of(_keyStatuses)
      ..remove(groupId);
    _keyErrors = Map<String, String>.of(_keyErrors)..remove(groupId);

    // Pertahankan tombstone sebelum membersihkan cache lain agar rekonsiliasi
    // antar-perangkat tidak membangkitkan kembali grup yang baru dihapus.
    await _groupsStore.markGroupDeleted(groupId);
    final uid = _user?.id;
    final cache = _cache;
    if (uid != null && cache is GroupCachePurger) {
      await (cache as GroupCachePurger).purgeGroup(uid, groupId);
    }
    await _persistGroupsToCache();
    await _groupKeys?.purgeLocalGroupKey(groupId);
    await SocialUnreadStore.instance.clearGroup(groupId);
  }

  Future<bool> invite({
    required String groupId,
    required String username,
  }) async {
    if (!groupsEnabled || _busy) return false;
    final normalized = normalizeUsername(username);
    if (!isValidUsername(normalized)) {
      _error = 'Username tidak valid.';
      _notify();
      return false;
    }
    _busy = true;
    _error = null;
    _notify();
    var sent = false;
    try {
      final entry = await _directory.findByUsername(normalized);
      if (entry == null) {
        _error = 'Username @$normalized tidak ditemukan (harus persis).';
        return false;
      }
      await _groupRemote!.inviteByUsername(
        groupId: groupId,
        username: entry.username,
      );
      _notice =
          'Undangan untuk @${entry.username} dibuat. Status masih menunggu penerimaan.';
      sent = true;
    } catch (error) {
      _error = _friendly(error);
    } finally {
      _busy = false;
      _notify();
    }
    return sent;
  }

  Future<void> respondToInvitation(
    IncomingInvitation invitation, {
    required bool accept,
  }) async {
    if (!groupsEnabled || _busy) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      final status = await _groupRemote!.respondToInvitation(
        invitationId: invitation.id,
        accept: accept,
        nowUtc: _clock.nowUtc(),
      );
      _invitations = _invitations
          .where((item) => item.id != invitation.id)
          .toList(growable: false);
      if (_user != null) {
        await _cache?.writeInvitations(_user!.id, _invitations);
      }
      if (status == InvitationStatus.accepted) {
        _notice = 'Undangan diterima. Menunggu pemilik membagikan kunci grup.';
      } else if (status == InvitationStatus.rejected) {
        _notice = 'Undangan ditolak.';
      } else if (status == InvitationStatus.expired) {
        _notice = 'Undangan sudah kedaluwarsa.';
      }
      await _refreshGroupsInternal(_generation);
      _ensureRealtimeSubscribed();
    } catch (error) {
      _error = _friendly(error);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> ensureGroupKey(String groupId) async {
    if (!groupsEnabled || _busy) return;
    if (_deviceKeyMismatch) {
      _error = 'Kunci perangkat berbeda dari direktori. Daftarkan ulang kunci '
          'perangkat sebelum memakai kunci grup.';
      _notify();
      return;
    }
    final matching = _groups.where((group) => group.group.id == groupId);
    if (matching.isEmpty) return;
    final group = matching.first;
    _busy = true;
    _error = null;
    _notify();
    try {
      final status = group.isOwner
          ? await _groupKeys!.ensureOwnedGroupKey(group)
          : await _groupKeys!.ensureMembershipKey(group);
      _keyStatuses = <String, GroupKeyStatus>{..._keyStatuses, groupId: status};
      _keyErrors = <String, String>{..._keyErrors}..remove(groupId);
      if (status.memberCount > 0) {
        _memberCounts = <String, int>{
          ..._memberCounts,
          groupId: status.memberCount,
        };
      }
      _notice = group.isOwner
          ? 'Kunci grup versi ${status.keyVersion} siap untuk ${status.memberCount} anggota.'
          : 'Kunci grup versi ${status.keyVersion} dimuat.';
      if (status.availability == GroupKeyAvailability.ready) {
        _emitGroupKeyReady(groupId);
        if (_groupRemote is GroupMissingKeyProvider) {
          unawaited(_groupKeys.shareKeyWithMissingMembers(group));
        }
      }
    } on GroupKeyPendingException {
      _keyStatuses = <String, GroupKeyStatus>{
        ..._keyStatuses,
        groupId: GroupKeyStatus(
          availability: GroupKeyAvailability.waitingForOwner,
          keyVersion: group.group.keyVersion,
        ),
      };
      _notice =
          'Masih menunggu pemilik membagikan kunci versi ${group.group.keyVersion}.';
    } catch (error) {
      _error = _friendly(error);
      _keyErrors = <String, String>{..._keyErrors, groupId: _friendly(error)};
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Memastikan kunci grup [groupId] sudah dimiliki secara lokal maupun
  /// dibagikan ke seluruh anggota yang belum menerima `group_key_blobs`.
  ///
  /// Sengaja tidak diblokir oleh [_busy] agar Realtime & ruang obrolan tetap
  /// dapat mendistribusikan kunci secara instan tanpa terkunci operasi lain.
  Future<bool> ensureGroupKeyDistributed(String groupId) async {
    if (!groupsEnabled ||
        _deviceKeyMismatch ||
        _disposed ||
        groupId.isEmpty ||
        _keySyncInFlight.contains(groupId)) {
      return _keyStatuses[groupId]?.availability == GroupKeyAvailability.ready;
    }
    final matching = _groups.where((g) => g.group.id == groupId);
    if (matching.isEmpty) return false;
    final group = matching.first;

    _keySyncInFlight.add(groupId);
    try {
      final ready = await _groupKeys!.shareKeyWithMissingMembers(group);
      if (ready && !_disposed) {
        _keyStatuses = <String, GroupKeyStatus>{
          ..._keyStatuses,
          groupId: GroupKeyStatus(
            availability: GroupKeyAvailability.ready,
            keyVersion: group.group.keyVersion,
            memberCount: memberCountFor(groupId),
          ),
        };
        _keyErrors = <String, String>{..._keyErrors}..remove(groupId);
        _emitGroupKeyReady(groupId);
        _notify();
      }
      return ready;
    } on GroupKeyPendingException {
      if (!_disposed) {
        _keyStatuses = <String, GroupKeyStatus>{
          ..._keyStatuses,
          groupId: GroupKeyStatus(
            availability: GroupKeyAvailability.waitingForOwner,
            keyVersion: group.group.keyVersion,
          ),
        };
        _notify();
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _keySyncInFlight.remove(groupId);
    }
  }

  void _scheduleMembershipKeyDistribution(String groupId) {
    if (groupId.isEmpty || _disposed || _deviceKeyMismatch) return;
    _membershipKeyTimers.remove(groupId)?.cancel();
    _membershipKeyTimers[groupId] = Timer(
      const Duration(milliseconds: 250),
      () {
        _membershipKeyTimers.remove(groupId);
        unawaited(ensureGroupKeyDistributed(groupId));
      },
    );
  }

  Future<void> _handleUser(AuthUser? user) async {
    final generation = ++_generation;
    final previousUserId = _user?.id;
    final switchingFromOtherUser =
        previousUserId != null && previousUserId != user?.id;
    final switchingUser = previousUserId != user?.id;
    _user = user;
    _error = null;
    _notice = null;

    if (user == null) {
      if (SupabaseServices.isAvailable) {
        AppPresenceService.instance.stop();
        UserNotificationsService.instance.clear();
      }
      await _stopRealtime();
      _profile = null;
      _profileResolved = false;
      _linkedIdentities = const <LinkedIdentity>[];
      _linkingProvider = null;
      _linkingError = null;
      _linkingNotice = null;
      _deviceKeyMismatch = false;
      _invitations = const <IncomingInvitation>[];
      _groups = const <RemoteGroup>[];
      _memberCounts = const <String, int>{};
      _membersByGroup = const <String, List<MemberDirectoryEntry>>{};
      _keyStatuses = const <String, GroupKeyStatus>{};
      _keyErrors = const <String, String>{};
      _knownInvitationIds.clear();
      _hasHydratedInvitations = false;
      _hasSyncedGroupsFromServer = false;
      _loading = false;
      _groupsStore.clearLocalGroups();
      await _resetLocalAccountState(nextUserId: null);
      _notify();
      return;
    }

    if (switchingFromOtherUser) {
      if (SupabaseServices.isAvailable) {
        AppPresenceService.instance.stop();
        GroupAutoLocationService.instance.stop();
        unawaited(ChatMuteService.instance.setActiveUser(user.id));
        UserNotificationsService.instance.clear();
        FriendsService.instance.clear();
      }
      _cloudBackupSyncedUserId = null;
      _profile = null;
      _profileResolved = false;
      _linkedIdentities = const <LinkedIdentity>[];
      _linkingProvider = null;
      _linkingError = null;
      _linkingNotice = null;
      _deviceKeyMismatch = false;
      _invitations = const <IncomingInvitation>[];
      _groups = const <RemoteGroup>[];
      _memberCounts = const <String, int>{};
      _membersByGroup = const <String, List<MemberDirectoryEntry>>{};
      _keyStatuses = const <String, GroupKeyStatus>{};
      _keyErrors = const <String, String>{};
      _knownInvitationIds.clear();
      _hasHydratedInvitations = false;
      _hasSyncedGroupsFromServer = false;
      _groupsStore.clearLocalGroups();
      await _resetLocalAccountState(nextUserId: user.id);
    } else {
      if (switchingUser) {
        _profile = null;
        _profileResolved = false;
        _linkedIdentities = const <LinkedIdentity>[];
        _linkingProvider = null;
        _linkingError = null;
        _linkingNotice = null;
        _deviceKeyMismatch = false;
        _invitations = const <IncomingInvitation>[];
        _groups = const <RemoteGroup>[];
        _memberCounts = const <String, int>{};
        _membersByGroup = const <String, List<MemberDirectoryEntry>>{};
        _keyStatuses = const <String, GroupKeyStatus>{};
        _keyErrors = const <String, String>{};
        _knownInvitationIds.clear();
        _hasHydratedInvitations = false;
        _hasSyncedGroupsFromServer = false;
      }
      ActiveAccountScope.setActiveUserId(user.id);
    }

    // Daftarkan token FCM ke `profiles.fcm_token` setelah login berhasil.
    unawaited(PushNotificationService.instance.registerForCurrentUser());
    if (SupabaseServices.isAvailable) {
      AppPresenceService.instance.start();
      unawaited(ChatMuteService.instance.setActiveUser(user.id).then((_) => ChatMuteService.instance.loadAll(forceRemote: true)));
      unawaited(UserNotificationsService.instance.loadNotifications());
      UserNotificationsService.instance.ensureRealtimeSubscribed();
    }

    // 1. Hidrasi instan dari cache lokal (offline-first, tanpa delay)
    final hydratedFromCache = await _hydrateFromLocalCache(user, generation);
    if (generation != _generation) return;

    // Hanya tampilkan indikator loading penuh bila cache lokal masih kosong.
    _loading = !hydratedFromCache;
    _notify();

    // 2. Sinkronkan dari Supabase di latar tanpa mengosongkan state cache bila gagal
    try {
      final fetched = await _fetchProfileFromServer(user, generation);
      if (generation != _generation) return;
      _profileResolved = true;
      unawaited(refreshLinkedIdentities());
      if (fetched != null || _profile != null) {
        await _refreshGroupsInternal(generation);
      }
      _ensureRealtimeSubscribed();
    } catch (error) {
      // Jangan pernah mengosongkan profil / grup / undangan lokal saat offline.
      if (generation == _generation) {
        if (hydratedFromCache) {
          _profileResolved = true;
        } else {
          _error = _friendly(error);
        }
      }
    } finally {
      if (generation == _generation) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<bool> _hydrateFromLocalCache(AuthUser user, int generation) async {
    final cache = _cache;
    if (cache == null) return false;
    try {
      await _groupsStore.load();
      final cachedProfile = await cache.readProfile(user.id);
      final cachedGroups = await cache.readGroups(user.id);
      final cachedInvitations = await cache.readInvitations(user.id);
      if (generation != _generation) return false;

      var hasAny = false;
      if (cachedProfile != null) {
        _profile = cachedProfile;
        if (cachedProfile.isProfileComplete &&
            (cachedProfile.fullName?.trim().isNotEmpty == true)) {
          _profileResolved = true;
        }
        hasAny = true;
        try {
          await _plusController?.syncAccountPlus(
            userId: cachedProfile.userId,
            isPlus: cachedProfile.isPlus,
            planId: cachedProfile.plusPlanId,
            startedAtUtc: cachedProfile.plusStartedAtUtc,
            expiresAtUtc: cachedProfile.plusExpiresAtUtc,
          );
        } catch (_) {}
      }
      final deletedIds = _groupsStore.deletedGroupIds;
      final activeCachedGroups = cachedGroups
          .where((e) => !deletedIds.contains(e.remote.group.id))
          .toList(growable: false);
      if (activeCachedGroups.length != cachedGroups.length) {
        // Pembersihan otomatis baris grup hantu/terhapus dari SQLite saat startup.
        await cache.writeGroups(user.id, activeCachedGroups);
      }
      if (activeCachedGroups.isNotEmpty) {
        _groups =
            activeCachedGroups.map((e) => e.remote).toList(growable: false);
        final counts = <String, int>{};
        final membersMap = <String, List<MemberDirectoryEntry>>{};
        for (final entry in activeCachedGroups) {
          final gid = entry.remote.group.id;
          counts[gid] = entry.memberCount;
          final members = await cache.readMembers(gid);
          if (members.isNotEmpty) {
            _seedPublicProfilesFromMembers(members);
            membersMap[gid] = List<MemberDirectoryEntry>.unmodifiable(members);
            counts[gid] = math.max(entry.memberCount, members.length);
          }
        }
        if (SupabaseServices.isAvailable) {
          unawaited(
              FriendsService.instance.loadCached(userIdOverride: user.id));
        }
        if (generation != _generation) return false;
        _memberCounts = counts;
        _membersByGroup = membersMap;
        hasAny = true;
      } else if (cachedGroups.isNotEmpty) {
        _groups = const <RemoteGroup>[];
        _memberCounts = const <String, int>{};
        _membersByGroup = const <String, List<MemberDirectoryEntry>>{};
      }
      if (cachedInvitations.isNotEmpty) {
        final nowUtc = _clock.nowUtc();
        _invitations = cachedInvitations
            .where((i) => i.effectiveStatus(nowUtc) == InvitationStatus.pending)
            .toList(growable: false);
        for (final inv in _invitations) {
          _knownInvitationIds.add(inv.id);
        }
        _hasHydratedInvitations = true;
        hasAny = true;
      }
      if (hasAny) {
        _notify();
      }
      return hasAny;
    } catch (_) {
      return false;
    }
  }

  Future<UserProfile?> _fetchProfileFromServer(
    AuthUser user,
    int generation,
  ) async {
    final remoteProfile = await _profiles.currentProfile();
    if (generation != _generation) return null;
    if (remoteProfile == null) {
      // Server mengembalikan null secara eksplisit (pengguna belum punya baris
      // profil) — hanya kosongkan jika sebelumnya belum ada profil lengkap.
      if (_profile == null || !_profile!.isProfileComplete) {
        _profile = null;
      }
      return null;
    }

    final merged = _mergeWithLocalProfile(remoteProfile, authUser: user);
    _profile = merged;

    if (merged.publicKeyBase64 != null && merged.publicKeyBase64!.isNotEmpty) {
      final publicKey = await _identity.publicKey();
      if (generation != _generation) return null;
      final localB64 = base64Encode(publicKey);
      final mismatch = !_sameKey(merged.publicKeyBase64!, localB64);
      if (mismatch &&
          merged.username != null &&
          merged.username!.trim().isNotEmpty) {
        // Auto-rekonsiliasi kunci perangkat secara diam-diam agar pengguna
        // tidak pernah terblokir pesan "Kunci perangkat berbeda dari direktori".
        try {
          final synced = await _profiles.registerProfile(
            username: merged.username!,
            publicKeyBase64: localB64,
          );
          _profile = _mergeWithLocalProfile(synced, authUser: user);
          _deviceKeyMismatch = false;
        } catch (_) {
          _deviceKeyMismatch = false;
        }
      } else {
        _deviceKeyMismatch = false;
      }
    } else {
      _deviceKeyMismatch = false;
    }

    await _persistProfileAndPlus(merged);

    // Unduh file gambar avatar ke penyimpanan lokal agar tetap tampil offline.
    final effectiveAvatarUrl = (merged.avatarUrl?.trim().isNotEmpty == true)
        ? merged.avatarUrl!.trim()
        : user.avatarUrl?.trim();
    if (effectiveAvatarUrl != null &&
        effectiveAvatarUrl.isNotEmpty &&
        _cache != null) {
      unawaited(
        _cacheAvatarFile(
          userId: user.id,
          avatarUrl: effectiveAvatarUrl,
          generation: generation,
        ),
      );
    }

    return merged;
  }

  Future<void> _cacheAvatarFile({
    required String userId,
    required String avatarUrl,
    required int generation,
  }) async {
    final path = await _cache?.cacheAvatarFile(
      userId: userId,
      avatarUrl: avatarUrl,
    );
    if (path == null ||
        path.isEmpty ||
        generation != _generation ||
        _disposed) {
      return;
    }
    final current = _profile;
    if (current == null || current.userId != userId) return;
    if (current.localAvatarPath == path) return;
    evictLocalAvatarFileCache(path);
    final updated = current.copyWith(localAvatarPath: path);
    _profile = updated;
    await _cache?.writeProfile(updated);
    _notify();
  }

  UserProfile _mergeWithLocalProfile(
    UserProfile incoming, {
    AuthUser? authUser,
  }) {
    final existing = _profile;
    final resolvedName = incoming.fullName?.trim().isNotEmpty == true
        ? incoming.fullName
        : (authUser?.displayName?.trim().isNotEmpty == true
            ? authUser!.displayName
            : existing?.fullName);
    final resolvedAvatar = incoming.avatarUrl?.trim().isNotEmpty == true
        ? incoming.avatarUrl
        : (authUser?.avatarUrl?.trim().isNotEmpty == true
            ? authUser!.avatarUrl
            : existing?.avatarUrl);
    final resolvedEmail = incoming.email?.trim().isNotEmpty == true
        ? incoming.email
        : (authUser?.email ?? existing?.email);
    final resolvedComplete = incoming.isProfileComplete ||
        (existing != null &&
            existing.userId == incoming.userId &&
            existing.isProfileComplete);
    return incoming.copyWith(
      fullName: resolvedName,
      avatarUrl: resolvedAvatar,
      localAvatarPath: incoming.localAvatarPath ?? existing?.localAvatarPath,
      email: resolvedEmail,
      isProfileComplete: resolvedComplete,
    );
  }

  Future<void> _persistProfileAndPlus(UserProfile profile) async {
    unawaited(
      PublicProfileCacheService.instance.putAll(<PublicProfile>[
        PublicProfile(
          userId: profile.userId,
          username: profile.username,
          fullName: profile.fullName,
          avatarUrl: MediaUrlNormalizer.normalize(profile.avatarUrl),
          isOfficial: profile.isOfficial ||
              UsernamePolicy.isOfficialUsername(profile.username),
        ),
      ]),
    );
    await _cache?.writeProfile(profile);
    await _plusController?.syncAccountPlus(
      userId: profile.userId,
      isPlus: profile.isPlus,
      planId: profile.plusPlanId,
      startedAtUtc: profile.plusStartedAtUtc,
      expiresAtUtc: profile.plusExpiresAtUtc,
    );
    unawaited(
      _plusController?.refreshSubscriptionHistory(userId: profile.userId),
    );
    unawaited(PushNotificationService.instance.registerForCurrentUser());
    if (profile.isPlus &&
        _isOnline &&
        _cloudBackupSyncedUserId != profile.userId) {
      _cloudBackupSyncedUserId = profile.userId;
      unawaited(
        SupabaseCloudBackupService.instance.syncAndRestore(
          hasPlusOverride: true,
        ),
      );
    }
  }

  Future<void> _refreshGroupsInternal(
    int generation, {
    bool allowRealtimeNotify = false,
  }) async {
    if (!groupsEnabled || _user == null) return;
    await _groupsStore.load();
    final nowUtc = _clock.nowUtc();

    try {
      final invitations = await _groupRemote!.pendingInvitations(nowUtc);
      if (generation != _generation) return;
      final activeInvitations = invitations
          .where((item) =>
              item.effectiveStatus(nowUtc) == InvitationStatus.pending)
          .toList(growable: false);

      // Deteksi undangan baru untuk notifikasi banner melayang in-app
      if (_hasHydratedInvitations || allowRealtimeNotify) {
        for (final inv in activeInvitations) {
          if (_knownInvitationIds.add(inv.id) &&
              !_incomingInvitationsCtrl.isClosed) {
            _incomingInvitationsCtrl.add(inv);
          }
        }
      } else {
        for (final inv in activeInvitations) {
          _knownInvitationIds.add(inv.id);
        }
        _hasHydratedInvitations = true;
      }

      _invitations = activeInvitations;
      await _cache?.writeInvitations(_user!.id, _invitations);
    } catch (_) {
      // Kegagalan muat undangan tidak boleh memblokir rekonsiliasi daftar grup.
    }

    try {
      final rawServerGroups = await _groupRemote!.myGroups();
      if (generation != _generation) return;

      final deletedIds = _groupsStore.deletedGroupIds;
      final activeGroups = <RemoteGroup>[];
      final cleanedOnServer = <String>{};
      for (final group in rawServerGroups) {
        if (deletedIds.contains(group.group.id)) {
          try {
            if (group.isOwner) {
              await _groupRemote.deleteGroup(group.group.id);
            } else {
              await _groupRemote.leaveGroup(group.group.id);
            }
            cleanedOnServer.add(group.group.id);
          } catch (_) {}
          continue;
        }
        activeGroups.add(group);
      }

      final remainingServerGroups = rawServerGroups
          .where((g) => !cleanedOnServer.contains(g.group.id))
          .toList(growable: false);

      _groups = List<RemoteGroup>.unmodifiable(activeGroups);

      // Sinkronkan jumlah anggota & daftar anggota hanya untuk grup yang masih aktif
      // (full replace sehingga ID grup lama yang sudah dihapus dibersihkan total).
      final activeIds = activeGroups.map((g) => g.group.id).toSet();
      final nextCounts = <String, int>{
        for (final id in activeIds)
          if (_memberCounts.containsKey(id)) id: _memberCounts[id]!,
      };
      final nextMembers = <String, List<MemberDirectoryEntry>>{
        for (final id in activeIds)
          if (_membersByGroup.containsKey(id)) id: _membersByGroup[id]!,
      };

      final groupIds =
          activeGroups.map((g) => g.group.id).toList(growable: false);
      if (_groupRemote is GroupMemberCountProvider && groupIds.isNotEmpty) {
        try {
          final fetchedCounts = await (_groupRemote as GroupMemberCountProvider)
              .fetchMemberCounts(groupIds);
          if (generation != _generation) return;
          nextCounts.addAll(fetchedCounts);
        } catch (_) {}
      }

      for (var start = 0; start < activeGroups.length; start += 3) {
        if (generation != _generation) return;
        final chunk = activeGroups.skip(start).take(3).toList(growable: false);
        await Future.wait<void>(
          chunk.map((group) async {
            final gid = group.group.id;
            try {
              final members = await _groupRemote.membersOf(gid);
              if (generation != _generation) return;
              if (members.isNotEmpty) {
                _seedPublicProfilesFromMembers(members);
                nextMembers[gid] =
                    List<MemberDirectoryEntry>.unmodifiable(members);
                nextCounts[gid] = members.length;
                unawaited(_cache?.writeMembers(gid, members));
              }
            } catch (_) {
              // Pertahankan cache anggota yang sudah ada.
            }
          }),
        );
      }
      if (generation != _generation) return;
      _memberCounts = nextCounts;
      _membersByGroup = nextMembers;
      _hasSyncedGroupsFromServer = true;

      // Full replace daftar grup di cache SQLite lokal & rekonsiliasi SharedPreferences.
      await _persistGroupsToCache();
      await _groupsStore.reconcileWithServer(remainingServerGroups);
      if (SupabaseServices.isAvailable && activeGroups.isNotEmpty) {
        unawaited(
          GroupHikePlanStore.instance.refreshForGroups(
            activeGroups.map((g) => g.group.id).toList(growable: false),
            groupNamesById: <String, String>{
              for (final g in activeGroups) g.group.id: g.group.name,
            },
          ),
        );
        GroupAutoLocationService.instance.start();
      }
      _notify();

      if (_deviceKeyMismatch) {
        _keyStatuses = const <String, GroupKeyStatus>{};
        _keyErrors = const <String, String>{};
        return;
      }

      final statuses = <String, GroupKeyStatus>{};
      final keyErrors = <String, String>{};
      for (final group in activeGroups) {
        if (generation != _generation) return;
        try {
          final status = group.isOwner
              ? await _groupKeys!.ensureOwnedGroupKey(group)
              : await _groupKeys!.ensureMembershipKey(group);
          statuses[group.group.id] = status;
          if (status.memberCount > 0 &&
              (_memberCounts[group.group.id] ?? 0) < status.memberCount) {
            _memberCounts = <String, int>{
              ..._memberCounts,
              group.group.id: status.memberCount,
            };
          }
          if (status.availability == GroupKeyAvailability.ready) {
            _emitGroupKeyReady(group.group.id);
            if (_groupRemote is GroupMissingKeyProvider) {
              unawaited(_groupKeys.shareKeyWithMissingMembers(group));
            }
          }
        } on GroupKeyPendingException {
          statuses[group.group.id] = GroupKeyStatus(
            availability: GroupKeyAvailability.waitingForOwner,
            keyVersion: group.group.keyVersion,
          );
        } catch (error) {
          keyErrors[group.group.id] = _friendly(error);
        }
      }
      if (generation != _generation) return;
      _keyStatuses = statuses;
      _keyErrors = keyErrors;
      await _persistGroupsToCache();
    } catch (error) {
      // OFFLINE-FIRST: JANGAN mengosongkan _groups / _invitations / _memberCounts!
      if (generation == _generation && _groups.isEmpty) {
        _error = _friendly(error);
      }
    }
  }

  Future<void> _persistGroupsToCache() async {
    final userId = _user?.id;
    final cache = _cache;
    if (userId == null || cache == null) return;
    final entries = _groups
        .map(
          (remote) => CachedGroupEntry(
            remote: remote,
            memberCount: memberCountFor(remote.group.id),
          ),
        )
        .toList(growable: false);
    await cache.writeGroups(userId, entries);
  }

  void _ensureRealtimeSubscribed() {
    final realtime = _realtimeService;
    final userId = _user?.id;
    if (realtime == null || userId == null || _disposed) return;

    final groupIds = _groups.map((g) => g.group.id).toList()..sort();
    final sig = '$userId|${groupIds.join(',')}';
    if (_realtimeSubscribedUserId == userId &&
        _realtimeGroupSignature == sig &&
        _realtimeSubscription != null) {
      return;
    }

    _realtimeSubscribedUserId = userId;
    _realtimeGroupSignature = sig;
    unawaited(_realtimeSubscription?.cancel());
    _realtimeSubscription =
        realtime.subscribe(userId: userId, groupIds: groupIds).listen(
              (event) => unawaited(_handleRealtimeEvent(event)),
              onError: (_) {},
            );
  }

  Future<void> _stopRealtime() async {
    _realtimeSubscribedUserId = null;
    _realtimeGroupSignature = null;
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    await _realtimeService?.unsubscribe();
  }

  Future<void> _handleRealtimeEvent(GroupRealtimeEvent event) async {
    if (_disposed || _user == null || !groupsEnabled) return;
    final gen = _generation;

    switch (event.kind) {
      case GroupRealtimeEventKind.membershipChanged:
        final gid = event.groupId;
        final isSelfAffected = event.userId == _user?.id;
        if (isSelfAffected || gid == null) {
          await _refreshGroupsInternal(gen, allowRealtimeNotify: true);
          _notify();
          if (gid != null && !_deviceKeyMismatch) {
            _scheduleMembershipKeyDistribution(gid);
          }
          return;
        }
        // Perbarui jumlah anggota & daftar anggota grup secara realtime
        try {
          final members = await _groupRemote!.membersOf(gid);
          if (gen != _generation || _disposed) return;
          if (members.isNotEmpty) {
            _seedPublicProfilesFromMembers(members);
            _membersByGroup = <String, List<MemberDirectoryEntry>>{
              ..._membersByGroup,
              gid: List<MemberDirectoryEntry>.unmodifiable(members),
            };
            _memberCounts = <String, int>{
              ..._memberCounts,
              gid: members.length,
            };
            unawaited(_cache?.writeMembers(gid, members));
            await _persistGroupsToCache();
            _notify();
          }
          // Pemilik maupun anggota yang sudah memegang kunci langsung membantu
          // membungkus dan membagikan kunci grup ke anggota baru via Realtime.
          if (!_deviceKeyMismatch) {
            _scheduleMembershipKeyDistribution(gid);
          }
        } catch (_) {}

      case GroupRealtimeEventKind.invitationChanged:
        try {
          final nowUtc = _clock.nowUtc();
          final invitations = await _groupRemote!.pendingInvitations(nowUtc);
          if (gen != _generation || _disposed) return;
          final active = invitations
              .where(
                (item) =>
                    item.effectiveStatus(nowUtc) == InvitationStatus.pending,
              )
              .toList(growable: false);
          for (final inv in active) {
            if (_knownInvitationIds.add(inv.id) &&
                !_incomingInvitationsCtrl.isClosed) {
              _incomingInvitationsCtrl.add(inv);
            }
          }
          _invitations = active;
          await _cache?.writeInvitations(_user!.id, active);
          _notify();
        } catch (_) {}

      case GroupRealtimeEventKind.groupKeyPublished:
        final gid = event.groupId;
        if (gid == null || _deviceKeyMismatch) return;
        final wrapped = event.wrappedKeyBase64;
        if (wrapped != null && wrapped.isNotEmpty) {
          final keyVer = event.keyVersion ?? 1;
          final ok = await _groupKeys!.ingestWrappedKeyFromRealtime(
            groupId: gid,
            keyVersion: keyVer,
            wrappedKeyBase64: wrapped,
          );
          if (ok && gen == _generation && !_disposed) {
            _keyStatuses = <String, GroupKeyStatus>{
              ..._keyStatuses,
              gid: GroupKeyStatus(
                availability: GroupKeyAvailability.ready,
                keyVersion: keyVer,
                memberCount: memberCountFor(gid),
              ),
            };
            _keyErrors = <String, String>{..._keyErrors}..remove(gid);
            _emitGroupKeyReady(gid);
            _notify();
            if (!_groups.any((g) => g.group.id == gid)) {
              unawaited(_refreshGroupsInternal(gen, allowRealtimeNotify: true));
            }
            return;
          }
        }

        var matching = _groups.where((g) => g.group.id == gid);
        if (matching.isEmpty) {
          await _refreshGroupsInternal(gen, allowRealtimeNotify: true);
          if (gen != _generation || _disposed) return;
          matching = _groups.where((g) => g.group.id == gid);
          if (matching.isEmpty) return;
        }
        try {
          final status = await _groupKeys!.ensureMembershipKey(matching.first);
          if (gen == _generation && !_disposed) {
            _keyStatuses = <String, GroupKeyStatus>{
              ..._keyStatuses,
              gid: status,
            };
            _keyErrors = <String, String>{..._keyErrors}..remove(gid);
            _emitGroupKeyReady(gid);
            _notify();
          }
        } catch (_) {}
    }
  }

  void _seedPublicProfilesFromMembers(List<MemberDirectoryEntry> members) {
    if (members.isEmpty) return;
    unawaited(
      PublicProfileCacheService.instance.putAll(
        members.map(
          (m) => PublicProfile(
            userId: m.userId,
            username: m.username.isNotEmpty ? m.username : null,
            fullName: m.displayName,
            avatarUrl: MediaUrlNormalizer.normalize(m.avatarUrl),
            lastSeenAtUtc: m.lastSeenAtUtc,
            isOfficial: m.isOfficial,
          ),
        ),
      ),
    );
  }

  bool _sameKey(String a, String b) {
    try {
      return base64Encode(base64Decode(a)) == base64Encode(base64Decode(b));
    } on FormatException {
      return false;
    }
  }

  String _friendly(Object error) {
    if (error is AccountException) return error.message;
    if (error is GroupOperationException) return error.message;
    if (error is GroupKeyPendingException) return error.toString();
    if (error is AeadAuthenticationException) {
      return 'Kunci grup gagal diautentikasi. Data atau kunci mungkin diubah.';
    }
    if (error is WrappedKeyException) {
      return 'Kunci grup tidak dapat dibuka dengan kunci perangkat ini.';
    }
    if (error is TimeoutException) {
      return 'Koneksi habis waktu. Periksa jaringan dan coba lagi.';
    }
    return 'Terjadi kesalahan. Periksa koneksi lalu coba lagi.';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _membershipKeyTimers.values) {
      timer.cancel();
    }
    _membershipKeyTimers.clear();
    unawaited(_authSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_stopRealtime());
    unawaited(_incomingInvitationsCtrl.close());
    unawaited(_groupKeyReadyCtrl.close());
    super.dispose();
  }
}
