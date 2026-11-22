import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/field_sketch_spec.dart';
import 'field_sketch_tokens.dart';

/// Menggambar seluruh ilustrasi vektor Panduan Pemula (Bab 1 - Bab 3 + Beranda).
void paintBeginnerSketch(
  Canvas canvas,
  FieldSketchId id, {
  FieldSketchOverlay? overlay,
}) {
  switch (id) {
    case FieldSketchId.homeBeginnerPreview:
      _drawHomePreview(canvas);
    case FieldSketchId.layeringBase:
      _drawLayering(canvas, activeLayer: 1);
    case FieldSketchId.layeringMid:
      _drawLayering(canvas, activeLayer: 2);
    case FieldSketchId.layeringOuter:
      _drawLayering(canvas, activeLayer: 3);
    case FieldSketchId.carrierZoneBottom:
      _drawCarrierZones(canvas, activeZone: 1);
    case FieldSketchId.carrierZoneCoreBack:
      _drawCarrierZones(canvas, activeZone: 2);
    case FieldSketchId.carrierZoneMidOuter:
      _drawCarrierZones(canvas, activeZone: 3);
    case FieldSketchId.carrierZoneTopHip:
      _drawCarrierZones(canvas, activeZone: 4);
    case FieldSketchId.waterBalanceLeftRight:
      _drawWaterBalance(canvas);
    case FieldSketchId.waterHydrationAccess:
      _drawHydrationAccess(canvas);
    case FieldSketchId.logisticsQuickVsCamp:
      _drawLogisticsSeparation(canvas);
    case FieldSketchId.campSiteHighFlat:
      _drawCampSiteHighFlat(canvas);
    case FieldSketchId.campSiteOverheadCheck:
      _drawCampSiteOverhead(canvas);
    case FieldSketchId.campSiteWindDoor:
      _drawCampSiteWindDoor(canvas);
    case FieldSketchId.campSiteFootprintMargin:
      _drawCampSiteFootprint(canvas);
    case FieldSketchId.domeCrossStep1Spread:
      _drawDomeCrossStep1(canvas, overlay);
    case FieldSketchId.domeCrossStep2PolesX:
      _drawDomeCrossStep2(canvas, overlay);
    case FieldSketchId.domeCrossStep3RaiseClip:
      _drawDomeCrossStep3(canvas, overlay);
    case FieldSketchId.domeCrossStep4FlysheetGuyline:
      _drawDomeCrossStep4(canvas, overlay);
    case FieldSketchId.domeHubStep1HubAssemble:
      _drawDomeHubStep1(canvas, overlay);
    case FieldSketchId.domeHubStep2PoleInsert:
      _drawDomeHubStep2(canvas, overlay);
    case FieldSketchId.domeHubStep3ClipFly:
      _drawDomeHubStep3(canvas, overlay);
    case FieldSketchId.tunnelStep1RearStake:
      _drawTunnelStep1(canvas, overlay);
    case FieldSketchId.tunnelStep2Hoops:
      _drawTunnelStep2(canvas, overlay);
    case FieldSketchId.tunnelStep3PullFront:
      _drawTunnelStep3(canvas, overlay);
    case FieldSketchId.trekkingPoleStep1FourCorners:
      _drawTrekkingPoleStep1(canvas, overlay);
    case FieldSketchId.trekkingPoleStep2CenterPole:
      _drawTrekkingPoleStep2(canvas, overlay);
    case FieldSketchId.trekkingPoleStep3GuylineTension:
      _drawTrekkingPoleStep3(canvas, overlay);
    case FieldSketchId.tentStake45Vs90:
      drawTentStake45Diagram(canvas);
    case FieldSketchId.kitchenSafeDistance:
      _drawKitchenSafeDistance(canvas);
    case FieldSketchId.kitchenNoClosedTentCo:
      _drawKitchenClosedTentCo(canvas);
    case FieldSketchId.kitchenFlatCanister:
      _drawKitchenFlatCanister(canvas);
    case FieldSketchId.paceRestStepVsWide:
      _drawPaceRestStep(canvas);
    case FieldSketchId.paceBreathingRhythm:
      _drawPaceBreathing(canvas);
    case FieldSketchId.paceMicroBreak:
      _drawPaceMicroBreak(canvas);
    case FieldSketchId.poleFlat90Deg:
      _drawPoleFlat90(canvas);
    case FieldSketchId.poleUphillShorten:
      _drawPoleUphill(canvas);
    case FieldSketchId.poleDownhillLengthen:
      _drawPoleDownhill(canvas);
    case FieldSketchId.etiquetteRightOfWay:
      _drawEtiquetteRightOfWay(canvas);
    case FieldSketchId.etiquetteCarryTrash:
      _drawEtiquetteCarryTrash(canvas);
    case FieldSketchId.etiquetteCathole60m:
      _drawEtiquetteCathole(canvas);
    default:
      break;
  }
}

void _drawHomePreview(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 2);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 184), Offset(180, 178), Offset(384, 186)],
    bottomY: 226,
  );
  // Mini tenda
  final tent = Path()
    ..moveTo(118, 180)
    ..quadraticBezierTo(186, 86, 254, 180)
    ..close();
  FieldSketchPrimitives.drawCrossHatch(
    canvas,
    Path()
      ..moveTo(156, 180)
      ..quadraticBezierTo(186, 128, 214, 180)
      ..close(),
    const Rect.fromLTRB(152, 120, 220, 182),
    spacing: 5.5,
  );
  canvas.drawPath(tent, FieldSketchPrimitives.inkPaint(width: 2.0));
  // Guyline + pasak 45°
  canvas.drawLine(
    const Offset(140, 134),
    const Offset(72, 178),
    FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawStake(canvas, const Offset(68, 174), math.pi * 0.25, 28);
  // Ikon carrier kecil di kanan
  final pack = RRect.fromRectAndRadius(
    const Rect.fromLTWH(286, 118, 44, 64),
    const Radius.circular(8),
  );
  canvas.drawRRect(pack, FieldSketchPrimitives.inkPaint(width: 1.8));
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(286, 150),
    const Offset(330, 150),
  );
  FieldSketchPrimitives.drawCurvedWindArrow(
    canvas,
    const Offset(44, 48),
    const Offset(104, 34),
    const Offset(164, 54),
    const Offset(228, 42),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Pasak 45°',
    const Offset(56, 138),
    color: FieldSketchPalette.sage,
    fontSize: 9.5,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    '4 Zona Carrier',
    const Offset(308, 96),
    align: TextAlign.center,
    fontSize: 9.5,
  );
}

void _drawLayering(Canvas canvas, {required int activeLayer}) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: activeLayer + 3);
  final labels = <(String, String)>[
    ('1. Base Layer', 'Merino / Sintetis ✓'),
    ('2. Mid Layer', 'Fleece / Down Hangat'),
    ('3. Outer Shell', 'Waterproof + Windproof'),
  ];
  final xCenters = <double>[88, 200, 312];

  for (var i = 0; i < 3; i++) {
    final active = (i + 1) == activeLayer;
    final c = active ? FieldSketchPalette.sage : FieldSketchPalette.inkSoft;
    final cx = xCenters[i];
    final jacket = Path()
      ..moveTo(cx - 24, 58)
      ..lineTo(cx - 42, 74)
      ..lineTo(cx - 34, 118)
      ..lineTo(cx - 24, 114)
      ..lineTo(cx - 24, 150)
      ..lineTo(cx + 24, 150)
      ..lineTo(cx + 24, 114)
      ..lineTo(cx + 34, 118)
      ..lineTo(cx + 42, 74)
      ..lineTo(cx + 24, 58)
      ..close();
    if (active) {
      FieldSketchPrimitives.drawCrossHatch(
        canvas,
        jacket,
        Rect.fromLTRB(cx - 42, 58, cx + 42, 150),
        spacing: 6.5,
        cross: false,
        color: FieldSketchPalette.sage.withValues(alpha: 0.25),
      );
    }
    canvas.drawPath(
      jacket,
      FieldSketchPrimitives.inkPaint(width: active ? 2.2 : 1.4, color: c),
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      labels[i].$1,
      Offset(cx, 32),
      align: TextAlign.center,
      color: c,
      fontSize: 10,
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      labels[i].$2,
      Offset(cx, 158),
      align: TextAlign.center,
      color: c,
      fontSize: 8.8,
    );
  }

  if (activeLayer == 1) {
    FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(90, 206), r: 8);
    FieldSketchPrimitives.drawLabel(
      canvas,
      'Hindari Katun & Jeans (Menahan Keringat)',
      const Offset(106, 198),
      color: FieldSketchPalette.coral,
      fontSize: 9.8,
    );
  } else if (activeLayer == 2) {
    FieldSketchPrimitives.drawArrow(
      canvas,
      const Offset(132, 102),
      const Offset(158, 102),
      color: FieldSketchPalette.sage,
    );
    FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(112, 206), r: 8);
    FieldSketchPrimitives.drawLabel(
      canvas,
      'Perangkap udara hangat di atas base kering',
      const Offset(128, 198),
      color: FieldSketchPalette.sage,
      fontSize: 9.8,
    );
  } else {
    FieldSketchPrimitives.drawCurvedWindArrow(
      canvas,
      const Offset(360, 74),
      const Offset(348, 86),
      const Offset(360, 102),
      const Offset(346, 114),
      color: FieldSketchPalette.sage,
    );
    FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(110, 206), r: 8);
    FieldSketchPrimitives.drawLabel(
      canvas,
      'Blokir hujan & angin tanpa jebak uap',
      const Offset(126, 198),
      color: FieldSketchPalette.sage,
      fontSize: 9.8,
    );
  }
}

void _drawCarrierZones(Canvas canvas, {required int activeZone}) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: activeZone + 7);

  // Siluet punggung pendaki di kiri agar titik berat jelas
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(108, 212),
    height: 152,
    color: FieldSketchPalette.inkSoft,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Tulang Belakang',
    const Offset(70, 216),
    align: TextAlign.center,
    color: FieldSketchPalette.inkSoft,
    fontSize: 9,
  );

  // Penampang 4 Zona Carrier di kanan punggung (x: 138..236)
  final zones = <Rect>[
    const Rect.fromLTRB(138, 152, 232, 196), // 1: Bawah
    const Rect.fromLTRB(138, 86, 184, 152), // 2: Tengah Rapat Punggung
    const Rect.fromLTRB(184, 86, 232, 152), // 3: Tengah Luar
    const Rect.fromLTRB(138, 52, 232, 86), // 4: Top Lid & Hip Belt
  ];

  for (var i = 0; i < 4; i++) {
    final isActive = (i + 1) == activeZone;
    final rect = zones[i];
    if (isActive) {
      FieldSketchPrimitives.drawCrossHatch(
        canvas,
        Path()..addRect(rect),
        rect,
        spacing: 5.5,
        color: FieldSketchPalette.sage.withValues(alpha: 0.35),
      );
    }
    canvas.drawRect(
      rect,
      FieldSketchPrimitives.inkPaint(
        width: isActive ? 2.2 : 1.3,
        color: isActive ? FieldSketchPalette.sage : FieldSketchPalette.ink,
      ),
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      'Z${i + 1}',
      rect.center.translate(0, -6),
      align: TextAlign.center,
      color: isActive ? FieldSketchPalette.sage : FieldSketchPalette.inkSoft,
      fontSize: 9.5,
      withBacking: false,
    );
  }

  // Panah pusat gravitasi dekat punggung pada Zona 2
  if (activeZone == 2) {
    FieldSketchPrimitives.drawArrow(
      canvas,
      const Offset(164, 118),
      const Offset(120, 118),
      color: FieldSketchPalette.sage,
      width: 2.2,
    );
  }

  final zoneInfo = <(String, String)>[
    ('Zona 1: Dasar Carrier', 'Sleeping bag, pakaian tidur ringan'),
    ('Zona 2: Tengah Dekat Punggung', 'Tenda, air, logistik paling berat'),
    ('Zona 3: Tengah Bagian Luar', 'Alat masak, panci, jaket cadangan'),
    ('Zona 4: Top Lid & Hip Belt', 'Jas hujan, P3K, headlamp, camilan'),
  ];
  FieldSketchPrimitives.drawLabel(
    canvas,
    zoneInfo[activeZone - 1].$1,
    const Offset(250, 82),
    color: FieldSketchPalette.sage,
    fontSize: 10.5,
    maxWidth: 144,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    zoneInfo[activeZone - 1].$2,
    const Offset(250, 108),
    color: FieldSketchPalette.ink,
    fontSize: 9.5,
    bold: false,
    maxWidth: 144,
  );
  if (activeZone == 2) {
    FieldSketchPrimitives.drawLabel(
      canvas,
      'Pusat Berat (CoG) <-',
      const Offset(250, 152),
      color: FieldSketchPalette.sage,
      fontSize: 9.5,
      maxWidth: 144,
    );
  }
}

void _drawWaterBalance(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 11);
  // Tampak belakang carrier dengan saku kanan-kiri seimbang
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(136, 44, 264, 198),
      const Radius.circular(14),
    ),
    FieldSketchPrimitives.inkPaint(width: 2.0),
  );
  // Kantong kiri & kanan botol 1L + bladder tengah
  final leftPocket = const Rect.fromLTRB(106, 126, 134, 184);
  final rightPocket = const Rect.fromLTRB(266, 126, 294, 184);
  canvas.drawRect(leftPocket, FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage));
  canvas.drawRect(rightPocket, FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawDashedRect(
    canvas,
    const Rect.fromLTRB(168, 66, 232, 138),
    color: FieldSketchPalette.sage,
    width: 1.5,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(132, 208),
    const Offset(268, 208),
    color: FieldSketchPalette.sage,
    doubleHead: true,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kiri 1 L = Kanan 1 L ✓',
    const Offset(200, 212),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Bladder dekat punggung',
    const Offset(200, 24),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawHydrationAccess(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 12);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(148, 56, 252, 194),
      const Radius.circular(12),
    ),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  // Selang minum di tali bahu
  final tube = Path()
    ..moveTo(200, 86)
    ..quadraticBezierTo(268, 64, 286, 122);
  canvas.drawPath(tube, FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Selang / Botol Mudah Diraih ✓',
    const Offset(292, 114),
    color: FieldSketchPalette.sage,
    fontSize: 9.5,
    maxWidth: 100,
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(62, 152), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Jangan taruh semua air di dasar tas ✗',
    const Offset(18, 168),
    color: FieldSketchPalette.coral,
    fontSize: 9.2,
    maxWidth: 118,
  );
}

void _drawLogisticsSeparation(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 13);
  final quickBox = const Rect.fromLTRB(34, 62, 182, 178);
  final campBox = const Rect.fromLTRB(218, 62, 366, 178);
  FieldSketchPrimitives.drawCrossHatch(
    canvas,
    Path()..addRect(quickBox),
    quickBox,
    spacing: 7,
    cross: false,
    color: FieldSketchPalette.sage.withValues(alpha: 0.22),
  );
  canvas.drawRect(quickBox, FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  canvas.drawRect(campBox, FieldSketchPrimitives.inkPaint(width: 1.8));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Akses Cepat (Hip/Top)',
    const Offset(108, 40),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Gula cepat, kurma, trail mix, garam elektrolit',
    const Offset(108, 104),
    align: TextAlign.center,
    fontSize: 9.5,
    maxWidth: 130,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Logistik Camp (Dalam)',
    const Offset(292, 40),
    align: TextAlign.center,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Beras, lauk, mi, gas cadangan terpisah plastik kedap',
    const Offset(292, 104),
    align: TextAlign.center,
    fontSize: 9.5,
    maxWidth: 130,
  );
}

void _drawCampSiteHighFlat(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 21);
  // Penampang tanah: cekungan kiri (air menggenang ✗) vs gundukan datar kanan (✓)
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[
      Offset(18, 134),
      Offset(88, 176),
      Offset(152, 174),
      Offset(210, 142),
      Offset(338, 142),
      Offset(382, 168),
    ],
    bottomY: 230,
  );
  // Tenda di tanah datar tinggi (kanan)
  final tent = Path()
    ..moveTo(234, 142)
    ..quadraticBezierTo(278, 88, 322, 142)
    ..close();
  canvas.drawPath(tent, FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(278, 72), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Datar & sedikit tinggi ✓',
    const Offset(278, 46),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );

  // Panah aliran air menjauh
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(224, 150),
    const Offset(180, 168),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(338, 150),
    const Offset(374, 172),
    color: FieldSketchPalette.sage,
  );
  // Genangan air di cekungan kiri
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(118, 146), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Cekungan banjir ✗',
    const Offset(118, 118),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
  );
}

void _drawCampSiteOverhead(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 22);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 198), Offset(384, 198)],
    bottomY: 232,
  );
  // Pohon kiri dengan dahan mati di atas
  canvas.drawLine(
    const Offset(76, 198),
    const Offset(76, 48),
    FieldSketchPrimitives.inkPaint(width: 3.0),
  );
  canvas.drawLine(
    const Offset(76, 72),
    const Offset(152, 54),
    FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.coral),
  );
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(146, 56),
    const Offset(146, 152),
    color: FieldSketchPalette.coral,
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(150, 118), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Dahan mati rapuh (Widowmaker) ✗',
    const Offset(164, 48),
    color: FieldSketchPalette.coral,
    maxWidth: 160,
  );

  // Tenda di area aman (kanan)
  final tent = Path()
    ..moveTo(232, 198)
    ..quadraticBezierTo(294, 130, 356, 198)
    ..close();
  canvas.drawPath(tent, FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(294, 114), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Area bebas tajuk mati ✓',
    const Offset(294, 90),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawCampSiteWindDoor(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 23);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 228,
  );
  // Angin dari kiri ke kanan
  FieldSketchPrimitives.drawCurvedWindArrow(
    canvas,
    const Offset(26, 78),
    const Offset(74, 68),
    const Offset(108, 86),
    const Offset(146, 78),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawCurvedWindArrow(
    canvas,
    const Offset(26, 108),
    const Offset(74, 98),
    const Offset(108, 116),
    const Offset(146, 108),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Angin Dominan',
    const Offset(84, 48),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );

  // Tenda aerodinamis membelakangi angin, pintu menghadap kanan
  final tent = Path()
    ..moveTo(164, 188)
    ..quadraticBezierTo(234, 86, 314, 188)
    ..close();
  canvas.drawPath(tent, FieldSketchPrimitives.inkPaint(width: 2.1));
  // Pintu tenda terbuka di kanan (leeward)
  final door = Path()
    ..moveTo(268, 188)
    ..quadraticBezierTo(286, 134, 306, 188);
  canvas.drawPath(door, FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Pintu membelakangi angin ✓',
    const Offset(316, 128),
    color: FieldSketchPalette.sage,
    maxWidth: 80,
  );
}

void _drawCampSiteFootprint(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 24);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(20, 178), Offset(380, 178)],
    bottomY: 226,
  );
  // Lantai tenda utama
  canvas.drawRect(
    const Rect.fromLTRB(86, 148, 314, 160),
    FieldSketchPrimitives.inkPaint(width: 2.0),
  );
  // Footprint di bawahnya 3-5 cm lebih kecil di tiap sisi
  canvas.drawRect(
    const Rect.fromLTRB(108, 164, 292, 174),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(86, 134),
    const Offset(108, 134),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    '3-5 cm masuk ✓',
    const Offset(96, 108),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    fontSize: 9.5,
  );
  // Tetesan hujan tidak tertampung
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(82, 118),
    const Offset(82, 172),
    color: FieldSketchPalette.inkSoft,
    headSize: 5,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Footprint tidak menampung air hujan di bawah lantai',
    const Offset(200, 44),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 280,
  );
}

void _drawTentOverlayBadges(Canvas canvas, FieldSketchOverlay? overlay) {
  if (overlay == null) return;
  FieldSketchPrimitives.drawPillBadge(
    canvas,
    '${overlay.sizeTag} · ${overlay.personBadge}',
    const Offset(106, 22),
    borderColor: FieldSketchPalette.sage,
    textColor: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawPillBadge(
    canvas,
    overlay.stakesBadge,
    const Offset(298, 22),
    borderColor: FieldSketchPalette.ink,
    textColor: FieldSketchPalette.ink,
  );
}

void _drawDomeCrossStep1(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 31);
  _drawTentOverlayBadges(canvas, overlay);
  // Tampak atas inner terbentang + 4 sudut
  const rect = Rect.fromLTRB(108, 72, 292, 182);
  FieldSketchPrimitives.drawCrossHatch(
    canvas,
    Path()..addRect(rect),
    rect,
    spacing: 8,
    cross: false,
    color: FieldSketchPalette.sage.withValues(alpha: 0.16),
  );
  canvas.drawRect(rect, FieldSketchPrimitives.inkPaint(width: 2.0));
  for (final pt in <Offset>[
    rect.topLeft,
    rect.topRight,
    rect.bottomLeft,
    rect.bottomRight,
  ]) {
    FieldSketchPrimitives.drawCheckBadge(canvas, pt, r: 7);
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Bentangkan inner & pasak ringan 4 sudut (tahan angin)',
    const Offset(200, 204),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
}

void _drawDomeCrossStep2(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 32);
  _drawTentOverlayBadges(canvas, overlay);
  const rect = Rect.fromLTRB(116, 78, 284, 178);
  canvas.drawRect(rect, FieldSketchPrimitives.inkPaint(width: 1.5));
  // 2 Frame X menyilang diagonal
  canvas.drawLine(
    const Offset(106, 68),
    const Offset(294, 188),
    FieldSketchPrimitives.inkPaint(width: 2.4, color: FieldSketchPalette.sage),
  );
  canvas.drawLine(
    const Offset(294, 68),
    const Offset(106, 188),
    FieldSketchPrimitives.inkPaint(width: 2.4, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Frame X1 + X2',
    const Offset(200, 120),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  if (overlay?.showVestibuleRidgePole == true) {
    FieldSketchPrimitives.drawDashedLine(
      canvas,
      const Offset(200, 62),
      const Offset(200, 194),
      color: FieldSketchPalette.sage,
      width: 2.0,
    );
    FieldSketchPrimitives.drawLabel(
      canvas,
      'Extra Ridge Pole Teras ✓',
      const Offset(200, 198),
      align: TextAlign.center,
      color: FieldSketchPalette.sage,
    );
  }
}

void _drawDomeCrossStep3(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 33);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 190), Offset(384, 190)],
    bottomY: 230,
  );
  _drawTentOverlayBadges(canvas, overlay);

  // Kubah berdiri
  final arch1 = Path()
    ..moveTo(116, 190)
    ..quadraticBezierTo(200, 62, 284, 190);
  canvas.drawPath(arch1, FieldSketchPrimitives.inkPaint(width: 2.3, color: FieldSketchPalette.sage));
  // Siluet orang saat menegakkan (1 vs 2+)
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(86, 190),
    height: 44,
    color: FieldSketchPalette.sage,
  );
  if (overlay != null && overlay.personBadge.startsWith('2')) {
    FieldSketchPrimitives.drawPersonSilhouette(
      canvas,
      const Offset(314, 190),
      height: 44,
      color: FieldSketchPalette.sage,
    );
  }
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(200, 162),
    const Offset(200, 108),
    color: FieldSketchPalette.sage,
    width: 1.8,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    overlay?.personBadge ?? 'Angkat & kait klip puncak',
    const Offset(200, 206),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawDomeCrossStep4(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 34);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 190), Offset(384, 190)],
    bottomY: 230,
  );
  _drawTentOverlayBadges(canvas, overlay);

  // Flysheet luar menutup tenda
  final fly = Path()
    ..moveTo(116, 190)
    ..quadraticBezierTo(200, 68, 284, 190)
    ..close();
  FieldSketchPrimitives.drawCrossHatch(
    canvas,
    fly,
    const Rect.fromLTRB(116, 68, 284, 190),
    spacing: 8.5,
    cross: false,
    color: FieldSketchPalette.ink.withValues(alpha: 0.14),
  );
  canvas.drawPath(fly, FieldSketchPrimitives.inkPaint(width: 2.0));

  if (overlay?.showVestibuleRidgePole == true) {
    final ridge = Path()
      ..moveTo(260, 114)
      ..quadraticBezierTo(304, 110, 324, 190);
    canvas.drawPath(ridge, FieldSketchPrimitives.inkPaint(width: 2.4, color: FieldSketchPalette.sage));
    FieldSketchPrimitives.drawLabel(
      canvas,
      'Ridge Pole Teras',
      const Offset(318, 92),
      align: TextAlign.center,
      color: FieldSketchPalette.sage,
      fontSize: 9.0,
    );
  }

  // Guyline kiri & kanan dengan label rentang dinamis
  canvas.drawLine(
    const Offset(142, 132),
    const Offset(52, 188),
    FieldSketchPrimitives.inkPaint(width: 1.9, color: FieldSketchPalette.sage),
  );
  canvas.drawLine(
    const Offset(258, 132),
    const Offset(348, 188),
    FieldSketchPrimitives.inkPaint(width: 1.9, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawStake(canvas, const Offset(48, 184), math.pi * 0.25, 22);
  FieldSketchPrimitives.drawStake(canvas, const Offset(352, 184), math.pi * 0.75, 22);
  if (overlay?.showExtraStormGuys == true) {
    FieldSketchPrimitives.drawDashedLine(
      canvas,
      const Offset(172, 102),
      const Offset(88, 188),
      color: FieldSketchPalette.sage,
    );
    FieldSketchPrimitives.drawDashedLine(
      canvas,
      const Offset(228, 102),
      const Offset(312, 188),
      color: FieldSketchPalette.sage,
    );
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    overlay?.guylineSpanLabel ?? 'Rentang guyline 1,2 m',
    const Offset(200, 206),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawDomeHubStep1(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 35);
  _drawTentOverlayBadges(canvas, overlay);
  // Y-Frame Hub pusat
  const hub = Offset(200, 122);
  canvas.drawCircle(hub, 10, FieldSketchPrimitives.inkPaint(width: 2.4, color: FieldSketchPalette.sage));
  canvas.drawLine(hub, const Offset(112, 72), FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  canvas.drawLine(hub, const Offset(112, 174), FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  canvas.drawLine(hub, const Offset(288, 122), FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage));
  if (overlay?.showVestibuleRidgePole == true) {
    FieldSketchPrimitives.drawDashedLine(
      canvas,
      const Offset(196, 62),
      const Offset(248, 182),
      color: FieldSketchPalette.sage,
      width: 1.8,
    );
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kunci sendi Y-Hub sebelum dipasang ke inner',
    const Offset(200, 198),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
}

void _drawDomeHubStep2(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 36);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 190), Offset(384, 190)],
    bottomY: 230,
  );
  _drawTentOverlayBadges(canvas, overlay);
  final spine = Path()
    ..moveTo(108, 190)
    ..quadraticBezierTo(186, 68, 294, 190);
  canvas.drawPath(spine, FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(204, 148),
    const Offset(204, 92),
    color: FieldSketchPalette.sage,
    width: 1.8,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Masukkan ujung kaki frame ke grommet sudut',
    const Offset(200, 206),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawDomeHubStep3(Canvas canvas, FieldSketchOverlay? overlay) {
  _drawDomeCrossStep4(canvas, overlay);
}

void _drawTunnelStep1(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 37);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 186), Offset(384, 186)],
    bottomY: 228,
  );
  _drawTentOverlayBadges(canvas, overlay);
  // Kain tunnel rata di tanah, wajib pasak ujung belakang dulu
  canvas.drawRect(
    const Rect.fromLTRB(96, 174, 304, 186),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  FieldSketchPrimitives.drawStake(canvas, const Offset(82, 176), math.pi * 0.25, 32);
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(82, 148), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'WAJIB pasak 2 sudut ekor belakang dulu ✓',
    const Offset(200, 204),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 320,
  );
}

void _drawTunnelStep2(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 38);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 228,
  );
  _drawTentOverlayBadges(canvas, overlay);
  // 2 atau 3 lengkung hoop tunnel paralel
  final xs = overlay?.showVestibuleRidgePole == true
      ? <double>[118, 200, 282]
      : <double>[142, 258];
  for (final x in xs) {
    final hoop = Path()
      ..moveTo(x - 42, 188)
      ..quadraticBezierTo(x, 86, x + 42, 188);
    canvas.drawPath(hoop, FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Masukkan frame lengkung berurutan ke sleeve',
    const Offset(200, 206),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawTunnelStep3(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 39);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 228,
  );
  _drawTentOverlayBadges(canvas, overlay);
  // Profil tenda terowongan berdiri + tarikan pasak depan
  final tunnel = Path()
    ..moveTo(76, 188)
    ..quadraticBezierTo(116, 84, 212, 82)
    ..quadraticBezierTo(290, 84, 326, 188)
    ..close();
  canvas.drawPath(tunnel, FieldSketchPrimitives.inkPaint(width: 2.0));
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(290, 152),
    const Offset(352, 178),
    color: FieldSketchPalette.sage,
    width: 2.2,
  );
  FieldSketchPrimitives.drawStake(canvas, const Offset(356, 182), math.pi * 0.75, 28);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Tarik ujung depan hingga tegang lalu pasak (${overlay?.guylineSpanLabel ?? "1,5 m"})',
    const Offset(200, 206),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 340,
  );
}

void _drawTrekkingPoleStep1(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 40);
  _drawTentOverlayBadges(canvas, overlay);
  // 4 pasak sudut dulu di tanah (tampak atas)
  const corners = Rect.fromLTRB(118, 72, 282, 180);
  FieldSketchPrimitives.drawDashedRect(canvas, corners, color: FieldSketchPalette.ink);
  for (final pt in <Offset>[
    corners.topLeft,
    corners.topRight,
    corners.bottomLeft,
    corners.bottomRight,
  ]) {
    FieldSketchPrimitives.drawStake(canvas, pt, math.pi * 0.25, 18);
    FieldSketchPrimitives.drawCheckBadge(canvas, pt.translate(-12, -10), r: 6.5);
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Pasak kuat 4 sudut utama dulu (tenda non-freestanding)',
    const Offset(200, 204),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 340,
  );
}

void _drawTrekkingPoleStep2(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 41);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 228,
  );
  _drawTentOverlayBadges(canvas, overlay);
  // Piramida dengan trekking pole tengah
  final pyramid = Path()
    ..moveTo(96, 188)
    ..lineTo(200, 68)
    ..lineTo(304, 188);
  canvas.drawPath(pyramid, FieldSketchPrimitives.inkPaint(width: 2.0));
  canvas.drawLine(
    const Offset(200, 72),
    const Offset(200, 188),
    FieldSketchPrimitives.inkPaint(width: 3.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(216, 152),
    const Offset(216, 98),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Tegakkan Trekking Pole di Puncak ✓',
    const Offset(200, 206),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawTrekkingPoleStep3(Canvas canvas, FieldSketchOverlay? overlay) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 42);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 228,
  );
  _drawTentOverlayBadges(canvas, overlay);
  final pyramid = Path()
    ..moveTo(106, 188)
    ..lineTo(200, 70)
    ..lineTo(294, 188)
    ..close();
  canvas.drawPath(pyramid, FieldSketchPrimitives.inkPaint(width: 2.0));
  canvas.drawLine(
    const Offset(200, 72),
    const Offset(52, 186),
    FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage),
  );
  canvas.drawLine(
    const Offset(200, 72),
    const Offset(348, 186),
    FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawStake(canvas, const Offset(48, 182), math.pi * 0.25, 22);
  FieldSketchPrimitives.drawStake(canvas, const Offset(352, 182), math.pi * 0.75, 22);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kencangkan semua guyline agar piramida kaku',
    const Offset(200, 206),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
}

void _drawKitchenSafeDistance(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 45);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 228,
  );
  // Tenda kiri + kompor di kanan berjarak aman >= 2-3 m
  final tent = Path()
    ..moveTo(40, 188)
    ..quadraticBezierTo(102, 108, 164, 188)
    ..close();
  canvas.drawPath(tent, FieldSketchPrimitives.inkPaint(width: 2.0));
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(168, 162),
    const Offset(278, 162),
    color: FieldSketchPalette.sage,
    width: 1.8,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Jarak aman >= 2-3 m ✓',
    const Offset(224, 138),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  // Kompor + panci
  canvas.drawRect(
    const Rect.fromLTRB(290, 162, 326, 188),
    FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.sage),
  );
  canvas.drawRect(
    const Rect.fromLTRB(286, 144, 330, 160),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Di luar tenda, arah hilir angin',
    const Offset(308, 204),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    fontSize: 9.5,
  );
}

void _drawKitchenClosedTentCo(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 46);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 188), Offset(384, 188)],
    bottomY: 228,
  );
  final tent = Path()
    ..moveTo(92, 188)
    ..quadraticBezierTo(200, 62, 308, 188)
    ..close();
  FieldSketchPrimitives.drawCrossHatch(
    canvas,
    tent,
    const Rect.fromLTRB(92, 62, 308, 188),
    spacing: 7.5,
    color: FieldSketchPalette.coral.withValues(alpha: 0.28),
  );
  canvas.drawPath(tent, FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.coral));
  // Kompor menyala di dalam tenda tertutup
  canvas.drawRect(
    const Rect.fromLTRB(186, 162, 214, 188),
    FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.coral),
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(200, 110), r: 11);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'DILARANG! Keracunan Gas CO & Kebakaran Nilon',
    const Offset(200, 204),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 340,
  );
}

void _drawKitchenFlatCanister(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 47);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 178), Offset(214, 178), Offset(384, 212)],
    bottomY: 232,
  );
  // Kiri datar ✓
  canvas.drawRect(
    const Rect.fromLTRB(94, 148, 134, 178),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  canvas.drawRect(
    const Rect.fromLTRB(84, 124, 144, 146),
    FieldSketchPrimitives.inkPaint(width: 1.8),
  );
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(114, 96), r: 9);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Permukaan Datar & Stabil ✓',
    const Offset(114, 68),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  // Kanan miring ✗
  canvas.save();
  canvas.translate(294, 184);
  canvas.rotate(0.28);
  canvas.drawRect(
    const Rect.fromLTRB(-18, -30, 18, 0),
    FieldSketchPrimitives.inkPaint(width: 1.8, color: FieldSketchPalette.coral),
  );
  canvas.restore();
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(298, 116), r: 9);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Tanah Miring Mudah Tumpah ✗',
    const Offset(298, 86),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
  );
}

void _drawPaceRestStep(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 51);
  // Tanjakan kiri (rest step ✓) vs kanan (langkah lebar ✗)
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(20, 200), Offset(188, 114), Offset(212, 200), Offset(380, 114)],
    bottomY: 230,
  );
  for (var i = 0; i < 4; i++) {
    final x = 44.0 + i * 32.0;
    final y = 186.0 - i * 16.0;
    FieldSketchPrimitives.drawCheckBadge(canvas, Offset(x, y - 12), r: 5.5);
  }
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Langkah kecil konsisten (Rest Step) ✓',
    const Offset(96, 52),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 160,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(234, 186),
    const Offset(346, 126),
    color: FieldSketchPalette.coral,
    width: 2.0,
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(292, 134), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Langkah lebar cepat -> Asam laktat menumpuk ✗',
    const Offset(296, 52),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 160,
  );
}

void _drawPaceBreathing(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 52);
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(112, 200),
    height: 118,
    withPack: true,
  );
  FieldSketchPrimitives.drawCurvedWindArrow(
    canvas,
    const Offset(136, 98),
    const Offset(188, 76),
    const Offset(244, 116),
    const Offset(312, 92),
    color: FieldSketchPalette.sage,
    width: 2.0,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Tarik 2 langkah : Hembus 2 langkah',
    const Offset(258, 56),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 190,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kunci lutut sejenak tiap langkah menumpu (Rest Step)',
    const Offset(258, 152),
    align: TextAlign.center,
    fontSize: 9.5,
    maxWidth: 190,
  );
}

void _drawPaceMicroBreak(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 53);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(20, 186), Offset(380, 186)],
    bottomY: 226,
  );
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(146, 186),
    height: 98,
    withPack: true,
  );
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(234, 96), r: 9);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Jeda berdiri 30-60 dtk tiap 20 menit ✓',
    const Offset(260, 118),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 190,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Hindari duduk lama (>15 mnt) agar otot tidak dingin',
    const Offset(260, 146),
    align: TextAlign.center,
    color: FieldSketchPalette.inkSoft,
    fontSize: 9.2,
    maxWidth: 190,
  );
}

void _drawPoleFlat90(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 54);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 198), Offset(384, 198)],
    bottomY: 230,
  );
  // Pendaki di datar dengan siku 90 derajat
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(164, 198),
    height: 112,
  );
  // Lengan kanan ditekuk tepat 90°
  const shoulder = Offset(164, 108);
  const elbow = Offset(172, 134);
  const hand = Offset(206, 134);
  canvas.drawLine(shoulder, elbow, FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  canvas.drawLine(elbow, hand, FieldSketchPrimitives.inkPaint(width: 2.2, color: FieldSketchPalette.sage));
  canvas.drawLine(hand, const Offset(206, 198), FieldSketchPrimitives.inkPaint(width: 2.4, color: FieldSketchPalette.sage));
  // Tanda sudut siku 90°
  canvas.drawRect(
    const Rect.fromLTRB(172, 124, 182, 134),
    FieldSketchPrimitives.inkPaint(width: 1.4, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Sudut Siku 90° di Medan Datar ✓',
    const Offset(282, 92),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 140,
  );
}

void _drawPoleUphill(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 55);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 206), Offset(384, 126)],
    bottomY: 232,
  );
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(166, 174),
    height: 98,
  );
  canvas.drawLine(
    const Offset(198, 126),
    const Offset(214, 162),
    FieldSketchPrimitives.inkPaint(width: 2.4, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(234, 118),
    const Offset(234, 148),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Tanjakan: Pendekkan -5 s/d -10 cm ✓',
    const Offset(292, 68),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 150,
  );
}

void _drawPoleDownhill(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 56);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 118), Offset(384, 208)],
    bottomY: 232,
  );
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(152, 152),
    height: 98,
  );
  canvas.drawLine(
    const Offset(184, 106),
    const Offset(212, 166),
    FieldSketchPrimitives.inkPaint(width: 2.4, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(236, 148),
    const Offset(236, 108),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Turunan: Panjangkan +5 s/d +10 cm ✓',
    const Offset(292, 68),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 150,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Tahan beban benturan lutut',
    const Offset(292, 106),
    align: TextAlign.center,
    color: FieldSketchPalette.inkSoft,
    fontSize: 9.2,
    maxWidth: 150,
  );
}

void _drawEtiquetteRightOfWay(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 57);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 198), Offset(384, 108)],
    bottomY: 230,
  );
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(132, 170),
    height: 62,
    color: FieldSketchPalette.sage,
    withPack: true,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(112, 126),
    const Offset(158, 114),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Pendaki Naik Prioritas ✓',
    const Offset(112, 76),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawPersonSilhouette(
    canvas,
    const Offset(282, 132),
    height: 58,
    color: FieldSketchPalette.inkSoft,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Pendaki Turun Menepi',
    const Offset(286, 48),
    align: TextAlign.center,
    color: FieldSketchPalette.ink,
  );
}

void _drawEtiquetteCarryTrash(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 58);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(94, 62, 190, 186),
      const Radius.circular(12),
    ),
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(142, 42), r: 8);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Kantong Sampah di Carrier (Bawa Turun 100%) ✓',
    const Offset(142, 196),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    maxWidth: 180,
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(306, 116), r: 10);
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Dilarang bakar tisu basah / bungkus plastik ✗',
    const Offset(306, 146),
    align: TextAlign.center,
    color: FieldSketchPalette.coral,
    maxWidth: 136,
  );
}

void _drawEtiquetteCathole(Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 59);
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[Offset(16, 178), Offset(282, 178), Offset(292, 198), Offset(316, 198), Offset(326, 178), Offset(384, 178)],
    bottomY: 228,
  );
  // Sungai di kiri
  FieldSketchPrimitives.drawCurvedWindArrow(
    canvas,
    const Offset(28, 174),
    const Offset(52, 168),
    const Offset(72, 182),
    const Offset(96, 174),
    color: FieldSketchPalette.ink,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Sumber Air / Jalur',
    const Offset(62, 144),
    align: TextAlign.center,
  );
  // Jarak >= 60-70 m
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(104, 152),
    const Offset(286, 152),
    color: FieldSketchPalette.sage,
    width: 2.0,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Min. 60-70 m (~70 langkah) ✓',
    const Offset(196, 126),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );
  // Lubang cathole dalam 15-20 cm
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Lubang 15-20 cm',
    const Offset(304, 206),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
    fontSize: 9.0,
  );
}
