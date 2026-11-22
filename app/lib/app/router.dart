import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../design/tokens.dart';
import '../features/auth/presentation/account_page.dart';
import '../features/auth/presentation/profile_onboarding_page.dart';
import '../features/chat/presentation/chat_page.dart';
import '../features/debug/glass_diagnostics_page.dart';
import '../features/guides/presentation/beginner_guide_page.dart';
import '../features/history/presentation/history_page.dart';
import '../features/home/beranda_page.dart';
import '../features/kartu/presentation/kartu_page.dart';
import '../features/map/domain/map_package.dart';
import '../features/map/domain/mountain_pack.dart';
import '../features/map/presentation/map_page.dart';
import '../features/map/presentation/mountain_detail_page.dart';
import '../features/map/presentation/mountain_list_page.dart';
import '../features/plus/application/plus_navigation.dart';
import '../features/plus/presentation/advanced_analytics_page.dart';
import '../features/plus/presentation/annual_recap_page.dart';
import '../features/plus/presentation/leaderboard_page.dart';
import '../features/plus/presentation/manage_subscription_page.dart';
import '../features/plus/presentation/paywall_page.dart';
import '../features/plus/presentation/route_estimate_page.dart';
import '../features/plus/presentation/route_weather_page.dart';
import '../features/plus/presentation/widgets/plus_gate.dart';
import '../features/preparation/presentation/siap_naik_page.dart';
import '../features/notifications/presentation/notifications_page.dart';
import '../features/profile/presentation/profil_page.dart';
import '../features/profile/presentation/settings_page.dart';
import '../features/safety/presentation/first_aid_guide_page.dart';
import '../features/safety/presentation/sos_page.dart';
import '../features/shell/hiqeo_shell.dart';
import '../features/social/presentation/friends_page.dart';
import '../features/splash/presentation/startup_gate_screen.dart';
import '../features/tracking/presentation/tracking_page.dart';

/// Rute sepuluh layar.
///
/// Lima di antaranya hidup di dalam [HiqeoShell] (punya navigasi bawah);
/// StartupGate, Siap Naik, SOS, dan Kartu Pendakian berdiri sendiri.
GoRouter buildHiqeoRouter() => GoRouter(
      initialLocation: '/splash',
      routes: <RouteBase>[
        GoRoute(
          path: '/splash',
          name: 'splash',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: state.pageKey,
            child: const StartupGateScreen(),
          ),
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
          path: '/p3k',
          name: 'p3k',
          builder: (context, state) => const FirstAidGuidePage(),
        ),
        GoRoute(
          path: '/panduan-pemula',
          name: 'panduan-pemula',
          builder: (context, state) => BeginnerGuidePage(
            initialTopicId: state.uri.queryParameters['topik'],
          ),
        ),
        GoRoute(
          path: '/riwayat',
          name: 'riwayat',
          builder: (context, state) => const HistoryPage(),
        ),
        GoRoute(
          path: '/teman',
          name: 'teman',
          builder: (context, state) => const FriendsPage(),
        ),
        GoRoute(
          path: '/notifikasi',
          name: 'notifikasi',
          builder: (context, state) => const NotificationsPage(),
        ),
        GoRoute(
          path: '/kartu',
          name: 'kartu',
          builder: (context, state) =>
              KartuPage(sessionId: state.uri.queryParameters['sesi']),
        ),
        GoRoute(
          path: '/pengaturan',
          name: 'pengaturan',
          builder: (context, state) => const SettingsPage(),
        ),
        GoRoute(
          path: '/akun',
          name: 'akun',
          builder: (context, state) => AccountPage(
            returnToRoute: state.uri.queryParameters['returnTo'],
          ),
        ),
        GoRoute(
          path: '/lengkapi-profil',
          name: 'lengkapi-profil',
          builder: (context, state) => ProfileOnboardingPage(
            nextRoute: state.uri.queryParameters['next'] ?? '/beranda',
          ),
        ),
        if (kEnableGlassDiagnostics)
          GoRoute(
            path: kGlassDiagnosticsRoute,
            name: 'debug-uji-kaca',
            builder: (context, state) => const GlassDiagnosticsPage(),
          ),
        GoRoute(
          path: PlusRoutes.paywall,
          name: 'plus-paywall',
          builder: (context, state) {
            final args =
                state.extra is PlusPaywallArgs ? state.extra as PlusPaywallArgs : null;
            return PaywallPage(
              notice: args?.notice,
              requireFullSocialPlan: args?.requireFullSocialPlan ?? false,
            );
          },
        ),
        GoRoute(
          path: PlusRoutes.weather,
          name: 'plus-weather',
          builder: (context, state) {
            final routeName = state.uri.queryParameters['rute']?.trim() ?? '';
            final routeContext = state.extra is PlusRouteContext
                ? state.extra as PlusRouteContext
                : null;
            final effectiveName =
                routeName.isEmpty ? (routeContext?.name ?? 'Rute pendakian') : routeName;
            return PlusGate(
              title: 'Cuaca rute',
              description:
                  'Prakiraan per rute dengan suhu basecamp/puncak, peringatan '
                  'keselamatan, dan cache offline.',
              child: RouteWeatherPage(
                routeName: effectiveName,
                routeContext: routeContext,
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
            requireFullPlan: true,
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
            requireFullPlan: true,
            child: AnnualRecapPage(),
          ),
        ),
        GoRoute(
          path: PlusRoutes.leaderboard,
          name: 'plus-leaderboard',
          builder: (context, state) => const LeaderboardPage(),
        ),
        GoRoute(
          path: PlusRoutes.manage,
          name: 'plus-manage',
          builder: (context, state) => const ManageSubscriptionPage(),
        ),
        StatefulShellRoute.indexedStack(
          pageBuilder: (context, state, navigationShell) =>
              CustomTransitionPage<void>(
            key: state.pageKey,
            transitionDuration: HiqeoMotion.screenFade,
            reverseTransitionDuration: HiqeoMotion.screenFade,
            child: HiqeoShell(navigationShell: navigationShell),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: HiqeoMotion.standard,
              ),
              child: child,
            ),
          ),
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
                  builder: (context, state) => MountainListPage(
                    initialFilter: state.uri.queryParameters['filter'],
                  ),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'jalur',
                      name: 'peta-jalur',
                      builder: (context, state) {
                        final extra = state.extra;
                        MountainMapPackage? initialPackage;
                        MapTrail? initialTrail;
                        var allowStartAscent = false;
                        var autoStartTracking = false;
                        String? activeGroupId;
                        String? activeGroupName;
                        var startButtonLabel = 'Mulai tracking';
                        if (extra is MountainMapPackage) {
                          initialPackage = extra;
                        } else if (extra is MountainPack) {
                          initialPackage = extra.package;
                        } else if (extra is Map<String, dynamic>) {
                          initialPackage =
                              extra['package'] as MountainMapPackage?;
                          initialTrail = extra['trail'] as MapTrail?;
                          allowStartAscent = extra['allowStartAscent'] == true;
                          autoStartTracking = extra['autoStartTracking'] == true;
                          activeGroupId = extra['activeGroupId'] as String?;
                          activeGroupName = extra['activeGroupName'] as String?;
                          final customLabel = extra['startButtonLabel'] as String?;
                          if (customLabel != null && customLabel.isNotEmpty) {
                            startButtonLabel = customLabel;
                          }
                        }
                        return MapPage(
                          initialPackage: initialPackage,
                          initialTrail: initialTrail,
                          allowStartAscent: allowStartAscent,
                          autoStartTracking: autoStartTracking,
                          activeGroupId: activeGroupId,
                          activeGroupName: activeGroupName,
                          startButtonLabel: startButtonLabel,
                        );
                      },
                    ),
                    GoRoute(
                      path: 'detail',
                      name: 'peta-detail',
                      builder: (context, state) {
                        final pack = state.extra as MountainPack;
                        return MountainDetailPage(pack: pack);
                      },
                    ),
                  ],
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
