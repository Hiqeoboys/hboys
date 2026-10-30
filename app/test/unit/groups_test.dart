import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/groups/domain/invitation.dart';
import 'package:nama_app/features/groups/domain/username.dart';

final t0 = DateTime.utc(2027, 5, 1);

Invitation invite() => Invitation(
      id: 'i1',
      groupId: 'g1',
      inviterId: 'u1',
      inviteeUsername: 'budi_99',
      createdAtUtc: t0,
      expiresAtUtc: t0.add(const Duration(days: 7)),
    );

void main() {
  group('Invitation', () {
    test('diterima sebelum kedaluwarsa', () {
      final accepted = invite().accept(t0.add(const Duration(days: 1)));
      expect(accepted.status, InvitationStatus.accepted);
    });

    test('ditolak', () {
      expect(invite().reject(t0).status, InvitationStatus.rejected);
    });

    test('tidak bisa diterima setelah kedaluwarsa', () {
      final late = t0.add(const Duration(days: 8));
      expect(invite().effectiveStatus(late), InvitationStatus.expired);
      expect(() => invite().accept(late), throwsStateError);
    });

    test('tidak bisa diterima dua kali', () {
      final accepted = invite().accept(t0);
      expect(() => accepted.accept(t0), throwsStateError);
      expect(() => accepted.reject(t0), throwsStateError);
    });

    test('pengundang bisa membatalkan selama pending', () {
      expect(invite().cancel(t0).status, InvitationStatus.cancelled);
    });
  });

  group('username', () {
    test('normalisasi trim dan huruf kecil', () {
      expect(normalizeUsername('  BudI_99 '), 'budi_99');
    });

    test('validasi', () {
      expect(isValidUsername('budi_99'), isTrue);
      expect(isValidUsername('ab'), isFalse);
      expect(isValidUsername('budi 99'), isFalse);
      expect(isValidUsername('a' * 21), isFalse);
    });
  });
}
