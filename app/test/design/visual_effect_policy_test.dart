import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

void main() {
  group('VisualEffectPolicy', () {
    VisualEffectPolicy policy({
      PowerProfile power = PowerProfile.normal,
      bool reduceMotion = false,
      DeviceTier tier = DeviceTier.capable,
    }) =>
        VisualEffectPolicy(
          powerProfile: power,
          reduceMotion: reduceMotion,
          deviceTier: tier,
        );

    test('perangkat mampu dan profil normal menyalakan kaca dan gooey', () {
      expect(policy().glassBlur, isTrue);
      expect(policy().gooey, isTrue);
      expect(VisualEffectPolicy.full.glassBlur, isTrue);
      expect(VisualEffectPolicy.full.gooey, isTrue);
    });

    test('profil daya Hemat dan Kritis mematikan kaca dan gooey', () {
      for (final power in <PowerProfile>[
        PowerProfile.saver,
        PowerProfile.critical,
      ]) {
        expect(policy(power: power).glassBlur, isFalse, reason: '$power');
        expect(policy(power: power).gooey, isFalse, reason: '$power');
      }
    });

    test('perangkat lemah mematikan kaca dan gooey', () {
      expect(policy(tier: DeviceTier.lowEnd).glassBlur, isFalse);
      expect(policy(tier: DeviceTier.lowEnd).gooey, isFalse);
    });

    test('kurangi animasi hanya mematikan gooey, kaca tetap jalan', () {
      expect(policy(reduceMotion: true).glassBlur, isTrue);
      expect(policy(reduceMotion: true).gooey, isFalse);
    });

    test('kesetaraan mengikuti ketiga masukan', () {
      expect(policy(), VisualEffectPolicy.full);
      expect(policy().hashCode, VisualEffectPolicy.full.hashCode);
      expect(
        policy(reduceMotion: true),
        isNot(VisualEffectPolicy.full),
      );
      expect(
        policy(power: PowerProfile.saver),
        isNot(VisualEffectPolicy.full),
      );
    });
  });

  group('probeDeviceTier', () {
    const int duaGigaKb = 2 * 1024 * 1024;
    const int empatGigaKb = 4 * 1024 * 1024;

    test('inti sangat sedikit digolongkan perangkat lemah', () {
      expect(
        VisualEffectPolicy.probeDeviceTier(processorCount: 2),
        DeviceTier.lowEnd,
      );
    });

    test('RAM di bawah 3 GB digolongkan perangkat lemah', () {
      expect(
        VisualEffectPolicy.probeDeviceTier(
          processorCount: 4,
          totalMemoryKb: duaGigaKb,
        ),
        DeviceTier.lowEnd,
      );
    });

    test('empat inti dengan RAM cukup digolongkan mampu', () {
      expect(
        VisualEffectPolicy.probeDeviceTier(
          processorCount: 4,
          totalMemoryKb: empatGigaKb,
        ),
        DeviceTier.capable,
      );
      expect(
        VisualEffectPolicy.probeDeviceTier(processorCount: 8),
        DeviceTier.capable,
      );
    });
  });
}
