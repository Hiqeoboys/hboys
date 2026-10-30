enum InvitationStatus { pending, accepted, rejected, expired, cancelled }

/// Undangan grup. Anggota baru HANYA masuk setelah undangan diterima; kunci grup
/// baru dibagikan setelah itu.
class Invitation {
  const Invitation({
    required this.id,
    required this.groupId,
    required this.inviterId,
    required this.inviteeUsername,
    required this.createdAtUtc,
    required this.expiresAtUtc,
    this.status = InvitationStatus.pending,
  });

  final String id;
  final String groupId;
  final String inviterId;
  final String inviteeUsername;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;
  final InvitationStatus status;

  /// Status efektif: undangan pending yang sudah lewat masa berlaku dianggap expired.
  InvitationStatus effectiveStatus(DateTime nowUtc) =>
      status == InvitationStatus.pending && !nowUtc.isBefore(expiresAtUtc)
          ? InvitationStatus.expired
          : status;

  Invitation accept(DateTime nowUtc) => _to(nowUtc, InvitationStatus.accepted);
  Invitation reject(DateTime nowUtc) => _to(nowUtc, InvitationStatus.rejected);
  Invitation cancel(DateTime nowUtc) => _to(nowUtc, InvitationStatus.cancelled);

  Invitation _to(DateTime nowUtc, InvitationStatus next) {
    final current = effectiveStatus(nowUtc);
    if (current != InvitationStatus.pending) {
      throw StateError('Undangan tidak bisa diubah: status $current');
    }
    return Invitation(
      id: id,
      groupId: groupId,
      inviterId: inviterId,
      inviteeUsername: inviteeUsername,
      createdAtUtc: createdAtUtc,
      expiresAtUtc: expiresAtUtc,
      status: next,
    );
  }
}
