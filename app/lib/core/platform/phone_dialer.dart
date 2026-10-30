import 'package:flutter/services.dart';

/// Membuka aplikasi telepon dengan nomor yang sudah diisi. Aplikasi tidak
/// menelepon sendiri; pengguna tetap menekan tombol panggil di aplikasi telepon.
abstract interface class PhoneDialer {
  Future<bool> dial(String number);
}

/// Jembatan ke sisi Android/iOS. Sisi Android memakai ACTION_DIAL tanpa izin
/// CALL_PHONE. Platform tanpa penangan (mis. iOS saat ini) mengembalikan
/// `false` agar layar dapat menampilkan nomor untuk diketik manual.
class MethodChannelPhoneDialer implements PhoneDialer {
  const MethodChannelPhoneDialer();

  static const MethodChannel _channel = MethodChannel('id.nama.nama_app/dialer');
  static final RegExp _allowedNumber = RegExp(r'^[0-9]{2,4}$');

  @override
  Future<bool> dial(String number) async {
    if (!_allowedNumber.hasMatch(number)) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'dial',
            <String, Object?>{'number': number},
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
