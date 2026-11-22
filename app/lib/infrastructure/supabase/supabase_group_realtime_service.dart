import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/groups/domain/group_remote_service.dart';

/// Langganan Supabase Realtime untuk perubahan keanggotaan grup (`group_members`),
/// undangan masuk (`invitations`), dan publikasi kunci grup (`group_key_blobs`).
class SupabaseGroupRealtimeService implements GroupRealtimeService {
  SupabaseGroupRealtimeService(this._client);

  final SupabaseClient _client;
  RealtimeChannel? _channel;
  StreamController<GroupRealtimeEvent>? _controller;

  @override
  Stream<GroupRealtimeEvent> subscribe({
    required String userId,
    required List<String> groupIds,
  }) {
    unawaited(unsubscribe());
    final controller = StreamController<GroupRealtimeEvent>.broadcast();
    _controller = controller;

    final channel = _client.channel('hiqeo-account-$userId');
    _channel = channel;

    // 1. Perubahan anggota grup (join / leave / remove) -> update jumlah anggota realtime
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'group_members',
      callback: (payload) {
        if (controller.isClosed) return;
        final gid = (payload.newRecord['group_id'] ??
            payload.oldRecord['group_id']) as String?;
        final uid = (payload.newRecord['user_id'] ??
            payload.oldRecord['user_id']) as String?;
        controller.add(
          GroupRealtimeEvent(
            kind: GroupRealtimeEventKind.membershipChanged,
            groupId: gid,
            userId: uid,
          ),
        );
      },
    );

    // 2. Undangan masuk baru / berubah status untuk akun saat ini -> banner in-app + badge
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'invitations',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'invitee_id',
        value: userId,
      ),
      callback: (payload) {
        if (controller.isClosed) return;
        final invId =
            (payload.newRecord['id'] ?? payload.oldRecord['id']) as String?;
        final gid = (payload.newRecord['group_id'] ??
            payload.oldRecord['group_id']) as String?;
        controller.add(
          GroupRealtimeEvent(
            kind: GroupRealtimeEventKind.invitationChanged,
            groupId: gid,
            userId: userId,
            invitationId: invId,
          ),
        );
      },
    );

    // 3. Kunci grup terbungkus baru diterbitkan oleh pemilik untuk akun ini
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'group_key_blobs',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        if (controller.isClosed) return;
        final gid = (payload.newRecord['group_id'] ??
            payload.oldRecord['group_id']) as String?;
        final rawVer = payload.newRecord['key_version'];
        final keyVersion =
            rawVer is num ? rawVer.toInt() : int.tryParse('$rawVer');
        final wrappedKeyBase64 = payload.newRecord['wrapped_key'] as String?;
        controller.add(
          GroupRealtimeEvent(
            kind: GroupRealtimeEventKind.groupKeyPublished,
            groupId: gid,
            userId: userId,
            keyVersion: keyVersion,
            wrappedKeyBase64: wrappedKeyBase64,
          ),
        );
      },
    );

    channel.subscribe();
    return controller.stream;
  }

  @override
  Future<void> unsubscribe() async {
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await _client.removeChannel(ch);
      } catch (_) {}
    }
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null && !ctrl.isClosed) {
      await ctrl.close();
    }
  }
}
