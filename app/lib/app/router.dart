import 'package:go_router/go_router.dart';

import '../features/chat/presentation/chat_page.dart';
import '../features/home/beranda_page.dart';
import '../features/kartu/presentation/kartu_page.dart';
import '../features/map/presentation/map_page.dart';
import '../features/plus/application/plus_navigation.dart';
import '../features/plus/presentation/advanced_analytics_page.dart';
import '../features/plus/presentation/annual_recap_page.dart';
import '../features/plus/presentation/manage_subscription_page.dart';
import '../features/plus/presentation/paywall_page.dart';
import '../features/plus/presentation/route_estimate_page.dart';
import '../features/plus/presentation/route_weather_page.dart';
import '../features/plus/presentation/widgets/plus_gate.dart';
import '../features/preparation/presentation/siap_naik_page.dart';
import '../features/profile/presentation/profil_page.dart';
import '../features/safety/presentation/sos_page.dart';
import '../features/shell/hiqeo_shell.dart';
import '../features/splash/presentation/splash_page.dart';
import '../features/tracking/presentation/tracking_page.dart';

/// Rute sepuluh layar.
///
/// Lima di antaranya hidup di dalam [HiqeoShell] (punya navigasi bawah);
/// Splash, Siap Naik, SOS, dan Kartu Pendakian berdiri sendiri.
GoRouter buildHiqeoRouter() => GoRouter(
      initialLocation: '/splash',
      routes: <RouteBase>[
        GoRoute(
          path: '/splash',
          name: 'splash',
          builder: (context, state) => const SplashPage(),
        ),
        GoRoute(
          path: '/siap-naik',
          name: 'siap-naik',
          builder: (context, state) => const SiapNaikPage(),
        ),
        GoRoute(
          path: '/sos',
          name: 'sos',
          builder: (context, state) => const SosPage(),
        ),
        GoRoute(
          path: '/kartu',
          name: 'kartu',
          builder: (context, state) =>
              KartuPage(sessionId: state.uri.queryParameters['sesi']),
        ),
        GoRoute(
          path: PlusRoutes.paywall,
          name: 'plus-paywall',
          builder: (context, state) => const PaywallPage(),
        ),
        GoRoute(
          path: PlusRoutes.weather,
          name: 'plus-weather',
          builder: (context, state) {
            final routeName = state.uri.queryParameters['rute']?.trim() ?? '';
            return PlusGate(
              title: 'Cuaca rute',
              description:
                  'Prakiraan per rute dengan label perkiraan, atribusi '
                  'BMKG, dan cache offline.',
              child: RouteWeatherPage(
                routeName: routeName.isEmpty ? 'Rute pendakian' : routeName,
              ),
            );
          },
        ),
        GoRoute(
          path: PlusRoutes.estimate,
          name: 'plus-estimate',
          builder: (context, state) {
            final extra = state.extra;
            final route = extra is PlusRouteContext
                ? extra
                : PlusRouteContext(
                    name:
                        state.uri.queryParameters['rute']?.trim().isNotEmpty ==
                                true
                            ? state.uri.queryParameters['rute']!.trim()
                            : 'Rute pendakian',
                  );
            return PlusGate(
              title: 'Estimasi & itinerary',
              description:
                  'Perkiraan waktu tiba dan garis waktu dari kecepatan '
                  'pribadi, bukan jadwal resmi.',
              child: RouteEstimatePage(route: route),
            );
          },
        ),
        GoRoute(
          path: PlusRoutes.analytics,
          name: 'plus-analytics',
          builder: (context, state) => const PlusGate(
            title: 'Analitik lanjutan',
            description: 'Pace per kemiringan, kecepatan vertikal, rekor jarak '
                'dan elevasi, serta indikasi kelelahan dari sesi di HP ini.',
            child: AdvancedAnalyticsPage(),
          ),
        ),
        GoRoute(
          path: PlusRoutes.recap,
          name: 'plus-recap',
          builder: (context, state) => const PlusGate(
            title: 'Rekap tahunan',
            description: 'Kartu rekap tahunan yang bisa dibagikan tanpa '
                'menampilkan lokasi.',
            child: AnnualRecapPage(),
          ),
        ),
        GoRoute(
          path: PlusRoutes.manage,
          name: 'plus-manage',
          builder: (context, state) => const ManageSubscriptionPage(),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              HiqeoShell(navigationShell: navigationShell),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/beranda',
                  name: 'beranda',
                  builder: (context, state) => const BerandaPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/peta',
                  name: 'peta',
                  builder: (context, state) => MapPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/lacak',
                  name: 'lacak',
                  builder: (context, state) => const TrackingPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/grup',
                  name: 'grup',
                  builder: (context, state) => const ChatPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/profil',
                  name: 'profil',
                  builder: (context, state) => const ProfilPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    );

/// Instansi tunggal untuk aplikasi. Uji memakai [buildHiqeoRouter] sendiri
/// agar tidak berbagi status navigasi antar kasus.
final GoRouter hiqeoRouter = buildHiqeoRouter();
