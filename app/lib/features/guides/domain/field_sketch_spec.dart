import 'package:flutter/foundation.dart';

/// Jenis konstruksi tenda untuk pemilih interaktif di Panduan Pemula.
enum TentType {
  domeCross('Dome Silang (2 Frame X)'),
  domeHub('Dome Hub / Y-Frame'),
  tunnel('Tunnel (Terowongan)'),
  trekkingPole('Trekking Pole / Pyramid');

  const TentType(this.label);
  final String label;
}

/// Kapasitas tenda yang menyesuaikan anotasi overlay dan jumlah kru/pasak.
enum TentSizeCategory {
  soloDuo1to2('1-2 Orang (Solo/Duo)', '1-2P'),
  smallGroup3to4('3-4 Orang (Grup Kecil)', '3-4P'),
  family4to6('4-6 Orang (Besar/Keluarga)', '4-6P');

  const TentSizeCategory(this.label, this.shortTag);
  final String label;
  final String shortTag;
}

/// Anotasi teknis dinamis yang digambar di atas sketsa vektor tenda yang sama
/// saat pengguna mengganti ukuran tenda.
@immutable
class FieldSketchOverlay {
  const FieldSketchOverlay({
    required this.personBadge,
    required this.stakesBadge,
    required this.guylineSpanLabel,
    required this.showVestibuleRidgePole,
    required this.showExtraStormGuys,
    required this.sizeTag,
  });

  final String personBadge;
  final String stakesBadge;
  final String guylineSpanLabel;
  final bool showVestibuleRidgePole;
  final bool showExtraStormGuys;
  final String sizeTag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldSketchOverlay &&
          personBadge == other.personBadge &&
          stakesBadge == other.stakesBadge &&
          guylineSpanLabel == other.guylineSpanLabel &&
          showVestibuleRidgePole == other.showVestibuleRidgePole &&
          showExtraStormGuys == other.showExtraStormGuys &&
          sizeTag == other.sizeTag;

  @override
  int get hashCode => Object.hash(
        personBadge,
        stakesBadge,
        guylineSpanLabel,
        showVestibuleRidgePole,
        showExtraStormGuys,
        sizeTag,
      );
}

/// Identitas tunggal kanvas sketsa teknis offline untuk tiap langkah.
enum FieldSketchId {
  // Pratinjau mini Beranda
  homeBeginnerPreview,

  // Panduan Pemula - Bab 1
  layeringBase,
  layeringMid,
  layeringOuter,
  carrierZoneBottom,
  carrierZoneCoreBack,
  carrierZoneMidOuter,
  carrierZoneTopHip,
  waterBalanceLeftRight,
  waterHydrationAccess,
  logisticsQuickVsCamp,

  // Panduan Pemula - Bab 2
  campSiteHighFlat,
  campSiteOverheadCheck,
  campSiteWindDoor,
  campSiteFootprintMargin,
  domeCrossStep1Spread,
  domeCrossStep2PolesX,
  domeCrossStep3RaiseClip,
  domeCrossStep4FlysheetGuyline,
  domeHubStep1HubAssemble,
  domeHubStep2PoleInsert,
  domeHubStep3ClipFly,
  tunnelStep1RearStake,
  tunnelStep2Hoops,
  tunnelStep3PullFront,
  trekkingPoleStep1FourCorners,
  trekkingPoleStep2CenterPole,
  trekkingPoleStep3GuylineTension,
  tentStake45Vs90,
  kitchenSafeDistance,
  kitchenNoClosedTentCo,
  kitchenFlatCanister,

  // Panduan Pemula - Bab 3
  paceRestStepVsWide,
  paceBreathingRhythm,
  paceMicroBreak,
  poleFlat90Deg,
  poleUphillShorten,
  poleDownhillLengthen,
  etiquetteRightOfWay,
  etiquetteCarryTrash,
  etiquetteCathole60m,

  // Panduan Keselamatan & P3K (10 topik lama, 1 sketsa per langkah)
  p3kHypoShelter,
  p3kHypoDryClothes,
  p3kHypoBurritoWrap,
  p3kHypoWarmDrinks,
  p3kHypoGentleEvac,
  p3kAmsStopClimb,
  p3kAmsDescend300m,
  p3kAmsSemiSitting,
  p3kAmsOxygenMeds,
  p3kFractureCsmCheck,
  p3kSprainRice,
  p3kFractureSplintTwoJoints,
  p3kFractureTieRecheck,
  p3kBleedDirectPressure,
  p3kBleedTourniquet,
  p3kWoundCleanDress,
  p3kBurnCoolWater,
  p3kSnakeCalmMoveAway,
  p3kSnakeRemoveRings,
  p3kSnakeImmobilizeSplint,
  p3kBeeScrapeCard,
  p3kHeatShadeRemovePack,
  p3kHeatElectrolyte,
  p3kHeatStrokeAggressiveCool,
  p3kHypoglycemiaSugar,
  p3kRecoveryPosition,
  p3kPoisonRehydrateSample,
  p3kLightningDescendRidge,
  p3kLightningCrouch,
  p3kLightningCprSafeTouch,
  p3kAnaEpipenPosition,
  p3kAsthmaTripodInhaler,
  p3kAirwayLoosenSos,
  p3kStopFreeze,
  p3kStopThink,
  p3kStopObserve,
  p3kStopPlanStayPut,

  // Bab Baru Wilderness Survival (6 topik x 4 langkah)
  survStopGolden3h,
  survNoFogNightWalk,
  survNoWildStreamDescent,
  survClimbRidgeDaylight,
  survRuleOf3Hierarchy,
  survRule3HoursShelter,
  survRule3DaysWater,
  survRule3WeeksFood,
  survBivouacSiteWind,
  survBivouacAFrame,
  survBivouacLeanTo,
  survBivouacLeafBed15cm,
  survWaterRainPoncho,
  survWaterMorningDew,
  survWaterSafeLiana,
  survWaterFilterBoil,
  survFireFeatherStick,
  survFireTeepeeTinder,
  survSarSignal3x,
  survBatteryGpsSosAirplane,
  survMentalRoutine,
  survRationingWaterFood,
  survPlantPatchTest,
  survAvoidPoisonMushrooms,
}

/// Satu langkah materi yang terikat 1:1 dengan satu kanvas sketsa teknis.
@immutable
class GuideStep {
  const GuideStep({
    required this.title,
    required this.instruction,
    required this.sketchId,
    this.tip,
    this.warning,
    this.overlay,
  });

  final String title;
  final String instruction;
  final FieldSketchId sketchId;
  final String? tip;
  final String? warning;
  final FieldSketchOverlay? overlay;
}
