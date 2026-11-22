import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/brand/app_brand.dart';
import '../../../core/config/supabase_config.dart';
import '../../../design/app_theme.dart';
import '../../../design/glass/glass_config.dart';
import '../../../design/system_ui.dart';
import '../../../design/theme_mode_controller.dart';
import '../../../design/tokens.dart';
import '../../../infrastructure/cache/avatar_disk_cache.dart';
import '../../../infrastructure/cache/media_cache_manager.dart';
import '../../../infrastructure/notifications/push_notification_overlay.dart';
import '../../../infrastructure/notifications/push_notification_service.dart';
import '../../../infrastructure/supabase/app_presence_service.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../../infrastructure/tracking/tracking_foreground_service.dart';
import '../../chat/application/group_auto_location_service.dart';
import '../../groups/application/group_selection.dart';
import '../../home/beranda_page.dart';
import '../../notifications/data/user_notifications_service.dart';
import '../../plus/plus_dependencies.dart';
import '../../preparation/application/packing_list_store.dart';
import '../../safety/application/sos_offline_queue_service.dart';
import '../../social/data/chat_mute_service.dart';
import '../../tracking/application/tracking_controller.dart';

/// Lapisan 3 startup lokal-first: latar `#313851` dan posisi logo identik dengan
/// Native Android Dark Splash agar serah-terima Android -> Flutter menyatu mulus.
///
/// Seluruh inisialisasi inti dan preload cache lokal dijalankan paralel dalam
/// satu `Future.wait` (tanpa panggilan jaringan online), lalu sinkronisasi server
/// berjalan asinkron di latar setelah pengguna masuk ke Beranda.
class StartupGateScreen extends StatefulWidget {
  const StartupGateScreen({
    super.key,
    this.initializer,
    this.minimumDuration = defaultMinimumDuration,
    this.onReady,
    this.onPostEntrySync,
  });

  static const Duration defaultMinimumDuration = Duration(milliseconds: 650);
  static const String logoAssetPath = 'assets/brand/hiqeo_logo_foreground.png';

  /// Ukuran kotak aset transparan (`hiqeo_logo_foreground.png`) agar tanda putih
  /// di dalamnya tepat ~126 dp, sejajar dengan `splash_logo.png` pada native splash.
  static const double logoExtent = 188;

  /// Kait uji: menggantikan paket inisialisasi lokal bawaan.
  final Future<void> Function()? initializer;

  /// Batas durasi tampil minimum (bawaan 650 ms agar mulus di layar 120Hz).
  final Duration minimumDuration;

  /// Kait uji: menggantikan navigasi ke Beranda.
  final VoidCallback? onReady;

  /// Kait uji: menggantikan sinkronisasi online latar setelah masuk Beranda.
  final VoidCallback? onPostEntrySync;

  @override
  State<StartupGateScreen> createState() => _StartupGateScreenState();
}

class _StartupGateScreenState extends State<StartupGateScreen>
    with SingleTickerProviderStateMixin {
  final Completer<void> _minimumDone = Completer<void>();
  Timer? _minimumTimer;
  late final AnimationController _logoMotion;
  late final Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    _logoMotion = AnimationController(
      vsync: this,
      duration: widget.minimumDuration > Duration.zero
          ? widget.minimumDuration
          : const Duration(milliseconds: 1),
    );
    // Mulai tepat di skala 1.0 agar frame pertama identik dengan Android splash.
    _logoScale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 1.035)
            .chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 50,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.035, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 50,
      ),
    ]).animate(_logoMotion);

    if (widget.minimumDuration <= Duration.zero) {
      _minimumDone.complete();
    } else {
      _minimumTimer = Timer(widget.minimumDuration, () {
        if (!_minimumDone.isCompleted) _minimumDone.complete();
      });
    }
    unawaited(_runStartupGate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.minimumDuration > Duration.zero &&
        !MediaQuery.disableAnimationsOf(context) &&
        !_logoMotion.isAnimating &&
        _logoMotion.value == 0) {
      unawaited(_logoMotion.forward());
    }
  }

  Future<void> _runStartupGate() async {
    final customInit = widget.initializer;
    if (customInit != null) {
      await Future.wait<void>(<Future<void>>[
        _safeRun(customInit),
        _minimumDone.future,
      ]);
    } else {
      await Future.wait<void>(<Future<void>>[
        // (a) Layanan inti lokal & hidrasi cache profil/grup (tanpa panggilan server).
        _safeRun(_initCoreServicesAndAccountCache),
        _safeRun(_initFirebaseAndLocalNotifications),
        _safeRun(_initDeviceAndTheme),
        // (b) Preload cache lokal Beranda: Plus, rencana pendakian, sesi terakhir & recovery.
        _safeRun(() => PlusDependencies.controller.loadCached()),
        _safeRun(_preloadHikePlanAndCleanDeletedGroups),
        _safeRun(_recoverTrackingAndPreloadLastTrip),
        // (c) Durasi minimum 650 ms agar transisi tenang dan halus pada layar 120Hz.
        _minimumDone.future,
      ]);
    }
    if (!mounted) return;

    // Keputusan navigasi cukup dari sesi lokal (offline-first, tanpa auth.getUser()).
    final hasLocalSession = SupabaseServices.hasLocalSession;
    final onReady = widget.onReady;
    if (onReady != null) {
      onReady();
    } else {
      context.go('/beranda');
      final initialPush =
          PushNotificationService.instance.takePendingInitialTap();
      if (initialPush != null) {
        final router = GoRouter.of(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          dispatchPushNavigation(
            router,
            initialPush,
            dialogContext: router.routerDelegate.navigatorKey.currentContext,
          );
        });
      }
    }

    // Sinkronisasi online berjalan asinkron di latar SETELAH masuk Beranda.
    final postSync = widget.onPostEntrySync;
    if (postSync != null) {
      postSync();
    } else if (customInit == null) {
      _scheduleBackgroundSync(hasLocalSession: hasLocalSession);
    }
  }

  Future<void> _safeRun(Future<void> Function() task) async {
    try {
      await task().timeout(const Duration(seconds: 5));
    } on Object {
      // Galat atau batas waktu inisialisasi lokal tidak boleh menahan startup gate.
    }
  }

  Future<void> _initCoreServicesAndAccountCache() async {
    await MediaCacheManager.instance.ensureCacheUpToDate();
    await AvatarDiskCache.instance.init();
    await SupabaseConfig.loadEnv();
    final mapboxToken = SupabaseConfig.mapboxAccessToken;
    if (mapboxToken.isNotEmpty &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      MapboxOptions.setAccessToken(mapboxToken);
    }
    await SupabaseServices.initialize();
    await SupabaseServices.warmUpLocalAccountCache();
  }

  Future<void> _initFirebaseAndLocalNotifications() async {
    await ChatMuteService.instance.ensureLoaded(forceReload: true);
    await PushNotificationService.instance.initializeFirebase();
    await PushNotificationService.instance.initializeLocalNotifications();
  }

  Future<void> _initDeviceAndTheme() async {
    if (!kIsWeb && Platform.isAndroid) {
      TrackingForegroundService.initialize();
    }
    await Future.wait<void>(<Future<void>>[
      _safeRun(GlassConfig.detectFromDevice),
      _safeRun(ThemeModeController.instance.load),
    ]);
  }

  Future<void> _preloadHikePlanAndCleanDeletedGroups() async {
    await SocialGroupsStore.instance.load();
    await GroupHikePlanStore.instance.load();
    await GroupHikePlanStore.instance.pruneDeletedGroups(
      SocialGroupsStore.instance.deletedGroupIds,
    );
  }

  Future<void> _recoverTrackingAndPreloadLastTrip() async {
    await TrackingController.instance.initialize();
    await BerandaPage.preloadLastTrip(
      repository: TrackingController.instance.repository,
    );
  }

  void _scheduleBackgroundSync({required bool hasLocalSession}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (hasLocalSession || SupabaseServices.isAvailable) {
        SupabaseServices.startBackgroundAccountSync();
        AppPresenceService.instance.start();
      }
      if (SupabaseServices.isAvailable) {
        GroupAutoLocationService.instance.start();
        UserNotificationsService.instance.ensureRealtimeSubscribed();
        unawaited(ChatMuteService.instance.loadAll(forceRemote: true));
        SosOfflineQueueService.instance.startConnectivityAutoSync();
        unawaited(SosOfflineQueueService.instance.flushPending());
        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 300),
            () => UserNotificationsService.instance.loadNotifications(),
          ),
        );
      }
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 200),
          () => PlusDependencies.controller.refreshRemote(),
        ),
      );
      unawaited(PushNotificationService.instance.initialize());
    });
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    if (!_minimumDone.isCompleted) _minimumDone.complete();
    _logoMotion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dark = HiqeoColors.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: hiqeoOverlayStyle(Brightness.dark),
      child: Theme(
        data: hiqeoDarkTheme,
        child: Scaffold(
          backgroundColor: dark.background,
          body: Center(
            child: Semantics(
              label: AppBrand.name,
              image: true,
              child: RepaintBoundary(
                child: ScaleTransition(
                  scale: _logoScale,
                  child: Image.asset(
                    StartupGateScreen.logoAssetPath,
                    width: StartupGateScreen.logoExtent,
                    height: StartupGateScreen.logoExtent,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
