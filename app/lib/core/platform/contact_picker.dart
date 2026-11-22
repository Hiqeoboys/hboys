import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Kontak yang dipilih pengguna dari buku alamat perangkat.
@immutable
class PickedContact {
  const PickedContact({required this.name, required this.phone});

  final String name;
  final String phone;
}

/// Hasil pemanggilan pemilih kontak perangkat.
enum ContactPickStatus { picked, cancelled, permissionDenied, unsupported }

@immutable
class ContactPickResult {
  const ContactPickResult({required this.status, this.contact});

  final ContactPickStatus status;
  final PickedContact? contact;
}

/// Abstraksi pemilih kontak HP agar dapat diuji tanpa perangkat asli.
abstract interface class ContactPicker {
  Future<ContactPickResult> pickContact();
}

/// Implementasi pemilih kontak melalui MethodChannel native Android & iOS.
///
/// Meminta izin [Permission.contacts] HANYA saat pengguna menekan tombol
/// "Pilih dari kontak".
class MethodChannelContactPicker implements ContactPicker {
  const MethodChannelContactPicker();

  static const MethodChannel _channel =
      MethodChannel('id.nama.nama_app/contacts');

  @override
  Future<ContactPickResult> pickContact() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return const ContactPickResult(status: ContactPickStatus.unsupported);
    }

    try {
      final status = await Permission.contacts.request();
      if (!status.isGranted && !status.isLimited) {
        return const ContactPickResult(
          status: ContactPickStatus.permissionDenied,
        );
      }

      final result = await _channel.invokeMapMethod<String, dynamic>(
        'pickContact',
      );
      if (result == null) {
        return const ContactPickResult(status: ContactPickStatus.cancelled);
      }
      final name = (result['name'] as String? ?? '').trim();
      final phone = (result['phone'] as String? ?? '').trim();
      if (phone.isEmpty) {
        return const ContactPickResult(status: ContactPickStatus.cancelled);
      }
      return ContactPickResult(
        status: ContactPickStatus.picked,
        contact: PickedContact(
          name: name.isEmpty ? 'Kontak darurat' : name,
          phone: phone,
        ),
      );
    } on MissingPluginException {
      return const ContactPickResult(status: ContactPickStatus.unsupported);
    } on PlatformException {
      return const ContactPickResult(status: ContactPickStatus.cancelled);
    }
  }
}
