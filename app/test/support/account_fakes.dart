import 'dart:async';
import 'dart:typed_data';

import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/infrastructure/crypto/crypto_interfaces.dart';

class FakeAuthService implements AuthService {
  FakeAuthService({this.isConfigured = true, this.currentUser});

  @override
  bool isConfigured;

  @override
  AuthUser? currentUser;

  final StreamController<AuthUser?> _changes =
      StreamController<AuthUser?>.broadcast();
  final List<AuthProviderKind> signInCalls = [];
  final List<AuthProviderKind> switchAccountCalls = [];
  int signOutCalls = 0;
  int deleteAccountCalls = 0;
  Object? signInError;
  Completer<void>? signInCompleter;

  @override
  Stream<AuthUser?> get authStateChanges => _changes.stream;

  void emit(AuthUser? user) {
    currentUser = user;
    _changes.add(user);
  }

  @override
  Future<void> signIn(AuthProviderKind provider) async {
    signInCalls.add(provider);
    if (signInCompleter != null) {
      await signInCompleter!.future;
    }
    if (signInError != null) {
      throw signInError!;
    }
  }

  @override
  Future<void> switchAccount(AuthProviderKind provider) async {
    switchAccountCalls.add(provider);
    if (signInError != null) {
      throw signInError!;
    }
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    currentUser = null;
    _changes.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalls++;
    currentUser = null;
    _changes.add(null);
  }

  Future<void> close() => _changes.close();
}

class FakeProfileRepository implements ProfileRepository {
  UserProfile? current;
  Object? setUsernameError;

  final List<({String username, String publicKeyBase64})> registrations = [];
  final List<String> setUsernameCalls = [];
  final List<String> avatarUrlCalls = [];
  final List<String> updateFullNameCalls = [];
  Object? updateFullNameError;

  @override
  Future<UserProfile?> currentProfile() async => current;

  @override
  Future<UserProfile> registerProfile({
    required String username,
    required String publicKeyBase64,
  }) async {
    registrations.add((
      username: username,
      publicKeyBase64: publicKeyBase64,
    ));
    final profile = UserProfile(
      userId: current?.userId ?? 'user-1',
      username: username,
      publicKeyBase64: publicKeyBase64,
    );
    current = profile;
    return profile;
  }

  @override
  Future<UserProfile> setUsername(String newUsername) async {
    setUsernameCalls.add(newUsername);
    if (setUsernameError != null) {
      throw setUsernameError!;
    }
    final updated = (current ?? const UserProfile(userId: 'user-1')).copyWith(
      username: newUsername,
      usernameChangedAtUtc: DateTime.now().toUtc(),
    );
    current = updated;
    return updated;
  }

  @override
  Future<UserProfile> updateAvatarUrl(String avatarUrl) async {
    avatarUrlCalls.add(avatarUrl);
    final updated = (current ?? const UserProfile(userId: 'user-1')).copyWith(
      avatarUrl: avatarUrl,
    );
    current = updated;
    return updated;
  }

  @override
  Future<UserProfile> updateFullName(String fullName) async {
    updateFullNameCalls.add(fullName);
    if (updateFullNameError != null) {
      throw updateFullNameError!;
    }
    final updated = (current ?? const UserProfile(userId: 'user-1')).copyWith(
      fullName: fullName,
    );
    current = updated;
    return updated;
  }
}

class FakeKeyDirectory implements KeyDirectory {
  final Map<String, DirectoryEntry> entries = {};

  @override
  Future<DirectoryEntry?> findByUsername(String username) async =>
      entries[username];
}

class FakeIdentity implements IdentityService {
  FakeIdentity(this.key);

  Uint8List key;
  int calls = 0;

  @override
  Future<Uint8List> publicKey() async {
    calls++;
    return Uint8List.fromList(key);
  }
}
