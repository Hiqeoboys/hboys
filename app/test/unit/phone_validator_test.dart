import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/safety/domain/phone_validator.dart';

void main() {
  group('IndonesianPhoneValidator.toE164', () {
    test('menormalkan format 08..., 628..., +628..., spasi & tanda hubung', () {
      expect(
        IndonesianPhoneValidator.toE164('0812-3456-7890'),
        '+6281234567890',
      );
      expect(
        IndonesianPhoneValidator.toE164('62812 3456 7890'),
        '+6281234567890',
      );
      expect(
        IndonesianPhoneValidator.toE164('+62 812 (3456) 7890'),
        '+6281234567890',
      );
      expect(
        IndonesianPhoneValidator.toE164('+6208123456789'),
        '+628123456789',
      );
      expect(
        IndonesianPhoneValidator.toE164('021 7654321'),
        '+62217654321',
      );
    });

    test('menolak nomor kosong, non-Indonesia, atau terlalu pendek/panjang', () {
      expect(IndonesianPhoneValidator.toE164(''), isNull);
      expect(IndonesianPhoneValidator.toE164('   '), isNull);
      expect(IndonesianPhoneValidator.toE164('+1 555 123 4567'), isNull);
      expect(IndonesianPhoneValidator.toE164('08123'), isNull);
      expect(IndonesianPhoneValidator.toE164('081234567890123456'), isNull);
      expect(IndonesianPhoneValidator.toE164('bukan nomor'), isNull);
    });

    test('validateError mengembalikan pesan bahasa Indonesia saat tidak valid',
        () {
      expect(IndonesianPhoneValidator.validateError(''), isNotNull);
      expect(IndonesianPhoneValidator.validateError('12345'), isNotNull);
      expect(IndonesianPhoneValidator.validateError('081234567890'), isNull);
    });
  });

  group('IndonesianPhoneValidator.mask', () {
    test('menyamarkan bagian tengah nomor E.164 Indonesia', () {
      expect(
        IndonesianPhoneValidator.mask('+6281234567890'),
        '+62 812-••••-7890',
      );
      expect(
        IndonesianPhoneValidator.mask('+628571234567'),
        '+62 857-••••-4567',
      );
    });
  });
}
