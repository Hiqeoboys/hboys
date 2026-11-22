import 'package:flutter/material.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:go_router/go_router.dart';

import '../presentation/paywall_page.dart';

/// Konteks gunung dan jalur yang dibawa ke layar Cuaca Rute dan Estimasi.
class PlusRouteContext {
  const PlusRouteContext({
    required this.name,
    this.points = const <LatLng>[],
    this.trailId,
    this.mountainId,
    this.trailName,
    this.gpxAssetPath,
    this.distanceM,
    this.elevationGainM,
    this.basecampElevationM,
    this.summitElevationM,
    this.basecampCoord,
    this.summitCoord,
  });

  final String name;
  final List<LatLng> points;
  final String? trailId;
  final String? mountainId;
  final String? trailName;
  final String? gpxAssetPath;
  final double? distanceM;
  final double? elevationGainM;
  final double? basecampElevationM;
  final double? summitElevationM;
  final LatLng? basecampCoord;
  final LatLng? summitCoord;

  bool get hasPath => points.length >= 2;

  bool get hasCalculatorMetadata =>
      mountainId != null ||
      gpxAssetPath != null ||
      (distanceM != null && distanceM! >= 100);
}

abstract final class PlusRoutes {
  static const String paywall = '/plus';
  static const String weather = '/plus/cuaca';
  static const String estimate = '/plus/estimasi';
  static const String analytics = '/plus/analitik';
  static const String recap = '/plus/rekap';
  static const String manage = '/plus/kelola';
  static const String leaderboard = '/plus/leaderboard';

  static String weatherFor(String routeName) =>
      '$weather?rute=${Uri.encodeQueryComponent(routeName)}';

  static String paywallFor(String next) =>
      '$paywall?next=${Uri.encodeQueryComponent(next)}';
}

bool _isImperativeRoute(BuildContext context) =>
    ModalRoute.of(context)?.settings is! Page<dynamic>;

class PlusPaywallArgs {
  const PlusPaywallArgs({
    this.notice,
    this.requireFullSocialPlan = false,
  });

  final String? notice;
  final bool requireFullSocialPlan;
}

void openPlusWeather(
  BuildContext context,
  String routeName, {
  PlusRouteContext? route,
}) {
  context.push(PlusRoutes.weatherFor(routeName), extra: route);
}

void openPlusEstimate(BuildContext context, PlusRouteContext route) {
  context.push(PlusRoutes.estimate, extra: route);
}

void openPlusPaywall(
  BuildContext context, {
  String? notice,
  bool requireFullSocialPlan = false,
}) {
  final args = (notice != null || requireFullSocialPlan)
      ? PlusPaywallArgs(
          notice: notice,
          requireFullSocialPlan: requireFullSocialPlan,
        )
      : null;
  final router = GoRouter.maybeOf(context);
  if (router != null && !_isImperativeRoute(context)) {
    router.push(PlusRoutes.paywall, extra: args);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PaywallPage(
        notice: notice,
        requireFullSocialPlan: requireFullSocialPlan,
      ),
    ),
  );
}

void popPlusRoute(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.maybePop();
    return;
  }
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    router.pop();
  }
}
