import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/field_sketch_spec.dart';
import 'field_sketch_tokens.dart';

/// Menggambar seluruh ilustrasi teknis untuk Bab Baru Wilderness Survival (6 topik x 4 langkah).
void paintSurvivalSketch(Canvas canvas, FieldSketchId id) {
  switch (id) {
    case FieldSketchId.survStopGolden3h:
      _drawStopGolden3h(canvas);
    case FieldSketchId.survNoFogNightWalk:
      _drawNoFogNightWalk(canvas);
    case FieldSketchId.survNoWildStreamDescent:
      _drawNoWildStream(canvas);
    case FieldSketchId.survClimbRidgeDaylight:
      _drawClimbRidgeDaylight(canvas);
    case FieldSketchId.survRuleOf3Hierarchy:
      _drawRuleOf3Hierarchy(canvas);
    case FieldSketchId.survRule3HoursShelter:
      _drawRuleOf3Detail(canvas, 1, '3 JAM : Cuaca & Hipotermia', 'Prioritas 1: Shelter & kering sebelum gelap');
    case FieldSketchId.survRule3DaysWater:
      _drawRuleOf3Detail(canvas, 2, '3 HARI : Kebutuhan Air Bersih', 'Prioritas 2: Tampung hujan, embun, & rebus air');
    case FieldSketchId.survRule3WeeksFood:
      _drawRuleOf3Detail(canvas, 3, '3 MINGGU : Daya Tahan Tanpa Makan', 'Prioritas 3: Hemat kalori, jangan buru-buru cari makan');
    case FieldSketchId.survBivouacSiteWind:
      _drawBivouacSiteWind(canvas);
    case FieldSketchId.survBivouacAFrame:
      _drawBivouacAFrame(canvas);
    case FieldSketchId.survBivouacLeanTo:
      _drawBivouacLeanTo(canvas);
    case FieldSketchId.survBivouacLeafBed15cm:
      _drawBivouacLeafBed(canvas);
    case FieldSketchId.survWaterRainPoncho:
      _drawWaterRainPoncho(canvas);
    case FieldSketchId.survWaterMorningDew:
      _drawWaterMorningDew(canvas);
    case FieldSketchId.survWaterSafeLiana:
      _drawWaterSafeLiana(canvas);
    case FieldSketchId.survWaterFilterBoil:
      _drawWaterFilterBoil(canvas);
    case FieldSketchId.survFireFeatherStick:
      _drawFireFeatherStick(canvas);
    case FieldSketchId.survFireTeepeeTinder:
      _drawFireTeepeeTinder(canvas);
    case FieldSketchId.survSarSignal3x:
      _drawSarSignal3x(canvas);
    case FieldSketchId.survBatteryGpsSosAirplane:
      _drawBatteryWorkflow(canvas);
    case FieldSketchId.survMentalRoutine:
      _drawMentalRoutine(canvas);
    case FieldSketchId.survRationingWaterFood:
      _drawRationing(canvas);
    case FieldSketchId.survPlantPatchTest:
      _drawPlantPatchTest(canvas);
    case FieldSketchId.survAvoidPoisonMushrooms:
      _drawAvoidPoisonMushrooms(canvas);
    default:
      break;
  }
}

void _drawStopGolden3h(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 101);
  final labels = <(String, String)>[
    ('S', 'Stop'),
    ('T', 'Think'),
    ('O', 'Observe'),
    ('P', 'Plan'),
  ];
  for (var i = 0; i < 4; i++) {
    final x = 62.0 + i * 92.0;
    canvas.drawCircle(
      Offset(x, 102),
      26,
      FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      labels[i].$1,
      Offset(x, 90),
      align: TextAlign.center,
      color: FieldSketchPalette.sage,
      fontSize: 17,
      withBacking: false,
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      labels[i].$2,
      Offset(x, 136),
      align: TextAlign.center,
      color: FieldSketchPalette.ink,
    );
    if (i < 3) {
      FieldSketchPrimitives.drawArrow(
        canvas,
        Offset(x + 30, 102),
        Offset(x + 60, 102),
        color: FieldSketchPalette.sage,
      );
    }
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Aturan Emas 3 Jam Pertama: Jangan habiskan tenaga tanpa arah',
    const Offset(200, 188),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 340,
  );
}

void _drawNoFogNightWalk(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 102);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 182), Offset(180, 182), Offset(216, 224), Offset(384, 224)],
    bottomY: 234,
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(164, 96), r: 12);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kabut Pekat / Gelap: BERHENTI & BERMALAM ✓',
    const Offset(200, 44),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 330,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Terobos kabut/malam berisiko jatuh ke tebing/jurang ✗',
    const Offset(248, 134),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 190,
  );
}

void _drawNoWildStream(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 103);
  // Penampang sungai gunung curam jatuh ke air terjun terjal (Indonesia-specific warning)
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[
      Offset(24, 72),
      Offset(152, 106),
      Offset(164, 206),
      Offset(368, 226),
    ],
    bottomY: 236,
  );
  // Air jatuh vertikal terjal
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(166, 108),
    const Offset(166, 204),
    color: FieldSketchPalette.coral,
    width: 2.2,
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(166, 78), r: 11);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'JANGAN Susuri Sungai Liar!\nRisiko Air Terjun & Jurang Licin ✗',
    const Offset(274, 76),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 175,
  );
}

void _drawClimbRidgeDaylight(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 104);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 192), Offset(188, 92), Offset(384, 152)],
    bottomY: 230,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(66, 154),
    const Offset(166, 94),
    color: FieldSketchPalette.sage,
    width: 2.4,
  );
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(188, 68), r: 10);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Saat Terang: Naik ke Punggungan Terbuka (Ridge) ✓',
    const Offset(274, 52),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 190,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Sinyal GPS/HP & visibilitas tim SAR jauh lebih baik',
    const Offset(274, 104),
    align: TextAlign.center,
    color: FieldSketchPalette.ink,
    fontSize: 9.2,
    maxWidth: 190,
  );
}

void _drawRuleOf3Hierarchy(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 105);
  // Piramida Prioritas Rule of 3
  final tiers = <(Rect, String, Color)>[
    (const Rect.fromLTRB(124, 38, 276, 86), '1. 3 JAM : Shelter / Panas', FieldSketchPalette.sage),
    (const Rect.fromLTRB(92, 96, 308, 144), '2. 3 HARI : Kebutuhan Air', FieldSketchPalette.ink),
    (const Rect.fromLTRB(60, 154, 340, 202), '3. 3 MINGGU : Tanpa Makanan', FieldSketchPalette.inkSoft),
  ];
  for (final (rect, label, color) in tiers) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      FieldSketchPrimitives.inkPaint(width: 2.0, color: color),
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      label,
      Offset(rect.center.dx, rect.center.dy - 8),
      align: TextAlign.center,
      color: color,
      withBacking: false,
    );
  }
}

void _drawRuleOf3Detail(Canvas canvas, int tier, String title, String sub) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 105 + tier);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(68, 62, 332, 178),
      const Radius.circular(18),
    ),
    FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    title,
    const Offset(200, 92),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    fontSize: 12,
    maxWidth: 240,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    sub,
    const Offset(200, 134),
    align: TextAlign.center,
    color: FieldSketchPalette.ink,
    fontSize: 10,
    bold: false,
    maxWidth: 240,
  );
}

void _drawBivouacSiteWind(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 110);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 228,
  );
  FieldSketchPrimitives.drawPineTree(canvas, const Offset(84, 188), height: 92);
  FieldSketchPrimitives.drawPineTree(canvas, const Offset(316, 188), height: 92);
  FieldSketchPrimitives.drawCurvedWindArrow(
    canvas,
    const Offset(22, 64),
    const Offset(74, 54),
    const Offset(110, 74),
    const Offset(154, 62),
    color: FieldSketchPalette.inkSoft,
  );
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(84, 128),
    const Offset(316, 128),
    color: FieldSketchPalette.sage,
    width: 2.0,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Bentang Tali Ridgeline di Antara 2 Pohon Kuat ✓',
    const Offset(200, 98),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 260,
  );
}

void _drawBivouacAFrame(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 111);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 228,
  );
  final aFrame = Path()
    ..moveTo(106, 188)
    ..lineTo(200, 76)
    ..lineTo(294, 188);
  canvas.drawPath(aFrame, FieldSketchPrimitives.inkPaint(width: 2.4, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawStake(canvas, const Offset(92, 184), math.pi * 0.25, 24);
  FieldSketchPrimitives.drawStake(canvas, const Offset(308, 184), math.pi * 0.75, 24);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Bivak A-Frame (Ponco / Flysheet) ✓',
    const Offset(200, 44),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Tutup rendah agar panas tubuh terperangkap',
    const Offset(200, 204),
    align: TextAlign.center,
    color: FieldSketchPalette.ink,
  );
}

void _drawBivouacLeanTo(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 112);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 228,
  );
  FieldSketchPrimitives.drawCurvedWindArrow(
    canvas,
    const Offset(26, 98),
    const Offset(72, 88),
    const Offset(104, 108),
    const Offset(146, 96),
    color: FieldSketchPalette.inkSoft,
  );
  canvas.drawLine(
    const Offset(132, 188),
    const Offset(282, 92),
    FieldSketchPrimitives.inkPaint(width: 2.6, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Bivak Lean-To: Sisi Rendah Hadap Angin ✓',
    const Offset(228, 52),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 260,
  );
}

void _drawBivouacLeafBed(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 113);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 198), Offset(384, 198)],
    bottomY: 230,
  );
  // Kasur daun / pakis kering tebal 15-20 cm di atas tanah dingin
  const bed = Rect.fromLTRB(76, 146, 324, 194);
  FieldSketchPrimitives.drawCrossHatch(
    canvas,
    Path()..addRect(bed),
    bed,
    spacing: 5.5,
    color: FieldSketchPalette.sage.withValues(alpha: 0.45),
  );
  canvas.drawRect(bed, FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(342, 146),
    const Offset(342, 194),
    color: FieldSketchPalette.sage,
    doubleHead: true,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    '15-20 cm',
    const Offset(348, 162),
    color: FieldSketchPalette.sage,
    fontSize: 9.5,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Alas Daun / Pakis Kering Tebal: Putus Konduksi Dingin Tanah ✓',
    const Offset(200, 62),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 330,
  );
}

void _drawWaterRainPoncho(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 114);
  // Ponco membentuk corong V ke botol tampung
  canvas.drawPath(
    Path()
      ..moveTo(86, 82)
      ..lineTo(200, 134)
      ..lineTo(314, 82),
    FieldSketchPrimitives.inkPaint(width: 2.3, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(200, 136),
    const Offset(200, 162),
    color: FieldSketchPalette.sage,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(174, 164, 226, 214),
      const Radius.circular(8),
    ),
    FieldSketchPrimitives.inkPaint(width: 2.0),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Tampung Air Hujan Dengan Ponco ✓',
    const Offset(200, 42),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawWaterMorningDew(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 115);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 184), Offset(384, 184)],
    bottomY: 226,
  );
  for (var i = 0; i < 6; i++) {
    final x = 76.0 + i * 48.0;
    canvas.drawLine(
      Offset(x, 184),
      Offset(x - 10, 134),
      FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage),
    );
    canvas.drawCircle(Offset(x - 10, 134), 3, Paint()..color = FieldSketchPalette.sage);
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kumpulkan Embun Pagi Pakai Kain Bersih Lalu Peras ✓',
    const Offset(200, 62),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
}

void _drawWaterSafeLiana(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 116);
  // Batang rotan/liana air jernih ✓ vs getah putih pekat ✗
  canvas.drawRect(
    const Rect.fromLTRB(62, 92, 166, 128),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(114, 68), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Rotan / Liana: Air Jernih Tanpa Bau Tajam ✓',
    const Offset(114, 146),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 160,
  );

  canvas.drawRect(
    const Rect.fromLTRB(234, 92, 338, 128),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.coral),
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(286, 68), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Getah Putih / Susu / Pahit Beracun ✗',
    const Offset(286, 146),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 160,
  );
}

void _drawWaterFilterBoil(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 117);
  // Botol corong 3 lapisan: Kerikil/Pasir -> Arang -> Kain
  final layers = <(Rect, String)>[
    (const Rect.fromLTRB(126, 48, 274, 82), '1. Kerikil & Pasir Bersih'),
    (const Rect.fromLTRB(126, 86, 274, 120), '2. Arang Kayu Tumbuk'),
    (const Rect.fromLTRB(126, 124, 274, 158), '3. Kain / Kapas Saring'),
  ];
  for (final (r, lbl) in layers) {
    canvas.drawRect(r, FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage));
    FieldSketchPrimitives.drawLabel(
      canvas,
      lbl,
      Offset(200, r.center.dy - 7),
      align: TextAlign.center,
      withBacking: false,
      fontSize: 9.5,
    );
  }
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(200, 162),
    const Offset(200, 188),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'WAJIB Rebus Mendidih 1-3 Menit Sebelum Diminum ✓',
    const Offset(200, 196),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 340,
  );
}

void _drawFireFeatherStick(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 118);
  // Ranting luar basah dibelah -> inti kayu kering diserut tipis (feather stick)
  canvas.drawRect(
    const Rect.fromLTRB(78, 118, 224, 148),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  for (var i = 0; i < 4; i++) {
    final x = 224.0 + i * 16.0;
    canvas.drawPath(
      Path()
        ..moveTo(x, 122)
        ..quadraticBezierTo(x + 16, 102, x + 22, 114),
      FieldSketchPrimitives.inkPaint(width: 1.6, color: FieldSketchPalette.sage),
    );
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Belah Ranting Mati -> Ambil Inti Kering & Serut Feather Stick ✓',
    const Offset(200, 56),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 340,
  );
}

void _drawFireTeepeeTinder(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 119);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 226,
  );
  // Kerucut ranting teepee
  canvas.drawLine(const Offset(146, 188), const Offset(200, 82), FieldSketchPrimitives.inkPaint(width: 2.2));
  canvas.drawLine(const Offset(254, 188), const Offset(200, 82), FieldSketchPrimitives.inkPaint(width: 2.2));
  canvas.drawLine(const Offset(174, 188), const Offset(212, 92), FieldSketchPrimitives.inkPaint(width: 1.8));
  canvas.drawCircle(const Offset(200, 166), 18, FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Susunan Teepee + Tinder Kering di Tengah ✓',
    const Offset(200, 44),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawSarSignal3x(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 120);
  for (var i = 0; i < 3; i++) {
    final x = 92.0 + i * 108.0;
    canvas.drawCircle(
      Offset(x, 108),
      26,
      FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage),
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      '3x',
      Offset(x, 97),
      align: TextAlign.center,
      color: FieldSketchPalette.sage,
      fontSize: 15,
      withBacking: false,
    );
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Peluit Panjang',
    const Offset(92, 146),
    align: TextAlign.center,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kilat Senter',
    const Offset(200, 146),
    align: TextAlign.center,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kepulan Asap',
    const Offset(308, 146),
    align: TextAlign.center,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kode Darurat SAR Internasional: 3 Repetisi Tiap 1 Menit ✓',
    const Offset(200, 192),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 340,
  );
}

void _drawBatteryWorkflow(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 121);
  final steps = <(String, String)>[
    ('1. Kunci GPS', 'Catat koordinat'),
    ('2. Hiqeo SOS', 'Kirim / antre SMS'),
    ('3. Airplane', 'Hemat baterai ekstrem'),
  ];
  for (var i = 0; i < 3; i++) {
    final x = 74.0 + i * 126.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, 114), width: 96, height: 64),
        const Radius.circular(12),
      ),
      FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      steps[i].$1,
      Offset(x, 96),
      align: TextAlign.center,
      color: FieldSketchPalette.sage,
      withBacking: false,
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      steps[i].$2,
      Offset(x, 120),
      align: TextAlign.center,
      fontSize: 9.0,
      withBacking: false,
    );
    if (i < 2) {
      FieldSketchPrimitives.drawArrow(
        canvas,
        Offset(x + 50, 114),
        Offset(x + 74, 114),
        color: FieldSketchPalette.sage,
      );
    }
  }
}

void _drawMentalRoutine(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 122);
  canvas.drawCircle(const Offset(200, 114), 56, FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Rutinitas Kecil Harian ✓',
    const Offset(200, 96),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Cek shelter · Atur air · Sinyal berkala · Lawan panik',
    const Offset(200, 186),
    align: TextAlign.center,
    maxWidth: 320,
  );
}

void _drawRationing(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 123);
  for (var i = 0; i < 3; i++) {
    final x = 84.0 + i * 116.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, 116), width: 88, height: 56),
        const Radius.circular(10),
      ),
      FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage),
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      'Hari ${i + 1}',
      Offset(x, 108),
      align: TextAlign.center,
      color: FieldSketchPalette.sage,
      withBacking: false,
    );
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Bagi Ransum Air & Kalori Porsi Kecil Terjadwal ✓',
    const Offset(200, 180),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
}

void _drawPlantPatchTest(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 124);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Uji Tempel Bertahap (Darurat Ekstrem)',
    const Offset(200, 38),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  final phases = <String>['1. Kulit 15m', '2. Bibir 15m', '3. Lidah (Jangan Telan)'];
  for (var i = 0; i < 3; i++) {
    final y = 84.0 + i * 44.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(76, y - 16, 324, y + 18),
        const Radius.circular(10),
      ),
      FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage),
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      phases[i],
      Offset(200, y - 8),
      align: TextAlign.center,
      withBacking: false,
    );
  }
}

void _drawAvoidPoisonMushrooms(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 125);
  // Jamur liar & buah getah putih dilarang mutlak
  canvas.drawPath(
    Path()
      ..moveTo(92, 114)
      ..quadraticBezierTo(132, 66, 172, 114)
      ..close(),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.coral),
  );
  canvas.drawRect(
    const Rect.fromLTRB(124, 114, 140, 152),
    FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.coral),
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(132, 52), r: 10);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'DILARANG MUTLAK!\nJamur Liar & Buah Bergetah Putih / Warna Mencolok ✗',
    const Offset(268, 96),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 195,
  );
}
