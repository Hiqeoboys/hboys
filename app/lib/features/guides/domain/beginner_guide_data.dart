import 'package:flutter/foundation.dart';

import 'field_sketch_spec.dart';

@immutable
class BeginnerGuideChapter {
  const BeginnerGuideChapter({
    required this.id,
    required this.filterLabel,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final String filterLabel;
  final String title;
  final String subtitle;
}

@immutable
class BeginnerGuideTopic {
  const BeginnerGuideTopic({
    required this.id,
    required this.chapterId,
    required this.title,
    required this.summary,
    required this.steps,
    this.isInteractiveTent = false,
  });

  final String id;
  final String chapterId;
  final String title;
  final String summary;
  final List<GuideStep> steps;
  final bool isInteractiveTent;
}

@immutable
class TentSetupSummary {
  const TentSetupSummary({
    required this.crewLabel,
    required this.stakesLabel,
    required this.guylineLabel,
    required this.ridgePoleNote,
    required this.overlay,
  });

  final String crewLabel;
  final String stakesLabel;
  final String guylineLabel;
  final String? ridgePoleNote;
  final FieldSketchOverlay overlay;
}

const List<BeginnerGuideChapter> kBeginnerChapters = <BeginnerGuideChapter>[
  BeginnerGuideChapter(
    id: 'ch1_packing',
    filterLabel: 'Bab 1: Packing',
    title: 'Bab 1: Persiapan & Sistem Packing',
    subtitle: 'Atur pakaian 3 lapis, zona beban carrier, dan seimbangkan air.',
  ),
  BeginnerGuideChapter(
    id: 'ch2_camp',
    filterLabel: 'Bab 2: Camp',
    title: 'Bab 2: Mendirikan Camp & Dapur Lapangan',
    subtitle: 'Pilih tapak aman, dirikan berbagai jenis tenda, dan masak aman.',
  ),
  BeginnerGuideChapter(
    id: 'ch3_trail',
    filterLabel: 'Bab 3: Jalur',
    title: 'Bab 3: Teknik Jalur & Etika Alam (Leave No Trace)',
    subtitle: 'Irama napas menanjak, setelan trekking pole, dan sanitasi gunung.',
  ),
];

/// Menghitung overlay teknis dan parameter dinamika tenda sesuai jenis & kapasitas.
TentSetupSummary tentSetupSummary(TentType type, TentSizeCategory size) {
  final (String crew, String stakes, String guyline, String? ridge) =
      switch (size) {
    TentSizeCategory.soloDuo1to2 => (
        type == TentType.trekkingPole ? '1 orang' : '1 orang',
        type == TentType.tunnel ? '6-8 pasak' : '4-6 pasak',
        'Rentang guyline 1,0-1,2 m',
        null,
      ),
    TentSizeCategory.smallGroup3to4 => (
        '2 orang saat tegakkan frame',
        type == TentType.tunnel ? '8-10 pasak' : '6-8 pasak',
        'Rentang guyline 1,5 m',
        'Pasang extra ridge pole atap teras (vestibule)',
      ),
    TentSizeCategory.family4to6 => (
        '2-3 orang saat tegakkan frame',
        '10-12 pasak',
        'Rentang guyline 2,0-2,5 m + tali badai tambahan',
        'Pasang extra ridge pole teras depan & belakang',
      ),
  };

  return TentSetupSummary(
    crewLabel: crew,
    stakesLabel: stakes,
    guylineLabel: guyline,
    ridgePoleNote: ridge,
    overlay: FieldSketchOverlay(
      personBadge: crew,
      stakesBadge: 'Min. $stakes',
      guylineSpanLabel: guyline,
      showVestibuleRidgePole: size != TentSizeCategory.soloDuo1to2,
      showExtraStormGuys: size == TentSizeCategory.family4to6,
      sizeTag: size.shortTag,
    ),
  );
}

/// Menghasilkan urutan langkah & sketsa tenda:
/// - Mengganti [size] pada [type] yang sama memakai ulang sketsa vektor dasar yang sama
///   dengan pembaruan [FieldSketchOverlay] & detail teks.
/// - Mengganti [type] menampilkan mekanik & sketsa khusus jenis tenda tersebut.
List<GuideStep> buildTentPitchingSteps(TentType type, TentSizeCategory size) {
  final summary = tentSetupSummary(type, size);
  final ov = summary.overlay;
  final isSmall = size == TentSizeCategory.soloDuo1to2;
  final isFamily = size == TentSizeCategory.family4to6;

  final List<GuideStep> typeSteps = switch (type) {
    TentType.domeCross => <GuideStep>[
        GuideStep(
          title: 'Bentangkan Inner & Pasak Ringan 4 Sudut',
          instruction:
              'Bentangkan footprint dan inner tenda (${size.label}) di lahan rata. Pasak ringan 4 sudut terlebih dahulu agar kain tidak terangkat angin saat rangka dipasang.',
          sketchId: FieldSketchId.domeCrossStep1Spread,
          tip: 'Pastikan ritsleting pintu tertutup rapat sebelum memasang frame.',
          overlay: ov,
        ),
        GuideStep(
          title: 'Rangkai 2 Frame Silang (X)',
          instruction:
              isSmall
                  ? 'Sambungkan kedua batang frame utama dengan teliti hingga tiap sambungan logam rapat penuh, lalu silangkan membentuk huruf X di atas inner.'
                  : 'Sambungkan kedua frame X yang lebih panjang. Untuk ukuran ${size.shortTag}, ${summary.ridgePoleNote!.toLowerCase()} sebagai penyangga atap teras.',
          sketchId: FieldSketchId.domeCrossStep2PolesX,
          tip: isSmall
              ? 'Jangan memaksa frame melengkung bila sambungan masih longgar.'
              : summary.ridgePoleNote,
          overlay: ov,
        ),
        GuideStep(
          title: 'Tegakkan Kubah & Kait Klip',
          instruction:
              'Masukkan ujung pin frame ke ring sudut berlawanan, lalu tegakkan (${summary.crewLabel}). Kaitkan klip inner dari puncak ke bawah agar beban merata.',
          sketchId: FieldSketchId.domeCrossStep3RaiseClip,
          tip: isSmall
              ? 'Dapat dilakukan 1 orang dengan menahan puncak frame secara perlahan.'
              : 'Kerjakan berdua dari sisi berlawanan agar frame panjang tidak patah.',
          overlay: ov,
        ),
        GuideStep(
          title: 'Pasang Flysheet & Rentang Guyline',
          instruction:
              'Tutupkan outer flysheet sejajar pintu, ikat tali velcro bagian dalam ke frame, lalu tarik guyline (${summary.guylineLabel}). Gunakan minimal ${summary.stakesLabel}.',
          sketchId: FieldSketchId.domeCrossStep4FlysheetGuyline,
          tip: isFamily
              ? 'Tambahkan guyline badai di sisi tengah dinding untuk tenda keluarga tinggi.'
              : 'Sisakan celah sirkulasi 5-8 cm antara inner dan outer agar bebas kondensasi.',
          overlay: ov,
        ),
      ],
    TentType.domeHub => <GuideStep>[
        GuideStep(
          title: 'Rakit Y-Frame / Hub Pusat',
          instruction:
              'Buka dan kunci semua sendi hub sentral Y-Frame (${size.label}) sampai tiap lengan terkunci lurus sempurna tanpa celah.',
          sketchId: FieldSketchId.domeHubStep1HubAssemble,
          tip: summary.ridgePoleNote ??
              'Tulang hub ringan sangat sensitif terhadap tekukan sudut tajam.',
          overlay: ov,
        ),
        GuideStep(
          title: 'Pasang Ujung Kaki ke Grommet & Tegakkan',
          instruction:
              'Masukkan ujung kaki Y-Frame ke sudut inner (${summary.crewLabel}), lalu angkat hub tengah dan jepitkan klip atau palang silang atas.',
          sketchId: FieldSketchId.domeHubStep2PoleInsert,
          tip: 'Pastikan ujung kaki tidak terselip keluar dari ring atau grommet.',
          overlay: ov,
        ),
        GuideStep(
          title: 'Tutup Flysheet, Ridge Pole, & Pasak',
          instruction:
              'Pasang flysheet dan palang teras bila ada, lalu bentangkan ${summary.guylineLabel.toLowerCase()} dengan total ${summary.stakesLabel}.',
          sketchId: FieldSketchId.domeHubStep3ClipFly,
          tip: summary.ridgePoleNote ??
              'Tenda hub butuh tarikan pasak teras depan agar ruang simpan tas luas.',
          overlay: ov,
        ),
      ],
    TentType.tunnel => <GuideStep>[
        GuideStep(
          title: 'Pasak Kuat Ujung Ekor Belakang Terlebih Dahulu',
          instruction:
              'Tenda tunnel bukan tipe berdiri bebas (non-freestanding). Wajib pasak 2 sudut ujung belakang terlebih dahulu agar tenda memiliki jangkar tarik (${size.label}).',
          sketchId: FieldSketchId.tunnelStep1RearStake,
          warning: 'Jangan memasang frame sebelum ujung ekor dipasak kuat.',
          overlay: ov,
        ),
        GuideStep(
          title: 'Masukkan Frame Lengkung ke Sleeve',
          instruction:
              'Selipkan tiap batang frame lengkung ke dalam selongsong (sleeve) secara berurutan dari belakang ke depan (${summary.crewLabel}).',
          sketchId: FieldSketchId.tunnelStep2Hoops,
          tip: 'Dorong batang frame dari belakang, jangan menarik agar sambungan tidak lepas.',
          overlay: ov,
        ),
        GuideStep(
          title: 'Tarik Ujung Depan Tegang & Kencangkan Guyline',
          instruction:
              'Tarik ujung depan hingga seluruh lengkungan berdiri tegak membentuk terowongan, lalu pasak sudut depan dan ${summary.guylineLabel.toLowerCase()} (${summary.stakesLabel}).',
          sketchId: FieldSketchId.tunnelStep3PullFront,
          tip: 'Hadapkan bagian ekor terowongan yang lebih rendah ke arah angin datang.',
          overlay: ov,
        ),
      ],
    TentType.trekkingPole => <GuideStep>[
        GuideStep(
          title: 'Pasak 4 Sudut Dasar Terlebih Dahulu',
          instruction:
              'Bentangkan kain piramida (${size.label}) rata di tanah lalu pasak kuat keempat sudut utamanya terlebih dahulu.',
          sketchId: FieldSketchId.trekkingPoleStep1FourCorners,
          tip: 'Pastikan bentuk persegi simetris sebelum tiang didirikan.',
          overlay: ov,
        ),
        GuideStep(
          title: 'Tegakkan Trekking Pole di Puncak',
          instruction:
              'Atur tinggi trekking pole sesuai spesifikasi tenda (atau gabungkan 2 tiang pada ukuran ${size.shortTag}), masukkan ke puncak berpelindung dan tegakkan (${summary.crewLabel}).',
          sketchId: FieldSketchId.trekkingPoleStep2CenterPole,
          warning: 'Gunakan pelindung ujung runcing atau pasang gagang di atas agar kain tidak sobek.',
          overlay: ov,
        ),
        GuideStep(
          title: 'Tarik Guyline Keliling Hingga Tegang',
          instruction:
              'Tarik tali guyline utama dan sisi samping (${summary.guylineLabel}) dengan total ${summary.stakesLabel} sampai dinding kain kencang tanpa kerutan.',
          sketchId: FieldSketchId.trekkingPoleStep3GuylineTension,
          tip: 'Cek ulang ketegangan guyline setelah 30 menit saat kain nilon mulai kendur.',
          overlay: ov,
        ),
      ],
  };

  return <GuideStep>[
    ...typeSteps,
    const GuideStep(
      title: 'Close-Up Teknik Pasak 45 Derajat',
      instruction:
          'Tanam pasak miring 45° menjauh dari badan tenda agar gaya tarik tali guyline menekan pasak lebih dalam ke tanah. Hindari menancap pasak tegak 90° karena mudah tercabut saat diterpa angin.',
      sketchId: FieldSketchId.tentStake45Vs90,
      tip: '45° Kuat ✓: gaya tarik membentuk sudut tahan terhadap tanah.',
      warning: '90° Tegak Mudah Cabut ✗: pasak mudah miring dan terlepas ditarik angin.',
    ),
  ];
}

const List<BeginnerGuideTopic> kBeginnerGuideTopics = <BeginnerGuideTopic>[
  // BAB 1 — PERSIAPAN & SISTEM PACKING
  BeginnerGuideTopic(
    id: 'layering',
    chapterId: 'ch1_packing',
    title: 'Sistem Pakaian 3 Lapis (Layering)',
    summary:
        'Cara mengatur lapisan pakaian agar tetap hangat tanpa basah keringat di gunung tropis.',
    steps: <GuideStep>[
      GuideStep(
        title: 'Base Layer (Lapisan Dasar)',
        instruction:
            'Kenakan bahan sintetis (polyester/nylon quick-dry) atau merino wool yang menyerap dan menguapkan keringat dengan cepat.',
        sketchId: FieldSketchId.layeringBase,
        tip: 'Pilih potongan pas di badan agar uap lembap cepat keluar.',
        warning:
            'Dilarang memakai kaos katun atau celana jeans ✗ karena menyerap air dan memicu hipotermia saat berhenti.',
      ),
      GuideStep(
        title: 'Mid Layer (Lapisan Penahan Hangat)',
        instruction:
            'Gunakan jaket fleece atau jaket down/bulu angsa di pos istirahat atau suhu dingin camp untuk memerangkap udara hangat tubuh.',
        sketchId: FieldSketchId.layeringMid,
        tip: 'Lepas mid layer saat mulai berkeringat di tanjakan curam.',
      ),
      GuideStep(
        title: 'Outer Shell (Jaket Pelindung Angin & Hujan)',
        instruction:
            'Gunakan jaket waterproof-windproof dengan seam sealed di lapisan terluar untuk menahan hujan deras dan angin punggungan.',
        sketchId: FieldSketchId.layeringOuter,
        tip: 'Buka ritsleting ketiak (pit zip) jika tersedia agar uap panas tetap keluar.',
      ),
    ],
  ),
  BeginnerGuideTopic(
    id: 'carrier_packing',
    chapterId: 'ch1_packing',
    title: 'Menyusun Beban Carrier (4 Zona Tas)',
    summary:
        'Penempatan barang di 4 zona carrier agar pusat gravitasi rapat ke tulang belakang.',
    steps: <GuideStep>[
      GuideStep(
        title: 'Zona Dasar (Paling Bawah)',
        instruction:
            'Isi bagian terbawah dengan barang ringan namun bervolume besar: sleeping bag, matras tiup, dan baju tidur kering di dalam dry bag.',
        sketchId: FieldSketchId.carrierZoneBottom,
        tip: 'Berikan lapisan plastik/trash bag di dinding dalam tas sebagai pelindung air ganda.',
      ),
      GuideStep(
        title: 'Zona Tengah Rapat Punggung (Pusat Berat)',
        instruction:
            'Taruh barang paling berat (tenda, stok air utama, dan logistik berat) menempel lurus di sepanjang punggung tas agar pusat gravitasi dekat tulang belakang.',
        sketchId: FieldSketchId.carrierZoneCoreBack,
        tip: 'Beban berat di dekat punggung mencegah bahu tertarik ke belakang.',
      ),
      GuideStep(
        title: 'Zona Tengah Sisi Luar',
        instruction:
            'Susun barang berbobot sedang di bagian luar zona tengah: kompor, nesting/alat masak, makanan ringan, dan jaket cadangan.',
        sketchId: FieldSketchId.carrierZoneMidOuter,
        tip: 'Gunakan jaket cadangan untuk mengisi celah kosong agar beban tidak bergeser.',
      ),
      GuideStep(
        title: 'Zona Top Lid & Hip Belt (Akses Cepat)',
        instruction:
            'Letakkan peralatan yang sering dipakai mendadak di tutup atas (top lid) dan saku pinggang: jas hujan, P3K, headlamp, tisu, dan camilan.',
        sketchId: FieldSketchId.carrierZoneTopHip,
        tip: 'Pastikan bobot terbanyak bertumpu di hip belt pinggul, bukan di pundak.',
      ),
    ],
  ),
  BeginnerGuideTopic(
    id: 'water_logistics',
    chapterId: 'ch1_packing',
    title: 'Manajemen Air & Logistik Jalur',
    summary:
        'Membagi botol kiri-kanan seimbang dan memisahkan camilan cepat dari logistik camp.',
    steps: <GuideStep>[
      GuideStep(
        title: 'Seimbangkan Botol Kiri & Kanan',
        instruction:
            'Bagi air ke dua botol di saku kiri dan kanan (misalnya 1 L kiri + 1 L kanan) atau pasang water bladder di kompartemen tengah punggung.',
        sketchId: FieldSketchId.waterBalanceLeftRight,
        tip: 'Beban kanan-kiri yang timpang membuat pinggang dan lutut cepat pegal.',
      ),
      GuideStep(
        title: 'Pastikan Air Mudah Dijangkau Sambil Jalan',
        instruction:
            'Taruh air minum harian di saku luar yang mudah diraih atau pakai selang hidrasi tanpa perlu melepas carrier.',
        sketchId: FieldSketchId.waterHydrationAccess,
        warning: 'Jangan menaruh seluruh cadangan air di dasar carrier yang sulit diambil.',
      ),
      GuideStep(
        title: 'Pisahkan Camilan Energi Cepat & Logistik Camp',
        instruction:
            'Simpan gula cepat serap (kurma, madu, trail mix, elektrolit) di hip belt, sedangkan bahan masak camp dibungkus terpisah di dalam carrier.',
        sketchId: FieldSketchId.logisticsQuickVsCamp,
        tip: 'Minum 2-3 teguk tiap 20 menit daripada menunggu haus berat.',
      ),
    ],
  ),

  // BAB 2 — MENDIRIKAN CAMP & DAPUR LAPANGAN
  BeginnerGuideTopic(
    id: 'tent_site',
    chapterId: 'ch2_camp',
    title: 'Memilih & Menyiapkan Tapak Tenda',
    summary:
        'Menghindari genangan hujan, dahan rapuh, terpaan angin langsung, dan rembesan footprint.',
    steps: <GuideStep>[
      GuideStep(
        title: 'Lahan Datar Sedikit Tinggi (Bebas Aliran Air)',
        instruction:
            'Pilih tanah datar yang posisinya sedikit lebih tinggi dari cekungan sekitarnya agar air hujan mengalir menjauh ke bawah.',
        sketchId: FieldSketchId.campSiteHighFlat,
        warning: 'Hindari dasar cekungan atau bekas aliran sungai kering yang berisiko tergenang saat hujan.',
      ),
      GuideStep(
        title: 'Periksa Tajuk Pohon di Atas (Widowmaker)',
        instruction:
            'Dongakkan kepala dan periksa ranting mati, pohon lapuk, atau batu menggantung tepat di atas area tenda sebelum membuka carrier.',
        sketchId: FieldSketchId.campSiteOverheadCheck,
        warning: 'Jangan mendirikan tenda di bawah dahan kering yang bisa jatuh saat angin malam.',
      ),
      GuideStep(
        title: 'Hadapkan Pintu Membelakangi Angin Dominan',
        instruction:
            'Arahkan bagian belakang tenda yang paling aerodinamis menghadap datangnya angin, sehingga pintu tenda berada di sisi teduh.',
        sketchId: FieldSketchId.campSiteWindDoor,
        tip: 'Amati gerak rumput atau kabut untuk membaca arah angin dominan.',
      ),
      GuideStep(
        title: 'Atur Ukuran Footprint 3-5 cm Lebih Kecil',
        instruction:
            'Lipat tepi alas footprint agar 3-5 cm lebih kecil di dalam garis lantai tenda, supaya footprint tidak menampung genangan air hujan.',
        sketchId: FieldSketchId.campSiteFootprintMargin,
        warning: 'Footprint yang menyembul keluar tenda akan menyalurkan air masuk ke bawah lantai.',
      ),
    ],
  ),
  BeginnerGuideTopic(
    id: 'pitch_tent',
    chapterId: 'ch2_camp',
    title: 'Cara Mendirikan Tenda (Pilih Jenis & Ukuran)',
    summary:
        'Panduan adaptif berbagai konstruksi tenda, jumlah kru, pasak, dan teknik pasak 45°.',
    isInteractiveTent: true,
    steps: <GuideStep>[],
  ),
  BeginnerGuideTopic(
    id: 'field_kitchen',
    chapterId: 'ch2_camp',
    title: 'Dapur Lapangan yang Aman',
    summary:
        'Jarak aman kompor dari tenda, bahaya keracunan gas CO, dan posisi tabung stabil.',
    steps: <GuideStep>[
      GuideStep(
        title: 'Jaga Jarak Kompor Minimal 2-3 Meter dari Tenda',
        instruction:
            'Masak di area terbuka berjarak 2-3 meter di sisi hilir angin dari tenda agar percikan api atau minyak tidak melubangi kain nilon.',
        sketchId: FieldSketchId.kitchenSafeDistance,
        tip: 'Gunakan windshield lipat rendah jika angin cukup kencang.',
      ),
      GuideStep(
        title: 'Larangan Memasak di Dalam Tenda Tertutup',
        instruction:
            'Dilarang keras menyalakan kompor di dalam inner tenda atau vestibule tertutup rapat karena menumpuk gas beracun karbon monoksida (CO) tak berbau.',
        sketchId: FieldSketchId.kitchenNoClosedTentCo,
        warning: 'Risiko fatal keracunan CO dan kebakaran tenda dalam hitungan detik ✗.',
      ),
      GuideStep(
        title: 'Letakkan Tabung Gas di Permukaan Datar & Stabil',
        instruction:
            'Pastikan kaki kompor dan tabung gas berdiri rata di tanah keras atau papan batu datar sebelum menyalakan pemantik.',
        sketchId: FieldSketchId.kitchenFlatCanister,
        tip: 'Pasang stabilizer kaki tabung atau ganjal dengan batu rata jika tanah berpasir.',
      ),
    ],
  ),

  // BAB 3 — TEKNIK JALUR & ETIKA ALAM
  BeginnerGuideTopic(
    id: 'pace_breathing',
    chapterId: 'ch3_trail',
    title: 'Irama Langkah & Napas di Tanjakan',
    summary:
        'Menjaga daya tahan otot dengan langkah pendek konsisten (rest step) dan ritme napas.',
    steps: <GuideStep>[
      GuideStep(
        title: 'Langkah Pendek Konsisten (Rest Step)',
        instruction:
            'Ambil langkah kecil setinggi mata kaki namun stabil terus-menerus. Hindari langkah lebar cepat yang memicu penumpukan asam laktat di paha.',
        sketchId: FieldSketchId.paceRestStepVsWide,
        tip: 'Kunci sendi lutut kaki belakang selama setengah detik tiap melangkah agar otot beristirahat singkat.',
      ),
      GuideStep(
        title: 'Sinkronkan Ritme Napas dengan Langkah',
        instruction:
            'Gunakan pola tarik napas 2 langkah dan hembuskan 2 langkah (atau 1:1 di tanjakan ekstrem) agar pasokan oksigen tetap stabil.',
        sketchId: FieldSketchId.paceBreathingRhythm,
        tip: 'Bila tidak bisa berbicara 1 kalimat utuh sambil jalan, perlambat ritme langkah.',
      ),
      GuideStep(
        title: 'Jeda Berdiri Singkat, Jangan Duduk Terlalu Lama',
        instruction:
            'Ambil jeda berdiri 30-60 detik setiap 20 menit untuk minum dan atur napas tanpa melepas carrier, agar otot kaki tidak kaku mendingin.',
        sketchId: FieldSketchId.paceMicroBreak,
        tip: 'Istirahat duduk penuh 10-15 menit cukup dilakukan setiap 1,5-2 jam.',
      ),
    ],
  ),
  BeginnerGuideTopic(
    id: 'trekking_pole',
    chapterId: 'ch3_trail',
    title: 'Teknik Trekking Pole Menanjak vs Menurun',
    summary:
        'Penyesuaian panjang tongkat saat datar (siku 90°), menanjak, dan menurun curam.',
    steps: <GuideStep>[
      GuideStep(
        title: 'Setel Awal Sudut Siku 90° di Medan Datar',
        instruction:
            'Berdiri tegak di permukaan datar, pegang grip trekking pole dengan ujung menyentuh tanah, lalu setel panjang hingga sudut siku tepat 90°.',
        sketchId: FieldSketchId.poleFlat90Deg,
        tip: 'Masukkan telapak tangan dari bawah ke tali strap agar berat ditahan pergelangan.',
      ),
      GuideStep(
        title: 'Pendekkan 5-10 cm Saat Menanjak',
        instruction:
            'Kurangi panjang pole sekitar 5-10 cm sebelum tanjakan panjang agar bahu tidak terangkat tinggi saat mendorong tubuh ke atas.',
        sketchId: FieldSketchId.poleUphillShorten,
        tip: 'Tancapkan pole di depan seiring langkah kaki berlawanan.',
      ),
      GuideStep(
        title: 'Panjangkan 5-10 cm Saat Menurun',
        instruction:
            'Tambahkan panjang pole 5-10 cm saat turunan curam untuk menjangkau pijakan bawah terlebih dahulu dan menyerap hingga 25% beban lutut.',
        sketchId: FieldSketchId.poleDownhillLengthen,
        tip: 'Periksa kunci pengatur tinggi (flick-lock/twist-lock) benar-benar rapat.',
      ),
    ],
  ),
  BeginnerGuideTopic(
    id: 'trail_etiquette',
    chapterId: 'ch3_trail',
    title: 'Etika Jalur & Sanitasi Gunung (Leave No Trace)',
    summary:
        'Prioritas berpapasan di jalur sempit, membawa turun 100% sampah, dan jarak aman cathole.',
    steps: <GuideStep>[
      GuideStep(
        title: 'Prioritas Jalur untuk Pendaki yang Menanjak',
        instruction:
            'Saat berpapasan di jalur sempit, pendaki yang sedang turun menepi memberi jalan bagi pendaki yang sedang menanjak.',
        sketchId: FieldSketchId.etiquetteRightOfWay,
        tip: 'Menepilah ke sisi tebing dalam, bukan ke tepi jurang yang rapuh.',
      ),
      GuideStep(
        title: 'Bawa Turun 100% Sampah & Sisa Tisu',
        instruction:
            'Simpan seluruh bungkus makanan, botol, kulit buah, hingga tisu basah ke dalam kantong sampah khusus di carrier.',
        sketchId: FieldSketchId.etiquetteCarryTrash,
        warning: 'Jangan membakar plastik atau meninggalkan tisu basah di semak ✗.',
      ),
      GuideStep(
        title: 'Gali Lubang Sanitasi (Cathole) Min. 60-70 m dari Air',
        instruction:
            'Jauhi sumber air, aliran sungai, dan jalur pendakian minimal 60-70 meter (sekitar 70 langkah dewasa). Gali lubang sedalam 15-20 cm lalu tutup kembali tanahnya rapat.',
        sketchId: FieldSketchId.etiquetteCathole60m,
        tip: 'Tisu toilet sebaiknya dimasukkan ke plastik zip-lock untuk dibawa turun.',
      ),
    ],
  ),
];
