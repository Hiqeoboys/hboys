import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/brand/app_brand.dart';
import '../domain/gpx_export.dart';

/// Menulis GPX ke berkas sementara lalu membuka lembar berbagi sistem.
class DeviceGpxExporter implements GpxExporter {
  const DeviceGpxExporter();

  @override
  Future<bool> share({
    required String fileName,
    required String contents,
    String? subject,
  }) async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(contents, flush: true);
      final result = await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(file.path, mimeType: 'application/gpx+xml'),
          ],
          subject: subject ?? AppBrand.shareSubject,
        ),
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (_) {
      return false;
    }
  }
}

/// Membagikan teks biasa (mis. ringkasan itinerary) lewat lembar berbagi.
abstract interface class PlusTextSharer {
  Future<bool> share(String text, {String? subject});
}

class DevicePlusTextSharer implements PlusTextSharer {
  const DevicePlusTextSharer();

  @override
  Future<bool> share(String text, {String? subject}) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, subject: subject ?? AppBrand.shareSubject),
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (_) {
      return false;
    }
  }
}
