import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/social/data/social_unread_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('menandai pesan belum dibaca secara lokal dan membersihkan saat dibuka',
      () async {
    final t1 = DateTime.utc(2026, 11, 20, 10, 0);
    final t2 = DateTime.utc(2026, 11, 20, 10, 5);
    var rows = <Map<String, dynamic>>[
      <String, dynamic>{
        'room_kind': 'group',
        'room_id': 'g-1',
        'message_id': 'm-1',
        'sender_id': 'user-other',
        'message_type': 'text',
        'ciphertext': 'cipher-ok',
        'key_version': 1,
        'created_at': t1.toIso8601String(),
      },
      <String, dynamic>{
        'room_kind': 'group',
        'room_id': 'g-self',
        'message_id': 'm-2',
        'sender_id': 'user-me',
        'message_type': 'text',
        'ciphertext': 'cipher-fail',
        'key_version': 1,
        'created_at': t1.toIso8601String(),
      },
      <String, dynamic>{
        'room_kind': 'community',
        'room_id': 'c-img',
        'message_id': 'cm-1',
        'sender_id': 'user-other',
        'sender_name': 'Rani',
        'message_type': 'image',
        'content': '',
        'created_at': t1.toIso8601String(),
      },
      <String, dynamic>{
        'room_kind': 'community',
        'room_id': 'c-vid',
        'message_id': 'cm-2',
        'sender_id': 'user-other',
        'sender_name': '',
        'message_type': 'video',
        'content': '',
        'created_at': t1.toIso8601String(),
      },
    ];

    final store = SocialUnreadStore(
      fetcher: () async => rows,
      decryptor: ({
        required String kind,
        required String groupId,
        required String recordId,
        required int keyVersion,
        required String ciphertextBase64,
      }) async {
        if (ciphertextBase64 == 'cipher-ok') {
          return <String, dynamic>{
            'sender_name': 'Budi',
            'text': 'Siap berangkat besok!',
          };
        }
        throw StateError('kunci tidak ada');
      },
      currentUserIdProvider: () => 'user-me',
    );

    await store.refresh();

    final g1 = store.groupPreview('g-1');
    expect(g1, isNotNull);
    expect(g1!.hasUnread, isTrue);
    expect(g1.snippet, 'Budi: Siap berangkat besok!');

    final gSelf = store.groupPreview('g-self');
    expect(gSelf, isNotNull);
    expect(gSelf!.hasUnread, isFalse);
    expect(gSelf.snippet, 'Pesan terenkripsi');

    final cImg = store.communityPreview('c-img');
    expect(cImg, isNotNull);
    expect(cImg!.hasUnread, isTrue);
    expect(cImg.snippet, 'Rani: Foto');

    final cVid = store.communityPreview('c-vid');
    expect(cVid, isNotNull);
    expect(cVid!.snippet, 'Video');
    expect(store.hasAnyUnread, isTrue);

    await store.markGroupRead('g-1', at: t1);
    await store.markCommunityRead('c-img', at: t1);
    await store.markCommunityRead('c-vid', at: t1);
    expect(store.groupPreview('g-1')!.hasUnread, isFalse);
    expect(store.hasAnyUnread, isFalse);

    // Refresh dengan pesan yang sama tetap dianggap sudah dibaca.
    await store.refresh();
    expect(store.groupPreview('g-1')!.hasUnread, isFalse);

    // Pesan lebih baru memicu titik belum dibaca lagi.
    rows = <Map<String, dynamic>>[
      <String, dynamic>{
        'room_kind': 'group',
        'room_id': 'g-1',
        'message_id': 'm-3',
        'sender_id': 'user-other',
        'message_type': 'text',
        'ciphertext': 'cipher-ok',
        'key_version': 1,
        'created_at': t2.toIso8601String(),
      },
    ];
    await store.refresh();
    expect(store.groupPreview('g-1')!.hasUnread, isTrue);
  });
}
