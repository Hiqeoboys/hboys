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

    test('profil daya Hemat tetap menyalakan blur kaca dan mematikan gooey; Kritis mematikan keduanya', () {
      expect(policy(power: PowerProfile.saver).glassBlur, isTrue);
      expect(policy(power: PowerProfile.saver).gooey, isFalse);

      expect(policy(power: PowerProfile.critical).glassBlur, isFalse);
      expect(policy(power: PowerProfile.critical).gooey, isFalse);
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
    const int satuSetengahGigaKb = 1536 * 1024;
    const int tigaGigaMeasuredKb = 2800 * 1024;
    const int empatGigaKb = 4 * 1024 * 1024;

    test('inti sangat sedikit digolongkan perangkat lemah', () {
      expect(
        VisualEffectPolicy.probeDeviceTier(processorCount: 2),
        DeviceTier.lowEnd,
      );
    });

    test('RAM di bawah 2 GB digolongkan perangkat lemah', () {
      expect(
        VisualEffectPolicy.probeDeviceTier(
          processorCount: 4,
          totalMemoryKb: satuSetengahGigaKb,
        ),
        DeviceTier.lowEnd,
      );
    });

    test('empat inti dengan RAM 3 GB (~2,7 GB terukur) maupun 4 GB digolongkan mampu', () {
      expect(
        VisualEffectPolicy.probeDeviceTier(
          processorCount: 4,
          totalMemoryKb: tigaGigaMeasuredKb,
        ),
        DeviceTier.capable,
      );
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
