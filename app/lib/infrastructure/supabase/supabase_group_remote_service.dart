import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/groups/domain/group.dart';
import '../../features/groups/domain/group_remote_service.dart';
import '../../features/groups/domain/invitation.dart';

class SupabaseGroupRemoteService implements GroupRemoteService {
  SupabaseGroupRemoteService(this._client);

  final SupabaseClient _client;

  @override
  Future<List<RemoteGroup>> myGroups() async {
    try {
      final data = await _client.rpc('my_groups');
      return _rows(data).map(_remoteGroupFromMap).toList(growable: false);
    } on PostgrestException catch (error) {
      throw _groupError(error);
    }
  }

  @override
  Future<RemoteGroup> createGroup({
    required String name,
    String? mountain,
  }) async {
    try {
      final data = await _client.rpc(
        'create_group',
        params: {
          'p_name': name.trim(),
          'p_mountain': mountain?.trim().isEmpty ?? true ? null : mountain!.trim(),
        },
      );
      final rows = _rows(data);
      if (rows.isEmpty) {
        throw const GroupOperationException(
          'GROUP_EMPTY_RESPONSE',
          'Server tidak mengembalikan grup yang dibuat.',
        );
      }
      return _remoteGroupFromMap(rows.first);
    } on PostgrestException catch (error) {
      throw _groupError(error);
    }
  }

  @override
  Future<void> inviteByUsername({
    required String groupId,
    required String username,
  }) async {
    try {
      await _client.rpc(
        'invite_user',
        params: {
          'p_group_id': groupId,
          'p_username': username,
        },
      );
    } on PostgrestException catch (error) {
      throw _groupError(error);
    }
  }

  @override
  Future<List<IncomingInvitation>> pendingInvitations(
    DateTime nowUtc,
  ) async {
    try {
      final data = await _client.rpc('my_pending_invitations');
      return _rows(data)
          .map((row) => _invitationFromMap(row, nowUtc))
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw _groupError(error);
    }
  }

  @override
  Future<InvitationStatus> respondToInvitation({
    required String invitationId,
    required bool accept,
    required DateTime nowUtc,
  }) async {
    try {
      final data = await _client.rpc(
        'respond_invitation',
        params: {
          'p_invitation_id': invitationId,
          'p_accept': accept,
        },
      );
      return _statusFromValue(data, nowUtc);
    } on PostgrestException catch (error) {
      throw _groupError(error);
    }
  }

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async {
    try {
      final data = await _client.rpc(
        'group_members_directory',
        params: {'p_group_id': groupId},
      );
      return _rows(data).map(_memberFromMap).toList(growable: false);
    } on PostgrestException catch (error) {
      throw _groupError(error);
    }
  }

  @override
  Future<void> publishWrappedKeys({
    required String groupId,
    required int keyVersion,
    required Map<String, String> wrappedKeys,
  }) async {
    try {
      await _client.rpc(
        'publish_group_keys',
        params: {
          'p_group_id': groupId,
          'p_key_version': keyVersion,
          'p_wrapped_keys': wrappedKeys.entries
              .map(
                (entry) => {
                  'user_id': entry.key,
                  'wrapped_key': entry.value,
                },
              )
              .toList(growable: false),
        },
      );
    } on PostgrestException catch (error) {
      throw _groupError(error);
    }
  }

  @override
  Future<String?> fetchOwnWrappedKey({
    required String groupId,
    required int keyVersion,
  }) async {
    try {
      final row = await _client
          .from('group_key_blobs')
          .select('wrapped_key')
          .eq('group_id', groupId)
          .eq('key_version', keyVersion)
          .maybeSingle();
      return row?['wrapped_key'] as String?;
    } on PostgrestException catch (error) {
      throw _groupError(error);
    }
  }

  @override
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    try {
      await _client.rpc(
        'remove_group_member',
        params: {
          'p_group_id': groupId,
          'p_user_id': userId,
        },
      );
    } on PostgrestException catch (error) {
      throw _groupError(error);
    }
  }

  RemoteGroup _remoteGroupFromMap(Map<String, dynamic> row) => RemoteGroup(
        group: Group(
          id: row['id'] as String,
          name: row['name'] as String,
          ownerId: row['owner_id'] as String,
          mountain: row['mountain'] as String?,
          keyVersion: (row['key_version'] as num).toInt(),
          createdAtUtc: _utc(row['created_at']),
        ),
        role: _role(row['role'] as String?),
      );

  IncomingInvitation _invitationFromMap(
    Map<String, dynamic> row,
    DateTime nowUtc,
  ) {
    return IncomingInvitation(
      id: row['id'] as String,
      groupId: row['group_id'] as String,
      groupName: row['group_name'] as String,
      inviterUsername: row['inviter_username'] as String,
      createdAtUtc: _utc(row['created_at']),
      expiresAtUtc: _utc(row['expires_at']),
    );
  }

  MemberDirectoryEntry _memberFromMap(Map<String, dynamic> row) =>
      MemberDirectoryEntry(
        userId: row['user_id'] as String,
        username: row['username'] as String,
        role: _role(row['role'] as String?),
        publicKeyBase64: row['public_key'] as String,
        joinedAtUtc: _utc(row['joined_at']),
      );

  GroupRole _role(String? value) => switch (value) {
        'owner' => GroupRole.owner,
        'member' => GroupRole.member,
        _ => throw const GroupOperationException(
            'ROLE_UNKNOWN',
            'Peran anggota grup tidak dikenal.',
          ),
      };

  InvitationStatus _statusFromValue(dynamic data, DateTime nowUtc) {
    final value = switch (data) {
      String status => status,
      List() when data.isNotEmpty => switch (data.first) {
          String status => status,
          Map() => data.first['status'] as String?,
          _ => null,
        },
      Map() => data['status'] as String?,
      _ => null,
    };
    return switch (value) {
      'accepted' => InvitationStatus.accepted,
      'rejected' => InvitationStatus.rejected,
      'expired' => InvitationStatus.expired,
      'pending' => InvitationStatus.pending,
      'cancelled' => InvitationStatus.cancelled,
      _ => throw GroupOperationException(
          'INVITATION_STATUS_UNKNOWN',
          'Status undangan tidak dikenal: $value',
        ),
    };
  }

  DateTime _utc(dynamic value) => DateTime.parse(value as String).toUtc();

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    if (data is Map) {
      return [Map<String, dynamic>.from(data)];
    }
    return const [];
  }

  GroupOperationException _groupError(PostgrestException error) {
    final text = '${error.message} ${error.details ?? ''}';
    if (text.contains('AUTH_REQUIRED')) {
      return const GroupOperationException(
        'AUTH_REQUIRED',
        'Sesi login sudah berakhir. Masuk kembali.',
      );
    }
    if (text.contains('PROFILE_REQUIRED')) {
      return const GroupOperationException(
        'PROFILE_REQUIRED',
        'Daftarkan username terlebih dahulu.',
      );
    }
    if (text.contains('OWNER_REQUIRED')) {
      return const GroupOperationException(
        'OWNER_REQUIRED',
        'Hanya pemilik grup yang dapat melakukan tindakan ini.',
      );
    }
    if (text.contains('NOT_MEMBER')) {
      return const GroupOperationException(
        'NOT_MEMBER',
        'Anda bukan anggota grup ini.',
      );
    }
    if (text.contains('USER_NOT_FOUND')) {
      return const GroupOperationException(
        'USER_NOT_FOUND',
        'Username tidak ditemukan. Pencocokan harus persis.',
      );
    }
    if (text.contains('ALREADY_MEMBER')) {
      return const GroupOperationException(
        'ALREADY_MEMBER',
        'Pengguna sudah menjadi anggota grup.',
      );
    }
    if (text.contains('INVITE_PENDING')) {
      return const GroupOperationException(
        'INVITE_PENDING',
        'Sudah ada undangan pending untuk pengguna ini.',
      );
    }
    if (text.contains('NOT_INVITEE')) {
      return const GroupOperationException(
        'NOT_INVITEE',
        'Undangan ini bukan untuk akun Anda.',
      );
    }
    if (text.contains('INVITATION_NOT_PENDING')) {
      return const GroupOperationException(
        'INVITATION_NOT_PENDING',
        'Undangan sudah tidak pending.',
      );
    }
    if (text.contains('INVITATION_NOT_FOUND')) {
      return const GroupOperationException(
        'INVITATION_NOT_FOUND',
        'Undangan tidak ditemukan.',
      );
    }
    if (text.contains('RECIPIENT_NOT_MEMBER') ||
        text.contains('MISSING_MEMBER_KEY')) {
      return const GroupOperationException(
        'KEY_RECIPIENTS_INVALID',
        'Daftar penerima kunci tidak cocok dengan anggota grup.',
      );
    }
    if (text.contains('KEY_VERSION_INVALID')) {
      return const GroupOperationException(
        'KEY_VERSION_INVALID',
        'Versi kunci tidak sesuai dengan versi grup.',
      );
    }
    if (text.contains('GROUP_NOT_FOUND')) {
      return const GroupOperationException(
        'GROUP_NOT_FOUND',
        'Grup tidak ditemukan.',
      );
    }
    if (text.contains('GROUP_EMPTY_RESPONSE')) {
      return const GroupOperationException(
        'GROUP_EMPTY_RESPONSE',
        'Server tidak mengembalikan grup.',
      );
    }
    return const GroupOperationException(
      'GROUP_SERVER_ERROR',
      'Permintaan grup ditolak server. Coba lagi.',
    );
  }
}
