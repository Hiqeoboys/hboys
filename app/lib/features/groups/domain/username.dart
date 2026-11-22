import '../../auth/domain/username_policy.dart';

/// Menormalkan masukan pengguna (trim + hapus awalan `@` + huruf kecil).
/// Tidak membuang karakter aneh: username salah ketik harus gagal, bukan
/// "diperbaiki" diam-diam.
String normalizeUsername(String input) => UsernamePolicy.normalizeInput(input);

/// Memeriksa kecocokan format username (3–20 karakter `[a-z0-9_.]`, tidak
/// diawali/diakhiri `.` atau `_`, tanpa `..`, bukan kata cadangan).
bool isValidUsername(String normalized) =>
    UsernamePolicy.validate(normalized).isValid;
