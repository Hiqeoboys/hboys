/// Aturan format, batas jeda 7 hari, normalisasi moderasi, dan pemetaan galat
/// server untuk perubahan username Hiqeo.
///
/// CATATAN KEAMANAN:
/// Daftar kata terlarang (`blocked_terms`) TIDAK disimpan di kode klien agar
/// tidak mudah diakali dan tidak membawa daftar kata kasar di dalam paket
/// aplikasi. Penegakan moderasi dilakukan di sisi server lewat RPC
/// `public.set_username`.
abstract final class UsernamePolicy {
  static const int minLength = 3;
  static const int maxLength = 20;
  static const int cooldownDays = 7;

  /// Akun resmi Hiqeo yang di-whitelist memakai `@hiqeo` dan `Hiqeo Official`.
  static const String officialAccountEmail = 'hiqeoofficial@gmail.com';
  static const String officialUsername = 'hiqeo';
  static const String officialDisplayName = 'Hiqeo Official';

  static bool isOfficialEmail(String? email) =>
      email != null && email.trim().toLowerCase() == officialAccountEmail;

  static bool isOfficialUsername(String? username) =>
      username != null && normalizeInput(username) == officialUsername;

  static final RegExp _allowedChars = RegExp(r'^[a-z0-9_.]+$');
  static final RegExp _edgePunctuation = RegExp(r'^[._]|[._]$');
  static final RegExp _doubleDot = RegExp(r'\.\.');

  /// Kata cadangan sistem yang ditolak agar tidak menyaru sebagai akun resmi.
  /// Daftar penuh termasuk kata terlarang SARA/kekerasan/pornografi dijaga di
  /// tabel server `public.blocked_terms`.
  static const Set<String> reservedWords = <String>{
    'admin',
    'administrator',
    'hiqeo',
    'hiqeo_id',
    'hiqeo.id',
    'hiqeo_official',
    'timhiqeo',
    'support',
    'bantuan',
    'layanan',
    'moderator',
    'mod',
    'official',
    'resmi',
    'staff',
    'system',
    'sistem',
    'root',
    'help',
    'security',
    'keamanan',
    'info',
    'api',
    'bot',
    'owner',
    'founder',
    'null',
    'undefined',
    'test',
    'testing',
    'basarnas',
    'sar',
    'polisi',
    'darurat',
    'sos',
  };

  /// Menormalkan input mentah pengguna untuk validasi format (hapus awalan `@`,
  /// trim spasi, dan ubah ke huruf kecil).
  static String normalizeInput(String input) {
    final trimmed = input.trim();
    final withoutAt = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
    return withoutAt.toLowerCase();
  }

  /// Normalisasi khusus moderasi (identik dengan fungsi SQL
  /// `public.normalize_username`):
  /// 1. Huruf kecil
  /// 2. Penggantian leetspeak (`0=o, 1=i, 3=e, 4=a, 5=s, 7=t, @=a, $=s`)
  /// 3. Hapus pemisah `.`, `_`, dan spasi
  /// 4. Ciutkan pengulangan huruf berturut-turut (`aaaanjiiing` -> `anjing`)
  static String normalizeForModeration(String input) {
    final lower = input.toLowerCase();
    final mapped = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      switch (ch) {
        case '0':
          mapped.write('o');
        case '1':
          mapped.write('i');
        case '3':
          mapped.write('e');
        case '4':
        case '@':
          mapped.write('a');
        case '5':
        case r'$':
          mapped.write('s');
        case '7':
          mapped.write('t');
        case '.':
        case '_':
        case ' ':
        case '-':
          break;
        default:
          mapped.write(ch);
      }
    }
    final stripped = mapped.toString();
    if (stripped.isEmpty) return '';

    final collapsed = StringBuffer()..write(stripped[0]);
    for (var i = 1; i < stripped.length; i++) {
      if (stripped[i] != stripped[i - 1]) {
        collapsed.write(stripped[i]);
      }
    }
    return collapsed.toString();
  }

  /// Memvalidasi format dan kata cadangan di klien untuk umpan balik langsung.
  ///
  /// Jika [userEmail] adalah akun resmi terverifikasi (`hiqeoofficial@gmail.com`),
  /// username `@hiqeo` diizinkan tanpa peringatan penolakan.
  static UsernameValidationResult validate(
    String rawInput, {
    String? userEmail,
  }) {
    final value = normalizeInput(rawInput);
    final lengthOk = value.length >= minLength && value.length <= maxLength;
    final charsOk = value.isNotEmpty && _allowedChars.hasMatch(value);
    final edgesOk = value.isNotEmpty && !_edgePunctuation.hasMatch(value);
    final noDoubleDot = !_doubleDot.hasMatch(value);

    final isWhitelistedOfficial =
        isOfficialEmail(userEmail) && value == officialUsername;
    final normalizedMod = normalizeForModeration(value);
    final isReserved = !isWhitelistedOfficial &&
        (reservedWords.contains(value) ||
            reservedWords.contains(normalizedMod) ||
            (!isOfficialEmail(userEmail) &&
                (value.contains('hiqeo') || normalizedMod.contains('hiqeo'))));

    String? error;
    if (value.isEmpty) {
      error = 'Masukkan username baru.';
    } else if (!lengthOk) {
      error = 'Username harus 3–20 karakter.';
    } else if (!charsOk) {
      error = 'Hanya boleh huruf kecil, angka, titik (.), atau garis bawah (_).';
    } else if (!edgesOk) {
      error = 'Tidak boleh diawali atau diakhiri titik atau garis bawah.';
    } else if (!noDoubleDot) {
      error = 'Tidak boleh mengandung dua titik berurutan (..).';
    } else if (isReserved) {
      error = 'Username ini tidak diperbolehkan. Pilih yang lain.';
    }

    return UsernameValidationResult(
      normalized: value,
      lengthOk: lengthOk,
      charsOk: charsOk,
      edgesOk: edgesOk,
      noDoubleDot: noDoubleDot,
      isReserved: isReserved,
      errorMessage: error,
    );
  }

  /// Validasi nama tampilan agar hanya akun resmi terverifikasi
  /// (`hiqeoofficial@gmail.com`) yang boleh memakai nama "Hiqeo Official".
  static String? validateDisplayName(
    String rawInput, {
    String? userEmail,
  }) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return 'Nama akun tidak boleh kosong.';
    if (trimmed.length > 40) return 'Nama akun maksimal 40 karakter.';
    if (!isOfficialEmail(userEmail)) {
      final lower = trimmed.toLowerCase();
      final mod = normalizeForModeration(trimmed);
      if (lower.contains('hiqeo official') ||
          mod.contains('hiqeofficial') ||
          mod == officialUsername) {
        return 'Nama tampilan "Hiqeo Official" khusus untuk akun resmi Hiqeo.';
      }
    }
    return null;
  }

  /// Memeriksa apakah username lama yang tersimpan masih sesuai aturan saat ini.
  static bool isCompliant(String? username) {
    if (username == null || username.isEmpty) return false;
    return validate(username).isValid;
  }

  /// Menghitung sisa hari jeda 7 hari sebelum username bisa diganti lagi.
  ///
  /// Mengembalikan `0` bila pengguna boleh mengganti sekarang:
  /// - Belum pernah mengganti (`usernameChangedAtUtc == null`).
  /// - Username lama belum memenuhi aturan (boleh langsung diperbaiki).
  /// - Sudah melewati 7 hari penuh sejak perubahan terakhir.
  static int cooldownDaysRemaining({
    required DateTime? usernameChangedAtUtc,
    required DateTime nowUtc,
    String? currentUsername,
  }) {
    if (usernameChangedAtUtc == null) return 0;
    if (currentUsername != null && !isCompliant(currentUsername)) return 0;

    final elapsed = nowUtc.toUtc().difference(usernameChangedAtUtc.toUtc());
    const limit = Duration(days: cooldownDays);
    if (elapsed >= limit) return 0;

    final remainingSeconds = (limit - elapsed).inSeconds;
    return (remainingSeconds / Duration.secondsPerDay).ceil().clamp(
          1,
          cooldownDays,
        );
  }

  /// Memetakan kode galat dari RPC server `set_username` menjadi pesan UI
  /// bahasa Indonesia yang netral dan konsisten.
  static UsernameServerError mapServerError(String raw) {
    final trimmed = raw.trim();
    final lower = trimmed.toLowerCase();

    final cooldownMatch = RegExp(r'cooldown:(\d+)').firstMatch(lower);
    if (cooldownMatch != null) {
      final days = int.tryParse(cooldownMatch.group(1) ?? '') ?? 1;
      final safeDays = days < 1 ? 1 : days;
      return UsernameServerError(
        code: 'cooldown:$safeDays',
        cooldownDays: safeDays,
        message: 'Username baru bisa diganti lagi dalam $safeDays hari',
      );
    }

    if (lower.contains('invalid_format') || lower.contains('username_invalid')) {
      return const UsernameServerError(
        code: 'invalid_format',
        message:
            'Format username tidak sesuai. Gunakan 3–20 karakter huruf kecil, angka, titik, atau garis bawah.',
      );
    }

    if (lower.contains('blocked') || lower.contains('username_blocked')) {
      return const UsernameServerError(
        code: 'blocked',
        message: 'Username ini tidak diperbolehkan. Pilih yang lain.',
      );
    }

    if (lower.contains('taken') || lower.contains('username_taken')) {
      return const UsernameServerError(
        code: 'taken',
        message: 'Username sudah dipakai. Pilih yang lain.',
      );
    }

    return const UsernameServerError(
      code: 'server_error',
      message: 'Gagal menyimpan username. Periksa koneksi lalu coba lagi.',
    );
  }
}

class UsernameValidationResult {
  const UsernameValidationResult({
    required this.normalized,
    required this.lengthOk,
    required this.charsOk,
    required this.edgesOk,
    required this.noDoubleDot,
    required this.isReserved,
    required this.errorMessage,
  });

  final String normalized;
  final bool lengthOk;
  final bool charsOk;
  final bool edgesOk;
  final bool noDoubleDot;
  final bool isReserved;
  final String? errorMessage;

  bool get isValid =>
      lengthOk && charsOk && edgesOk && noDoubleDot && !isReserved;
}

class UsernameServerError {
  const UsernameServerError({
    required this.code,
    required this.message,
    this.cooldownDays,
  });

  final String code;
  final String message;
  final int? cooldownDays;
}
