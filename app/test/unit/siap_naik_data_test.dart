import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/preparation/presentation/siap_naik_page.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';

EmergencyContact _contact({
  required String id,
  required String name,
  required EmergencyContactConsentStatus consent,
}) =>
    EmergencyContact(
      id: id,
      userId: 'user-1',
      name: name,
      phoneE164: '+628123456789',
      consentStatus: consent,
      createdAtUtc: DateTime.utc(2026, 10, 20),
    );

void main() {
  test('tiga chip kesiapan mengikuti keadaan yang diperiksa', () {
    final checks = readinessChecks(
      groupKeyReady: true,
      mapReady: false,
      permissionReady: true,
    );
    expect(
      checks.map((check) => check.label).toList(),
      <String>['Kunci grup', 'Peta', 'Izin'],
    );
    expect(
      checks.map((check) => check.ready).toList(),
      <bool>[true, false, true],
    );
    expect(readyCheckCount(checks), 2);
  });

  test('judul dan persentase kesiapan rombongan', () {
    expect(
      readinessHeadline(readyMembers: 3, totalMembers: 4),
      '3 dari 4 anggota melapor siap',
    );
    expect(
      readinessHeadline(readyMembers: 0, totalMembers: 0),
      'Kesiapan belum bisa dihitung',
    );
    expect(readinessPercent(readyMembers: 3, totalMembers: 4), 75);
    expect(readinessPercent(readyMembers: 1, totalMembers: 3), 33);
    expect(readinessPercent(readyMembers: 0, totalMembers: 0), 0);
  });

  test('kontak darurat memilih yang sudah menyetujui', () {
    final pending = _contact(
      id: 'c1',
      name: 'Ayah',
      consent: EmergencyContactConsentStatus.pending,
    );
    final granted = _contact(
      id: 'c2',
      name: 'Ibu',
      consent: EmergencyContactConsentStatus.granted,
    );
    expect(primaryContact(<EmergencyContact>[pending, granted])?.name, 'Ibu');
    expect(
      contactSubtitle(primaryContact(<EmergencyContact>[pending, granted]), 2),
      'Ibu · sudah menyetujui · +1 lainnya',
    );
    expect(contactSubtitle(pending, 1), 'Ayah · menunggu persetujuan');
    expect(contactSubtitle(null, 0), 'Belum ada kontak darurat');
    expect(
      contactConsentText(EmergencyContactConsentStatus.revoked),
      'persetujuan dicabut',
    );
  });
}
