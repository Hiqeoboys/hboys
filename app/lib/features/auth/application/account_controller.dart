import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/utils/clock.dart';
import '../../../infrastructure/crypto/crypto_interfaces.dart';
import '../../groups/application/group_key_manager.dart';
import '../../groups/domain/group_remote_service.dart';
import '../../groups/domain/invitation.dart';
import '../../groups/domain/username.dart';
import '../domain/auth_service.dart';
import '../domain/profile_repository.dart';

class AccountController extends ChangeNotifier {
  AccountController({
    required AuthService authService,
    required ProfileRepository profileRepository,
    required KeyDirectory keyDirectory,
    required IdentityService identity,
    GroupRemoteService? groupRemote,
    GroupKeyManager? groupKeyManager,
    Clock clock = const SystemClock(),
  })  : _auth = authService,
        _profiles = profileRepository,
        _directory = keyDirectory,
        _identity = identity,
        _groupRemote = groupRemote,
        _groupKeys = groupKeyManager,
        _clock = clock;

  final AuthService _auth;
  final ProfileRepository _profiles;
  final KeyDirectory _directory;
  final IdentityService _identity;
  final GroupRemoteService? _groupRemote;
  final GroupKeyManager? _groupKeys;
  final Clock _clock;

  StreamSubscription<AuthUser?>? _authSubscription;
  bool _initialized = false;
  bool _disposed = false;
  int _generation = 0;

  AuthUser? _user;
  UserProfile? _profile;
  bool _deviceKeyMismatch = false;
  List<IncomingInvitation> _invitations = const [];
  List<RemoteGroup> _groups = const [];
  Map<String, GroupKeyStatus> _keyStatuses = const {};
  Map<String, String> _keyErrors = const {};
  bool _loading = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  bool get isConfigured => _auth.isConfigured;
  bool get groupsEnabled => _groupRemote != null && _groupKeys != null;
  bool get isLoading => _loading;
  bool get isBusy => _busy;
  AuthUser? get user => _user;
  UserProfile? get profile => _profile;
  bool get needsUsername => _user != null && _profile == null && !_loading;
  bool get deviceKeyMismatch => _deviceKeyMismatch;
  List<IncomingInvitation> get invitations => _invitations;
  List<RemoteGroup> get groups => _groups;
  String? get error => _error;
  String? get notice => _notice;

  GroupKeyStatus? keyStatusFor(String groupId) => _keyStatuses[groupId];
  String? keyErrorFor(String groupId) => _keyErrors[groupId];

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _authSubscription = _auth.authStateChanges.listen(
      (user) => unawaited(_handleUser(user)),
      onError: (Object error, StackTrace stackTrace) {
        _error = _friendly(error);
        _notify();
      },
    );
    final current = _auth.currentUser;
    if (current != null) unawaited(_handleUser(current));
  }

  Future<void> signIn(AuthProviderKind provider) async {
    if (!isConfigured || _busy) return;
    _busy = true;
    _error = null;
    _notice = null;
    _notify();
    try {
      await _auth.signIn(provider);
      _notice =
          'Selesaikan login di browser. Aplikasi akan terbuka kembali otomatis.';
    } catch (error) {
      _error = _friendly(error);
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
      await _auth.signOut();
      _generation++;
      _user = null;
      _profile = null;
      _deviceKeyMismatch = false;
      _invitations = const [];
      _groups = const [];
      _keyStatuses = const {};
      _keyErrors = const {};
      _notice = 'Sudah keluar. Kunci identitas tetap tersimpan di perangkat.';
    } catch (error) {
      _error = _friendly(error);
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
      _profile = profile;
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
    if (_busy || profile == null) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      final publicKey = await _identity.publicKey();
      final updated = await _profiles.registerProfile(
        username: profile.username,
        publicKeyBase64: base64Encode(publicKey),
      );
      _profile = updated;
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
      await _refreshGroupsInternal(_generation);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> createGroup(String name, {String? mountain}) async {
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
      final group = await _groupRemote!.createGroup(
        name: trimmed,
        mountain: mountain,
      );
      _notice = 'Grup "${group.group.name}" dibuat.';
      await _refreshGroupsInternal(_generation);
      created = true;
    } catch (error) {
      _error = _friendly(error);
    } finally {
      _busy = false;
      _notify();
    }
    return created;
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
      if (status == InvitationStatus.accepted) {
        _notice =
            'Undangan diterima. Menunggu pemilik membagikan kunci grup.';
      } else if (status == InvitationStatus.rejected) {
        _notice = 'Undangan ditolak.';
      } else if (status == InvitationStatus.expired) {
        _notice = 'Undangan sudah kedaluwarsa.';
      }
      await _refreshGroupsInternal(_generation);
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
      _error =
          'Kunci perangkat berbeda dari direktori. Daftarkan ulang kunci '
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
      _keyStatuses = {..._keyStatuses, groupId: status};
      _keyErrors = {..._keyErrors}..remove(groupId);
      _notice = group.isOwner
          ? 'Kunci grup versi ${status.keyVersion} siap untuk ${status.memberCount} anggota.'
          : 'Kunci grup versi ${status.keyVersion} dimuat.';
    } on GroupKeyPendingException {
      _keyStatuses = {
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
      _keyErrors = {..._keyErrors, groupId: _friendly(error)};
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _handleUser(AuthUser? user) async {
    final generation = ++_generation;
    _user = user;
    _profile = null;
    _deviceKeyMismatch = false;
    _invitations = const [];
    _groups = const [];
    _keyStatuses = const {};
    _keyErrors = const {};
    _error = null;
    _notice = null;
    if (user == null) {
      _loading = false;
      _notify();
      return;
    }
    _loading = true;
    _notify();
    try {
      final profile = await _profiles.currentProfile();
      if (generation != _generation) return;
      _profile = profile;
      if (profile != null) {
        final publicKey = await _identity.publicKey();
        if (generation != _generation) return;
        _deviceKeyMismatch = !_sameKey(
          profile.publicKeyBase64,
          base64Encode(publicKey),
        );
        await _refreshGroupsInternal(generation);
      }
    } catch (error) {
      if (generation == _generation) _error = _friendly(error);
    } finally {
      if (generation == _generation) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<void> _refreshGroupsInternal(int generation) async {
    if (!groupsEnabled || _user == null) return;
    try {
      final nowUtc = _clock.nowUtc();
      final invitations =
          await _groupRemote!.pendingInvitations(nowUtc);
      final groups = await _groupRemote.myGroups();
      if (generation != _generation) return;
      _invitations = invitations
          .where((item) => item.effectiveStatus(nowUtc) == InvitationStatus.pending)
          .toList(growable: false);
      _groups = groups;

      if (_deviceKeyMismatch) {
        _keyStatuses = const {};
        _keyErrors = const {};
        return;
      }

      final statuses = <String, GroupKeyStatus>{};
      final keyErrors = <String, String>{};
      for (final group in groups) {
        if (generation != _generation) return;
        try {
          final status = group.isOwner
              ? await _groupKeys!.ensureOwnedGroupKey(group)
              : await _groupKeys!.ensureMembershipKey(group);
          statuses[group.group.id] = status;
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
    } catch (error) {
      if (generation == _generation) _error = _friendly(error);
    }
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
    _authSubscription?.cancel();
    super.dispose();
  }
}
