import 'package:flutter/foundation.dart';

import '../../guides/domain/field_sketch_spec.dart';

/// Satu topik Panduan Keselamatan, P3K, & Wilderness Survival 100% offline mengacu
/// standar medis lapangan Wilderness Medical Society (WMS), WHO, Palang Merah,
/// AHA, dan Basarnas.
@immutable
class FirstAidTopic {
  const FirstAidTopic({
    required this.id,
    required this.title,
    required this.category,
    required this.summary,
    required this.dangerSigns,
    required this.firstAidSteps,
    required this.prohibitionsAndMyths,
    this.stepSketches = const <FieldSketchId>[],
    this.isSurvivalChapter = false,
  });

  final String id;
  final String title;
  final String category;
  final String summary;

  /// Tanda Bahaya (SOS / Evakuasi Segera)
  final List<String> dangerSigns;

  /// Langkah Pertolongan Pertama / Protokol Bertahan Hidup
  final List<String> firstAidSteps;

  /// Larangan & Mitos Berbahaya
  final List<String> prohibitionsAndMyths;

  /// Kanvas Technical Field Sketch 1:1 untuk tiap item di [firstAidSteps].
  final List<FieldSketchId> stepSketches;

  /// Menandai topik dari bab baru Protokol Tersesat & Bertahan Hidup Multi-Hari.
  final bool isSurvivalChapter;
}

const List<String> kFirstAidCategories = <String>[
  'Semua',
  'Suhu & Ketinggian',
  'Cedera & Luka',
  'Hewan & Alergi',
  'Cuaca & Navigasi',
  'Survival & Tersesat',
];

const List<String> kSafetyGuideCategories = kFirstAidCategories;

const List<FirstAidTopic> kFirstAidTopics = <FirstAidTopic>[
  FirstAidTopic(
    id: 'hipotermia',
    title: 'Hipotermia (Ringan, Sedang, Berat)',
    category: 'Suhu & Ketinggian',
    summary:
        'Penurunan suhu inti tubuh di bawah 35°C akibat paparan angin, hujan, pakaian basah, dan kelelahan.',
    dangerSigns: <String>[
      'Menggigil berhenti total padahal korban masih sangat kedinginan (tanda hipotermia sedang–berat).',
      'Bicara melantur, bingung berat, apatis, atau kesadaran menurun hingga pingsan.',
      'Napas dan denyut nadi sangat lambat, kulit pucat/kebiruan, atau otot kaku.',
    ],
    firstAidSteps: <String>[
      'Pindahkan korban ke tempat terlindung dari angin dan hujan (tenda atau bivak).',
      'Ganti segera seluruh pakaian basah dengan pakaian kering; tutup kepala, leher, tangan, dan kaki.',
      'Isolasi dari tanah memakai matras tebal, lalu bungkus dengan sleeping bag dan selimut foil darurat (hipotermia wrap).',
      'Hipotermia ringan (sadar penuh & bisa menelan): beri minuman hangat manis dan kalori tinggi; kompres hangat di ketiak, dada, dan selangkangan.',
      'Hipotermia berat: tangani tubuh korban secara SANGAT LEMBUT (horizontal) dan lakukan evakuasi medis segera; siapkan RJP bila napas/nadi hilang.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.p3kHypoShelter,
      FieldSketchId.p3kHypoDryClothes,
      FieldSketchId.p3kHypoBurritoWrap,
      FieldSketchId.p3kHypoWarmDrinks,
      FieldSketchId.p3kHypoGentleEvac,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN menggosok-gosok kulit atau anggota gerak korban secara keras (berisiko memicu henti jantung/afterdrop).',
      'JANGAN memberikan alkohol, kopi berkafein tinggi, atau minuman kepada korban yang mengantuk berat/tidak sadar.',
      'MITOS BERBAHAYA: "Kontak kulit-ke-kulit telanjang lebih cepat menghangatkan". Hindari di lapangan terbuka karena justru mempercepat kehilangan panas kedua orang; gunakan insulasi kering dan sumber panas eksternal terbungkus kain.',
    ],
  ),
  FirstAidTopic(
    id: 'ams_hape_hace',
    title: 'Penyakit Ketinggian (AMS, HAPE, HACE)',
    category: 'Suhu & Ketinggian',
    summary:
        'Gangguan adaptasi oksigen rendah pada ketinggian >2.500 mdpl meliputi Acute Mountain Sickness, edema paru, dan edema otak.',
    dangerSigns: <String>[
      'HACE: sakit kepala hebat tak membaik, hilang keseimbangan (ataksia/jalan sempoyongan), halusinasi, atau penurunan kesadaran.',
      'HAPE: sesak napas bahkan saat istirahat, batuk kering berubah berdahak merah muda/berbusa, bibir/kuku membiru, suara napas berderak.',
      'AMS berat: muntah terus-menerus dan tidak mampu makan/minum.',
    ],
    firstAidSteps: <String>[
      'AMS ringan (pusing, mual ringan, lemas): BERHENTI naik ketinggian, istirahat, hidrasi cukup, dan pantau ketat 12–24 jam.',
      'Bila gejala tidak membaik dalam 24 jam atau muncul tanda HAPE/HACE: SEGERA TURUN ketinggian minimal 300–1.000 meter (evakuasi adalah terapi utama!).',
      'Jaga korban tetap hangat dan posisi setengah duduk pada kecurigaan HAPE; kurangi beban kerja fisik korban saat turun.',
      'Jika tersedia sesuai resep dokter/protokol WMS: oksigen portabel, asetazolamid (AMS), deksametason (HACE), atau nifedipin (HAPE).',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.p3kAmsStopClimb,
      FieldSketchId.p3kAmsDescend300m,
      FieldSketchId.p3kAmsSemiSitting,
      FieldSketchId.p3kAmsOxygenMeds,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN pernah memaksa naik ketinggian ("mumpung dekat puncak") saat gejala AMS/HAPE/HACE sudah muncul.',
      'JANGAN biarkan penderita gejala ketinggian tidur sendirian atau turun sendirian tanpa pendamping.',
      'MITOS BERBAHAYA: "Orang bugar dan atlet tidak bisa kena AMS/HAPE/HACE". Kebugaran fisik tidak melindungi dari penyakit ketinggian; laju kenaikan dan aklimatisasi yang menentukan.',
    ],
  ),
  FirstAidTopic(
    id: 'keseleo_patah_tulang',
    title: 'Keseleo / Terkilir & Patah Tulang (Bidai Darurat)',
    category: 'Cedera & Luka',
    summary:
        'Cedera ligamen sendi atau fraktur tulang akibat terpeleset di jalur licin, berbatu, atau turunan curam.',
    dangerSigns: <String>[
      'Patah tulang terbuka (tulang menembus kulit) atau pendarahan aktif hebat.',
      'Bagian ujung jari/kaki di bawah cedera tampak pucat, dingin, kebiruan, mati rasa, atau nadi tidak teraba.',
      'Kecurigaan cedera tulang belakang/leher (jatuh dari tebing) atau patah panggul/paha.',
    ],
    firstAidSteps: <String>[
      'Hentikan pergerakan dan cek sirkulasi, sensasi, serta gerak jari di distal cedera (CSM).',
      'Keseleo ringan: istirahatkan sendi, kompres dingin 15–20 menit (balut kain), balut elastis sedang tanpa mencekik, dan elevasikan.',
      'Patah tulang: imobilisasi dengan bidai darurat (trekking pole, ranting lurus, atau matras gulung) yang dilapisi kain lembut, melewati DUA sendi (di atas dan di bawah area patah).',
      'Ikat bidai cukup kuat agar tidak bergeser namun tetap longgar bagi aliran darah; cek ulang CSM tiap 15–30 menit dan panggil evakuasi.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.p3kFractureCsmCheck,
      FieldSketchId.p3kSprainRice,
      FieldSketchId.p3kFractureSplintTwoJoints,
      FieldSketchId.p3kFractureTieRecheck,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN memijat, mengurut, atau menarik paksa tulang/sendi yang bengkok atau dislokasi.',
      'JANGAN mendorong tulang yang mencuat keluar kembali ke dalam luka (cukup tutup steril lembap dan bidai di posisi ditemukan).',
      'JANGAN memindahkan korban cedera tulang belakang tanpa stabilisasi kepala-leher kecuali ada bahaya langsung (longsor/api).',
    ],
  ),
  FirstAidTopic(
    id: 'luka_pendarahan_bakar',
    title: 'Luka Terbuka, Pendarahan Hebat & Luka Bakar',
    category: 'Cedera & Luka',
    summary:
        'Penanganan cepat pendarahan mengancam nyawa (standar Stop the Bleed / AHA) dan luka bakar kompor lapangan.',
    dangerSigns: <String>[
      'Darah memancar deras atau terus merembes menembus kasa tekan (pendarahan arteri/hebat).',
      'Tanda syok: pucat, keringat dingin, napas cepat, nadi cepat lemah, pusing hebat/pingsan.',
      'Luka bakar luas (>10% tubuh), mengenai wajah/jalan napas, tangan, kaki, sendi besar, atau luka bakar listrik/kimia.',
    ],
    firstAidSteps: <String>[
      'Pendarahan hebat: tekan langsung titik pendarahan dengan kasa/kain bersih secara kuat dan konstan minimal 10–15 menit; tambahkan kasa di atasnya jika tembus.',
      'Jika pendarahan ekstremitas tak terkendali dengan tekanan langsung: pasang torniket komersial 5–7 cm di atas luka (bukan di sendi) dan catat waktu pemasangan; aktifkan SOS.',
      'Luka sayat/lecet ringan: cuci bersih dengan air mengalir matang/bersih, tutup kasa steril dan plester.',
      'Luka bakar kompor/air panas: dinginkan segera dengan air mengalir sejuk (bukan es) selama 10–20 menit, lepaskan jam/cincin sebelum bengkak, lalu tutup longgar kasa steril tidak lengket.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.p3kBleedDirectPressure,
      FieldSketchId.p3kBleedTourniquet,
      FieldSketchId.p3kWoundCleanDress,
      FieldSketchId.p3kBurnCoolWater,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN mengoleskan pasta gigi, mentega, kopi, minyak goreng, kecap, atau dedaunan mentah pada luka bakar maupun luka terbuka.',
      'JANGAN memecahkan lepuhan (blister) luka bakar karena meningkatkan risiko infeksi berat.',
      'JANGAN mencabut benda tajam/ranting yang menancap dalam (stabilkan di posisinya dengan bantalan kasa lalu evakuasi).',
    ],
  ),
  FirstAidTopic(
    id: 'gigitan_ular_serangga',
    title: 'Gigitan Ular Berbisa & Sengatan Serangga / Lebah',
    category: 'Hewan & Alergi',
    summary:
        'Protokol standar WHO & WMS untuk memperlambat penyebaran bisa dan mencegah syok.',
    dangerSigns: <String>[
      'Bengkak menjalar cepat, nyeri hebat, memar/lepuh luas, atau pendarahan gusi/luka tak berhenti.',
      'Kelopak mata turun (ptosis), pandangan ganda, sulit menelan/berbicara, lemas otot, atau sesak napas.',
      'Sengatan lebah/tawon multipel atau muncul bentol seluruh tubuh/bengkak bibir-tenggorokan (anafilaksis).',
    ],
    firstAidSteps: <String>[
      'Jauhkan korban dari lokasi ular/sarang lebah; tenangkan korban agar detak jantung tidak memacu penyebaran bisa.',
      'Lepaskan cincin, gelang, jam, dan sepatu/kaus kaki ketat di sekitar gigitan sebelum pembengkakan terjadi.',
      'Imobilisasi anggota gerak yang digigit dengan bidai longgar dan posisikan sejajar atau sedikit di bawah jantung; evakuasi korban dengan tandu/bantuan (jangan biarkan berjalan jauh bila memungkinkan).',
      'Sengatan lebah: kikis sengat mendatar dengan kartu (jangan dijepit pinset), cuci bersih, kompres dingin untuk nyeri/bengkak.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.p3kSnakeCalmMoveAway,
      FieldSketchId.p3kSnakeRemoveRings,
      FieldSketchId.p3kSnakeImmobilizeSplint,
      FieldSketchId.p3kBeeScrapeCard,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN menyedot bisa dengan mulut, menyayat/mengiris luka, atau membakar luka gigitan.',
      'JANGAN mengikat torniket ketat (mematikan jaringan dan berisiko amputasi).',
      'JANGAN menangkap atau membunuh ular untuk dibawa (cukup ingat ciri atau foto dari jarak aman jika memungkinkan).',
    ],
  ),
  FirstAidTopic(
    id: 'dehidrasi_heat_stroke',
    title: 'Dehidrasi, Heat Exhaustion & Heat Stroke',
    category: 'Suhu & Ketinggian',
    summary:
        'Gangguan cairan dan suhu tubuh berlebih akibat terik sabana, kelembapan tinggi, dan kurang elektrolit.',
    dangerSigns: <String>[
      'Heat Stroke (DARURAT MEDIS): suhu tubuh sangat panas (>40°C), bingung/mengigau, kejang, perilaku aneh, atau pingsan.',
      'Tidak bisa minum karena muntah terus-menerus atau tidak buang air kecil >8 jam dengan urine sangat pekat.',
      'Denyut nadi sangat cepat dan lemah disertai pusing berat saat berdiri.',
    ],
    firstAidSteps: <String>[
      'Pindahkan segera ke tempat teduh, lepaskan carrier dan pakaian berlapis/ketat.',
      'Heat Exhaustion (sadar, lemas, kram, mual): beri minum air + oralit/elektrolit sedikit demi sedikit, basahi kulit dan kipasi.',
      'Heat Stroke: DINGINKAN SEGERA secara agresif (siram/basahi seluruh tubuh dengan air dingin, kompres es/air dingin di leher, ketiak, dan selangkangan sambil dikipasi terus-menerus) lalu evakuasi segera.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.p3kHeatShadeRemovePack,
      FieldSketchId.p3kHeatElectrolyte,
      FieldSketchId.p3kHeatStrokeAggressiveCool,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN memaksa memberi minum pada korban yang setengah sadar, kebingungan berat, atau pingsan (risiko tersedak).',
      'JANGAN menunda pendinginan pada Heat Stroke, karena setiap menit keterlambatan meningkatkan kerusakan organ.',
      'JANGAN memberikan obat penurun demam (parasetamol/ibuprofen) untuk Heat Stroke karena mekanismenya berbeda dan berisiko memperberat hati/ginjal.',
    ],
  ),
  FirstAidTopic(
    id: 'hipoglikemia_keracunan',
    title: 'Hipoglikemia & Keracunan Makanan/Tanaman',
    category: 'Suhu & Ketinggian',
    summary:
        'Penurunan gula darah mendadak ("bonking") atau gejala keracunan akibat air tidak steril, makanan basi, maupun tanaman liar.',
    dangerSigns: <String>[
      'Kebingungan mendadak, kejang, atau penurunan kesadaran/pingsan.',
      'Muntah darah, diare hebat terus-menerus dengan tanda dehidrasi berat, atau sesak napas.',
      'Nyeri perut hebat yang tidak kunjung mereda atau detak jantung tidak teratur.',
    ],
    firstAidSteps: <String>[
      'Hipoglikemia (gemetar, keringat dingin, pucat, lemas mendadak) saat SADAR: segera berikan 15–20 g gula cepat serap (madu, gula pasir/aren, permen manis, jus), evaluasi 15 menit, lalu lanjutkan karbohidrat kompleks.',
      'Bila korban tidak sadar: miringkan ke posisi pemulihan (recovery position), jaga jalan napas, panggil SOS segera.',
      'Keracunan makanan/air: fokus rehidrasi oral dengan oralit/air matang sedikit demi sedikit namun sering; simpan sampel makanan/tanaman yang dikonsumsi untuk tim medis.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.p3kHypoglycemiaSugar,
      FieldSketchId.p3kRecoveryPosition,
      FieldSketchId.p3kPoisonRehydrateSample,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN memaksa memuntahkan isi perut pada kasus keracunan (berisiko aspirasi paru dan melukai kerongkongan).',
      'JANGAN memasukkan makanan, gula cair, atau minuman ke mulut korban yang sudah pingsan/kejang.',
      'MITOS BERBAHAYA: "Air sungai gunung yang jernih pasti aman diminum langsung". Tetap rebus mendidih minimal 1–3 menit atau gunakan filter mikrobiologi.',
    ],
  ),
  FirstAidTopic(
    id: 'petir_badai',
    title: 'Tersambar Petir & Prosedur Berlindung dari Badai',
    category: 'Cuaca & Navigasi',
    summary:
        'Tindakan penyelamatan korban sambaran petir (standar AHA/WMS) dan posisi aman saat badai petir di punggungan gunung.',
    dangerSigns: <String>[
      'Korban tidak bernapas atau tidak ada denyut nadi (henti napas/henti jantung akibat arus listrik).',
      'Luka bakar masuk/keluar arus, gangguan pendengaran/penglihatan, kelumpuhan sementara, atau bingung berat.',
      'Kilat dan guntur berjarak <30 detik (badai petir berada dalam radius bahaya <10 km).',
    ],
    firstAidSteps: <String>[
      'Pencegahan di jalur: SEGERA turun dari puncak, punggungan terbuka, dan area berair; hindari pohon tunggal tertinggi; cari lereng lebih rendah dengan pepohonan seragam.',
      'Posisi darurat jika terjebak di tempat terbuka: jongkok di atas matras/carrier kering dengan kedua kaki merapat (hanya ujung kaki menyentuh tanah), tundukkan kepala, tutup telinga, jaga jarak minimal 10–15 meter antar pendaki.',
      'Pertolongan korban sambaran: korban petir AMAN disentuh (tidak menyimpan muatan listrik!). Utamakan korban yang tampak tidak bernapas/tidak responsif: lakukan RJP (kompresi dada & napas buatan) segera dan aktifkan SOS.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.p3kLightningDescendRidge,
      FieldSketchId.p3kLightningCrouch,
      FieldSketchId.p3kLightningCprSafeTouch,
    ],
    prohibitionsAndMyths: <String>[
      'MITOS BERBAHAYA: "Korban tersambar petir masih mengandung listrik sehingga berbahaya disentuh". SALAH TOTAL: segera sentuh dan lakukan RJP bila tidak bernapas!',
      'JANGAN berbaring telentang langsung di tanah basah (memperbesar beda potensial arus tanah / ground current).',
      'JANGAN berteduh di bawah pohon tunggal, gua dangkal/ceruk batu, atau menempel pada tiang logam/tenda ber-frame logam di area terbuka.',
    ],
  ),
  FirstAidTopic(
    id: 'anafilaksis_asma',
    title: 'Reaksi Alergi Berat (Anafilaksis) & Asma',
    category: 'Hewan & Alergi',
    summary:
        'Kegawatdaruratan penyempitan jalan napas akibat alergi makanan/sengatan atau serangan asma terpicu udara dingin gunung.',
    dangerSigns: <String>[
      'Pembengkakan cepat pada bibir, lidah, wajah, atau tenggorokan disertai suara serak/mengi.',
      'Sesak napas berat, kesulitan berbicara dalam kalimat utuh, dada terasa tercekik.',
      'Pusing hebat, kulit pucat/kebiruan, tekanan darah turun mendadak, atau pingsan.',
    ],
    firstAidSteps: <String>[
      'Anafilaksis: segera gunakan auto-injektor epinefrin (EpiPen) di paha luar bila korban membawanya; baringkan korban dengan kaki sedikit ditinggikan (atau duduk tegak bila sesak napas dominan).',
      'Serangan Asma: bantu korban duduk condong sedikit ke depan (tripod position), tenangkan napas, bantu gunakan inhaler pereda cepat (salbutamol) sesuai dosis pribadinya, dan hangatkan udara yang dihirup memakai buff/masker.',
      'Longgarkan tali carrier, kerah jaket, dan pakaian ketat di dada/leher; aktifkan SOS & siapkan evakuasi segera.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.p3kAnaEpipenPosition,
      FieldSketchId.p3kAsthmaTripodInhaler,
      FieldSketchId.p3kAirwayLoosenSos,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN menyuruh korban anafilaksis berdiri atau berjalan tiba-tiba (risiko syok fatal / empty ventricle syndrome).',
      'JANGAN hanya mengandalkan antihistamin tablet atau minyak angin untuk reaksi anafilaksis berat.',
      'JANGAN meninggalkan korban sendirian meski gejala sempat mereda (reaksi bifasik dapat kambuh beberapa jam kemudian).',
    ],
  ),
  FirstAidTopic(
    id: 'tersesat_stop',
    title: 'Tersesat di Gunung (Prinsip STOP & Hemat Energi)',
    category: 'Cuaca & Navigasi',
    summary:
        'Protokol Basarnas & survival gunung saat kehilangan jalur untuk mencegah kepanikan, hipotermia, dan salah arah.',
    dangerSigns: <String>[
      'Hari menjelang gelap, kabut pekat, hujan deras, atau suhu turun drastis.',
      'Air minum/logistik menipis, baterai HP kritis, atau ada anggota mengalami cedera/hipotermia.',
      'Tidak berhasil kembali ke jalur utama setelah evaluasi tenang.',
    ],
    firstAidSteps: <String>[
      'S: Stop (Berhenti). Hentikan langkah seketika begitu sadar jalur tidak dikenal; jangan terus memaksa jalan.',
      'T: Think (Berpikir Tenang). Atur napas, minum air, makan camilan manis untuk menjaga fokus otak; ingat kembali titik jalur terakhir yang pasti benar.',
      'O: Observe (Amati). Periksa peta offline & titik GPS di Hiqeo, kompas, sisa logistik, cuaca, dan lokasi aman untuk berlindung.',
      'P: Plan (Rencanakan). Bila jalur asli dekat dan terverifikasi GPS, kembali perlahan sambil menandai jejak; jika ragu atau gelap, BERTAHAN DI SATU TEMPAT TERBUKA yang aman, bangun bivak hangat, hemat baterai (mode pesawat), dan bunyikan peluit 3x tiap 1 menit (kode SOS internasional).',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.p3kStopFreeze,
      FieldSketchId.p3kStopThink,
      FieldSketchId.p3kStopObserve,
      FieldSketchId.p3kStopPlanStayPut,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN panik dan berlari atau memotong kompas menuruni jurang/sungai terjal tanpa peta (penyebab utama kecelakaan fatal pendaki tersesat).',
      'JANGAN berpencar mencari jalan sendiri-sendiri; seluruh anggota rombongan WAJIB tetap bersama.',
      'JANGAN terus berjalan malam hari saat kabut/hujan tanpa jalur jelas: berhenti lebih awal untuk mendirikan shelter jauh lebih aman daripada kehabisan tenaga.',
    ],
  ),
];

/// Bab Baru: Protokol Tersesat & Bertahan Hidup Multi-Hari (Wilderness Survival).
const List<FirstAidTopic> kWildernessSurvivalTopics = <FirstAidTopic>[
  FirstAidTopic(
    id: 'survival_stop_3jam',
    title: 'Prinsip STOP & Aturan Emas 3 Jam Pertama',
    category: 'Survival & Tersesat',
    summary:
        'Langkah krusial 3 jam pertama saat tersesat agar tidak jatuh ke tebing sungai gunung Indonesia.',
    isSurvivalChapter: true,
    dangerSigns: <String>[
      'Jejak jalur pendakian hilang total disertai kabut tebal atau hari mulai gelap.',
      'Anggota tim terpancing menuruni lembah sungai liar tanpa melihat tebing di bawah.',
      'Kepanikan memicu keputusan berpisah mencari jalur masing-masing.',
    ],
    firstAidSteps: <String>[
      'Terapkan urutan STOP (Stop, Think, Observe, Plan) segera setelah sadar keluar jalur untuk menghentikan kesalahan arah makin jauh.',
      'Hentikan seluruh pergerakan seketika bila kabut pekat, hujan deras, atau menjelang gelap agar tidak terperosok ke jurang.',
      'KHUSUS GUNUNG INDONESIA: JANGAN menuruni alur sungai liar karena sering berujung air terjun vertikal terjal dan batu lumut licin.',
      'Tetap diam di titik aman dekat lokasi terakhir atau naik perlahan ke punggungan terbuka saat hari terang untuk mendapat sinyal GPS dan jangkauan pandang SAR.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.survStopGolden3h,
      FieldSketchId.survNoFogNightWalk,
      FieldSketchId.survNoWildStreamDescent,
      FieldSketchId.survClimbRidgeDaylight,
    ],
    prohibitionsAndMyths: <String>[
      'MITOS BERBAHAYA: "Ikuti aliran sungai pasti tembus ke kampung". Di gunung tropis Indonesia, sungai hutan sering berakhir di tebing air terjun curam tanpa jalur keluar.',
      'JANGAN berpencar dari rombongan saat mencari jalur balik.',
    ],
  ),
  FirstAidTopic(
    id: 'survival_rule_of_3',
    title: 'Prioritas Survival (Aturan Angka 3 / Rule of 3)',
    category: 'Survival & Tersesat',
    summary:
        'Urutan prioritas bertahan hidup agar tenaga tidak terbuang mencari hal yang salah lebih dulu.',
    isSurvivalChapter: true,
    dangerSigns: <String>[
      'Suhu malam turun drastis sementara penyintas membuang energi mencari makanan sebelum membuat shelter.',
      'Stok air bersih menipis tanpa rencana penampungan hujan atau embun.',
    ],
    firstAidSteps: <String>[
      'Pahami hierarki Rule of 3: manusia rata-rata bertahan 3 jam tanpa perlindungan cuaca ekstrem, 3 hari tanpa air, dan 3 minggu tanpa makanan.',
      'Prioritas 3 JAM: fokus pertama adalah menahan angin/hujan, menjaga pakaian tetap kering, dan memutus kontak dingin tanah.',
      'Prioritas 3 HARI: kumpulkan dan murnikan air dari hujan, embun, atau sumber aman sebelum dehidrasi menurunkan fokus otak.',
      'Prioritas 3 MINGGU: hemat kalori dengan istirahat cukup di shelter sebelum memikirkan sumber makanan darurat.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.survRuleOf3Hierarchy,
      FieldSketchId.survRule3HoursShelter,
      FieldSketchId.survRule3DaysWater,
      FieldSketchId.survRule3WeeksFood,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN menghabiskan tenaga seharian berburu makanan saat malam dingin sudah dekat dan shelter belum berdiri.',
      'JANGAN menahan diri minum air bersih yang ada terlalu ketat sampai dehidrasi berat (minum sedikit tetapi teratur).',
    ],
  ),
  FirstAidTopic(
    id: 'survival_bivak_darurat',
    title: 'Membangun Shelter Darurat (Bivak Ponco & Alam)',
    category: 'Survival & Tersesat',
    summary:
        'Teknik membuat bivak A-frame / lean-to dan kasur daun kering 15-20 cm pemutus dingin tanah.',
    isSurvivalChapter: true,
    dangerSigns: <String>[
      'Angin kencang menyapu area punggungan tanpa perlindungan.',
      'Tanah camp lembap atau basah berisiko menyedot panas tubuh saat tidur malam.',
    ],
    firstAidSteps: <String>[
      'Pilih lokasi aman dari dahan rapuh dan cekungan air, lalu bentangkan tali ridgeline di antara dua batang pohon kokoh.',
      'Model A-Frame: sampirkan ponco/flysheet di atas tali ridgeline rendah dan pasak kedua sisi ke tanah untuk perlindungan penuh dari angin dua arah.',
      'Model Lean-To: ikat satu sisi atas ponco ke tali/dahan dan pasak sisi bawah rapat ke tanah menghadap arah datangnya angin dominan.',
      'WAJIB buat alas tidur (insulating bed) setebal 15-20 cm dari tumpukan daun kering, ranting kecil, dan pakis kering untuk memutus konduksi panas ke tanah lembap.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.survBivouacSiteWind,
      FieldSketchId.survBivouacAFrame,
      FieldSketchId.survBivouacLeanTo,
      FieldSketchId.survBivouacLeafBed15cm,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN tidur langsung di atas tanah atau hanya beralas plastik tipis tanpa lapisan daun kering tebal (tanah menyerap panas jauh lebih cepat daripada udara).',
      'JANGAN membangun bivak terlalu tinggi sehingga angin bebas masuk dari samping.',
    ],
  ),
  FirstAidTopic(
    id: 'survival_air_darurat',
    title: 'Mencari, Menampung, & Memurnikan Air',
    category: 'Survival & Tersesat',
    summary:
        'Cara mendapatkan air hujan, embun pagi, tumbuhan aman, penyaringan arang, dan perebusan.',
    isSurvivalChapter: true,
    dangerSigns: <String>[
      'Bibir pecah, pusing berdiri, dan urine sangat pekat atau tidak buang air >8 jam.',
      'Cairan tumbuhan berwarna putih susu, berbau menyengat, atau terasa pahit/gatal.',
    ],
    firstAidSteps: <String>[
      'Tadah hujan langsung menggunakan ponco atau flysheet yang dibentuk corong huruf V menuju botol atau wadah bersih.',
      'Kumpulkan embun pagi dari dedaunan rumput bersih memakai kain/kaos bersih lalu peras ke dalam botol.',
      'Air tumbuhan (rotan/liana): potong batang berdiameter sedang dan periksa airnya jernih tidak berbau tajam serta tidak bergetah putih susu.',
      'Saring air keruh melalui lapisan kerikil, pasir bersih, arang tumbuk, dan kain, lalu WAJIB rebus mendidih minimal 1-3 menit sebelum diminum.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.survWaterRainPoncho,
      FieldSketchId.survWaterMorningDew,
      FieldSketchId.survWaterSafeLiana,
      FieldSketchId.survWaterFilterBoil,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN minum urine, darah, atau air tumbuhan bergetah putih susu (beracun dan memperparah dehidrasi).',
      'JANGAN mengandalkan kain saring saja tanpa perebusan untuk menghilangkan bakteri/parasit gunung.',
    ],
  ),
  FirstAidTopic(
    id: 'survival_api_sar_baterai',
    title: 'Api di Hutan Lembap, Sinyal SAR, & Baterai HP',
    category: 'Survival & Tersesat',
    summary:
        'Teknik kayu kering inti (feather stick), sinyal darurat 3 repetisi, dan urutan hemat baterai HP.',
    isSurvivalChapter: true,
    dangerSigns: <String>[
      'Seluruh kayu permukaan basah kuyup oleh hujan dan baterai ponsel tersisa <25%.',
      'Terdengar suara helikopter atau tim pencari di kejauhan.',
    ],
    firstAidSteps: <String>[
      'Belah ranting mati (bukan kayu lapuk di tanah) menggunakan pisau/batu untuk mengambil bagian inti dalam yang masih kering, lalu serut tipis membentuk feather stick.',
      'Susun tinder kering di tengah kerucut ranting kecil (teepee) di atas alas batu/kulit kayu kering agar tidak menyerap lembap tanah.',
      'Kirim sinyal darurat internasional 3 repetisi tiap 1 menit: 3 tiupan peluit panjang, 3 kilatan senter ke langit/lereng seberang, atau 3 kepulan asap daun hijau saat siang.',
      'Urutan baterai HP: kunci koordinat GPS dahulu -> kirim atau antrekan Hiqeo SOS -> langsung aktifkan Mode Pesawat & penghemat baterai ekstrem.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.survFireFeatherStick,
      FieldSketchId.survFireTeepeeTinder,
      FieldSketchId.survSarSignal3x,
      FieldSketchId.survBatteryGpsSosAirplane,
    ],
    prohibitionsAndMyths: <String>[
      'JANGAN membiarkan layar HP menyala terus mencari sinyal di area blank-spot (menghabiskan baterai dalam hitungan jam).',
      'JANGAN meninggalkan api menyala tanpa sekat tanah/batu pembersih dari dedaunan kering sekitar.',
    ],
  ),
  FirstAidTopic(
    id: 'survival_mental_pangan',
    title: 'Ketahanan Mental & Pangan Darurat Multi-Hari',
    category: 'Survival & Tersesat',
    summary:
        'Menjaga ritme psikologis melawan panik, manajemen ransum, dan protokol ketat cegah keracunan tumbuhan.',
    isSurvivalChapter: true,
    dangerSigns: <String>[
      'Keputusasaan, apatis berat, atau nekat makan buah/jamur liar tanpa uji keamanan.',
      'Ransum tersisa dihabiskan sekaligus pada hari pertama karena panik.',
    ],
    firstAidSteps: <String>[
      'Bangun rutinitas kecil harian: periksa pengikat bivak pagi hari, keringkan kaus kaki, kumpulkan air, dan bunyikan sinyal SAR pada jadwal tetap untuk menjaga mental tetap terkendali.',
      'Bagi sisa makanan dan minuman menjadi porsi-porsi kecil terjadwal setiap beberapa jam; utamakan pasokan air sebelum makanan padat.',
      'Bila terpaksa menguji tumbuhan liar tak dikenal (hanya bila persediaan habis total): lakukan uji tempel kulit 15 menit -> sudut bibir 15 menit -> ujung lidah tanpa ditelan; hentikan seketika jika gatal, panas, atau pahit.',
      'PATUHI LARANGAN MUTLAK: jangan pernah memakan jamur liar apa pun maupun buah berwarna mencolok atau bergetah putih susu.',
    ],
    stepSketches: <FieldSketchId>[
      FieldSketchId.survMentalRoutine,
      FieldSketchId.survRationingWaterFood,
      FieldSketchId.survPlantPatchTest,
      FieldSketchId.survAvoidPoisonMushrooms,
    ],
    prohibitionsAndMyths: <String>[
      'DILARANG MUTLAK makan jamur liar gunung (banyak spesies beracun mematikan sulit dibedakan secara visual).',
      'MITOS BERBAHAYA: "Jika dimakan burung atau monyet berarti aman untuk manusia". Sistem pencernaan satwa liar berbeda dan tetap bisa beracun fatal bagi manusia.',
    ],
  ),
];

final List<FirstAidTopic> kAllSafetyTopics = <FirstAidTopic>[
  ...kFirstAidTopics,
  ...kWildernessSurvivalTopics,
];
