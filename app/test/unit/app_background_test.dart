import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/background/app_background.dart';
import 'package:nama_app/design/background/background_motion_controller.dart';

void main() {
  group('AppBackground Konfigurasi & Spesifikasi Desain', () {
    test('konstanta kekuatan, noise, dan periode drift sesuai spesifikasi', () {
      expect(kBackgroundStrength, 1.4);
      expect(kNoiseOpacity, 0.0);
      expect(kDriftHalfPeriod, const Duration(seconds: 15));
      expect(kDriftDeltaFraction.dx, 0.084);
      expect(kDriftDeltaFraction.dy, 0.056);
    });

    test('tabel kPageBackgroundConfigs memetakan intensitas dan izin drift dengan tepat', () {
      expect(kPageBackgroundConfigs[AppBackgroundPage.beranda]?.intensity, 1.0);
      expect(kPageBackgroundConfigs[AppBackgroundPage.beranda]?.allowDrift, isTrue);

      expect(kPageBackgroundConfigs[AppBackgroundPage.track]?.intensity, 0.5);
      expect(kPageBackgroundConfigs[AppBackgroundPage.track]?.allowDrift, isFalse);

      expect(kPageBackgroundConfigs[AppBackgroundPage.petaDaftar]?.intensity, 1.0);
      expect(kPageBackgroundConfigs[AppBackgroundPage.petaDaftar]?.allowDrift, isTrue);

      expect(kPageBackgroundConfigs[AppBackgroundPage.petaPenuh]?.intensity, 0.0);
      expect(kPageBackgroundConfigs[AppBackgroundPage.petaPenuh]?.allowDrift, isFalse);
      expect(kPageBackgroundConfigs[AppBackgroundPage.petaPenuh]?.visible, isFalse);

      expect(kPageBackgroundConfigs[AppBackgroundPage.grup]?.intensity, 1.0);
      expect(kPageBackgroundConfigs[AppBackgroundPage.grup]?.allowDrift, isTrue);

      expect(kPageBackgroundConfigs[AppBackgroundPage.profil]?.intensity, 1.0);
      expect(kPageBackgroundConfigs[AppBackgroundPage.profil]?.allowDrift, isTrue);

      expect(kPageBackgroundConfigs[AppBackgroundPage.pengaturan]?.intensity, 1.0);
      expect(kPageBackgroundConfigs[AppBackgroundPage.pengaturan]?.allowDrift, isTrue);

      expect(kPageBackgroundConfigs[AppBackgroundPage.hiqeoPlus]?.intensity, 1.0);
      expect(kPageBackgroundConfigs[AppBackgroundPage.hiqeoPlus]?.allowDrift, isTrue);

      expect(kPageBackgroundConfigs[AppBackgroundPage.detailGunung]?.intensity, 1.0);
      expect(kPageBackgroundConfigs[AppBackgroundPage.detailGunung]?.allowDrift, isTrue);
    });

    test('BackgroundMotionController menyimpan dan memperbarui status sakelar', () async {
      final store = InMemoryBackgroundMotionStore(true);
      final controller = BackgroundMotionController(store: store);

      expect(controller.enabled, isTrue);

      await controller.setEnabled(false);
      expect(controller.enabled, isFalse);
      expect(store.enabled, isFalse);
      expect(store.writes, 1);

      await controller.setEnabled(true);
      expect(controller.enabled, isTrue);
      expect(store.enabled, isTrue);
      expect(store.writes, 2);
    });
  });
}

