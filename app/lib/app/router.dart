import 'package:go_router/go_router.dart';

import '../features/shell/altracq_shell.dart';
import '../features/shell/placeholder_screen.dart';

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
      builder: (context, state) => const PlaceholderScreen(
        title: 'Splash',
        subtitle: 'Menyiapkan data lokal di HP',
      ),
    ),
    GoRoute(
      path: '/siap-naik',
      name: 'siap-naik',
      builder: (context, state) => const PlaceholderScreen(
        title: 'Siap Naik',
        subtitle: 'Kesiapan rombongan sebelum berangkat',
      ),
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
              builder: (context, state) =>
                  const PlaceholderScreen(title: 'Beranda'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/peta',
              name: 'peta',
              builder: (context, state) =>
                  const PlaceholderScreen(title: 'Peta Offline'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/lacak',
              name: 'lacak',
              builder: (context, state) =>
                  const PlaceholderScreen(title: 'Pelacakan'),
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
