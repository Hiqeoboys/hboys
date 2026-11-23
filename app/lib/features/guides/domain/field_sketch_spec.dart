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
  homeBeginnerPreview('home_beginner_preview'),

  // Panduan Pemula - Bab 1
  layeringBase('layering_step1_base'),
  layeringMid('layering_step2_mid'),
  layeringOuter('layering_step3_outer'),
  carrierZoneBottom('carrier_zone1_bottom'),
  carrierZoneCoreBack('carrier_zone2_core_back'),
  carrierZoneMidOuter('carrier_zone3_mid_outer'),
  carrierZoneTopHip('carrier_zone4_top_hip'),
  waterBalanceLeftRight('water_balance_left_right'),
  waterHydrationAccess('water_hydration_access'),
  logisticsQuickVsCamp('logistics_quick_vs_camp'),

  // Panduan Pemula - Bab 2
  campSiteHighFlat('camp_site_high_flat'),
  campSiteOverheadCheck('camp_site_overhead_check'),
  campSiteWindDoor('camp_site_wind_door'),
  campSiteFootprintMargin('camp_site_footprint_margin'),
  domeCrossStep1Spread('tent_dome_cross_step1'),
  domeCrossStep2PolesX('tent_dome_cross_step2'),
  domeCrossStep3RaiseClip('tent_dome_cross_step3'),
  domeCrossStep4FlysheetGuyline('tent_dome_cross_step4'),
  domeHubStep1HubAssemble('tent_dome_hub_step1'),
  domeHubStep2PoleInsert('tent_dome_hub_step2'),
  domeHubStep3ClipFly('tent_dome_hub_step3'),
  tunnelStep1RearStake('tent_tunnel_step1'),
  tunnelStep2Hoops('tent_tunnel_step2'),
  tunnelStep3PullFront('tent_tunnel_step3'),
  trekkingPoleStep1FourCorners('tent_trekking_pole_step1'),
  trekkingPoleStep2CenterPole('tent_trekking_pole_step2'),
  trekkingPoleStep3GuylineTension('tent_trekking_pole_step3'),
  tentStake45Vs90('tent_stake_45_vs_90'),
  kitchenSafeDistance('kitchen_safe_distance'),
  kitchenNoClosedTentCo('kitchen_no_closed_tent_co'),
  kitchenFlatCanister('kitchen_flat_canister'),

  // Panduan Pemula - Bab 3
  paceRestStepVsWide('pace_rest_step_vs_wide'),
  paceBreathingRhythm('pace_breathing_rhythm'),
  paceMicroBreak('pace_micro_break'),
  poleFlat90Deg('pole_flat_90deg'),
  poleUphillShorten('pole_uphill_shorten'),
  poleDownhillLengthen('pole_downhill_lengthen'),
  etiquetteRightOfWay('etiquette_right_of_way'),
  etiquetteCarryTrash('etiquette_carry_trash'),
  etiquetteCathole60m('etiquette_cathole_60m'),

  // Panduan Keselamatan & P3K (10 topik lama, 1 sketsa per langkah)
  p3kHypoShelter('p3k_hypo_shelter'),
  p3kHypoDryClothes('p3k_hypo_dry_clothes'),
  p3kHypoBurritoWrap('p3k_hypo_burrito_wrap'),
  p3kHypoWarmDrinks('p3k_hypo_warm_drinks'),
  p3kHypoGentleEvac('p3k_hypo_gentle_evac'),
  p3kAmsStopClimb('p3k_ams_stop_climb'),
  p3kAmsDescend300m('p3k_ams_descend_300m'),
  p3kAmsSemiSitting('p3k_ams_semi_sitting'),
  p3kAmsOxygenMeds('p3k_ams_oxygen_meds'),
  p3kFractureCsmCheck('p3k_fracture_csm_check'),
  p3kSprainRice('p3k_sprain_rice'),
  p3kFractureSplintTwoJoints('p3k_fracture_splint_two_joints'),
  p3kFractureTieRecheck('p3k_fracture_tie_recheck'),
  p3kBleedDirectPressure('p3k_bleed_direct_pressure'),
  p3kBleedTourniquet('p3k_bleed_tourniquet'),
  p3kWoundCleanDress('p3k_wound_clean_dress'),
  p3kBurnCoolWater('p3k_burn_cool_water'),
  p3kSnakeCalmMoveAway('p3k_snake_calm_move_away'),
  p3kSnakeRemoveRings('p3k_snake_remove_rings'),
  p3kSnakeImmobilizeSplint('p3k_snake_immobilize_splint'),
  p3kBeeScrapeCard('p3k_bee_scrape_card'),
  p3kHeatShadeRemovePack('p3k_heat_shade_remove_pack'),
  p3kHeatElectrolyte('p3k_heat_electrolyte'),
  p3kHeatStrokeAggressiveCool('p3k_heat_stroke_aggressive_cool'),
  p3kHypoglycemiaSugar('p3k_hypoglycemia_sugar'),
  p3kRecoveryPosition('p3k_recovery_position'),
  p3kPoisonRehydrateSample('p3k_poison_rehydrate_sample'),
  p3kLightningDescendRidge('p3k_lightning_descend_ridge'),
  p3kLightningCrouch('p3k_lightning_crouch'),
  p3kLightningCprSafeTouch('p3k_lightning_cpr_safe_touch'),
  p3kAnaEpipenPosition('p3k_ana_epipen_position'),
  p3kAsthmaTripodInhaler('p3k_asthma_tripod_inhaler'),
  p3kAirwayLoosenSos('p3k_airway_loosen_sos'),
  p3kStopFreeze('p3k_stop_freeze'),
  p3kStopThink('p3k_stop_think'),
  p3kStopObserve('p3k_stop_observe'),
  p3kStopPlanStayPut('p3k_stop_plan_stay_put'),

  // Bab Baru Wilderness Survival (6 topik x 4 langkah)
  survStopGolden3h('surv_stop_golden_3h'),
  survNoFogNightWalk('surv_no_fog_night_walk'),
  survNoWildStreamDescent('surv_no_wild_stream_descent'),
  survClimbRidgeDaylight('surv_climb_ridge_daylight'),
  survRuleOf3Hierarchy('surv_rule_of_3_hierarchy'),
  survRule3HoursShelter('surv_rule_3_hours_shelter'),
  survRule3DaysWater('surv_rule_3_days_water'),
  survRule3WeeksFood('surv_rule_3_weeks_food'),
  survBivouacSiteWind('surv_bivouac_site_wind'),
  survBivouacAFrame('surv_bivouac_a_frame'),
  survBivouacLeanTo('surv_bivouac_lean_to'),
  survBivouacLeafBed15cm('surv_bivouac_leaf_bed_15cm'),
  survWaterRainPoncho('surv_water_rain_poncho'),
  survWaterMorningDew('surv_water_morning_dew'),
  survWaterSafeLiana('surv_water_safe_liana'),
  survWaterFilterBoil('surv_water_filter_boil'),
  survFireFeatherStick('surv_fire_feather_stick'),
  survFireTeepeeTinder('surv_fire_teepee_tinder'),
  survSarSignal3x('surv_sar_signal_3x'),
  survBatteryGpsSosAirplane('surv_battery_gps_sos_airplane'),
  survMentalRoutine('surv_mental_routine'),
  survRationingWaterFood('surv_rationing_water_food'),
  survPlantPatchTest('surv_plant_patch_test'),
  survAvoidPoisonMushrooms('surv_avoid_poison_mushrooms');

  const FieldSketchId(this.assetSlug);

  final String assetSlug;

  String get assetPath => 'assets/guides/$assetSlug.webp';
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
