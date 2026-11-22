/// Maksimal jumlah kontak darurat yang disimpan di perangkat.
const int kMaxEmergencyContacts = 3;

/// Pemilik kontak lokal bila pengguna belum masuk (tamu).
const String kLocalEmergencyContactOwnerId = 'local-device';

/// Validasi dan pemformatan nomor telepon Indonesia ke format E.164 (`+62...`)
/// serta penyamaran nomor untuk tampilan UI.
abstract final class IndonesianPhoneValidator {
  static final RegExp _e164Indonesia = RegExp(r'^\+62[1-9][0-9]{7,12}$');

  /// Mengubah input nomor telepon Indonesia (`0812-3456-7890`, `62812...`,
  /// `+62 812 3456 7890`) menjadi format E.164 (`+6281234567890`).
  ///
  /// Mengembalikan `null` bila format tidak valid untuk nomor Indonesia.
  static String? toE164(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (cleaned.isEmpty) return null;

    String normalized;
    if (cleaned.startsWith('+62')) {
      normalized = cleaned;
    } else if (cleaned.startsWith('62')) {
      normalized = '+$cleaned';
    } else if (cleaned.startsWith('0')) {
      normalized = '+62${cleaned.substring(1)}';
    } else {
      return null;
    }

    // Tolak +620... (salah tulis 0 setelah kode negara)
    if (normalized.startsWith('+620')) {
      normalized = '+62${normalized.substring(4)}';
    }

    if (!_e164Indonesia.hasMatch(normalized)) return null;
    return normalized;
  }

  /// Pesan galat validasi nomor telepon Indonesia untuk formulir manual.
  static String? validateError(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Masukkan nomor telepon.';
    if (toE164(trimmed) == null) {
      return 'Gunakan nomor Indonesia yang valid (mis. 08123456789 atau +628123456789).';
    }
    return null;
  }

  /// Menyamarkan bagian tengah nomor untuk tampilan daftar, mis.
  /// `+6281234567890` -> `+62 812-••••-7890`.
  static String mask(String phoneE164) {
    final digits = phoneE164.trim();
    if (digits.startsWith('+62') && digits.length >= 10) {
      final rest = digits.substring(3);
      final prefix = rest.substring(0, rest.length >= 3 ? 3 : rest.length);
      final suffix = rest.substring(rest.length - 4);
      return '+62 $prefix-••••-$suffix';
    }
    if (digits.length > 6) {
      return '${digits.substring(0, 4)}••••${digits.substring(digits.length - 3)}';
    }
    return digits;
  }
}
