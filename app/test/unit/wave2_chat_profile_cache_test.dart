import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/chat/presentation/chat_mute_sheet.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/chat/presentation/group_members_sheet.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/social/data/chat_mute_service.dart';
import 'package:nama_app/features/social/data/community_service.dart';
import 'package:nama_app/features/social/data/friends_service.dart';
import 'package:nama_app/features/social/data/social_unread_store.dart';
import 'package:nama_app/features/social/presentation/widgets/community_chat_interactions.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestMsg {
  const _TestMsg({
    required this.id,
    required this.senderId,
    required this.createdAtUtc,
  });

  final String id;
  final String senderId;
  final DateTime createdAtUtc;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    FriendsService.instance.clear();
    await ChatMuteService.instance.clearLocal();
  });

  group('Wave 2 friends offline cache & fallback label', () {
    test('FriendRecord toJson/fromJson round-trip, label fallback, dan loadCached offline', () async {
      final createdAt = DateTime.utc(2026, 11, 15, 8, 30);
      final record = FriendRecord(
        friendshipId: 'f-1',
        userId: 'u-sari',
        username: 'sari_hiker',
        displayName: 'Sari Dewi',
        avatarUrl: 'https://cdn.example.com//avatars/u-sari.webp',
        status: 'accepted',
        isIncoming: false,
        createdAt: createdAt,
      );
      final parsed = FriendRecord.fromJson(record.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.displayName, 'Sari Dewi');
      expect(parsed.username, 'sari_hiker');
      expect(parsed.label, 'Sari Dewi');
      expect(parsed.avatarUrl, 'https://cdn.example.com/avatars/u-sari.webp');

      expect(
        FriendRecord(
          friendshipId: 'f-2',
          userId: 'u-2',
          username: '@bayu',
          displayName: '',
          status: 'accepted',
          isIncoming: false,
          createdAt: createdAt,
        ).label,
        '@bayu',
      );
      expect(
        FriendRecord(
          friendshipId: 'f-3',
          userId: 'u-3',
          username: '',
          displayName: null,
          status: 'accepted',
          isIncoming: false,
          createdAt: createdAt,
        ).label,
        'Pendaki',
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'hiqeo_friends_cache_v1_u-me': jsonEncode(<String, dynamic>{
          'friends': <Map<String, dynamic>>[record.toJson()],
          'incoming': const <Map<String, dynamic>>[],
          'outgoing': const <Map<String, dynamic>>[],
        }),
      });
      await FriendsService.instance.loadCached(userIdOverride: 'u-me');
      expect(FriendsService.instance.friends, hasLength(1));
      expect(FriendsService.instance.friends.first.displayName, 'Sari Dewi');
      expect(
        FriendsService.instance.friends.first.avatarUrl,
        'https://cdn.example.com/avatars/u-sari.webp',
      );
    });
  });

  group('Wave 2 presence & group readiness badges', () {
    test('formatLastActiveLabel menggunakan last_seen_at secara akurat', () {
      final now = DateTime.utc(2026, 11, 21, 12, 0);
      expect(
        formatLastActiveLabel(now.subtract(const Duration(seconds: 40)), now),
        'Sedang aktif',
      );
      expect(
        formatLastActiveLabel(now.subtract(const Duration(minutes: 2)), now),
        'Sedang aktif',
      );
      expect(
        formatLastActiveLabel(now.subtract(const Duration(minutes: 12)), now),
        'Aktif 12 mnt lalu',
      );
      expect(
        formatLastActiveLabel(now.subtract(const Duration(hours: 3)), now),
        'Aktif 3 jam lalu',
      );
      expect(
        formatLastActiveLabel(now.subtract(const Duration(days: 2)), now),
        'Aktif 2 hari lalu',
      );
    });

    test('formatGroupReadinessBadge menangani tidak ada undangan, 0 siap, sebagian, dan semua siap', () {
      expect(
        formatGroupReadinessBadge(
          hasActiveInvite: false,
          readyCount: 1,
          memberCount: 2,
        ),
        isNull,
      );
      expect(
        formatGroupReadinessBadge(
          hasActiveInvite: true,
          readyCount: 0,
          memberCount: 4,
        ),
        'Belum ada yang siap',
      );
      expect(
        formatGroupReadinessBadge(
          hasActiveInvite: true,
          readyCount: 3,
          memberCount: 5,
        ),
        'Siap naik 3/5',
      );
      expect(
        formatGroupReadinessBadge(
          hasActiveInvite: true,
          readyCount: 5,
          memberCount: 5,
        ),
        'Semua siap',
      );
    });

    test('GroupCardData default memiliki hasActiveHikeInvite=false dan readyCount=0', () {
      final card = GroupCardData(
        remote: RemoteGroup(
          group: Group(
            id: 'g-1',
            name: 'Grup Baru',
            ownerId: 'u-1',
            createdAtUtc: DateTime.utc(2026, 11, 21),
          ),
          role: GroupRole.owner,
        ),
        memberCount: 1,
      );
      expect(card.hasActiveHikeInvite, isFalse);
      expect(card.readyCount, 0);
      final updated = card.copyWith(hasActiveHikeInvite: true, readyCount: 1);
      expect(updated.hasActiveHikeInvite, isTrue);
      expect(updated.readyCount, 1);
    });

    test('GroupHikePlanStore melacak rencana aktif per groupId dan pembatalan', () async {
      final store = GroupHikePlanStore();
      const planA = GroupHikePlan(
        inviteId: 'inv-a',
        groupId: 'g-a',
        groupName: 'Tim A',
        mountainId: 'merbabu',
        mountainName: 'Gunung Merbabu',
        organizerUserId: 'u-1',
        organizerName: 'Raka',
        readyUserIds: <String>{'u-1', 'u-2'},
        memberCount: 4,
      );
      await store.setPlan(planA);
      expect(store.activePlanForGroup('g-a')?.readyUserIds.length, 2);
      expect(store.activePlanForGroup('g-other'), isNull);

      store.markInviteCancelledLocally('inv-a', groupId: 'g-a');
      expect(store.isInviteCancelled('inv-a'), isTrue);
      expect(store.activePlanForGroup('g-a'), isNull);
    });
  });

  group('Wave 2 community date, @mentions & highlight spans', () {
    final joinedMembers = <CommunityMemberEntry>[
      CommunityMemberEntry(
        userId: 'u-me',
        username: 'aku',
        fullName: 'Aku Sendiri',
        role: 'member',
        joinedAt: DateTime.utc(2026, 10, 1),
      ),
      CommunityMemberEntry(
        userId: 'u-raka',
        username: 'raka_hiker',
        fullName: 'Raka Pratama',
        role: 'admin',
        joinedAt: DateTime.utc(2026, 10, 2),
      ),
      CommunityMemberEntry(
        userId: 'u-sari',
        username: 'sari_dewi',
        fullName: 'Sari Dewi',
        role: 'member',
        joinedAt: DateTime.utc(2026, 10, 3),
      ),
    ];

    test('formatIndonesianFullDate memformat tanggal penuh Bahasa Indonesia', () {
      expect(
        formatIndonesianFullDate(DateTime(2026, 11, 14)),
        '14 November 2026',
      );
      expect(
        formatIndonesianFullDate(DateTime(2026, 1, 5)),
        '5 Januari 2026',
      );
    });

    test('extractActiveMentionQuery dan filterCommunityMentions hanya memuat anggota bergabung', () {
      const value = TextEditingValue(
        text: 'Halo @rak',
        selection: TextSelection.collapsed(offset: 9),
      );
      final match = extractActiveMentionQuery(value);
      expect(match, isNotNull);
      expect(match!.query, 'rak');
      expect(match.startOffset, 5);

      final filtered = filterCommunityMentions(
        joinedMembers,
        match.query,
        excludeUserId: 'u-me',
      );
      expect(filtered.map((m) => m.username), <String>['raka_hiker']);

      // Jangan anggap alamat email sebagai mention
      const emailValue = TextEditingValue(
        text: 'emailku test@rak',
        selection: TextSelection.collapsed(offset: 16),
      );
      expect(extractActiveMentionQuery(emailValue), isNull);
    });

    test('resolveMentionedUserIds hanya mengambil anggota komunitas terdaftar tanpa duplikasi', () {
      final ids = resolveMentionedUserIds(
        'Ketemu @raka_hiker di pos 2 sama @sari_dewi & @raka_hiker plus @orang_luar',
        joinedMembers,
      );
      expect(ids, <String>['u-raka', 'u-sari']);
    });

    test('buildHighlightedMentionSpans menyorot token @username', () {
      const base = TextStyle(color: Colors.white);
      const mention = TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.w700);
      final spans = buildHighlightedMentionSpans(
        'Halo @raka_hiker ayo berangkat',
        baseStyle: base,
        mentionStyle: mention,
      );
      final texts = spans.whereType<TextSpan>().map((s) => s.text).toList();
      final styles = spans.whereType<TextSpan>().map((s) => s.style).toList();
      expect(texts.join(), 'Halo @raka_hiker ayo berangkat');
      final mentionIdx = texts.indexOf('@raka_hiker');
      expect(mentionIdx, greaterThanOrEqualTo(0));
      expect(styles[mentionIdx], mention);
    });
  });

  group('Wave 2 unread cursor & notification mute service', () {
    test('SocialUnreadStore menyimpan last_read_message_id dan computeUnreadMarker menghitung pesan belum dibaca', () async {
      final store = SocialUnreadStore(
        currentUserIdProvider: () => 'u-me',
      );
      final t1 = DateTime.utc(2026, 11, 21, 9, 0);
      final t2 = DateTime.utc(2026, 11, 21, 9, 5);
      final t3 = DateTime.utc(2026, 11, 21, 9, 10);

      await store.markCommunityRead('c-1', at: t1, lastMessageId: 'm-1');
      final cursor = await store.getCommunityReadCursor('c-1');
      expect(cursor.lastReadMessageId, 'm-1');
      expect(cursor.lastReadAtUtc, t1);

      final marker = computeUnreadMarker<_TestMsg>(
        messages: <_TestMsg>[
          _TestMsg(id: 'm-1', senderId: 'u-other', createdAtUtc: t1),
          _TestMsg(id: 'm-2', senderId: 'u-other', createdAtUtc: t2),
          _TestMsg(id: 'm-3', senderId: 'u-other', createdAtUtc: t3),
        ],
        cursor: cursor,
        currentUserId: 'u-me',
        idOf: (m) => m.id,
        senderIdOf: (m) => m.senderId,
        createdAtOf: (m) => m.createdAtUtc,
      );
      expect(marker.firstUnreadIndex, 1);
      expect(marker.unreadCount, 2);

      // Kunjungan perdana tanpa kursor tidak menampilkan divider belum dibaca
      final firstVisit = computeUnreadMarker<_TestMsg>(
        messages: <_TestMsg>[
          _TestMsg(id: 'm-1', senderId: 'u-other', createdAtUtc: t1),
        ],
        cursor: const RoomReadCursor(),
        currentUserId: 'u-me',
        idOf: (m) => m.id,
        senderIdOf: (m) => m.senderId,
        createdAtOf: (m) => m.createdAtUtc,
      );
      expect(firstVisit.firstUnreadIndex, isNull);
      expect(firstVisit.unreadCount, 0);
    });

    test('ChatMuteService menyimpan 1 hari, 1 minggu, selamanya, dan unmute dengan sinkronisasi lokal', () async {
      final remoteCalls = <({String roomType, String roomId, DateTime? until})>[];
      final service = ChatMuteService(
        userIdProvider: () => 'u-me',
        remoteUpsert: (_, roomType, roomId, mutedUntilUtc) async {
          remoteCalls.add((roomType: roomType, roomId: roomId, until: mutedUntilUtc));
        },
        remoteFetchAll: (_) async => const <Map<String, dynamic>>[],
      );
      final now = DateTime.utc(2026, 11, 21, 10, 0);

      await service.muteFor('group', 'g-1', const Duration(days: 1), nowUtc: now);
      expect(service.isMuted('group', 'g-1', nowUtc: now), isTrue);
      expect(service.isMutedForever('group', 'g-1'), isFalse);
      expect(
        chatMuteStatusShortLabel(service, 'group', 'g-1', nowUtc: now),
        '1 hari lagi',
      );

      await service.muteFor('community', 'c-1', const Duration(days: 7), nowUtc: now);
      expect(
        chatMuteStatusShortLabel(service, 'community', 'c-1', nowUtc: now),
        '7 hari lagi',
      );

      await service.muteForever('group', 'g-1');
      expect(service.isMutedForever('group', 'g-1'), isTrue);
      expect(
        chatMuteStatusShortLabel(service, 'group', 'g-1', nowUtc: now),
        'Selamanya',
      );

      await service.unmute('group', 'g-1');
      expect(service.isMuted('group', 'g-1', nowUtc: now), isFalse);
      expect(remoteCalls.length, 4);
      expect(remoteCalls.last.until, isNull);
    });
  });
}
