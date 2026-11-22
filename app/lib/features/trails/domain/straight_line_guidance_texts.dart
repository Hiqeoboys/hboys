/// Kumpulan teks resmi untuk petunjuk arah garis lurus (mode cadangan)
/// dan kebijakan peringatan keselamatan.
///
/// PERINGATAN KESELAMATAN:
/// Dilarang keras menambahkan kata "aman" atau "rute aman" pada teks ini
/// karena garis lurus bukan rute terverifikasi dan dapat menembus tebing,
/// jurang, atau sungai berbahaya.
abstract final class StraightLineGuidanceTexts {
  /// Label nama mode pemanduan garis lurus
  static const String modeLabel = 'Garis lurus, bukan rute';

  /// Judul dialog peringatan wajib sebelum arah ditampilkan
  static const String dialogTitle = 'Peringatan penting';

  /// Isi pesan dialog peringatan wajib
  static const String dialogContent =
      'Petunjuk ini hanya garis lurus ke jalur terdekat, bukan rute yang sudah kamu lalui. '
      'Di antaranya bisa ada tebing, jurang, sungai, atau medan berbahaya yang tidak terlihat di peta. '
      'Jangan menembus medan yang tidak kamu lihat jelas. Bila ragu, berhenti, tetap di tempat, dan minta bantuan.';

  /// Tombol batal pada dialog peringatan (menutup panel petunjuk)
  static const String dialogCancel = 'Batal';

  /// Tombol SOS pada dialog peringatan dan kartu petunjuk
  static const String dialogSos = 'SOS';

  /// Tombol konfirmasi pada dialog peringatan untuk menampilkan arah
  static const String dialogAcknowledge = 'Saya mengerti';

  /// Teks kartu peringatan permanen di panel petunjuk selama mode garis lurus aktif
  static const String warningCardText =
      'Ini hanya arah lurus. Di antaranya bisa ada tebing, jurang, atau sungai. '
      'Jangan menembus medan yang tidak terlihat jelas. Bila ragu, berhenti dan minta bantuan.';

  /// Peringatan tambahan jika jarak ke jalur sangat jauh (> 1.000 meter)
  static const String farFromRouteWarning =
      'Kamu jauh dari jalur. Pertimbangkan berhenti dan minta bantuan.';

  /// Peringatan tambahan jika akurasi GPS rendah (> 30 meter)
  static const String lowAccuracyWarning =
      'Akurasi GPS rendah, arah bisa meleset.';

  /// Status di panel sebelum pengguna mengonfirmasi dialog peringatan
  static const String pendingAcknowledgeNotice =
      'Konfirmasi peringatan untuk melihat arah garis lurus';

  /// Tombol buka dialog konfirmasi di panel jika belum dikonfirmasi
  static const String openDialogButton = 'Buka peringatan';

  /// Daftar seluruh teks yang ditampilkan ke pengguna dalam mode garis lurus
  /// untuk diverifikasi oleh test otomatis bahwa tidak ada kata "aman".
  static const List<String> allUserFacingTexts = [
    modeLabel,
    dialogTitle,
    dialogContent,
    dialogCancel,
    dialogSos,
    dialogAcknowledge,
    warningCardText,
    farFromRouteWarning,
    lowAccuracyWarning,
    pendingAcknowledgeNotice,
    openDialogButton,
  ];
}

