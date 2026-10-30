import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

void main() {
  test('turun bertahap dengan histeresis', () {
    final m = PowerProfileManager();
    expect(m.update(50), PowerProfile.normal);
    expect(m.update(39), PowerProfile.saver);
    expect(m.update(41), PowerProfile.saver); // belum cukup naik
    expect(m.update(43), PowerProfile.normal);
    expect(m.update(19), PowerProfile.critical);
    expect(m.update(22), PowerProfile.critical);
    expect(m.update(23), PowerProfile.saver);
  });

  test('mengisi daya mengembalikan ke normal', () {
    final m = PowerProfileManager()..update(10);
    expect(m.profile, PowerProfile.critical);
    expect(m.update(10, charging: true), PowerProfile.normal);
  });

  test('profil kritis mematikan media', () {
    final c = PowerProfileConfig.of(PowerProfile.critical);
    expect(c.allowVoice, isFalse);
    expect(c.allowImages, isFalse);
  });
}
