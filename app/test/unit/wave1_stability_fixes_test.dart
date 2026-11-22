import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/chat/application/group_chat_crypto.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/chat/domain/group_chat_remote_service.dart';
import 'package:nama_app/features/groups/application/group_key_manager.dart';
import 'package:nama_app/features/groups/application/group_selection.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/invitation.dart';
import 'package:nama_app/infrastructure/cache/hiqeo_media_cache_service.dart';
import 'package:nama_app/infrastructure/cache/offline_account_cache.dart';
import 'package:nama_app/infrastructure/crypto/crypto_interfaces.dart';
import 'package:nama_app/infrastructure/crypto/cryptography_identity_service.dart';
import 'package:nama_app/infrastructure/crypto/secure_group_key_store.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_chat_local_store.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_supabase_sync_service.dart';
import 'package:nama_app/infrastructure/storage/media_url_normalizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemSecretStore implements SecretValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

class _FakeAuth implements AuthService {
  _FakeAuth(this._user);

  final AuthUser? _user;
  final StreamController<AuthUser?> _ctrl =
      StreamController<AuthUser?>.broadcast();

  @override
  Stream<AuthUser?> get authStateChanges => _ctrl.stream;

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<void> deleteAccount() async {}

  @override
  bool get isConfigured => true;

  @override
  Future<void> signIn(AuthProviderKind provider) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> switchAccount(AuthProviderKind provider) async {}
}

class _FakeProfileRepo implements ProfileRepository, KeyDirectory {
  _FakeProfileRepo(this._profile);

  final UserProfile _profile;

  @override
  Future<UserProfile?> currentProfile() async => _profile;

  @override
  Future<DirectoryEntry?> findByUsername(String username) async => null;

  @override
  Future<UserProfile> registerProfile({
    required String username,
    required String publicKeyBase64,
  }) async =>
      _profile;

  @override
  Future<UserProfile> setUsername(String newUsername) async => _profile;

  @override
  Future<UserProfile> updateAvatarUrl(String avatarUrl) async => _profile;

  @override
  Future<UserProfile> updateFullName(String fullName) async => _profile;
}

class _FakeRealtime implements GroupRealtimeService {
  final StreamController<GroupRealtimeEvent> controller =
      StreamController<GroupRealtimeEvent>.broadcast();

  @override
  Stream<GroupRealtimeEvent> subscribe({
    required String userId,
    required List<String> groupIds,
  }) =>
      controller.stream;

  @override
  Future<void> unsubscribe() async {}
}

class _FakeGroupRemote implements GroupRemoteService, GroupMissingKeyProvider {
  _FakeGroupRemote({
    required List<RemoteGroup> groups,
    Map<String, List<MemberDirectoryEntry>>? membersByGroup,
    Map<String, List<MemberDirectoryEntry>>? missingByGroup,
    Map<String, Map<int, String>>? wrappedBlobs,
  })  : _groups = List<RemoteGroup>.of(groups),
        _membersByGroup = membersByGroup ?? <String, List<MemberDirectoryEntry>>{},
        _missingByGroup = missingByGroup ?? <String, List<MemberDirectoryEntry>>{},
        _wrappedBlobs = wrappedBlobs ?? <String, Map<int, String>>{};

  final List<RemoteGroup> _groups;
  final Map<String, List<MemberDirectoryEntry>> _membersByGroup;
  final Map<String, List<MemberDirectoryEntry>> _missingByGroup;
  final Map<String, Map<int, String>> _wrappedBlobs;
  final List<Map<String, String>> publishedBatches = <Map<String, String>>[];
  final List<String> deletedGroupIds = <String>[];

  @override
  Future<RemoteGroup> createGroup({
    required String name,
    String? mountain,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteGroup(String groupId) async {
    deletedGroupIds.add(groupId);
    _groups.removeWhere((g) => g.group.id == groupId);
  }

  @override
  Future<String?> fetchOwnWrappedKey({
    required String groupId,
    required int keyVersion,
  }) async =>
      _wrappedBlobs[groupId]?[keyVersion];

  @override
  Future<void> inviteByUsername({
    required String groupId,
    required String username,
  }) async {}

  @override
  Future<void> leaveGroup(String groupId) async {
    _groups.removeWhere((g) => g.group.id == groupId);
  }

  @override
  Future<List<MemberDirectoryEntry>> membersMissingGroupKey({
    required String groupId,
    int? keyVersion,
  }) async =>
      _missingByGroup[groupId] ?? const <MemberDirectoryEntry>[];

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async =>
      _membersByGroup[groupId] ?? const <MemberDirectoryEntry>[];

  @override
  Future<List<RemoteGroup>> myGroups() async => List<RemoteGroup>.of(_groups);

  @override
  Future<List<IncomingInvitation>> pendingInvitations(DateTime nowUtc) async =>
      const <IncomingInvitation>[];

  @override
  Future<void> publishWrappedKeys({
    required String groupId,
    required int keyVersion,
    required Map<String, String> wrappedKeys,
  }) async {
    publishedBatches.add(Map<String, String>.from(wrappedKeys));
    _missingByGroup[groupId]?.removeWhere((m) => wrappedKeys.containsKey(m.userId));
  }

  @override
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {}

  @override
  Future<InvitationStatus> respondToInvitation({
    required String invitationId,
    required bool accept,
    required DateTime nowUtc,
  }) async =>
      InvitationStatus.accepted;
}

class _FakeChatRemote implements GroupChatRemoteService {
  _FakeChatRemote({
    required this.messages,
    required this.locations,
  });

  List<GroupMessageRecord> messages;
  List<MemberLastLocation> locations;

  @override
  Future<void> cancelHikeInviteMessage({
    required String groupId,
    required String clientMsgId,
  }) async {}

  @override
  Future<Uint8List?> downloadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required String storagePath,
    int keyVersion = 1,
  }) async =>
      null;

  @override
  Future<List<MemberLastLocation>> fetchMemberLocations(
    String groupId, {
    required String currentUserId,
  }) async =>
      locations;

  @override
  Future<List<GroupMessageRecord>> fetchMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeCreatedAtUtc,
  }) async =>
      messages;

  @override
  Future<String> resolveVoiceNotePlayUrl(String storagePathOrUrl) async =>
      storagePathOrUrl;

  @override
  Future<void> softDeleteMessage({
    required String groupId,
    required String clientMsgId,
  }) async {}

  @override
  Future<int> syncOfflineMemberLocations({
    required String groupId,
    required List<MemberLastLocation> locations,
    int keyVersion = 1,
  }) async =>
      locations.length;

  @override
  Future<int> syncOfflineMessages(List<GroupMessageRecord> messages) async =>
      messages.length;

  @override
  Future<String> uploadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required Uint8List audioBytes,
    int keyVersion = 1,
  }) async =>
      'path';

  @override
  Future<void> upsertMemberLocation({
    required String groupId,
    required MemberLastLocation location,
    int keyVersion = 1,
  }) async {}

  @override
  Future<void> upsertMessage(GroupMessageRecord message) async {}

  @override
  Stream<List<MemberLastLocation>> watchMemberLocations(
    String groupId, {
    required String currentUserId,
  }) =>
      const Stream<List<MemberLastLocation>>.empty();

  @override
  Stream<List<GroupMessageRecord>> watchMessages(String groupId) =>
      const Stream<List<GroupMessageRecord>>.empty();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Bug #1 - Isolate Batch Crypto & Single-Emit Store', () {
    test('decryptJsonBatch mendekripsi 40 pesan dalam 1 batch isolate dan tetap tahan terhadap baris tak terbaca', () async {
      final keyStore = SecureGroupKeyStore(store: _MemSecretStore());
      const gid = '11111111-1111-4111-8111-111111111111';
      final groupKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      await keyStore.writeGroupKey(gid, 1, groupKey);

      final crypto = GroupChatCrypto(keyStore: keyStore);
      final items = <GroupChatDecryptBatchItem>[];
      for (var i = 0; i < 39; i++) {
        final recId = '22222222-2222-4222-8222-${i.toString().padLeft(12, '0')}';
        final sealed = await crypto.encryptJson(
          kind: 'text',
          groupId: gid,
          recordId: recId,
          keyVersion: 1,
          payload: <String, dynamic>{'text': 'Pesan ke-$i', 'sender_name': 'Andi'},
        );
        items.add(
          GroupChatDecryptBatchItem(
            kind: 'text',
            groupId: gid,
            recordId: recId,
            keyVersion: 1,
            ciphertextBase64: sealed.ciphertextBase64,
          ),
        );
      }
      // 1 baris dengan kunci versi lain / rusak tidak boleh menggagalkan batch lain.
      items.add(
        const GroupChatDecryptBatchItem(
          kind: 'text',
          groupId: gid,
          recordId: '22222222-2222-4222-8222-999999999999',
          keyVersion: 99,
          ciphertextBase64: 'AAAA',
        ),
      );

      final results = await crypto.decryptJsonBatch(items);
      expect(results, hasLength(40));
      for (var i = 0; i < 39; i++) {
        expect(results[i]?['text'], 'Pesan ke-$i');
      }
      expect(results[39], isNull);
    });

    test('wrapForMembersBatch & unwrap round-trip berjalan di background isolate', () async {
      final senderIdentity = CryptographyIdentityService(store: _MemSecretStore());
      final memberA = CryptographyIdentityService(store: _MemSecretStore());
      final memberB = CryptographyIdentityService(store: _MemSecretStore());

      final pubA = await memberA.publicKey();
      final pubB = await memberB.publicKey();
      final groupKey = await senderIdentity.generateGroupKey();
      final aad = groupKeyAssociatedData('11111111-1111-4111-8111-111111111111', 1);

      final wrappedBatch = await senderIdentity.wrapForMembersBatch(
        groupKey: groupKey,
        recipients: <Map<String, Object>>[
          <String, Object>{'userId': 'u-a', 'publicKey': pubA},
          <String, Object>{'userId': 'u-b', 'publicKey': pubB},
        ],
        associatedData: aad,
      );
      expect(wrappedBatch, hasLength(2));

      final unwrappedA = await memberA.unwrap(
        wrappedKey: wrappedBatch[0]['wrappedKey'] as Uint8List,
        associatedData: aad,
      );
      final unwrappedB = await memberB.unwrap(
        wrappedKey: wrappedBatch[1]['wrappedKey'] as Uint8List,
        associatedData: aad,
      );
      expect(unwrappedA, groupKey);
      expect(unwrappedB, groupKey);
    });

    test('OffGridChatLocalStore.upsertMessagesBatch memancarkan stream sekali saja untuk batch 10 pesan', () async {
      final store = OffGridChatLocalStore();
      const gid = '11111111-1111-4111-8111-111111111111';
      var emissions = 0;
      List<GroupMessageRecord>? lastList;
      final sub = store.watchGroupMessages(gid).listen((list) {
        emissions++;
        lastList = list;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final before = emissions;

      final batch = <GroupMessageRecord>[
        for (var i = 0; i < 10; i++)
          GroupMessageRecord(
            clientMsgId: generateUuidV4(),
            groupId: gid,
            senderId: 'u-1',
            senderName: 'Budi',
            messageType: GroupMessageType.text,
            content: 'Halo $i',
            syncStatus: ChatSyncStatus.sent,
            clientCreatedAtUtc: DateTime.utc(2026, 11, 22, 7, 0, i),
          ),
      ];
      await store.upsertMessagesBatch(batch);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emissions - before, 1);
      expect(lastList, hasLength(10));
      await sub.cancel();
      await store.dispose();
    });
  });

  group('Bug #2 - UUID Normalization & Delete Group Cache Purge', () {
    test('normalizeToUuid mengubah ID berprefiks sos-/invite_hike_ menjadi UUID kanonik stabil', () {
      const validUpper = 'D58FBE4E-1234-4111-8111-111111111111';
      expect(normalizeToUuid(validUpper), validUpper.toLowerCase());

      final sosNorm = normalizeToUuid('sos-d58fbe4e-1234-4111-8111-111111111111');
      final hikeNorm = normalizeToUuid('invite_hike_1732250000');
      expect(isValidUuid(sosNorm), isTrue);
      expect(isValidUuid(hikeNorm), isTrue);
      expect(normalizeToUuid('sos-d58fbe4e-1234-4111-8111-111111111111'), sosNorm);
      expect(sosNorm, isNot(equals(hikeNorm)));
    });

    test('AccountController.deleteGroup mempertahankan tombstone dan memanggil GroupCachePurger.purgeGroup', () async {
      const uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      const gid = '11111111-1111-4111-8111-111111111111';
      final group = RemoteGroup(
        group: Group(
          id: gid,
          name: 'Tim Rinjani',
          ownerId: uid,
          keyVersion: 1,
          createdAtUtc: DateTime.utc(2026, 11, 1),
        ),
        role: GroupRole.owner,
      );
      final cache = InMemoryOfflineAccountCache();
      await cache.writeGroups(uid, <CachedGroupEntry>[
        CachedGroupEntry(remote: group, memberCount: 2),
      ]);
      final identity = CryptographyIdentityService(store: _MemSecretStore());
      final pub = base64Encode(await identity.publicKey());
      final profile = UserProfile(userId: uid, username: 'owner', publicKeyBase64: pub);
      final remote = _FakeGroupRemote(
        groups: <RemoteGroup>[group],
        membersByGroup: <String, List<MemberDirectoryEntry>>{
          gid: <MemberDirectoryEntry>[
            MemberDirectoryEntry(
              userId: uid,
              username: 'owner',
              role: GroupRole.owner,
              publicKeyBase64: pub,
              joinedAtUtc: DateTime.utc(2026, 11, 1),
            ),
          ],
        },
      );
      final groupsStore = SocialGroupsStore();
      await groupsStore.load();
      final keyStore = SecureGroupKeyStore(store: _MemSecretStore());
      await keyStore.writeGroupKey(gid, 1, Uint8List(32));

      final ctrl = AccountController(
        authService: _FakeAuth(const AuthUser(id: uid)),
        profileRepository: _FakeProfileRepo(profile),
        keyDirectory: _FakeProfileRepo(profile),
        identity: identity,
        groupRemote: remote,
        groupKeyManager: GroupKeyManager(
          remote: remote,
          crypto: identity,
          store: keyStore,
        ),
        cache: cache,
        groupsStore: groupsStore,
      );

      ctrl.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(ctrl.groups.map((g) => g.group.id), contains(gid));

      final deleted = await ctrl.deleteGroup(gid);
      expect(deleted, isTrue);
      expect(remote.deletedGroupIds, contains(gid));
      expect(groupsStore.deletedGroupIds, contains(gid));
      expect(await cache.readGroups(uid), isEmpty);
      expect(await keyStore.readGroupKey(gid, 1), isNull);

      // Saat refresh/restart berikutnya, grup lama tidak boleh bangkit lagi dari tombstone/cache.
      await ctrl.refreshGroups(force: true);
      expect(ctrl.groups.map((g) => g.group.id), isNot(contains(gid)));
      ctrl.dispose();
    });
  });

  group('Bug #3 - Non-Owner Key Sharing, Realtime Unwrap, & Instant Re-decrypt', () {
    test('Anggota non-pemilik pemegang kunci bisa menerbitkan kunci untuk anggota baru yang belum punya blob', () async {
      const gid = '11111111-1111-4111-8111-111111111111';
      final holderIdentity = CryptographyIdentityService(store: _MemSecretStore());
      final newbieIdentity = CryptographyIdentityService(store: _MemSecretStore());
      final newbiePub = base64Encode(await newbieIdentity.publicKey());

      final groupKey = await holderIdentity.generateGroupKey();
      final keyStore = SecureGroupKeyStore(store: _MemSecretStore());
      await keyStore.writeGroupKey(gid, 1, groupKey);

      final group = RemoteGroup(
        group: Group(
          id: gid,
          name: 'Semeru',
          ownerId: 'owner-1',
          keyVersion: 1,
          createdAtUtc: DateTime.utc(2026, 11, 22),
        ),
        role: GroupRole.member,
      );

      final remote = _FakeGroupRemote(
        groups: <RemoteGroup>[group],
        missingByGroup: <String, List<MemberDirectoryEntry>>{
          gid: <MemberDirectoryEntry>[
            MemberDirectoryEntry(
              userId: 'newbie-1',
              username: 'pendaki_baru',
              role: GroupRole.member,
              publicKeyBase64: newbiePub,
              joinedAtUtc: DateTime.utc(2026, 11, 22),
            ),
          ],
        },
      );
      final manager = GroupKeyManager(
        remote: remote,
        crypto: holderIdentity,
        store: keyStore,
      );

      final distributed = await manager.shareKeyWithMissingMembers(group);
      expect(distributed, isTrue);
      expect(remote.publishedBatches, hasLength(1));
      final wrappedForNewbie = remote.publishedBatches.first['newbie-1'];
      expect(wrappedForNewbie, isNotNull);

      final unwrapped = await newbieIdentity.unwrap(
        wrappedKey: Uint8List.fromList(base64Decode(wrappedForNewbie!)),
        associatedData: groupKeyAssociatedData(gid, 1),
      );
      expect(unwrapped, groupKey);
    });

    test('Realtime groupKeyPublished membuka kunci langsung dan redecryptGroup mengganti placeholder', () async {
      const uid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      const gid = '11111111-1111-4111-8111-111111111111';

      final senderIdentity = CryptographyIdentityService(store: _MemSecretStore());
      final receiverIdentity = CryptographyIdentityService(store: _MemSecretStore());
      final receiverPub = await receiverIdentity.publicKey();
      final receiverPubB64 = base64Encode(receiverPub);

      final groupKey = await senderIdentity.generateGroupKey();
      final wrapped = await senderIdentity.wrapForMember(
        groupKey: groupKey,
        memberPublicKey: receiverPub,
        associatedData: groupKeyAssociatedData(gid, 1),
      );
      final wrappedB64 = base64Encode(wrapped);

      final profile = UserProfile(
        userId: uid,
        username: 'user_b',
        publicKeyBase64: receiverPubB64,
      );
      final realtime = _FakeRealtime();
      final remote = _FakeGroupRemote(groups: const <RemoteGroup>[]);
      final receiverKeyStore = SecureGroupKeyStore(store: _MemSecretStore());
      final groupsStore = SocialGroupsStore();
      await groupsStore.load();

      final ctrl = AccountController(
        authService: _FakeAuth(const AuthUser(id: uid)),
        profileRepository: _FakeProfileRepo(profile),
        keyDirectory: _FakeProfileRepo(profile),
        identity: receiverIdentity,
        groupRemote: remote,
        groupKeyManager: GroupKeyManager(
          remote: remote,
          crypto: receiverIdentity,
          store: receiverKeyStore,
        ),
        realtimeService: realtime,
        groupsStore: groupsStore,
      );

      final readyEvents = <String>[];
      final readySub = ctrl.onGroupKeyReady.listen(readyEvents.add);
      ctrl.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Simulasikan placeholder tersimpan lokal sebelum kunci tiba.
      final localStore = OffGridChatLocalStore();
      final msgUuid = generateUuidV4();
      await localStore.insertMessageIfAbsent(
        GroupMessageRecord(
          clientMsgId: msgUuid,
          groupId: gid,
          senderId: 'owner-a',
          senderName: 'Anggota',
          messageType: GroupMessageType.text,
          content: 'Pesan terenkripsi (menunggu kunci grup)',
          syncStatus: ChatSyncStatus.sent,
          clientCreatedAtUtc: DateTime.utc(2026, 11, 22, 7, 1),
        ),
      );

      final fakeChatRemote = _FakeChatRemote(
        messages: <GroupMessageRecord>[
          GroupMessageRecord(
            clientMsgId: msgUuid,
            groupId: gid,
            senderId: 'owner-a',
            senderName: 'Owner A',
            messageType: GroupMessageType.text,
            content: 'Kita naik jam 5 pagi ya!',
            syncStatus: ChatSyncStatus.sent,
            clientCreatedAtUtc: DateTime.utc(2026, 11, 22, 7, 1),
          ),
        ],
        locations: <MemberLastLocation>[
          MemberLastLocation(
            groupId: gid,
            userId: 'owner-a',
            displayName: 'Owner A',
            initial: 'O',
            hasSignal: true,
            lat: -6.89,
            lon: 108.4,
            sourceTransport: ChatTransportOrigin.online,
            syncStatus: ChatSyncStatus.sent,
            recordedAtUtc: DateTime.utc(2026, 11, 22, 7, 1),
            updatedAtUtc: DateTime.utc(2026, 11, 22, 7, 1),
          ),
        ],
      );
      final syncService = OffGridSupabaseSyncService(
        localStore: localStore,
        remoteService: fakeChatRemote,
      );

      // Event Realtime group_key_blobs tiba meski _groups belum mengandung gid.
      realtime.controller.add(
        GroupRealtimeEvent(
          kind: GroupRealtimeEventKind.groupKeyPublished,
          groupId: gid,
          userId: uid,
          keyVersion: 1,
          wrappedKeyBase64: wrappedB64,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(readyEvents, contains(gid));
      expect(await receiverKeyStore.readGroupKey(gid, 1), groupKey);

      final redecrypted = await syncService.redecryptGroup(gid, currentUserId: uid);
      expect(redecrypted, isTrue);

      final msgsAfter = await localStore.messagesForGroup(gid);
      expect(msgsAfter.single.content, 'Kita naik jam 5 pagi ya!');
      final locsAfter =
          await localStore.memberLocationsForGroup(gid, currentUserId: uid);
      expect(locsAfter.single.userId, 'owner-a');
      expect(locsAfter.single.lat, closeTo(-6.89, 0.001));

      await readySub.cancel();
      await syncService.dispose();
      await localStore.dispose();
      await realtime.controller.close();
      ctrl.dispose();
    });
  });

  group('Bug #4 - Android 16 Media URL Extraction, Proxy Fallback, & Cache', () {
    test('MediaUrlNormalizer.extractR2ObjectKey mengekstrak key R2 publik & presigned dengan aman', () {
      expect(
        MediaUrlNormalizer.extractR2ObjectKey(
          'http://pub-abc123.r2.dev//avatars/u1.webp?v=123',
        ),
        'avatars/u1.webp',
      );
      expect(
        MediaUrlNormalizer.extractR2ObjectKey(
          'https://acct.r2.cloudflarestorage.com/hiqeo-media/community-media/c1/u1/img.webp?X-Amz-Signature=deadbeef',
        ),
        'community-media/c1/u1/img.webp',
      );
      expect(
        MediaUrlNormalizer.extractR2ObjectKey(
          'https://evil.example.com/avatars/../secret.txt',
        ),
        isNull,
      );
    });

    test('HiqeoMediaCacheService fallback ke r2-presign proxy, bertahan offline, dan tidak men-cache error secara permanen', () async {
      final tempDir = await Directory.systemTemp.createTemp('hiqeo_media_test_');
      addTearDown(() async {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final validWebp = Uint8List.fromList(<int>[
        0x52, 0x49, 0x46, 0x46, 0x20, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
        0x56, 0x50, 0x38, 0x20,
      ]);

      var directCalls = 0;
      var proxyShouldFail = true;
      var clockNow = DateTime.utc(2026, 11, 22, 7, 0);

      final service = HiqeoMediaCacheService(
        cacheDirResolver: () async => tempDir,
        nowUtc: () => clockNow,
        httpFetcher: (uri) async {
          directCalls++;
          throw const SocketException('r2.dev blocked by carrier DNS');
        },
        edgeProxyFetcher: (objectKey) async {
          if (proxyShouldFail) {
            return (statusCode: 503, bytes: Uint8List(0));
          }
          return (statusCode: 200, bytes: validWebp);
        },
      );

      const url = 'https://pub-abc.r2.dev/community-avatars/c1111111-1111-4111-8111-111111111111.webp';

      // 1. Kegagalan sementara tidak di-cache ke disk dan memulih begitu cooldown di-clear / waktu maju.
      final firstAttempt = await service.resolveMediaFile(url);
      expect(firstAttempt, isNull);
      expect(directCalls, 1);

      proxyShouldFail = false;
      service.clearFailureCooldowns();

      // 2. Retry sukses lewat proxy dan tersimpan ke disk cache persisten.
      final recovered = await service.resolveMediaFile(url);
      expect(recovered, isNotNull);
      expect(recovered!.existsSync(), isTrue);
      expect(await recovered.readAsBytes(), validWebp);

      // 3. Permintaan berikutnya (mis. offline) hit cache disk tanpa memanggil jaringan lagi.
      final callsBeforeCacheHit = directCalls;
      final offlineHit = await service.resolveMediaFile(url);
      expect(offlineHit?.path, recovered.path);
      expect(directCalls, callsBeforeCacheHit);
    });
  });
}
