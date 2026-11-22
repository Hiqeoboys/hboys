import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/chat/domain/group_chat_remote_service.dart';
import 'package:nama_app/features/groups/domain/group_key_store.dart';
import 'package:nama_app/features/plus/application/plus_navigation.dart';
import 'package:nama_app/features/plus/application/plus_scope.dart';
import 'package:nama_app/features/plus/domain/plus_plan.dart';
import 'package:nama_app/features/plus/presentation/paywall_page.dart';
import 'package:nama_app/features/social/data/chat_mute_service.dart';
import 'package:nama_app/features/social/data/community_service.dart';
import 'package:nama_app/features/social/data/social_unread_store.dart';
import 'package:nama_app/features/social/presentation/community_chat_page.dart';
import 'package:nama_app/infrastructure/crypto/crypto_interfaces.dart';
import 'package:nama_app/infrastructure/notifications/push_notification_service.dart';
import 'package:nama_app/infrastructure/offgrid/global_off_grid_outbox_service.dart';
import 'package:nama_app/infrastructure/offgrid/mesh_packet_codec.dart';
import 'package:nama_app/infrastructure/offgrid/mesh_router_service.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_chat_local_store.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_transport_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plus_fixtures.dart';

class _MemSecretStore implements SecretValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

class _MemGroupKeyStore implements GroupKeyStore {
  _MemGroupKeyStore(this._store);
  final SecretValueStore _store;

  @override
  Future<Uint8List?> readGroupKey(String groupId, int keyVersion) async {
    final v = await _store.read('$groupId:v$keyVersion');
    return v == null ? null : Uint8List.fromList(base64Decode(v));
  }

  @override
  Future<void> writeGroupKey(
    String groupId,
    int keyVersion,
    Uint8List groupKey,
  ) =>
      _store.write('$groupId:v$keyVersion', base64Encode(groupKey));

  @override
  Future<void> deleteGroupKey(String groupId, int keyVersion) =>
      _store.delete('$groupId:v$keyVersion');

  @override
  Future<String?> readDistributionSignature(
    String groupId,
    int keyVersion,
  ) async =>
      null;

  @override
  Future<void> writeDistributionSignature(
    String groupId,
    int keyVersion,
    String signature,
  ) async {}

  @override
  Future<void> deleteDistributionSignature(
    String groupId,
    int keyVersion,
  ) async {}
}

class _FakeGroupChatRemote implements GroupChatRemoteService {
  final List<GroupMessageRecord> syncedMessages = <GroupMessageRecord>[];
  final Set<String> seenIds = <String>{};
  int batchCalls = 0;

  @override
  Future<List<GroupMessageRecord>> fetchMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeCreatedAtUtc,
  }) async =>
      syncedMessages.where((m) => m.groupId == groupId).toList();

  @override
  Stream<List<GroupMessageRecord>> watchMessages(String groupId) =>
      const Stream<List<GroupMessageRecord>>.empty();

  @override
  Future<void> upsertMessage(GroupMessageRecord message) async {
    if (seenIds.add(message.clientMsgId)) {
      syncedMessages.add(message);
    }
  }

  @override
  Future<int> syncOfflineMessages(List<GroupMessageRecord> messages) async {
    batchCalls++;
    var added = 0;
    for (final m in messages) {
      if (seenIds.add(m.clientMsgId)) {
        syncedMessages.add(m);
        added++;
      }
    }
    return added;
  }

  @override
  Future<void> softDeleteMessage({
    required String groupId,
    required String clientMsgId,
  }) async {}

  @override
  Future<void> cancelHikeInviteMessage({
    required String groupId,
    required String clientMsgId,
  }) async {}

  @override
  Future<String> uploadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required Uint8List audioBytes,
    int keyVersion = 1,
  }) async =>
      '$groupId/$clientMsgId.enc';

  @override
  Future<Uint8List?> downloadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required String storagePath,
    int keyVersion = 1,
  }) async =>
      null;

  @override
  Future<String> resolveVoiceNotePlayUrl(String storagePathOrUrl) async =>
      storagePathOrUrl;

  @override
  Future<List<MemberLastLocation>> fetchMemberLocations(
    String groupId, {
    required String currentUserId,
  }) async =>
      const <MemberLastLocation>[];

  @override
  Stream<List<MemberLastLocation>> watchMemberLocations(
    String groupId, {
    required String currentUserId,
  }) =>
      const Stream<List<MemberLastLocation>>.empty();

  @override
  Future<void> upsertMemberLocation({
    required String groupId,
    required MemberLastLocation location,
    int keyVersion = 1,
  }) async {}

  @override
  Future<int> syncOfflineMemberLocations({
    required String groupId,
    required List<MemberLastLocation> locations,
    int keyVersion = 1,
  }) async =>
      locations.length;
}

CommunitySummary _testCommunity({
  bool isJoined = true,
  String ownerId = 'u-owner',
}) =>
    CommunitySummary(
      id: 'comm-w3',
      name: 'Semeru Hikers',
      description: 'Komunitas Ranu Kumbolo',
      ownerId: ownerId,
      createdBy: ownerId,
      memberCount: 12,
      isJoined: isJoined,
      createdAt: DateTime.utc(2026, 11, 1),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NavBarVisibilityController.instance.reset();
    PushNotificationService.instance.showNotificationForTesting = null;
  });

  tearDown(() {
    NavBarVisibilityController.instance.reset();
    PushNotificationService.instance.showNotificationForTesting = null;
  });

  testWidgets(
      'CommunityChatPage (#13, #16, #28): membatasi pesan sebelum firstEnteredAt, menyembunyikan tombol muat pesan lama, dan menampilkan centang abu tunggal',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final entryAt = DateTime.utc(2026, 11, 20, 10, 0);
    final messages = <CommunityMessage>[
      CommunityMessage(
        id: 'cm-old',
        communityId: 'comm-w3',
        senderId: 'u-owner',
        senderName: 'Raka',
        messageType: CommunityMessageType.text,
        content: 'Pesan lama sebelum masuk pertama',
        createdAt: entryAt.subtract(const Duration(minutes: 15)),
      ),
      CommunityMessage(
        id: 'cm-mine',
        communityId: 'comm-w3',
        senderId: 'u-me',
        senderName: 'Saya',
        messageType: CommunityMessageType.text,
        content: 'Pesan baru sesudah masuk',
        createdAt: entryAt.add(const Duration(minutes: 1)),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoDarkTheme,
        home: CommunityChatPage(
          community: _testCommunity(isJoined: true),
          initialMessages: messages,
          firstEnteredAtOverride: entryAt,
          hasFullSocialOverride: true,
          currentUserIdOverride: 'u-me',
          muteService: ChatMuteService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pesan lama sebelum masuk pertama'), findsNothing);
    expect(find.text('Pesan baru sesudah masuk'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('community-load-older-btn')),
      findsNothing,
    );
    expect(find.text('Muat pesan sebelumnya'), findsNothing);

    // #28: Pesan sendiri di komunitas memakai 1 centang abu, bukan centang ganda biru.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
  });

  testWidgets(
      'CommunityChatPage (#14, #15): non-anggota melihat "Gabung / Ikuti komunitas", bergabung langsung membuka kolom ketik untuk Tahunan, dan Tiket 1x Naik diarahkan ke Hiqeo Plus lalu kembali ke ruang komunitas',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Bagian A: Pelanggan penuh -> Gabung langsung memunculkan bilah ketik.
    var joinedFull = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoDarkTheme,
        home: CommunityChatPage(
          community: _testCommunity(isJoined: false),
          initialMessages: const <CommunityMessage>[],
          hasFullSocialOverride: true,
          currentUserIdOverride: 'u-me',
          muteService: ChatMuteService(),
          onJoinCommunity: () async {
            joinedFull = true;
            return _testCommunity(isJoined: true);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('community-join-button')),
      findsOneWidget,
    );
    expect(find.text('Gabung / Ikuti komunitas'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('community-input')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('community-join-button')));
    await tester.pumpAndSettle();

    expect(joinedFull, isTrue);
    expect(
      find.byKey(const ValueKey<String>('community-join-button')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('community-input')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('community-send-button')),
      findsOneWidget,
    );

    // Bagian B: Pemilik Tiket 1x Naik bergabung -> diarahkan ke PaywallPage dengan penjelasan -> tekan '<' kembali tepat ke ruang komunitas.
    final tripController = await buildPlusController(
      token: 'tok-trip',
      payload: plusPayload(planId: 'trip_pass_3d'),
      config: plusConfig(
        fetchedAtUtc: DateTime.utc(2026, 11, 20),
        plans: const <PlusPlan>[
          PlusPlan(
            id: 'trip_pass_3d',
            title: 'Tiket 1x Naik',
            priceLabel: 'Rp 19.000',
            periodLabel: 'per pendakian',
          ),
          PlusPlan(
            id: 'student_annual',
            title: 'Hiqeo Plus Mahasiswa',
            priceLabel: 'Rp 99.000',
            periodLabel: 'per tahun',
          ),
          annualPlan,
        ],
      ),
    );
    addTearDown(tripController.dispose);

    var joinedTrip = false;
    await tester.pumpWidget(
      PlusScope(
        controller: tripController,
        child: MaterialApp(
          theme: hiqeoLightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey<String>('open-comm-room'),
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CommunityChatPage(
                          community: _testCommunity(isJoined: false),
                          initialMessages: const <CommunityMessage>[],
                          currentUserIdOverride: 'u-me',
                          muteService: ChatMuteService(),
                          onJoinCommunity: () async {
                            joinedTrip = true;
                            return _testCommunity(isJoined: true);
                          },
                        ),
                      ),
                    );
                  },
                  child: const Text('Buka komunitas'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('open-comm-room')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('community-join-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('community-join-button')));
    await tester.pumpAndSettle();

    expect(joinedTrip, isTrue);
    expect(find.byType(PaywallPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('paywall-custom-notice')),
      findsOneWidget,
    );
    expect(find.text('Hiqeo Plus Mahasiswa'), findsOneWidget);
    expect(find.text('Hiqeo Plus Tahunan'), findsOneWidget);
    expect(find.text('Tiket 1x Naik'), findsNothing);

    // Tekan tombol '<' -> wajib kembali tepat ke CommunityChatPage (bukan root).
    await tester.tap(find.bySemanticsLabel('Kembali'));
    await tester.pumpAndSettle();

    expect(find.byType(CommunityChatPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('community-upgrade-plus-button')),
      findsOneWidget,
    );
  });

  testWidgets(
      'Hiqeo Plus back navigation (#15): GoRouter push dari Profil ke /plus lalu tekan "<" kembali ke Profil',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await buildPlusController(
      config: plusConfig(fetchedAtUtc: DateTime.utc(2026, 11, 20)),
    );
    addTearDown(controller.dispose);

    final router = GoRouter(
      initialLocation: '/profil',
      routes: <RouteBase>[
        GoRoute(
          path: '/profil',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey<String>('profil-open-plus'),
                onPressed: () => openPlusPaywall(context),
                child: const Text('Halaman Profil'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: PlusRoutes.paywall,
          builder: (_, __) => const PaywallPage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      PlusScope(
        controller: controller,
        child: MaterialApp.router(
          theme: hiqeoLightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Halaman Profil'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('profil-open-plus')));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallPage), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Kembali'));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallPage), findsNothing);
    expect(find.text('Halaman Profil'), findsOneWidget);
  });

  testWidgets(
      'CommunityChatPage (#30): pembuat yang masih bergabung melihat "Keluar komunitas" dan "Hapus komunitas"',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoDarkTheme,
        home: CommunityChatPage(
          community: _testCommunity(isJoined: true, ownerId: 'u-me'),
          initialMessages: const <CommunityMessage>[],
          hasFullSocialOverride: true,
          currentUserIdOverride: 'u-me',
          muteService: ChatMuteService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey<String>('community-hamburger-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('community-menu-leave')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('community-menu-delete')),
      findsOneWidget,
    );
    expect(find.text('Keluar komunitas'), findsOneWidget);
    expect(find.text('Hapus komunitas'), findsOneWidget);
  });

  test('SocialUnreadStore (#25): status baca grup bertahan setelah restart',
      () async {
    final t1 = DateTime.utc(2026, 11, 20, 9, 0);
    final t2 = DateTime.utc(2026, 11, 20, 9, 10);
    var latestId = 'm-1';
    var latestAt = t1;

    SocialUnreadStore makeStore() => SocialUnreadStore(
          fetcher: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'room_kind': 'group',
              'room_id': 'g-1',
              'message_id': latestId,
              'sender_id': 'u-other',
              'message_type': 'text',
              'ciphertext': 'cipher-1',
              'key_version': 1,
              'created_at': latestAt.toIso8601String(),
            },
          ],
          decryptor: ({
            required String kind,
            required String groupId,
            required String recordId,
            required int keyVersion,
            required String ciphertextBase64,
          }) async =>
              <String, dynamic>{'sender_name': 'Dimas', 'text': 'Halo tim'},
          currentUserIdProvider: () => 'u-me',
        );

    final storeBeforeRestart = makeStore();
    await storeBeforeRestart.refresh();
    expect(storeBeforeRestart.groupPreview('g-1')?.hasUnread, isTrue);

    await storeBeforeRestart.markGroupRead(
      'g-1',
      at: t1,
      lastMessageId: 'm-1',
    );
    expect(storeBeforeRestart.groupPreview('g-1')?.hasUnread, isFalse);

    // Simulasikan restart aplikasi dengan instance baru yang membaca SharedPreferences.
    final storeAfterRestart = makeStore();
    await storeAfterRestart.refresh();
    expect(storeAfterRestart.groupPreview('g-1')?.hasUnread, isFalse);

    // Pesan baru datang sesudah m-1 -> kembali ditandai belum dibaca.
    latestId = 'm-2';
    latestAt = t2;
    await storeAfterRestart.refresh();
    expect(storeAfterRestart.groupPreview('g-1')?.hasUnread, isTrue);
  });

  test(
      'Mesh offline (#26, #27): notifikasi perangkat untuk pesan peer masuk & auto-sync idempoten saat online',
      () async {
    const groupUuid = '11111111-2222-4333-8444-555555555555';
    final msgId = generateUuidV4();

    final delivered = <({String title, String body, String payload})>[];
    PushNotificationService.instance.showNotificationForTesting = ({
      required int id,
      required String title,
      required String body,
      required NotificationDetails details,
      required String payload,
    }) async {
      delivered.add((title: title, body: body, payload: payload));
    };

    final bus = LoopbackOffGridMeshBus();
    final keyStore = _MemGroupKeyStore(_MemSecretStore());
    final txStore = OffGridChatLocalStore();
    final rxStore = OffGridChatLocalStore();
    final txRouter = MeshRouterService(
      adapter: InMemoryOffGridTransportAdapter(nodeId: 'tx', bus: bus),
      codec: MeshPacketCodec(keyStore: keyStore),
      localStore: txStore,
    );
    final rxRouter = MeshRouterService(
      adapter: InMemoryOffGridTransportAdapter(nodeId: 'rx', bus: bus),
      codec: MeshPacketCodec(keyStore: keyStore),
      localStore: rxStore,
    );
    bus.connect('tx', 'rx');

    final receivedViaStream = <GroupMessageRecord>[];
    final rxSub = rxRouter.onIncomingMessage.listen(receivedViaStream.add);
    addTearDown(rxSub.cancel);

    await txRouter.start(groupId: groupUuid, highDuty: true);
    await rxRouter.start(groupId: groupUuid, highDuty: true);

    await txRouter.sendTextMessage(
      GroupMessageRecord(
        clientMsgId: msgId,
        groupId: groupUuid,
        senderId: 'user-raka',
        senderName: 'Raka',
        messageType: GroupMessageType.text,
        content: 'Kabut turun di Pos 3',
        originTransport: ChatTransportOrigin.bleMesh,
        syncStatus: ChatSyncStatus.pending,
        clientCreatedAtUtc: DateTime.utc(2026, 11, 22, 8, 0),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(receivedViaStream, hasLength(1));
    expect(receivedViaStream.single.clientMsgId, msgId);

    // Self-sent diabaikan; pesan peer lain memunculkan notifikasi OS.
    await PushNotificationService.instance.showOfflineMeshMessageNotification(
      record: receivedViaStream.single,
      groupName: 'Tim Prau',
      currentUserId: 'user-raka',
    );
    expect(delivered, isEmpty);

    await PushNotificationService.instance.showOfflineMeshMessageNotification(
      record: receivedViaStream.single,
      groupName: 'Tim Prau',
      currentUserId: 'user-me',
    );
    expect(delivered, hasLength(1));
    expect(delivered.single.title, contains('Tim Prau'));
    expect(delivered.single.body, 'Raka: Kabut turun di Pos 3');

    // #27: Begitu koneksi kembali online, outbox menyinkronkan pesan pending otomatis & idempoten.
    final connCtrl = StreamController<bool>.broadcast();
    final remote = _FakeGroupChatRemote();
    final outbox = GlobalOffGridOutboxService(
      localStore: rxStore,
      remoteFactory: () => remote,
      connectivityOnlineStream: connCtrl.stream,
    );
    outbox.start();

    connCtrl.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(remote.syncedMessages, hasLength(1));
    expect(remote.syncedMessages.single.clientMsgId, msgId);
    final storedAfterSync = await rxStore.messagesForGroup(groupUuid);
    expect(storedAfterSync.single.syncStatus, ChatSyncStatus.sent);

    // Emisi ulang event online tidak membuat pesan ganda.
    connCtrl.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(remote.syncedMessages, hasLength(1));

    await outbox.dispose();
    await connCtrl.close();
    await txRouter.dispose();
    await rxRouter.dispose();
    await txStore.dispose();
    await rxStore.dispose();
  });
}
