import 'package:go_router/go_router.dart';

import '../features/home/beranda_page.dart';
import '../features/map/presentation/map_page.dart';
import '../features/preparation/presentation/siap_naik_page.dart';
import '../features/shell/altracq_shell.dart';
import '../features/shell/placeholder_screen.dart';
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
      builder: (context, state) => const PlaceholderScreen(
        title: 'SOS',
        subtitle: 'Tekan-tahan 3 detik untuk memulai',
      ),
    ),
    GoRoute(
      path: '/kartu',
      name: 'kartu',
      builder: (context, state) => const PlaceholderScreen(
        title: 'Kartu Pendakian',
        subtitle: 'Ringkasan untuk dibagikan',
      ),
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
              builder: (context, state) =>
                  const PlaceholderScreen(title: 'Grup Chat'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/profil',
              name: 'profil',
              builder: (context, state) =>
                  const PlaceholderScreen(title: 'Profil'),
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
