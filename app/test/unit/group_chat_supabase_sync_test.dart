import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:nama_app/features/chat/domain/chat_message.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';

void main() {
  group('GroupMessageRecord & client_msg_id', () {
    const groupUuid = '11111111-2222-4333-8444-555555555555';
    const userUuid = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

    test('deterministicClientMsgId menghasilkan UUID kanonik yang identik lintas perangkat', () {
      final sentAt = DateTime.utc(2026, 11, 19, 1, 15, 30, 123);
      final idDeviceA = deterministicClientMsgId(
        groupId: groupUuid,
        authorId: userUuid,
        seq: 7,
        sentAtUtc: sentAt,
      );
      final idDeviceB = deterministicClientMsgId(
        groupId: groupUuid,
        authorId: userUuid,
        seq: 7,
        sentAtUtc: sentAt.toLocal(),
      );
      final idDifferentSeq = deterministicClientMsgId(
        groupId: groupUuid,
        authorId: userUuid,
        seq: 8,
        sentAtUtc: sentAt,
      );

      expect(isValidUuid(idDeviceA), isTrue);
      expect(idDeviceA, equals(idDeviceB));
      expect(idDeviceA, isNot(equals(idDifferentSeq)));
    });

    test('serialisasi dan deserialisasi pesan teks relay BLE Mesh cocok dengan skema Supabase', () {
      final clientCreated = DateTime.utc(2026, 11, 19, 2, 0, 5);
      final localMsg = ChatMessage(
        authorId: userUuid,
        seq: 3,
        groupId: groupUuid,
        type: PacketType.text,
        sentAtUtc: clientCreated,
        receivedAtUtc: clientCreated,
        payload: Uint8List.fromList(utf8.encode('Aman di Pos 3, lanjut puncak.')),
        isOutgoing: true,
      );

      final record = GroupMessageRecord.fromChatMessage(
        localMsg,
        senderName: 'Dimas',
        keyVersion: 2,
        originTransport: ChatTransportOrigin.bleMesh,
      );

      final insertMap = record.toSupabaseInsertMap();
      expect(isValidUuid(insertMap['client_msg_id'] as String?), isTrue);
      expect(insertMap['group_id'], groupUuid);
      expect(insertMap['sender_id'], userUuid);
      expect(insertMap['sender_name'], 'Dimas');
      expect(insertMap['message_type'], 'text');
      expect(insertMap['content'], 'Aman di Pos 3, lanjut puncak.');
      expect(insertMap['audio_url'], isNull);
      expect(insertMap['audio_duration_sec'], isNull);
      expect(insertMap['key_version'], 2);
      expect(insertMap['origin_transport'], 'ble_mesh');
      expect(insertMap['client_created_at'], clientCreated.toIso8601String());

      final restored = GroupMessageRecord.fromSupabaseMap(<String, dynamic>{
        'id': '99999999-8888-4777-8666-555555555555',
        ...insertMap,
        'created_at': DateTime.utc(2026, 11, 19, 2, 10, 0).toIso8601String(),
      });

      expect(restored.clientMsgId, record.clientMsgId);
      expect(restored.originTransport, ChatTransportOrigin.bleMesh);
      expect(restored.keyVersion, 2);
      expect(restored.clientCreatedAtUtc, clientCreated);

      final chatMsg = restored.toChatMessage(currentUserId: userUuid);
      expect(chatMsg.type, PacketType.text);
      expect(chatMsg.isOutgoing, isTrue);
      expect(utf8.decode(chatMsg.payload), 'Aman di Pos 3, lanjut puncak.');
    });

    test('serialisasi pesan suara (audio .m4a) menyimpan audio_url, durasi, dan Wi-Fi Direct', () {
      final clientCreated = DateTime.utc(2026, 11, 19, 3, 5, 12);
      final clientId = deterministicClientMsgId(
        groupId: groupUuid,
        authorId: userUuid,
        seq: 11,
        sentAtUtc: clientCreated,
      );
      final voice = VoiceNoteData(
        durationSeconds: 18,
        peaks: VoiceNoteData.defaultPeaks,
        clientMsgId: clientId,
      );
      final msg = ChatMessage(
        authorId: userUuid,
        seq: 11,
        groupId: groupUuid,
        type: PacketType.voiceFragment,
        sentAtUtc: clientCreated,
        receivedAtUtc: clientCreated,
        payload: voice.toBytes(),
        isOutgoing: false,
      );

      final record = GroupMessageRecord.fromChatMessage(
        msg,
        senderName: 'Sari',
        keyVersion: 1,
        originTransport: ChatTransportOrigin.wifiDirect,
        audioUrl: '$groupUuid/$clientId.m4a',
      );

      final insertMap = record.toSupabaseInsertMap();
      expect(insertMap['message_type'], 'audio');
      expect(insertMap['audio_url'], '$groupUuid/$clientId.m4a');
      expect(insertMap['audio_duration_sec'], 18);
      expect(insertMap['origin_transport'], 'wifi_direct');

      final roundtrip = GroupMessageRecord.fromSupabaseMap(insertMap)
          .toChatMessage(currentUserId: 'other-user');
      expect(roundtrip.type, PacketType.voiceFragment);
      expect(roundtrip.isOutgoing, isFalse);
      final decodedVoice = VoiceNoteData.fromBytes(roundtrip.payload);
      expect(decodedVoice.durationSeconds, 18);
      expect(decodedVoice.audioUrl, '$groupUuid/$clientId.m4a');
      expect(decodedVoice.clientMsgId, clientId);
    });
  });

  group('MemberLastLocation Supabase mapping', () {
    const groupUuid = '11111111-2222-4333-8444-555555555555';
    const userUuid = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    const peerUuid = 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff';

    test('toSupabaseUpsertMap & fromSupabaseMap memetakan elevasi, baterai, transport, dan recorded_at', () {
      final recordedAt = DateTime.utc(2026, 11, 19, 4, 30, 0);
      final loc = MemberLastLocation(
        groupId: groupUuid,
        userId: userUuid,
        displayName: 'Dimas',
        initial: 'D',
        hasSignal: true,
        lat: -7.4541,
        lon: 110.4402,
        altitudeMdpl: 2840,
        batteryPercent: 64,
        sourceTransport: ChatTransportOrigin.bleMesh,
        recordedAtUtc: recordedAt,
        updatedAtUtc: recordedAt,
      );

      final map = loc.toSupabaseUpsertMap(groupId: groupUuid);
      expect(map['group_id'], groupUuid);
      expect(map['user_id'], userUuid);
      expect(map['display_name'], 'Dimas');
      expect(map['latitude'], -7.4541);
      expect(map['longitude'], 110.4402);
      expect(map['altitude_mdpl'], 2840);
      expect(map['battery_percent'], 64);
      expect(map['source_transport'], 'ble_mesh');
      expect(map['recorded_at'], recordedAt.toIso8601String());

      final decodedSelf = MemberLastLocation.fromSupabaseMap(
        map,
        currentUserId: userUuid,
      );
      expect(decodedSelf.displayName, 'Kamu');
      expect(decodedSelf.altitudeMdpl, 2840);
      expect(decodedSelf.batteryPercent, 64);
      expect(decodedSelf.sourceTransport, ChatTransportOrigin.bleMesh);

      final decodedPeer = MemberLastLocation.fromSupabaseMap(
        <String, dynamic>{...map, 'user_id': peerUuid, 'display_name': 'Bayu'},
        currentUserId: userUuid,
      );
      expect(decodedPeer.displayName, 'Bayu');
      expect(decodedPeer.initial, 'B');
    });
  });
}
