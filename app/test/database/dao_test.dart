import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/infrastructure/database/app_database.dart';
import 'package:nama_app/infrastructure/database/daos/chat_dao.dart';
import 'package:nama_app/infrastructure/database/daos/group_dao.dart';
import 'package:nama_app/infrastructure/database/daos/invitation_dao.dart';
import 'package:nama_app/infrastructure/database/daos/outbox_dao.dart';
import 'package:nama_app/infrastructure/database/daos/safety_dao.dart';
import 'package:nama_app/infrastructure/database/daos/tracking_dao.dart';
import 'package:nama_app/infrastructure/database/database_connection.dart';

final t0 = DateTime.utc(2027, 6, 1, 8);

GroupsCompanion groupRow(String id) => GroupsCompanion.insert(
      id: id,
      name: 'Rombongan $id',
      ownerId: 'owner_01',
      mountain: const Value('Gede'),
      createdAtUtc: t0,
    );

MembersCompanion member(
  String groupId,
  String userId, {
  String role = 'member',
  DateTime? joinedAtUtc,
}) =>
    MembersCompanion.insert(
      groupId: groupId,
      userId: userId,
      username: userId,
      role: Value(role),
      joinedAtUtc: joinedAtUtc ?? t0,
    );

InvitationsCompanion invitation(
  String id, {
  String groupId = 'g1',
  String username = 'budi_99',
  String status = 'pending',
  DateTime? expiresAtUtc,
}) =>
    InvitationsCompanion.insert(
      id: id,
      groupId: groupId,
      inviterId: 'owner_01',
      inviteeUsername: username,
      status: Value(status),
      createdAtUtc: t0,
      expiresAtUtc: expiresAtUtc ?? t0.add(const Duration(days: 7)),
    );

MessagesCompanion message(
  String id, {
  String groupId = 'g1',
  int? seq,
  int typeCode = 1,
  DateTime? sentAtUtc,
}) {
  final messageSeq = seq ?? int.parse(id.split(':').last);
  return MessagesCompanion.insert(
    id: id,
    authorId: id.split(':').first,
    seq: messageSeq,
    groupId: groupId,
    typeCode: typeCode,
    sentAtUtc: sentAtUtc ?? t0.add(Duration(minutes: messageSeq)),
    receivedAtUtc: t0,
    payload: Uint8List.fromList([messageSeq]),
  );
}

SessionsCompanion session(String id, {DateTime? startedAtUtc}) =>
    SessionsCompanion.insert(
      id: id,
      startedAtUtc: startedAtUtc ?? t0,
      endedAtUtc: Value(t0.add(const Duration(hours: 2))),
      groupId: const Value('g1'),
      distanceM: const Value(1234.5),
      movingSeconds: const Value(3600),
      elevationGainM: const Value(120),
      elevationLossM: const Value(80),
      status: const Value('completed'),
    );

TrackPointsCompanion point(
  String sessionId, {
  double lat = -6.9,
  double lon = 107.6,
  DateTime? recordedAtUtc,
}) =>
    TrackPointsCompanion.insert(
      sessionId: sessionId,
      lat: lat,
      lon: lon,
      accuracyM: 5,
      recordedAtUtc: recordedAtUtc ?? t0,
    );

SosEventsCompanion sos(String id, {String status = 'active'}) =>
    SosEventsCompanion.insert(
      id: id,
      authorId: 'aaaaaaaaaaaaaaaa',
      categoryCode: 1,
      lat: -6.9,
      lon: 107.6,
      accuracyM: const Value(10),
      batteryPercent: const Value(42),
      createdAtUtc: t0,
      receivedAtUtc: t0,
      status: Value(status),
    );

EmergencyContactsCompanion contact(
  String id, {
  String userId = 'u1',
  String phone = '+628123456789',
}) =>
    EmergencyContactsCompanion.insert(
      id: id,
      userId: userId,
      name: 'Ibu',
      phoneE164: phone,
      createdAtUtc: t0,
    );

void main() {
  late AppDatabase db;

  setUp(() => db = openInMemoryAppDatabase());
  tearDown(() => db.close());

  group('GroupDao', () {
    test('upsert anggota, urutan, dan cascade saat grup dihapus', () async {
      final dao = GroupDao(db);
      await dao.upsertGroup(groupRow('g1'));
      await dao.upsertMember(
        member('g1', 'budi_99', joinedAtUtc: t0.add(const Duration(minutes: 1))),
      );
      await dao.upsertMember(member('g1', 'ani_88'));

      final members = await dao.membersOf('g1');
      expect(members.map((m) => m.userId), ['ani_88', 'budi_99']);
      expect(members.first.role, 'member');

      await dao.upsertMember(member('g1', 'ani_88', role: 'owner'));
      final updated = await dao.membersOf('g1');
      expect(updated.first.role, 'owner');

      await dao.deleteGroup('g1');
      expect(await dao.groupById('g1'), isNull);
      expect(await dao.membersOf('g1'), isEmpty);
    });

    test('menolak anggota dengan grup yang tidak ada', () async {
      final dao = GroupDao(db);
      await expectLater(
        dao.upsertMember(member('tidak_ada', 'budi_99')),
        throwsA(isA<Exception>()),
      );
    });

    test('menolak role di luar owner/member', () async {
      final dao = GroupDao(db);
      await dao.upsertGroup(groupRow('g1'));
      await expectLater(
        dao.upsertMember(member('g1', 'budi_99', role: 'leader')),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('InvitationDao', () {
    test('pending hanya mengembalikan yang pending dan belum kedaluwarsa',
        () async {
      final dao = InvitationDao(db);
      await dao.upsert(invitation('i1'));
      await dao.upsert(invitation(
        'i2',
        username: 'ani_88',
        expiresAtUtc: t0.subtract(const Duration(days: 1)),
      ));
      await dao.upsert(invitation('i3', status: 'accepted'));

      final rows = await dao.pendingFor('budi_99', t0);
      expect(rows.map((r) => r.id), ['i1']);
    });

    test('upsert memperbarui status undangan', () async {
      final dao = InvitationDao(db);
      await dao.upsert(invitation('i1'));
      await dao.upsert(invitation('i1', status: 'accepted'));

      expect((await dao.byId('i1'))!.status, 'accepted');
    });

    test('menolak undangan pending kedua untuk grup dan orang yang sama',
        () async {
      final dao = InvitationDao(db);
      await dao.upsert(invitation('i1'));
      await expectLater(
        dao.upsert(invitation('i2')),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ChatDao', () {
    test('pesan terbaru, halaman sebelumnya, dan media terlampir', () async {
      final dao = ChatDao(db);
      for (var i = 1; i <= 3; i++) {
        await dao.upsertMessage(message('aaaaaaaaaaaaaaaa:$i'));
      }
      await dao.upsertMessage(message('bbbbbbbbbbbbbbbb:9', groupId: 'g2'));

      final latest = await dao.recentMessages('g1', limit: 2);
      expect(latest.map((m) => m.id), ['aaaaaaaaaaaaaaaa:2', 'aaaaaaaaaaaaaaaa:3']);

      final older = await dao.recentMessages(
        'g1',
        limit: 2,
        beforeUtc: t0.add(const Duration(minutes: 3)),
      );
      expect(older.map((m) => m.id), ['aaaaaaaaaaaaaaaa:1', 'aaaaaaaaaaaaaaaa:2']);

      await dao.upsertMedia(
        MediaCompanion.insert(
          id: 'media_1',
          messageId: const Value('aaaaaaaaaaaaaaaa:1'),
          groupId: const Value('g1'),
          kind: 'image',
          relativePath: 'media/foto.jpg',
          mimeType: 'image/jpeg',
          byteSize: 2048,
          createdAtUtc: t0,
        ),
      );
      final media = await dao.mediaForMessage('aaaaaaaaaaaaaaaa:1');
      expect(media.single.relativePath, 'media/foto.jpg');
      expect(await dao.mediaForMessage('aaaaaaaaaaaaaaaa:2'), isEmpty);
    });

    test('menolak media yang menunjuk pesan tidak ada', () async {
      final dao = ChatDao(db);
      await expectLater(
        dao.upsertMedia(
          MediaCompanion.insert(
            id: 'media_1',
            messageId: const Value('tidak_ada'),
            kind: 'image',
            relativePath: 'media/foto.jpg',
            mimeType: 'image/jpeg',
            byteSize: 1,
            createdAtUtc: t0,
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('TrackingDao', () {
    test('titik diurutkan menurut waktu dan ikut terhapus dengan sesi',
        () async {
      final dao = TrackingDao(db);
      await dao.upsertSession(session('s1'));
      await dao.insertPoint(point('s1', recordedAtUtc: t0.add(const Duration(seconds: 2))));
      await dao.insertPoint(point('s1', recordedAtUtc: t0.add(const Duration(seconds: 1))));

      final points = await dao.points('s1');
      expect(
        points.map((p) => p.recordedAtUtc),
        [t0.add(const Duration(seconds: 1)), t0.add(const Duration(seconds: 2))],
      );

      await dao.deleteSession('s1');
      expect(await dao.sessionById('s1'), isNull);
      expect(await dao.points('s1'), isEmpty);
    });

    test('menolak titik untuk sesi yang tidak ada', () async {
      final dao = TrackingDao(db);
      await expectLater(
        dao.insertPoint(point('tidak_ada')),
        throwsA(isA<Exception>()),
      );
    });

    test('menolak koordinat di luar rentang', () async {
      final dao = TrackingDao(db);
      await dao.upsertSession(session('s1'));
      await expectLater(
        dao.insertPoint(point('s1', lat: 91)),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('SafetyDao', () {
    test('SOS aktif bisa dibatalkan satu arah', () async {
      final dao = SafetyDao(db);
      await dao.upsertSosEvent(sos('s1'));
      await dao.upsertSosEvent(sos('s2', status: 'cancelled'));

      final active = await dao.activeSosEvents();
      expect(active.map((s) => s.id), ['s1']);

      expect(await dao.cancelSosEvent('s1', t0.add(const Duration(minutes: 1))), isTrue);
      expect(await dao.activeSosEvents(), isEmpty);
      final cancelled = await dao.sosEventById('s1');
      expect(cancelled!.status, 'cancelled');
      expect(cancelled.cancelledAtUtc, t0.add(const Duration(minutes: 1)));

      expect(await dao.cancelSosEvent('s1', t0), isFalse);
    });

    test('kontak hanya terlihat oleh pemiliknya', () async {
      final dao = SafetyDao(db);
      await dao.upsertContact(contact('c1'));
      await dao.upsertContact(contact('c2', userId: 'u2'));
      await dao.upsertContact(contact('c3', phone: '+628111111111'));

      expect(
        (await dao.contactsOf('u1')).map((c) => c.id),
        ['c1', 'c3'],
      );
      await dao.deleteContact('c1');
      expect((await dao.contactsOf('u1')).map((c) => c.id), ['c3']);
    });
  });

  group('OutboxDao', () {
    Future<void> enqueue(
      OutboxDao dao,
      String id, {
      int priority = 2,
      DateTime? at,
    }) =>
        dao.enqueue(
          messageId: id,
          packet: Uint8List.fromList([1, 2, 3]),
          priority: priority,
          enqueuedAtUtc: at ?? t0,
          nextAttemptAtUtc: at ?? t0,
          repeatUntilAck: false,
        );

    test('idempoten dan berurutan menurut prioritas lalu usia', () async {
      final dao = OutboxDao(db);
      await enqueue(dao, 'teks:1', at: t0);
      await enqueue(dao, 'sos:2', priority: 0, at: t0.add(const Duration(seconds: 1)));
      await enqueue(dao, 'teks:1', priority: 0, at: t0);

      final due = await dao.due(t0.add(const Duration(minutes: 1)));
      expect(due.map((e) => e.messageId), ['sos:2', 'teks:1']);
      expect(due.last.priority, 2, reason: 'enqueue kedua tidak menimpa');
      expect(await dao.pendingCount(), 2);
    });

    test('attempt menaikkan hitungan dan menunda pengiriman berikutnya',
        () async {
      final dao = OutboxDao(db);
      await enqueue(dao, 'teks:1');

      await dao.recordAttempt('teks:1', t0.add(const Duration(seconds: 10)));
      expect(await dao.due(t0.add(const Duration(seconds: 5))), isEmpty);
      final due = await dao.due(t0.add(const Duration(seconds: 10)));
      expect(due.single.attempts, 1);

      await dao.recordAttempt('tidak_ada', t0);
      expect(await dao.pendingCount(), 1);

      expect(await dao.deleteById('teks:1'), 1);
      expect(await dao.contains('teks:1'), isFalse);
      expect(await dao.pendingCount(), 0);
    });
  });
}
