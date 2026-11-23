import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/background/app_background.dart';
import '../../design/background/page_background.dart';
import '../../design/motion/visual_effect_policy.dart';
import '../../design/system_ui.dart';
import '../../design/tokens.dart';
import '../../design/widgets/hiqeo_nav_bar.dart';
import '../../design/widgets/line_icons.dart';
import '../../design/widgets/nav_bar_visibility.dart';
import '../../infrastructure/notifications/fcm_notification_service.dart';
import '../../infrastructure/notifications/push_notification_overlay.dart';
import '../../infrastructure/offgrid/global_off_grid_outbox_service.dart';
import '../../infrastructure/power/power_profile_controller.dart';
import '../../infrastructure/supabase/supabase_services.dart';
import '../auth/application/account_controller.dart';
import '../notifications/data/user_notifications_service.dart';
import '../preparation/application/packing_list_store.dart';
import '../safety/application/emergency_contact_sync_service.dart';
import '../social/data/friends_service.dart';
import '../social/data/social_unread_store.dart';
import '../tracking/application/tracking_controller.dart';

/// Kerangka lima tab (Beranda, Peta, Track, Grup, Profil).
///
/// Layar di luar tab — Splash, Siap Naik, SOS, Kartu Pendakian — berada di
/// rute terpisah sehingga tidak menampilkan navigasi bawah. Navbar juga
/// disembunyikan halus (turun 90 dp + fade 300 ms) saat masuk ke Ruang Obrolan
/// atau saat memulai tracking rute pada peta.
class HiqeoShell extends StatefulWidget {
  const HiqeoShell({
    super.key,
    required this.navigationShell,
    this.powerController,
    this.accountController,
  });

  final StatefulNavigationShell navigationShell;

  /// Disuntikkan untuk uji; produksi membaca baterai perangkat.
  final PowerProfileController? powerController;

  /// Disuntikkan untuk uji; produksi memakai controller akun bersama.
  final AccountController? accountController;

  static final List<HiqeoNavBarItem> navItems = <HiqeoNavBarItem>[
    HiqeoNavBarItem(label: 'Beranda', icon: HiqeoIcons.home, route: '/beranda'),
    HiqeoNavBarItem(label: 'Peta', icon: HiqeoIcons.map, route: '/peta'),
    HiqeoNavBarItem(
      label: 'Track',
      icon: HiqeoIcons.activity,
      route: '/lacak',
    ),
    HiqeoNavBarItem(label: 'Sosial', icon: HiqeoIcons.group, route: '/grup'),
    HiqeoNavBarItem(label: 'Profil', icon: HiqeoIcons.user, route: '/profil'),
  ];

  /// Indeks cabang Peta. Peta digambar penuh di bawah navbar (edge-to-edge),
  /// sehingga hanya tab ini yang mematikan blob latar dan memakai kaca
  /// bertint rapat di atas peta.
  static const int mapBranchIndex = 1;

  /// Indeks cabang Track untuk memicu penyegaran status izin & kesiapan rekaman.
  static const int trackBranchIndex = 2;

  /// Indeks cabang Grup (untuk lencana undangan & navigasi cepat banner in-app).
  static const int groupBranchIndex = 3;

  /// Indeks tab aktif terkini agar animasi Beranda berhenti saat pengguna pindah tab.
  static final ValueNotifier<int> activeBranchIndex = ValueNotifier<int>(0);

  static AppBackgroundPage _pageForBranch(int index) => switch (index) {
        0 => AppBackgroundPage.beranda,
        1 => AppBackgroundPage.petaPenuh,
        2 => AppBackgroundPage.track,
        3 => AppBackgroundPage.grup,
        4 => AppBackgroundPage.profil,
        _ => AppBackgroundPage.beranda,
      };

  @override
  State<HiqeoShell> createState() => _HiqeoShellState();
}

class _HiqeoShellState extends State<HiqeoShell> {
  static final DeviceTier _deviceTier = VisualEffectPolicy.probeDeviceTier();

  late final PowerProfileController _power =
      widget.powerController ?? PowerProfileController();
  final NavBarVisibilityController _visibility =
      NavBarVisibilityController.instance;
  final TrackingController _tracking = TrackingController.instance;

  AccountController? _account;
  StreamSubscription<InAppPushNotification>? _fcmTapSub;
  bool _redirectingToOnboarding = false;

  @override
  void initState() {
    super.initState();
    final currentBranch = widget.navigationShell.currentIndex;
    if (HiqeoShell.activeBranchIndex.value != currentBranch) {
      HiqeoShell.activeBranchIndex.value = currentBranch;
    }
    if (widget.powerController == null) {
      unawaited(_power.refresh());
    }
    _account =
        widget.accountController ?? SupabaseServices.sharedAccountController;
    _account?.addListener(_checkProfileOnboardingRedirect);
    FriendsService.instance.ensureRealtimeSubscribed();
    EmergencyContactSyncService.instance.ensureRealtimeSubscribed();
    UserNotificationsService.instance.ensureRealtimeSubscribed();
    SocialUnreadStore.instance.ensureRealtimeSubscribed();
    GlobalOffGridOutboxService.instance.start();
    unawaited(UserNotificationsService.instance.loadNotifications());
    GroupHikePlanStore.instance.ensureRealtimeSubscribed(
      groupNamesById: <String, String>{
        if (_account != null)
          for (final g in _account!.groups) g.group.id: g.group.name,
      },
    );
    _fcmTapSub = FcmNotificationService.instance.onNotificationTap.listen((
      notif,
    ) {
      if (!mounted || PushNotificationOverlayHost.isActiveIn(context)) return;
      _navigateFromPush(notif);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkProfileOnboardingRedirect();
      if (!mounted || PushNotificationOverlayHost.isActiveIn(context)) return;
      final initialPush =
          FcmNotificationService.instance.takePendingInitialTap();
      if (initialPush != null) _navigateFromPush(initialPush);
    });
  }

  void _checkProfileOnboardingRedirect() {
    if (!mounted || _redirectingToOnboarding) return;
    final account = _account;
    if (account == null || !account.needsProfileOnboarding) return;
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final currentUri = router.routeInformationProvider.value.uri.path;
    if (currentUri == '/lengkapi-profil' || currentUri == '/akun') return;
    _redirectingToOnboarding = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _redirectingToOnboarding = false;
      if (!mounted) return;
      if (_account?.needsProfileOnboarding == true) {
        context.go('/lengkapi-profil');
      }
    });
  }

  @override
  void didUpdateWidget(covariant HiqeoShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentBranch = widget.navigationShell.currentIndex;
    if (HiqeoShell.activeBranchIndex.value != currentBranch) {
      HiqeoShell.activeBranchIndex.value = currentBranch;
    }
    if (currentBranch == HiqeoShell.trackBranchIndex &&
        oldWidget.navigationShell.currentIndex != HiqeoShell.trackBranchIndex) {
      unawaited(TrackingController.instance.refreshPermissionsAndResume());
    }
  }

  void _navigateFromPush(InAppPushNotification notif) {
    if (!mounted) return;
    _visibility.reset();
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      dispatchPushNavigation(router, notif, dialogContext: context);
      return;
    }
    switch (notif.route) {
      case '/teman':
        context.push('/teman');
      case '/sos':
        context.push('/sos');
      case '/siap-naik':
        context.push('/siap-naik');
      case '/profil':
        widget.navigationShell.goBranch(4);
      case '/grup':
        unawaited(SocialUnreadStore.instance.refresh());
        widget.navigationShell.goBranch(HiqeoShell.groupBranchIndex);
      default:
        widget.navigationShell.goBranch(0);
    }
  }

  @override
  void dispose() {
    _account?.removeListener(_checkProfileOnboardingRedirect);
    unawaited(_fcmTapSub?.cancel());
    if (widget.powerController == null) {
      _power.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.navigationShell.currentIndex;
    final systemInset = MediaQuery.paddingOf(context).bottom;
    final account = _account;
    final listenables = <Listenable>[
      _visibility,
      _tracking,
      if (account != null) account,
    ];
    return ListenableBuilder(
      listenable: _power,
      builder: (context, child) => VisualEffectPolicyScope(
        policy: VisualEffectPolicy(
          powerProfile: _power.profile,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          deviceTier: _deviceTier,
        ),
        child: child!,
      ),
      child: HiqeoSystemInset(
        bottom: systemInset,
        child: ListenableBuilder(
          listenable: Listenable.merge(listenables),
          builder: (context, bodyChild) {
            final isOnRouteMap = _visibility.onRouteScreen;
            final hideNavBar = _visibility.isHidden ||
                (index == HiqeoShell.mapBranchIndex &&
                    isOnRouteMap &&
                    _tracking.isRecording);
            final pendingInvites = account?.pendingInvitationCount ?? 0;
            final badgeCounts = pendingInvites > 0
                ? <int, int>{HiqeoShell.groupBranchIndex: pendingInvites}
                : const <int, int>{};
            return PageBackground(
              // Peta rute aktif digambar penuh tanpa aura latar; tab lain & daftar peta memakai aura.
              showBlobs: !isOnRouteMap,
              page: HiqeoShell._pageForBranch(index),
              child: Scaffold(
                extendBody: true,
                extendBodyBehindAppBar: true,
                backgroundColor: Colors.transparent,
                body: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Builder(
                      builder: (context) {
                        final mediaQuery = MediaQuery.of(context);
                        final keyboardOpen = mediaQuery.viewInsets.bottom > 0;
                        final bodyBottomPadding = keyboardOpen
                            ? 0.0
                            : (hideNavBar
                                ? systemInset
                                : HiqeoMetrics.navbarHeight +
                                    HiqeoMetrics.navbarBottomMargin +
                                    systemInset);
                        return MediaQuery(
                          data: mediaQuery.copyWith(
                            padding: mediaQuery.padding.copyWith(
                              bottom: bodyBottomPadding,
                            ),
                          ),
                          child: bodyChild!,
                        );
                      },
                    ),
                    Positioned(
                      left: HiqeoMetrics.navbarInset,
                      right: HiqeoMetrics.navbarInset,
                      bottom: HiqeoMetrics.navbarBottomMargin + systemInset,
                      child: _AnimatedNavBarOverlay(
                        hidden: hideNavBar,
                        currentIndex: index,
                        overMap: isOnRouteMap,
                        badgeCounts: badgeCounts,
                        onTap: (target) {
                          if (target == HiqeoShell.groupBranchIndex) {
                            unawaited(SocialUnreadStore.instance.refresh());
                          } else if (target == HiqeoShell.trackBranchIndex) {
                            unawaited(
                              TrackingController.instance
                                  .refreshPermissionsAndResume(),
                            );
                          }
                          if (target == index) return;
                          HiqeoShell.activeBranchIndex.value = target;
                          widget.navigationShell.goBranch(target);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          child: _TabFade(
            index: index,
            child: widget.navigationShell,
          ),
        ),
      ),
    );
  }
}

/// Animasi turun 90 dp + fade (300 ms, Cubic(0.4, 0, 0.2, 1)) untuk menyembunyikan
/// navbar saat tracking aktif atau di ruang obrolan, lalu mengeluarkannya dari
/// hit-test.
///
/// Pada posisi diam tampil (`value == 0`), navbar dirender langsung TANPA
/// pembungkus [Opacity] agar [BackdropFilter] tidak terganggu saveLayer.
class _AnimatedNavBarOverlay extends StatefulWidget {
  const _AnimatedNavBarOverlay({
    required this.hidden,
    required this.currentIndex,
    required this.overMap,
    this.badgeCounts = const <int, int>{},
    required this.onTap,
  });

  final bool hidden;
  final int currentIndex;
  final bool overMap;
  final Map<int, int> badgeCounts;
  final ValueChanged<int> onTap;

  @override
  State<_AnimatedNavBarOverlay> createState() => _AnimatedNavBarOverlayState();
}

class _AnimatedNavBarOverlayState extends State<_AnimatedNavBarOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 300);
  static const Curve _curve = Cubic(0.4, 0.0, 0.2, 1.0);
  static const double _slideDownDp = 90.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.hidden ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(_AnimatedNavBarOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hidden == widget.hidden) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        VisualEffectPolicyScope.of(context).reduceMotion;
    if (reduceMotion) {
      _controller.value = widget.hidden ? 1.0 : 0.0;
    } else if (widget.hidden) {
      _controller.animateTo(1.0, duration: _duration, curve: _curve);
    } else {
      _controller.animateTo(0.0, duration: _duration, curve: _curve);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        if (t >= 1.0 && widget.hidden) {
          return const SizedBox.shrink();
        }
        final isTransitioning = t > 0.0;
        final navBar = HiqeoNavBar(
          currentIndex: widget.currentIndex,
          items: HiqeoShell.navItems,
          overMap: widget.overMap,
          badgeCounts: widget.badgeCounts,
          // Hindari BackdropFilter di dalam Opacity selama transisi 300 ms.
          blurEnabledOverride: isTransitioning ? false : null,
          onTap: widget.onTap,
        );

        if (!isTransitioning && !widget.hidden) {
          return navBar;
        }

        return IgnorePointer(
          ignoring: widget.hidden || isTransitioning,
          child: ExcludeSemantics(
            excluding: widget.hidden,
            child: Transform.translate(
              offset: Offset(0, _slideDownDp * t),
              child: Opacity(
                opacity: (1.0 - t).clamp(0.0, 1.0),
                child: navBar,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Memudarkan isi tab baru selama 180 ms. Tab lama hilang seketika; pemilik
/// proyek memilih fade-in isi baru, bukan silang dua cabang.
class _TabFade extends StatefulWidget {
  const _TabFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 180);

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: _duration,
    value: 1,
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = VisualEffectPolicyScope.of(context).reduceMotion;
  }

  @override
  void didUpdateWidget(_TabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    if (_reduceMotion) {
      _fade.value = 1;
      return;
    }
    _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        key: const ValueKey<String>('tab-fade'),
        opacity: _fade,
        child: widget.child,
      );
}
