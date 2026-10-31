import 'package:flutter/widgets.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:go_router/go_router.dart';

/// Rute yang dibuka dari Peta atau Siap Naik.
///
/// Titik hanya tersedia saat rute dipilih di Peta. Dari Siap Naik, nama
/// gunung tetap dibawa meskipun jalur belum terunduh supaya layar bisa
/// menjelaskan apa yang kurang, bukan menampilkan angka karangan.
class PlusRouteContext {
  const PlusRouteContext({
    required this.name,
    this.points = const <LatLng>[],
    this.trailId,
  });

  final String name;
  final List<LatLng> points;
  final String? trailId;

  bool get hasPath => points.length >= 2;
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

void openPlusWeather(BuildContext context, String routeName) {
  context.push(PlusRoutes.weatherFor(routeName));
}

void openPlusEstimate(BuildContext context, PlusRouteContext route) {
  context.push(PlusRoutes.estimate, extra: route);
}

void openPlusPaywall(BuildContext context) {
  context.push(PlusRoutes.paywall);
}
