import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:nama_app/features/chat/domain/chat_message.dart';
import 'package:nama_app/features/chat/domain/media_attachment.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/invitation.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/sos_category.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/infrastructure/database/app_database.dart';
import 'package:nama_app/infrastructure/database/database_connection.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_chat_repository.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_group_repository.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_invitation_repository.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_safety_repository.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_tracking_repository.dart';

final t0 = DateTime.utc(2027, 6, 1, 8);
const idA = 'aaaaaaaaaaaaaaaa';
const groupHex = '1111111111111111';

void main() {
  late AppDatabase db;

  setUp(() => db = openInMemoryAppDatabase());
  tearDown(() => db.close());

  test('DriftGroupRepository memetakan grup dan anggota', () async {
    final repo = DriftGroupRepository(db);
    final group = Group(
      id: 'g1',
      name: 'Sukamaju',
      ownerId: 'owner_01',
      mountain: 'Gede',
      keyVersion: 2,
      createdAtUtc: t0,
    );
    await repo.saveGroup(group);
    await repo.saveMember(
      GroupMember(
        groupId: 'g1',
        userId: 'budi_99',
        username: 'budi_99',
        role: GroupRole.owner,
        joinedAtUtc: t0,
      ),
    );
    await repo.saveMember(
      GroupMember(
        groupId: 'g1',
        userId: 'ani_88',
        username: 'ani_88',
        joinedAtUtc: t0.add(const Duration(minutes: 1)),
      ),
    );

    final stored = await repo.findGroup('g1');
    expect(stored!.name, 'Sukamaju');
    expect(stored.mountain, 'Gede');
    expect(stored.keyVersion, 2);

    final members = await repo.membersOf('g1');
    expect(members.map((m) => m.username), ['budi_99', 'ani_88']);
    expect(members.first.role, GroupRole.owner);
    expect(members.last.role, GroupRole.member);

    final watched = await repo.watchMembers('g1').first;
    expect(watched, hasLength(2));

    await repo.removeMember('g1', 'ani_88');
    expect(await repo.membersOf('g1'), hasLength(1));

    await repo.deleteGroup('g1');
    expect(await repo.findGroup('g1'), isNull);
    expect(await repo.membersOf('g1'), isEmpty);
  });

  test('DriftInvitationRepository menormalkan username dan menyaring kedaluwarsa',
      () async {
    final repo = DriftInvitationRepository(db);
    final invitation = Invitation(
      id: 'i1',
      groupId: 'g1',
      inviterId: 'owner_01',
      inviteeUsername: '  BuDi_99 ',
      createdAtUtc: t0,
      expiresAtUtc: t0.add(const Duration(days: 7)),
    );
    await repo.save(invitation);

    final stored = await repo.findById('i1');
    expect(stored!.inviteeUsername, 'budi_99');
    expect(stored.status, InvitationStatus.pending);
    expect((await repo.pendingFor('BUDI_99', t0)).single.id, 'i1');
    expect(
      await repo.pendingFor('budi_99', t0.add(const Duration(days: 8))),
      isEmpty,
    );

    await repo.save(stored.accept(t0.add(const Duration(days: 1))));
    expect(
      (await repo.findById('i1'))!.status,
      InvitationStatus.accepted,
    );
    expect(await repo.watchAll().first, hasLength(1));
  });

  test('DriftChatRepository menyimpan pesan dan media', () async {
    final repo = DriftChatRepository(db);
    final first = ChatMessage(
      authorId: idA,
      seq: 1,
      groupId: groupHex,
      type: PacketType.text,
      sentAtUtc: t0.add(const Duration(minutes: 1)),
      receivedAtUtc: t0,
      payload: Uint8List.fromList([1, 2, 3]),
      isOutgoing: true,
    );
    final second = ChatMessage(
      authorId: idA,
      seq: 2,
      groupId: groupHex,
      type: PacketType.location,
      sentAtUtc: t0.add(const Duration(minutes: 2)),
      receivedAtUtc: t0.add(const Duration(minutes: 2)),
      payload: Uint8List.fromList([4, 5, 6]),
    );
    await repo.saveMessage(first);
    await repo.saveMessage(second);

    final found = await repo.findMessage(first.messageId);
    expect(found!.type, PacketType.text);
    expect(found.isOutgoing, isTrue);
    expect(found.payload, [1, 2, 3]);

    final recent = await repo.recentMessages(groupHex);
    expect(recent.map((m) => m.messageId), [first.messageId, second.messageId]);
    expect(
      (await repo.recentMessages(groupHex, limit: 1)).single.messageId,
      second.messageId,
    );
    expect(
      (await repo.recentMessages(groupHex, beforeUtc: second.sentAtUtc))
          .single
          .messageId,
      first.messageId,
    );
    expect(await repo.watchMessages(groupHex).first, hasLength(2));

    await repo.saveMedia(
      MediaAttachment(
        id: 'media_1',
        messageId: first.messageId,
        groupId: groupHex,
        kind: MediaKind.image,
        relativePath: 'media/foto.jpg',
        mimeType: 'image/jpeg',
        byteSize: 2048,
        createdAtUtc: t0,
      ),
    );
    final media = await repo.mediaForMessage(first.messageId);
    expect(media.single.kind, MediaKind.image);
    expect(media.single.byteSize, 2048);
    expect(await repo.mediaForMessage(second.messageId), isEmpty);
  });

  test('DriftTrackingRepository menyimpan sesi dan titik', () async {
    final repo = DriftTrackingRepository(db);
    final session = TrackingSession(
      id: 's1',
      startedAtUtc: t0,
      endedAtUtc: t0.add(const Duration(hours: 2)),
      groupId: 'g1',
      trailId: 'gede',
      distanceM: 1234.5,
      movingSeconds: 3600,
      elevationGainM: 120,
      elevationLossM: 80,
      status: TrackingSessionStatus.completed,
    );
    await repo.saveSession(session);
    await repo.addPoint(
      's1',
      TrackPoint(
        lat: -6.9,
        lon: 107.6,
        timestampUtc: t0.add(const Duration(seconds: 2)),
        accuracyM: 5,
        altitudeM: 1500,
        speedMps: 1.2,
      ),
    );
    await repo.addPoint(
      's1',
      TrackPoint(
        lat: -6.91,
        lon: 107.61,
        timestampUtc: t0.add(const Duration(seconds: 1)),
        accuracyM: 4,
      ),
    );

    final stored = await repo.findSession('s1');
    expect(stored!.trailId, 'gede');
    expect(stored.distanceM, 1234.5);
    expect(stored.movingSeconds, 3600);
    expect(stored.status, TrackingSessionStatus.completed);

    final points = await repo.points('s1');
    expect(points, hasLength(2));
    expect(points.first.timestampUtc, t0.add(const Duration(seconds: 1)));
    expect(points.last.altitudeM, 1500);
    expect(points.last.speedMps, 1.2);

    final latest = await repo.latestPoint('s1');
    expect(latest!.timestampUtc, t0.add(const Duration(seconds: 2)));
    expect(latest.lat, -6.9);
    expect(await repo.latestPoint('sesi_lain'), isNull);

    expect(await repo.watchSessions().first, hasLength(1));

    await repo.deleteSession('s1');
    expect(await repo.findSession('s1'), isNull);
    expect(await repo.points('s1'), isEmpty);
  });

  test('DriftSafetyRepository menyimpan SOS dan membatalkannya', () async {
    final repo = DriftSafetyRepository(db);
    final event = SosEvent(
      id: 'sos_1',
      authorId: idA,
      category: SosCategory.injury,
      lat: -6.9,
      lon: 107.6,
      accuracyM: 10,
      batteryPercent: 42,
      createdAtUtc: t0,
      receivedAtUtc: t0,
    );
    await repo.saveSosEvent(event);

    final stored = await repo.findSosEvent('sos_1');
    expect(stored!.category, SosCategory.injury);
    expect(stored.accuracyM, 10);
    expect(stored.status, SosEventStatus.active);
    expect((await repo.activeSosEvents()).single.id, 'sos_1');
    expect(await repo.watchSosEvents().first, hasLength(1));

    final cancelledAt = t0.add(const Duration(minutes: 5));
    expect(await repo.cancelSosEvent('sos_1', cancelledAt), isTrue);
    final cancelled = await repo.findSosEvent('sos_1');
    expect(cancelled!.status, SosEventStatus.cancelled);
    expect(cancelled.cancelledAtUtc, cancelledAt);
    expect(await repo.activeSosEvents(), isEmpty);
    expect(await repo.cancelSosEvent('sos_1', cancelledAt), isFalse);
  });

  test('DriftSafetyRepository menyimpan kontak darurat dan persetujuannya',
      () async {
    final repo = DriftSafetyRepository(db);
    expect(
      () => EmergencyContact(
        id: 'c0',
        userId: 'u1',
        name: 'Salah',
        phoneE164: '08123456789',
        createdAtUtc: t0,
      ),
      throwsArgumentError,
    );

    final contact = EmergencyContact(
      id: 'c1',
      userId: 'u1',
      name: 'Ibu',
      phoneE164: '+628123456789',
      channel: EmergencyContactChannel.whatsapp,
      createdAtUtc: t0,
    );
    await repo.saveContact(contact);
    await repo.saveContact(
      EmergencyContact(
        id: 'c2',
        userId: 'u2',
        name: 'Ayah',
        phoneE164: '+628111111111',
        createdAtUtc: t0,
      ),
    );

    final contacts = await repo.contactsOf('u1');
    expect(contacts.single.channel, EmergencyContactChannel.whatsapp);
    expect(contacts.single.consentStatus, EmergencyContactConsentStatus.pending);

    await repo.saveContact(
      EmergencyContact(
        id: 'c1',
        userId: 'u1',
        name: 'Ibu',
        phoneE164: '+628123456789',
        channel: EmergencyContactChannel.whatsapp,
        consentStatus: EmergencyContactConsentStatus.granted,
        consentAtUtc: t0.add(const Duration(hours: 1)),
        createdAtUtc: t0,
      ),
    );
    final granted = await repo.contactsOf('u1');
    expect(granted.single.consentStatus, EmergencyContactConsentStatus.granted);
    expect(granted.single.consentAtUtc, t0.add(const Duration(hours: 1)));
    expect(await repo.watchContacts('u1').first, hasLength(1));

    await repo.deleteContact('c1');
    expect(await repo.contactsOf('u1'), isEmpty);
  });
}
