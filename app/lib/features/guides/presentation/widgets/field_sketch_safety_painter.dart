import 'package:flutter/material.dart';

import '../../domain/field_sketch_spec.dart';
import 'field_sketch_tokens.dart';

/// Menggambar seluruh ilustrasi teknis untuk 10 topik Panduan Keselamatan & P3K.
void paintSafetySketch(Canvas canvas, FieldSketchId id) {
  switch (id) {
    case FieldSketchId.p3kHypoShelter:
      _drawHypoShelter(canvas);
    case FieldSketchId.p3kHypoDryClothes:
      _drawHypoDryClothes(canvas);
    case FieldSketchId.p3kHypoBurritoWrap:
      _drawHypoBurritoWrap(canvas);
    case FieldSketchId.p3kHypoWarmDrinks:
      _drawHypoWarmDrinks(canvas);
    case FieldSketchId.p3kHypoGentleEvac:
      _drawHypoGentleEvac(canvas);
    case FieldSketchId.p3kAmsStopClimb:
      _drawAmsStopClimb(canvas);
    case FieldSketchId.p3kAmsDescend300m:
      _drawAmsDescend(canvas);
    case FieldSketchId.p3kAmsSemiSitting:
      _drawAmsSemiSitting(canvas);
    case FieldSketchId.p3kAmsOxygenMeds:
      _drawAmsOxygenMeds(canvas);
    case FieldSketchId.p3kFractureCsmCheck:
      _drawFractureCsm(canvas);
    case FieldSketchId.p3kSprainRice:
      _drawSprainRice(canvas);
    case FieldSketchId.p3kFractureSplintTwoJoints:
      _drawFractureSplint(canvas);
    case FieldSketchId.p3kFractureTieRecheck:
      _drawFractureTieRecheck(canvas);
    case FieldSketchId.p3kBleedDirectPressure:
      _drawBleedDirectPressure(canvas);
    case FieldSketchId.p3kBleedTourniquet:
      _drawBleedTourniquet(canvas);
    case FieldSketchId.p3kWoundCleanDress:
      _drawWoundClean(canvas);
    case FieldSketchId.p3kBurnCoolWater:
      _drawBurnCoolWater(canvas);
    case FieldSketchId.p3kSnakeCalmMoveAway:
      _drawSnakeCalm(canvas);
    case FieldSketchId.p3kSnakeRemoveRings:
      _drawSnakeRemoveRings(canvas);
    case FieldSketchId.p3kSnakeImmobilizeSplint:
      _drawSnakeImmobilize(canvas);
    case FieldSketchId.p3kBeeScrapeCard:
      _drawBeeScrape(canvas);
    case FieldSketchId.p3kHeatShadeRemovePack:
      _drawHeatShade(canvas);
    case FieldSketchId.p3kHeatElectrolyte:
      _drawHeatElectrolyte(canvas);
    case FieldSketchId.p3kHeatStrokeAggressiveCool:
      _drawHeatStrokeCool(canvas);
    case FieldSketchId.p3kHypoglycemiaSugar:
      _drawHypoSugar(canvas);
    case FieldSketchId.p3kRecoveryPosition:
      _drawRecoveryPosition(canvas);
    case FieldSketchId.p3kPoisonRehydrateSample:
      _drawPoisonRehydrate(canvas);
    case FieldSketchId.p3kLightningDescendRidge:
      _drawLightningDescend(canvas);
    case FieldSketchId.p3kLightningCrouch:
      _drawLightningCrouch(canvas);
    case FieldSketchId.p3kLightningCprSafeTouch:
      _drawLightningCpr(canvas);
    case FieldSketchId.p3kAnaEpipenPosition:
      _drawAnaEpipen(canvas);
    case FieldSketchId.p3kAsthmaTripodInhaler:
      _drawAsthmaTripod(canvas);
    case FieldSketchId.p3kAirwayLoosenSos:
      _drawAirwayLoosen(canvas);
    case FieldSketchId.p3kStopFreeze:
      _drawStopLetter(canvas, 'S', 'STOP : Hentikan Langkah', 'Jangan terus memaksa jalan');
    case FieldSketchId.p3kStopThink:
      _drawStopLetter(canvas, 'T', 'THINK : Atur Napas & Tenang', 'Minum & makan camilan manis');
    case FieldSketchId.p3kStopObserve:
      _drawStopLetter(canvas, 'O', 'OBSERVE : Cek Peta Offline & GPS', 'Amati cuaca, arah & logistik');
    case FieldSketchId.p3kStopPlanStayPut:
      _drawStopLetter(canvas, 'P', 'PLAN : Bertahan & Peluit 3x', 'Dirikan bivak & aktifkan mode pesawat');
    default:
      break;
  }
}

void _drawHypoShelter(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 61);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 228,
  );
  FieldSketchPrimitives.drawCurvedWindArrow(
    canvas,
    const Offset(24, 96),
    const Offset(78, 86),
    const Offset(104, 102),
    const Offset(132, 92),
    color: FieldSketchPalette.coral,
  );
  final shelter = Path()
    ..moveTo(148, 188)
    ..quadraticBezierTo(234, 78, 320, 188)
    ..close();
  FieldSketchPrimitives.drawCrossHatch(
    canvas,
    shelter,
    const Rect.fromLTRB(148, 78, 320, 188),
    spacing: 8,
    cross: false,
    color: FieldSketchPalette.sage.withValues(alpha: 0.2),
  );
  canvas.drawPath(shelter, FieldSketchPrimitives.inkPaint(width: 2.1, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Evakuasi ke Dalam Tenda / Bivak Tertutup ✓',
    const Offset(234, 52),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawHypoDryClothes(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 62);
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(104, 54), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Pakaian Basah Dilepas',
    const Offset(104, 72),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(172, 122),
    const Offset(228, 122),
    color: FieldSketchPalette.sage,
    width: 2.2,
  );
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(296, 54), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Ganti Kering + Kupluk + Sarung Tangan + Kaos Kaki ✓',
    const Offset(296, 72),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 165,
  );
}

void _drawHypoBurritoWrap(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 63);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(20, 196), Offset(380, 196)],
    bottomY: 230,
  );
  // Lapisan 1: Matras isolasi dari tanah dingin
  const matRect = Rect.fromLTRB(68, 180, 332, 194);
  FieldSketchPrimitives.drawCrossHatch(canvas, Path()..addRect(matRect), matRect, spacing: 5);
  canvas.drawRect(matRect, FieldSketchPrimitives.inkPaint(width: 1.8));
  // Lapisan 2: Selimut foil darurat / Tarp luar (Burrito Wrap)
  final foil = RRect.fromRectAndRadius(
    const Rect.fromLTRB(84, 118, 316, 178),
    const Radius.circular(26),
  );
  canvas.drawRRect(foil, FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  // Lapisan 3: Sleeping bag + korban horizontal di dalam
  final bag = RRect.fromRectAndRadius(
    const Rect.fromLTRB(102, 128, 298, 168),
    const Radius.circular(18),
  );
  canvas.drawRRect(bag, FieldSketchPrimitives.inkPaint(width: 1.6));
  canvas.drawCircle(const Offset(122, 148), 10, FieldSketchPrimitives.inkPaint(width: 1.8));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Hypothermia Burrito Wrap ✓',
    const Offset(200, 44),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Selimut Foil / Tarp luar',
    const Offset(200, 92),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    fontSize: 9.5,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Matras Isolasi Tanah',
    const Offset(200, 204),
    align: TextAlign.center,
    color: FieldSketchPalette.ink,
    fontSize: 9.5,
  );
}

void _drawHypoWarmDrinks(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 64);
  // Cangkir hangat + titik kompres (ketiak, dada, selangkangan)
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(62, 102, 122, 162),
      const Radius.circular(8),
    ),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Sadar: Minum Hangat Manis ✓',
    const Offset(92, 174),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 145,
  );
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(286, 198),
    height: 124,
  );
  for (final pt in const <Offset>[
    Offset(274, 114),
    Offset(298, 114),
    Offset(286, 104),
    Offset(286, 142),
  ]) {
    canvas.drawCircle(pt, 5, Paint()..color = FieldSketchPalette.sage);
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kompres Hangat: Dada, Ketiak, Pangkal Paha',
    const Offset(286, 42),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 165,
  );
}

void _drawHypoGentleEvac(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 65);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 196), Offset(384, 196)],
    bottomY: 228,
  );
  // Posisi horizontal stabil di tandu
  canvas.drawLine(
    const Offset(76, 152),
    const Offset(324, 152),
    FieldSketchPrimitives.inkPaint(width: 2.5, color: FieldSketchPalette.sage),
  );
  canvas.drawCircle(const Offset(112, 138), 11, FieldSketchPrimitives.inkPaint(width: 1.8));
  canvas.drawLine(const Offset(124, 142), const Offset(286, 144), FieldSketchPrimitives.inkPaint(width: 2.0));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Hipotermia Berat: Pertahankan Horizontal & Lembut ✓',
    const Offset(200, 62),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'DILARANG gosok kulit keras / berdiri mendadak ✗',
    const Offset(200, 204),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 320,
  );
}

void _drawAmsStopClimb(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 66);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(20, 200), Offset(220, 128), Offset(380, 66)],
    bottomY: 230,
  );
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(196, 114), r: 10);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'AMS Ringan: BERHENTI Naik >2.500 mdpl ✓',
    const Offset(152, 52),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 190,
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(312, 74), r: 9);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Paksa Puncak ✗',
    const Offset(320, 44),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
  );
}

void _drawAmsDescend(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 67);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(20, 74), Offset(214, 148), Offset(380, 198)],
    bottomY: 230,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(112, 72),
    const Offset(292, 144),
    color: FieldSketchPalette.sage,
    width: 2.5,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'TURUN 300 - 1.000 m SEGERA ✓',
    const Offset(218, 60),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'HAPE / HACE: Turun adalah terapi utama',
    const Offset(200, 204),
    align: TextAlign.center,
    color: FieldSketchPalette.ink,
  );
}

void _drawAmsSemiSitting(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 68);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(20, 186), Offset(380, 186)],
    bottomY: 226,
  );
  // Sandaran carrier + posisi setengah duduk 45 derajat
  canvas.drawPath(
    Path()
      ..moveTo(124, 184)
      ..lineTo(156, 126)
      ..lineTo(192, 184)
      ..close(),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  canvas.drawCircle(const Offset(164, 112), 11, FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  canvas.drawLine(const Offset(172, 124), const Offset(216, 174), FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  canvas.drawLine(const Offset(216, 174), const Offset(286, 176), FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Posisi Setengah Duduk 45° + Hangat (Suspek HAPE) ✓',
    const Offset(210, 48),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 300,
  );
}

void _drawAmsOxygenMeds(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 69);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(92, 64, 140, 178),
      const Radius.circular(14),
    ),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'O₂ Portabel',
    const Offset(116, 188),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Protokol Medis WMS:\n- Asetazolamid (AMS)\n- Deksametason (HACE)\n- Nifedipin (HAPE)',
    const Offset(276, 86),
    align: TextAlign.center,
    color: FieldSketchPalette.ink,
    maxWidth: 190,
  );
}

void _drawFractureCsm(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 70);
  // Telapak kaki / tangan cek sirkulasi, sensasi, gerak (CSM)
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(132, 76, 268, 172),
      const Radius.circular(24),
    ),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Cek CSM Distal Cedera ✓',
    const Offset(200, 36),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'C: Sirkulasi (Hangat/Nadi)\nS: Sensasi (Terasa Sentuh)\nM: Gerak Jari',
    const Offset(200, 102),
    align: TextAlign.center,
    maxWidth: 210,
  );
}

void _drawSprainRice(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 71);
  // Kaki elevasi di atas carrier + kompres dingin berbalut kain
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 192), Offset(384, 192)],
    bottomY: 228,
  );
  canvas.drawRect(
    const Rect.fromLTRB(226, 144, 306, 192),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  canvas.drawLine(
    const Offset(118, 184),
    const Offset(256, 134),
    FieldSketchPrimitives.inkPaint(width: 3.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Istirahat + Kompres 15-20 mnt + Balut + Elevasi ✓',
    const Offset(200, 48),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
}

void _drawFractureSplint(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 72);
  // Kaki dengan garis patah + 2 sendi (lutut & pergelangan) + bidai panjang melewati 2 sendi
  canvas.drawLine(
    const Offset(78, 126),
    const Offset(322, 126),
    FieldSketchPrimitives.inkPaint(width: 8.0, color: FieldSketchPalette.inkSoft),
  );
  // Titik patah di tengah
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(200, 104), r: 7);
  // Sendi 1 & Sendi 2
  canvas.drawCircle(const Offset(122, 126), 9, FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  canvas.drawCircle(const Offset(278, 126), 9, FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  // Bidai melewati 2 sendi
  canvas.drawRect(
    const Rect.fromLTRB(92, 142, 308, 154),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(92, 66),
    const Offset(308, 66),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Bidai Melewati 2 Sendi (Atas & Bawah Patah) ✓',
    const Offset(200, 42),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 330,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Lapisi kain lembut di antara kulit dan bidai',
    const Offset(200, 178),
    align: TextAlign.center,
    color: FieldSketchPalette.ink,
  );
}

void _drawFractureTieRecheck(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 73);
  canvas.drawRect(
    const Rect.fromLTRB(76, 104, 324, 136),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  for (final x in <double>[114, 162, 238, 286]) {
    canvas.drawLine(
      Offset(x, 96),
      Offset(x, 144),
      FieldSketchPrimitives.inkPaint(width: 2.5, color: FieldSketchPalette.sage),
    );
  }
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(200, 120), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Ikat di atas & bawah titik patah (JANGAN tepat di patahan)',
    const Offset(200, 52),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Cek ulang CSM tiap 15-30 menit ✓',
    const Offset(200, 174),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawBleedDirectPressure(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 74);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(78, 124, 322, 164),
      const Radius.circular(18),
    ),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  canvas.drawRect(
    const Rect.fromLTRB(170, 114, 230, 136),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(200, 62),
    const Offset(200, 110),
    color: FieldSketchPalette.sage,
    width: 2.6,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Tekan Langsung Kuat & Konstan 10-15 Menit ✓',
    const Offset(200, 36),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 330,
  );
}

void _drawBleedTourniquet(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 75);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(74, 118, 326, 158),
      const Radius.circular(18),
    ),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  // Luka di kanan, torniket 5-7 cm di atasnya
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(258, 138), r: 8);
  canvas.drawRect(
    const Rect.fromLTRB(150, 112, 176, 164),
    FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(178, 92),
    const Offset(250, 92),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    '5-7 cm di atas luka ✓',
    const Offset(214, 68),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Catat jam pemasangan + Aktifkan SOS',
    const Offset(200, 188),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
  );
}

void _drawWoundClean(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 76);
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(154, 52),
    const Offset(196, 128),
    color: FieldSketchPalette.sage,
    width: 2.2,
  );
  canvas.drawOval(
    const Rect.fromLTRB(156, 136, 244, 166),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Bilas Air Bersih Mengalir -> Tutup Kasa Steril ✓',
    const Offset(200, 192),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
}

void _drawBurnCoolWater(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 77);
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(166, 52),
    const Offset(188, 120),
    color: FieldSketchPalette.sage,
    width: 2.2,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(214, 52),
    const Offset(212, 120),
    color: FieldSketchPalette.sage,
    width: 2.2,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Air Mengalir Sejuk 10-20 Menit (Bukan Es) ✓',
    const Offset(200, 148),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'JANGAN odol / mentega / kopi / pecah lepuhan ✗',
    const Offset(200, 186),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 320,
  );
}

void _drawSnakeCalm(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 78);
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(122, 196),
    height: 108,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(234, 142),
    const Offset(152, 142),
    color: FieldSketchPalette.sage,
    width: 2.2,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Menjauh & Tenangkan Korban (Cegah Detak Naik) ✓',
    const Offset(200, 48),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
}

void _drawSnakeRemoveRings(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 79);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(116, 98, 284, 148),
      const Radius.circular(18),
    ),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  canvas.drawRect(
    const Rect.fromLTRB(194, 96, 206, 150),
    FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.coral),
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(200, 92),
    const Offset(200, 56),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Lepas Cincin, Jam, & Sepatu Sebelum Bengkak ✓',
    const Offset(200, 178),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 330,
  );
}

void _drawSnakeImmobilize(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 80);
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(40, 108),
    const Offset(360, 108),
    color: FieldSketchPalette.inkSoft,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Level Jantung',
    const Offset(66, 86),
    align: TextAlign.center,
  );
  canvas.drawRect(
    const Rect.fromLTRB(124, 128, 286, 152),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Bidai Longgar <= Level Jantung ✓',
    const Offset(205, 166),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'JANGAN sedot, iris, atau torniket ketat ✗',
    const Offset(200, 202),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 320,
  );
}

void _drawBeeScrape(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 81);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(40, 162), Offset(360, 162)],
    bottomY: 224,
  );
  canvas.drawRect(
    const Rect.fromLTRB(132, 114, 186, 154),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(132, 142),
    const Offset(228, 142),
    color: FieldSketchPalette.sage,
    width: 2.2,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kikis Sengat Mendatar Memakai Kartu ✓',
    const Offset(200, 52),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
}

void _drawHeatShade(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 82);
  // Tenda/pohon peneduh + lepas carrier
  final shade = Path()
    ..moveTo(74, 164)
    ..quadraticBezierTo(184, 72, 294, 164);
  canvas.drawPath(shade, FieldSketchPrimitives.inkPaint(width: 2.1, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Pindah ke Tempat Teduh + Lepas Carrier & Jaket ✓',
    const Offset(200, 188),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 340,
  );
}

void _drawHeatElectrolyte(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 83);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(166, 68, 234, 168),
      const Radius.circular(14),
    ),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Oralit + Air Sedikit demi Sedikit (Saat Sadar) ✓',
    const Offset(200, 188),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
}

void _drawHeatStrokeCool(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 84);
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(200, 200),
    height: 132,
  );
  // Leher, ketiak, selangkangan = titik pendinginan cepat
  for (final pt in const <Offset>[
    Offset(200, 96),
    Offset(184, 118),
    Offset(216, 118),
    Offset(200, 148),
  ]) {
    canvas.drawCircle(pt, 6, Paint()..color = FieldSketchPalette.sage);
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'HEAT STROKE: Siram & Kompres Leher, Ketiak, Selangkangan + Kipasi ✓',
    const Offset(200, 34),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 340,
  );
}

void _drawHypoSugar(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 85);
  canvas.drawCircle(
    const Offset(136, 122),
    34,
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    '15-20 g Gula Cepat Serap ✓',
    const Offset(136, 174),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Madu / Gula Aren / Jus\nEvaluasi 15 Menit',
    const Offset(286, 112),
    align: TextAlign.center,
    maxWidth: 150,
  );
}

void _drawRecoveryPosition(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 86);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 178), Offset(384, 178)],
    bottomY: 226,
  );
  // Korban miring stabil (Recovery Position)
  canvas.drawCircle(const Offset(112, 162), 12, FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  canvas.drawLine(const Offset(124, 164), const Offset(234, 166), FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  canvas.drawLine(const Offset(234, 166), const Offset(276, 146), FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  canvas.drawLine(const Offset(276, 146), const Offset(306, 174), FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Posisi Pemulihan Miring (Jaga Jalan Napas) ✓',
    const Offset(200, 62),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'JANGAN beri minum/gula bila pingsan ✗',
    const Offset(200, 198),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
  );
}

void _drawPoisonRehydrate(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 87);
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(116, 98), r: 10);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Rehidrasi Sering + Simpan Sampel ✓',
    const Offset(116, 128),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 150,
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(286, 98), r: 10);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'JANGAN Paksa Muntahkan ✗',
    const Offset(286, 128),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 150,
  );
}

void _drawLightningDescend(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 88);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(20, 74), Offset(180, 148), Offset(380, 192)],
    bottomY: 230,
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(76, 62), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Puncak & Punggungan Terbuka ✗',
    const Offset(122, 42),
    color: FieldSketchPalette.coral,
    maxWidth: 170,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(96, 82),
    const Offset(234, 152),
    color: FieldSketchPalette.sage,
    width: 2.2,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Turun ke Lereng Pepohonan Seragam ✓',
    const Offset(276, 128),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 150,
  );
}

void _drawLightningCrouch(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 89);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 194), Offset(384, 194)],
    bottomY: 228,
  );
  // Matras kering di bawah kaki rapat
  const pad = Rect.fromLTRB(96, 180, 164, 194);
  FieldSketchPrimitives.drawCrossHatch(canvas, Path()..addRect(pad), pad, spacing: 4.5);
  canvas.drawRect(pad, FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage));
  // Siluet jongkok rapat
  canvas.drawCircle(const Offset(130, 118), 10, FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  canvas.drawPath(
    Path()
      ..moveTo(130, 128)
      ..quadraticBezierTo(116, 148, 128, 178)
      ..moveTo(130, 128)
      ..lineTo(138, 156)
      ..lineTo(132, 178),
    FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage),
  );
  // Jarak 10-15 meter antar pendaki
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(172, 166),
    const Offset(286, 166),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Jarak 10-15 m',
    const Offset(228, 142),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(304, 194),
    height: 44,
    color: FieldSketchPalette.inkSoft,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Lightning Crouch: Kaki Rapat di Atas Matras ✓',
    const Offset(200, 38),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 330,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'DILARANG rebahan di tanah atau di bawah pohon tunggal ✗',
    const Offset(200, 204),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 340,
  );
}

void _drawLightningCpr(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 90);
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(200, 56), r: 11);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Korban Petir AMAN Disentuh (Tidak Menyimpan Listrik!) ✓',
    const Offset(200, 82),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Prioritaskan korban henti napas: segera RJP & aktifkan SOS',
    const Offset(200, 148),
    align: TextAlign.center,
    maxWidth: 300,
  );
}

void _drawAnaEpipen(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 91);
  // Paha luar + auto-injektor 90 derajat
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(96, 128, 304, 174),
      const Radius.circular(20),
    ),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  canvas.drawRect(
    const Rect.fromLTRB(190, 62, 210, 128),
    FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(200, 44),
    const Offset(200, 60),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'EpiPen di Paha Luar (90°) + Baringkan Kaki Naik ✓',
    const Offset(200, 192),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 330,
  );
}

void _drawAsthmaTripod(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 92);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 192), Offset(384, 192)],
    bottomY: 228,
  );
  // Duduk condong depan (Tripod Position)
  canvas.drawCircle(const Offset(172, 102), 11, FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  canvas.drawLine(const Offset(172, 114), const Offset(152, 166), FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  canvas.drawLine(const Offset(164, 128), const Offset(202, 162), FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Posisi Tripod Condong Depan + Inhaler + Hangatkan Udara ✓',
    const Offset(200, 48),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 330,
  );
}

void _drawAirwayLoosen(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 93);
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(176, 116),
    const Offset(128, 116),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(224, 116),
    const Offset(272, 116),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Longgarkan Tali Carrier, Kerah & Dada · Aktifkan SOS ✓',
    const Offset(200, 152),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
}

void _drawStopLetter(Canvas canvas, String letter, String title, String sub) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: letter.codeUnitAt(0));
  canvas.drawCircle(
    const Offset(112, 120),
    42,
    FieldSketchPrimitives.inkPaint(width: 2.4, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    letter,
    const Offset(112, 98),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    fontSize: 30,
    withBacking: false,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    title,
    const Offset(278, 86),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    fontSize: 11.5,
    maxWidth: 195,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    sub,
    const Offset(278, 134),
    align: TextAlign.center,
    color: FieldSketchPalette.ink,
    fontSize: 10,
    bold: false,
    maxWidth: 195,
  );
}
