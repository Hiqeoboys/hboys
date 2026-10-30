final RegExp _usernamePattern = RegExp(r'^[a-z0-9_.]{3,20}$');

/// Menormalkan masukan pengguna (trim + huruf kecil). Tidak membuang karakter
/// aneh: username salah ketik harus gagal, bukan "diperbaiki" diam-diam.
String normalizeUsername(String input) => input.trim().toLowerCase();

bool isValidUsername(String normalized) => _usernamePattern.hasMatch(normalized);
