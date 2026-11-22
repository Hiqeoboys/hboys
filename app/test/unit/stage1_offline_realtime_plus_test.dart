import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/groups/application/group_key_manager.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_key_store.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/invitation.dart';
import 'package:nama_app/features/plus/application/plus_controller.dart';
import 'package:nama_app/features/plus/domain/plus_entitlement.dart';
import 'package:nama_app/features/plus/domain/plus_remote_config.dart';
import 'package:nama_app/features/plus/domain/plus_repositories.dart';
import 'package:nama_app/features/plus/infrastructure/local_plus_stores.dart';
import 'package:nama_app/infrastructure/cache/offline_account_cache.dart';
import 'package:nama_app/infrastructure/crypto/cryptography_identity_service.dart';
import 'package:nama_app/infrastructure/crypto/crypto_interfaces.dart';
import 'package:nama_app/infrastructure/database/app_database.dart';
import 'package:nama_app/infrastructure/offgrid/mesh_packet_codec.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_chat_local_store.dart';

import '../support/account_fakes.dart';

class _MemSecretStore implements SecretValueStore {
  final Map<String, String> data = <String, String>{};
  @override
  Future<void> delete(String key) async => data.remove(key);
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

class _MemKeyStore implements GroupKeyStore {
  final Map<String, Uint8List> keys = <String, Uint8List>{};
  final Map<String, String> sigs = <String, String>{};
  String _k(String g, int v) => '$g:v$v';

  @override
  Future<void> deleteDistributionSignature(String groupId, int keyVersion) async =>
      sigs.remove(_k(groupId, keyVersion));

  @override
  Future<void> deleteGroupKey(String groupId, int keyVersion) async =>
      keys.remove(_k(groupId, keyVersion));

  @override
  Future<String?> readDistributionSignature(String groupId, int keyVersion) async =>
      sigs[_k(groupId, keyVersion)];

  @override
  Future<Uint8List?> readGroupKey(String groupId, int keyVersion) async =>
      keys[_k(groupId, keyVersion)];

  @override
  Future<void> writeDistributionSignature(
    String groupId,
    int keyVersion,
    String signature,
  ) async =>
      sigs[_k(groupId, keyVersion)] = signature;

  @override
  Future<void> writeGroupKey(
    String groupId,
    int keyVersion,
    Uint8List groupKey,
  ) async =>
      keys[_k(groupId, keyVersion)] = Uint8List.fromList(groupKey);
}

class _FakeGroupRemoteWithRealtime implements GroupRemoteService {
  _FakeGroupRemoteWithRealtime({required this.viewerId});

  String viewerId;
  bool failAllNetwork = false;
  List<RemoteGroup> groups = <RemoteGroup>[];
  List<IncomingInvitation> invitations = <IncomingInvitation>[];
  Map<String, List<MemberDirectoryEntry>> membersByGroup =
      <String, List<MemberDirectoryEntry>>{};
  Map<String, Map<String, String>> wrappedByGroup =
      <String, Map<String, String>>{};
  int publishCalls = 0;

  void _checkOnline() {
    if (failAllNetwork) {
      throw const GroupOperationException('OFFLINE', 'Tidak ada internet');
    }
  }

  @override
  Future<List<RemoteGroup>> myGroups() async {
    _checkOnline();
    return List<RemoteGroup>.of(groups);
  }

  @override
  Future<RemoteGroup> createGroup({required String name, String? mountain}) async {
    _checkOnline();
    final created = RemoteGroup(
      group: Group(
        id: 'g-${groups.length + 1}',
        name: name,
        ownerId: viewerId,
        mountain: mountain,
        createdAtUtc: DateTime.utc(2026, 11, 1),
      ),
      role: GroupRole.owner,
    );
    groups.add(created);
    return created;
  }

  @override
  Future<void> inviteByUsername({
    required String groupId,
    required String username,
  }) async =>
      _checkOnline();

  @override
  Future<List<IncomingInvitation>> pendingInvitations(DateTime nowUtc) async {
    _checkOnline();
    return List<IncomingInvitation>.of(invitations);
  }

  @override
  Future<InvitationStatus> respondToInvitation({
    required String invitationId,
    required bool accept,
    required DateTime nowUtc,
  }) async {
    _checkOnline();
    invitations.removeWhere((i) => i.id == invitationId);
    return accept ? InvitationStatus.accepted : InvitationStatus.rejected;
  }

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async {
    _checkOnline();
    return List<MemberDirectoryEntry>.of(
      membersByGroup[groupId] ?? const <MemberDirectoryEntry>[],
    );
  }

  @override
  Future<void> publishWrappedKeys({
    required String groupId,
    required int keyVersion,
    required Map<String, String> wrappedKeys,
  }) async {
    _checkOnline();
    publishCalls++;
    wrappedByGroup['$groupId:v$keyVersion'] = Map<String, String>.of(wrappedKeys);
  }

  @override
  Future<String?> fetchOwnWrappedKey({
    required String groupId,
    required int keyVersion,
  }) async {
    _checkOnline();
    return wrappedByGroup['$groupId:v$keyVersion']?[viewerId];
  }

  @override
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async =>
      _checkOnline();

  @override
  Future<void> deleteGroup(String groupId) async {
    _checkOnline();
    groups.removeWhere((g) => g.group.id == groupId);
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    _checkOnline();
    groups.removeWhere((g) => g.group.id == groupId);
  }
}

class _FakeRealtimeService implements GroupRealtimeService {
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

  Future<void> close() => controller.close();
}

class _OfflineConfigRepo implements PlusRemoteConfigRepository {
  @override
  Future<PlusRemoteConfig> fetch({required DateTime fetchedAtUtc}) =>
      Future<PlusRemoteConfig>.error(const PlusConfigUnavailable('offline'));
}

class _NoopBilling implements PlusBillingRepository {
  @override
  Future<PlusBillingResult> purchase(String planId) async =>
      const PlusBillingResult.unavailable('offline');

  @override
  Future<PlusBillingResult> restore() async =>
      const PlusBillingResult.nothingToRestore();
}

class _RejectVerifier implements EntitlementVerifier {
  @override
  Future<EntitlementPayload?> verify(String token) async => null;
}

class _OfflineFailingProfileRepo implements ProfileRepository {
  _OfflineFailingProfileRepo({this.profile, this.fail = false});

  UserProfile? profile;
  bool fail;

  @override
  Future<UserProfile?> currentProfile() async {
    if (fail) throw const AccountException('OFFLINE', 'Tidak ada koneksi');
    return profile;
  }

  @override
  Future<UsernameAvailabilityResult> checkUsernameAvailability(
    String username,
  ) async {
    if (fail) throw const AccountException('OFFLINE', 'Tidak ada koneksi');
    return const UsernameAvailabilityResult(available: true);
  }

  @override
  Future<UserProfile> registerProfile({
    required String username,
    required String publicKeyBase64,
  }) async {
    if (fail) throw const AccountException('OFFLINE', 'Tidak ada koneksi');
    profile = UserProfile(
      userId: profile?.userId ?? 'u1',
      username: username,
      publicKeyBase64: publicKeyBase64,
    );
    return profile!;
  }

  @override
  Future<UserProfile> setUsername(String newUsername) async {
    if (fail) throw const AccountException('OFFLINE', 'Tidak ada koneksi');
    profile = (profile ?? const UserProfile(userId: 'u1'))
        .copyWith(username: newUsername);
    return profile!;
  }

  @override
  Future<UserProfile> updateAvatarUrl(String avatarUrl) async {
    if (fail) throw const AccountException('OFFLINE', 'Tidak ada koneksi');
    profile = (profile ?? const UserProfile(userId: 'u1'))
        .copyWith(avatarUrl: avatarUrl);
    return profile!;
  }

  @override
  Future<UserProfile> updateFullName(String fullName) async {
    if (fail) throw const AccountException('OFFLINE', 'Tidak ada koneksi');
    profile = (profile ?? const UserProfile(userId: 'u1'))
        .copyWith(fullName: fullName);
    return profile!;
  }
}

void main() {
  group('TAHAP 1 — Offline-First Cache, Realtime, Dedup, Key Sync & Plus Offline',
      () {
    test(
        'SqliteOfflineAccountCache menyimpan & memulihkan profil, avatar lokal, grup, anggota, dan undangan',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final tempDir = await Directory.systemTemp.createTemp('hiqeo_avatar_test');
      addTearDown(() async {
        await db.close();
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });

      final cache = SqliteOfflineAccountCache(
        database: db,
        avatarDirResolver: () async => tempDir,
        httpDownloader: (_) async => Uint8List.fromList(<int>[137, 80, 78, 71]),
      );

      final avatarPath = await cache.cacheAvatarFile(
        userId: 'user-1',
        avatarUrl: 'https://example.com/avatar.png',
      );
      expect(avatarPath, isNotNull);
      expect(File(avatarPath!).existsSync(), isTrue);

      await cache.writeProfile(
        UserProfile(
          userId: 'user-1',
          username: 'pendaki_merbabu',
          fullName: 'Raka Pratama',
          avatarUrl: 'https://example.com/avatar.png',
          localAvatarPath: avatarPath,
          isProfileComplete: true,
          isPlus: true,
          plusPlanId: 'lifetime',
        ),
      );

      final group = RemoteGroup(
        group: Group(
          id: 'grp-1',
          name: 'Tim Merbabu',
          ownerId: 'user-1',
          mountain: 'Gunung Merbabu',
          createdAtUtc: DateTime.utc(2026, 11, 1),
        ),
        role: GroupRole.owner,
      );
      await cache.writeGroups('user-1', <CachedGroupEntry>[
        CachedGroupEntry(remote: group, memberCount: 3),
      ]);
      await cache.writeMembers('grp-1', <MemberDirectoryEntry>[
        MemberDirectoryEntry(
          userId: 'user-1',
          username: 'pendaki_merbabu',
          displayName: 'Raka Pratama',
          role: GroupRole.owner,
          publicKeyBase64: 'pk1',
          joinedAtUtc: DateTime.utc(2026, 11, 1),
        ),
        MemberDirectoryEntry(
          userId: 'user-2',
          username: 'sari_trail',
          displayName: 'Sari',
          role: GroupRole.member,
          publicKeyBase64: 'pk2',
          joinedAtUtc: DateTime.utc(2026, 11, 2),
        ),
      ]);
      await cache.writeInvitations('user-1', <IncomingInvitation>[
        IncomingInvitation(
          id: 'inv-1',
          groupId: 'grp-2',
          groupName: 'Tim Prau',
          inviterUsername: 'bayu',
          createdAtUtc: DateTime.utc(2026, 11, 10),
          expiresAtUtc: DateTime.utc(2026, 11, 20),
        ),
      ]);

      final loadedProfile = await cache.readProfile('user-1');
      final loadedGroups = await cache.readGroups('user-1');
      final loadedMembers = await cache.readMembers('grp-1');
      final loadedInvites = await cache.readInvitations('user-1');

      expect(loadedProfile?.username, 'pendaki_merbabu');
      expect(loadedProfile?.localAvatarPath, avatarPath);
      expect(loadedProfile?.isProfileComplete, isTrue);
      expect(loadedProfile?.isPlus, isTrue);
      expect(loadedGroups, hasLength(1));
      expect(loadedGroups.single.memberCount, 3);
      expect(loadedMembers, hasLength(2));
      expect(loadedMembers.first.role, GroupRole.owner);
      expect(loadedInvites, hasLength(1));
      expect(loadedInvites.single.groupName, 'Tim Prau');
    });

    test(
        'AccountController merender cache lokal saat offline tanpa menghapus state, lalu auto-sync saat online kembali',
        () async {
      final now = DateTime.utc(2026, 11, 15);
      final cache = InMemoryOfflineAccountCache();
      final ownerCrypto = CryptographyIdentityService(store: _MemSecretStore());
      final ownerPk = base64Encode(await ownerCrypto.publicKey());

      await cache.writeProfile(
        UserProfile(
          userId: 'user-1',
          username: 'raka_hiker',
          fullName: 'Raka',
          publicKeyBase64: ownerPk,
          isProfileComplete: true,
          isPlus: true,
          plusPlanId: 'lifetime',
        ),
      );
      final cachedGroup = RemoteGroup(
        group: Group(
          id: 'g-1',
          name: 'Tim Rinjani',
          ownerId: 'user-1',
          mountain: 'Gunung Rinjani',
          createdAtUtc: now,
        ),
        role: GroupRole.owner,
      );
      await cache.writeGroups('user-1', <CachedGroupEntry>[
        CachedGroupEntry(remote: cachedGroup, memberCount: 2),
      ]);
      await cache.writeMembers('g-1', <MemberDirectoryEntry>[
        MemberDirectoryEntry(
          userId: 'user-1',
          username: 'raka_hiker',
          role: GroupRole.owner,
          publicKeyBase64: ownerPk,
          joinedAtUtc: now,
        ),
        MemberDirectoryEntry(
          userId: 'user-2',
          username: 'sari_hiker',
          role: GroupRole.member,
          publicKeyBase64: ownerPk,
          joinedAtUtc: now,
        ),
      ]);

      final auth = FakeAuthService(
        currentUser: const AuthUser(id: 'user-1', email: 'raka@gmail.com'),
      );
      final profileRepo = _OfflineFailingProfileRepo(
        profile: UserProfile(
          userId: 'user-1',
          username: 'raka_hiker',
          fullName: 'Raka Updated',
          publicKeyBase64: ownerPk,
          isPlus: true,
          plusPlanId: 'lifetime',
        ),
        fail: true, // Mulai dalam keadaan OFFLINE
      );
      final remote = _FakeGroupRemoteWithRealtime(viewerId: 'user-1')
        ..failAllNetwork = true
        ..groups = <RemoteGroup>[cachedGroup]
        ..membersByGroup['g-1'] = <MemberDirectoryEntry>[
          MemberDirectoryEntry(
            userId: 'user-1',
            username: 'raka_hiker',
            role: GroupRole.owner,
            publicKeyBase64: ownerPk,
            joinedAtUtc: now,
          ),
          MemberDirectoryEntry(
            userId: 'user-2',
            username: 'sari_hiker',
            role: GroupRole.member,
            publicKeyBase64: ownerPk,
            joinedAtUtc: now,
          ),
          MemberDirectoryEntry(
            userId: 'user-3',
            username: 'budi_hiker',
            role: GroupRole.member,
            publicKeyBase64: ownerPk,
            joinedAtUtc: now,
          ),
        ];
      final realtime = _FakeRealtimeService();
      final connectivity = StreamController<bool>.broadcast();
      final plusStore = InMemoryAccountPlusCacheStore();
      final plus = PlusController(
        configRepository: _OfflineConfigRepo(),
        configStore: InMemoryPlusConfigStore(),
        entitlementStore: InMemoryEntitlementLocalStore(),
        verifier: _RejectVerifier(),
        billing: _NoopBilling(),
        accountPlusStore: plusStore,
        clock: FakeClock(now),
      );
      await plus.loadCached();

      final controller = AccountController(
        authService: auth,
        profileRepository: profileRepo,
        keyDirectory: FakeKeyDirectory(),
        identity: ownerCrypto,
        groupRemote: remote,
        groupKeyManager: GroupKeyManager(
          remote: remote,
          crypto: ownerCrypto,
          store: _MemKeyStore(),
        ),
        cache: cache,
        realtimeService: realtime,
        plusController: plus,
        connectivityStream: connectivity.stream,
        clock: FakeClock(now),
      );
      addTearDown(() async {
        controller.dispose();
        await auth.close();
        await realtime.close();
        await connectivity.close();
      });

      connectivity.add(false);
      controller.initialize();
      await pumpEventQueue();

      // Saat offline, seluruh data dari cache lokal TETAP tampil dan tidak dihapus
      expect(controller.groups, hasLength(1));
      expect(controller.groups.single.group.name, 'Tim Rinjani');
      expect(controller.memberCountFor('g-1'), 2);
      expect(controller.needsUsername, isFalse);
      expect(controller.profile?.username, 'raka_hiker');
      expect(plus.hasPlus, isTrue);

      // Koneksi kembali ONLINE -> auto-sync via connectivity listener
      profileRepo.fail = false;
      remote.failAllNetwork = false;
      connectivity.add(true);
      await pumpEventQueue();

      expect(controller.profile?.fullName, 'Raka Updated');
      expect(controller.memberCountFor('g-1'), 3);

      // Realtime member leave -> jumlah anggota otomatis berkurang
      remote.membersByGroup['g-1'] = remote.membersByGroup['g-1']!.take(2).toList();
      realtime.controller.add(
        const GroupRealtimeEvent(
          kind: GroupRealtimeEventKind.membershipChanged,
          groupId: 'g-1',
          userId: 'user-3',
        ),
      );
      await pumpEventQueue();
      expect(controller.memberCountFor('g-1'), 2);

      // Realtime undangan baru masuk -> memicu stream notifikasi in-app
      final receivedBanners = <IncomingInvitation>[];
      final sub = controller.onIncomingInvitation.listen(receivedBanners.add);
      addTearDown(sub.cancel);

      remote.invitations = <IncomingInvitation>[
        IncomingInvitation(
          id: 'inv-realtime-1',
          groupId: 'g-99',
          groupName: 'Ekspedisi Semeru',
          inviterUsername: 'deni',
          createdAtUtc: now,
          expiresAtUtc: now.add(const Duration(days: 7)),
        ),
      ];
      realtime.controller.add(
        const GroupRealtimeEvent(
          kind: GroupRealtimeEventKind.invitationChanged,
          groupId: 'g-99',
          userId: 'user-1',
          invitationId: 'inv-realtime-1',
        ),
      );
      await pumpEventQueue();

      expect(controller.pendingInvitationCount, 1);
      expect(receivedBanners, hasLength(1));
      expect(receivedBanners.single.groupName, 'Ekspedisi Semeru');
      expect(receivedBanners.single.inviterUsername, 'deni');
    });

    test(
        'OffGridChatLocalStore deduplikasi ketat berdasarkan client_msg_id & membersihkan duplikat lama',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = OffGridChatLocalStore(database: db);
      addTearDown(() async {
        await store.dispose();
        await db.close();
      });

      final msgUuid = generateUuidV4();
      final sentTime = DateTime.utc(2026, 11, 19, 8, 30, 0);

      // 1. Kirim pesan lokal (pending)
      final inserted = await store.insertMessageIfAbsent(
        GroupMessageRecord(
          clientMsgId: msgUuid,
          groupId: 'grp-1',
          senderId: 'u-sender',
          senderName: 'Raka',
          messageType: GroupMessageType.text,
          content: 'Sudah sampai Pos 2',
          originTransport: ChatTransportOrigin.online,
          syncStatus: ChatSyncStatus.pending,
          clientCreatedAtUtc: sentTime,
        ),
      );
      expect(inserted, isTrue);

      // 2. Pantulan Supabase Realtime echo dengan client_msg_id yang sama ->
      //    menimpa/update baris menjadi 'sent' tanpa pernah membuat baris baru!
      final echoed = await store.insertMessageIfAbsent(
        GroupMessageRecord(
          id: msgUuid,
          clientMsgId: msgUuid,
          groupId: 'grp-1',
          senderId: 'u-sender',
          senderName: 'Raka',
          messageType: GroupMessageType.text,
          content: 'Sudah sampai Pos 2',
          originTransport: ChatTransportOrigin.online,
          syncStatus: ChatSyncStatus.sent,
          clientCreatedAtUtc: sentTime,
        ),
      );
      expect(echoed, isFalse);

      var rows = await store.messagesForGroup('grp-1');
      expect(rows, hasLength(1));
      expect(rows.single.syncStatus, ChatSyncStatus.sent);

      // 3. Simulasikan baris duplikat historis (UUID berbeda, isi & waktu hampir identik)
      await store.insertMessageIfAbsent(
        GroupMessageRecord(
          clientMsgId: generateUuidV4(),
          groupId: 'grp-1',
          senderId: 'u-sender',
          senderName: 'Raka',
          messageType: GroupMessageType.text,
          content: 'Sudah sampai Pos 2',
          originTransport: ChatTransportOrigin.online,
          syncStatus: ChatSyncStatus.pending,
          clientCreatedAtUtc: sentTime.add(const Duration(milliseconds: 500)),
        ),
      );
      expect(await store.messagesForGroup('grp-1'), hasLength(2));

      final cleaned = await store.cleanupDuplicateMessages(groupId: 'grp-1');
      expect(cleaned, 1);

      rows = await store.messagesForGroup('grp-1');
      expect(rows, hasLength(1));
      expect(rows.single.clientMsgId, msgUuid);
      expect(rows.single.syncStatus, ChatSyncStatus.sent);
    });

    test(
        'Sinkronisasi kunci grup BLE Mesh: MeshPacketCodec tidak meracuni secure storage & kunci identik antar-HP',
        () async {
      final ownerCrypto = CryptographyIdentityService(store: _MemSecretStore());
      final memberCrypto = CryptographyIdentityService(store: _MemSecretStore());
      final ownerStore = _MemKeyStore();
      final memberStore = _MemKeyStore();
      final groupId = '11111111-2222-4333-8444-555555555555';

      // Skenario 1: Member membuka MeshPacketCodec sebelum kunci dibagikan pemilik
      final memberCodec = MeshPacketCodec(keyStore: memberStore);
      await memberCodec.resolveGroupKey(groupId, 1);
      // Pastikan keyStore TIDAK diracuni oleh kunci fallback deterministik!
      expect(await memberStore.readGroupKey(groupId, 1), isNull);

      // Skenario 2: Simulasikan HP lama yang pernah teracuni fallback lama
      final poisonedFallback =
          await MeshPacketCodec.deriveFallbackGroupKey(groupId, 1);
      await memberStore.writeGroupKey(groupId, 1, poisonedFallback);

      final group = Group(
        id: groupId,
        name: 'Tim Ciremai',
        ownerId: 'owner-1',
        createdAtUtc: DateTime.utc(2026, 11, 1),
      );
      final remote = _FakeGroupRemoteWithRealtime(viewerId: 'owner-1')
        ..membersByGroup[groupId] = <MemberDirectoryEntry>[
          MemberDirectoryEntry(
            userId: 'owner-1',
            username: 'pemilik',
            role: GroupRole.owner,
            publicKeyBase64: base64Encode(await ownerCrypto.publicKey()),
            joinedAtUtc: DateTime.utc(2026, 11, 1),
          ),
          MemberDirectoryEntry(
            userId: 'member-1',
            username: 'anggota',
            role: GroupRole.member,
            publicKeyBase64: base64Encode(await memberCrypto.publicKey()),
            joinedAtUtc: DateTime.utc(2026, 11, 1),
          ),
        ];

      final ownerMgr = GroupKeyManager(
        remote: remote,
        crypto: ownerCrypto,
        store: ownerStore,
      );
      final memberMgr = GroupKeyManager(
        remote: remote,
        crypto: memberCrypto,
        store: memberStore,
      );

      await ownerMgr.ensureOwnedGroupKey(
        RemoteGroup(group: group, role: GroupRole.owner),
      );
      remote.viewerId = 'member-1';
      await memberMgr.ensureMembershipKey(
        RemoteGroup(group: group, role: GroupRole.member),
      );

      final ownerKey = await ownerStore.readGroupKey(groupId, 1);
      final memberKey = await memberStore.readGroupKey(groupId, 1);
      expect(ownerKey, isNotNull);
      expect(memberKey, equals(ownerKey));

      // Verifikasi enkripsi BLE Mesh dari HP Pemilik berhasil didekripsi HP Anggota
      final ownerCodec = MeshPacketCodec(keyStore: ownerStore);
      memberCodec.invalidateKeyCache(groupId);
      final chunks = await ownerCodec.encodeAndChunk(
        MeshEnvelope(
          kind: MeshPayloadKind.chatMessage,
          clientMsgId: generateUuidV4(),
          groupId: groupId,
          keyVersion: 1,
          ttl: 5,
          chatMessage: GroupMessageRecord(
            clientMsgId: generateUuidV4(),
            groupId: groupId,
            senderId: 'owner-1',
            senderName: 'Pemilik',
            messageType: GroupMessageType.text,
            content: 'Pesan BLE Mesh terenkripsi sukses!',
            originTransport: ChatTransportOrigin.bleMesh,
            syncStatus: ChatSyncStatus.pending,
            clientCreatedAtUtc: DateTime.utc(2026, 11, 19, 9, 0),
          ),
        ),
      );

      MeshIngestResult? decoded;
      for (final chunk in chunks) {
        decoded = await memberCodec.ingestChunk(chunk, groupId: groupId);
      }
      expect(decoded, isNotNull);
      expect(
        decoded!.envelope.chatMessage?.content,
        'Pesan BLE Mesh terenkripsi sukses!',
      );
    });

    test(
        'PlusController menyimpan status Hiqeo Plus dari akun Supabase ke cache lokal untuk mode offline',
        () async {
      final now = DateTime.utc(2026, 11, 19);
      final accountPlusStore = InMemoryAccountPlusCacheStore();

      final onlineController = PlusController(
        configRepository: _OfflineConfigRepo(),
        configStore: InMemoryPlusConfigStore(),
        entitlementStore: InMemoryEntitlementLocalStore(),
        verifier: _RejectVerifier(),
        billing: _NoopBilling(),
        accountPlusStore: accountPlusStore,
        clock: FakeClock(now),
      );
      await onlineController.loadCached();
      expect(onlineController.hasPlus, isFalse);

      await onlineController.syncAccountPlus(
        userId: 'test-google-1',
        isPlus: true,
        planId: 'lifetime',
      );
      expect(onlineController.hasPlus, isTrue);
      expect(onlineController.access.lifetime, isTrue);

      // Cold restart aplikasi saat OFFLINE -> tetap Hiqeo Plus aktif dari cache!
      final offlineRestartController = PlusController(
        configRepository: _OfflineConfigRepo(),
        configStore: InMemoryPlusConfigStore(),
        entitlementStore: InMemoryEntitlementLocalStore(),
        verifier: _RejectVerifier(),
        billing: _NoopBilling(),
        accountPlusStore: accountPlusStore,
        clock: FakeClock(now.add(const Duration(days: 5))),
      );
      await offlineRestartController.loadCached();
      expect(offlineRestartController.hasPlus, isTrue);
      expect(offlineRestartController.access.lifetime, isTrue);
    });
  });
}
