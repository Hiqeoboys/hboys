import 'dart:async';

import 'package:drift/drift.dart';

import '../../../features/groups/domain/invitation.dart';
import '../../../features/groups/domain/invitation_repository.dart';
import '../../../features/groups/domain/username.dart';
import '../app_database.dart';
import '../daos/invitation_dao.dart';

class DriftInvitationRepository implements InvitationRepository {
  DriftInvitationRepository(AppDatabase db) : _dao = InvitationDao(db);

  final InvitationDao _dao;

  @override
  Future<void> save(Invitation invitation) => _dao.upsert(
        InvitationsCompanion.insert(
          id: invitation.id,
          groupId: invitation.groupId,
          inviterId: invitation.inviterId,
          inviteeUsername: normalizeUsername(invitation.inviteeUsername),
          status: Value(invitation.status.name),
          createdAtUtc: invitation.createdAtUtc.toUtc(),
          expiresAtUtc: invitation.expiresAtUtc.toUtc(),
        ),
      );

  @override
  Future<Invitation?> findById(String id) async {
    final row = await _dao.byId(id);
    return row == null ? null : _toInvitation(row);
  }

  @override
  Future<List<Invitation>> pendingFor(
    String inviteeUsername,
    DateTime nowUtc,
  ) async {
    final rows = await _dao.pendingFor(
      normalizeUsername(inviteeUsername),
      nowUtc.toUtc(),
    );
    return rows.map(_toInvitation).toList(growable: false);
  }

  @override
  Stream<List<Invitation>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map(_toInvitation).toList());

  Invitation _toInvitation(InvitationRow row) => Invitation(
        id: row.id,
        groupId: row.groupId,
        inviterId: row.inviterId,
        inviteeUsername: row.inviteeUsername,
        status: _statusFromDb(row.status),
        createdAtUtc: row.createdAtUtc,
        expiresAtUtc: row.expiresAtUtc,
      );

  InvitationStatus _statusFromDb(String value) => switch (value) {
        'pending' => InvitationStatus.pending,
        'accepted' => InvitationStatus.accepted,
        'rejected' => InvitationStatus.rejected,
        'expired' => InvitationStatus.expired,
        'cancelled' => InvitationStatus.cancelled,
        _ => throw StateError('Status undangan tidak dikenal: $value'),
      };
}
