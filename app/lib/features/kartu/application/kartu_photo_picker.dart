import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Sumber foto latar untuk kartu. Disuntikkan agar tes tidak membuka galeri.
abstract interface class KartuPhotoPicker {
  Future<Uint8List?> pick();
}

class GalleryKartuPhotoPicker implements KartuPhotoPicker {
  const GalleryKartuPhotoPicker();

  @override
  Future<Uint8List?> pick() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (file == null) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
