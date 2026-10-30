import 'invitation.dart';

abstract interface class InvitationRepository {
  Future<void> save(Invitation invitation);
  Future<Invitation?> findById(String id);

  /// Undangan yang masih pending DAN belum kedaluwarsa pada [nowUtc].
  Future<List<Invitation>> pendingFor(
    String inviteeUsername,
    DateTime nowUtc,
  );

  Stream<List<Invitation>> watchAll();
}
