import 'package:go_router/go_router.dart';

import '../features/chat/presentation/chat_page.dart';
import '../features/home/beranda_page.dart';
import '../features/kartu/presentation/kartu_page.dart';
import '../features/map/presentation/map_page.dart';
import '../features/preparation/presentation/siap_naik_page.dart';
import '../features/profile/presentation/profil_page.dart';
import '../features/safety/presentation/sos_page.dart';
import '../features/shell/altracq_shell.dart';
import '../features/splash/presentation/splash_page.dart';
import '../features/tracking/presentation/tracking_page.dart';

/// Rute sepuluh layar.
///
/// Lima di antaranya hidup di dalam [AltracqShell] (punya navigasi bawah);
/// Splash, Siap Naik, SOS, dan Kartu Pendakian berdiri sendiri.
GoRouter buildAltracqRouter() => GoRouter(
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
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AltracqShell(navigationShell: navigationShell),
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

/// Instansi tunggal untuk aplikasi. Uji memakai [buildAltracqRouter] sendiri
/// agar tidak berbagi status navigasi antar kasus.
final GoRouter altracqRouter = buildAltracqRouter();
