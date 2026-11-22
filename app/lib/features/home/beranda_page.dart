import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/glass/hiqeo_liquid_glass.dart';
import '../../design/layout.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/hiqeo_button.dart';
import '../../design/widgets/line_icons.dart';
import '../../infrastructure/auth/active_account_scope.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/database_connection.dart';
import '../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../infrastructure/supabase/supabase_services.dart';
import '../auth/application/account_controller.dart';
import '../groups/application/group_key_manager.dart';
import '../kartu/domain/kartu_data.dart';
import '../notifications/data/user_notifications_service.dart';
import '../plus/application/plus_navigation.dart';
import '../plus/application/plus_scope.dart';
import '../preparation/application/packing_list_store.dart';
import '../profile/domain/profile_summary.dart';
import '../safety/domain/safety_repository.dart';
import '../safety/presentation/emergency_contacts_sheet.dart';
import '../tracking/domain/tracking_repository.dart';
import '../tracking/domain/tracking_session.dart';
import 'expandable_features_card.dart';
import 'last_trip_summary_card.dart';

/// Pilihan set fitur untuk grid 2x2 "Fitur Utama" di Beranda.
///
/// - [standard]: Hiqeo Plus, SOS, Peta offline, Kontak darurat.
/// - [withPreparation]: mengganti Kontak darurat dengan Persiapan pendakian.
enum HomeFeatureSet { standard, withPreparation }

/// Konstanta tunggal pemilih set fitur utama Beranda.
const HomeFeatureSet kHomeFeatureSet = HomeFeatureSet.standard;

/// Sapaan menurut jam lokal perangkat (bukan waktu domain).
String greetingForHour(int hour) {
  if (hour < 11) return 'Selamat pagi';
  if (hour < 15) return 'Selamat siang';
  if (hour < 18) return 'Selamat sore';
  return 'Selamat malam';
}

/// Ringkasan yang hanya memuat keadaan yang benar-benar diketahui.
String nextHikeMeta(GroupKeyStatus? status) {
  final parts = <String>[];
  final memberCount = status?.memberCount ?? 0;
  if (memberCount > 0) parts.add('$memberCount anggota');
  if (status == null) {
    parts.add('kunci grup belum dimuat');
  } else if (status.availability == GroupKeyAvailability.ready) {
    parts.add('kunci v${status.keyVersion} siap');
  } else {
    parts.add('menunggu kunci v${status.keyVersion}');
  }
  final joined = parts.join(' · ');
  if (joined.isEmpty) return joined;
  return joined[0].toUpperCase() + joined.substring(1);
}

class BerandaPage extends StatefulWidget {
  const BerandaPage({
    super.key,
    this.accountController,
    this.repository,
    this.safetyRepository,
    this.groupHikePlanStore,
    this.notificationsService,
    this.now,
    this.featureSet = kHomeFeatureSet,
  });

  /// Disuntikkan untuk uji; produksi memakai layanan Supabase yang tersedia.
  final AccountController? accountController;

  /// Disuntikkan untuk uji; produksi membuka basis data perangkat.
  final TrackingRepository? repository;

  /// Disuntikkan untuk uji sheet Kontak darurat langsung dari Beranda.
  final SafetyRepository? safetyRepository;

  /// Disuntikkan untuk uji; produksi memakai [GroupHikePlanStore.instance].
  final GroupHikePlanStore? groupHikePlanStore;

  /// Disuntikkan untuk uji; produksi memakai [UserNotificationsService.instance].
  final UserNotificationsService? notificationsService;

  final DateTime Function()? now;
  final HomeFeatureSet featureSet;

  static ({TrackingSession? session, KartuData? data})? _preloadedLastTrip;

  /// Memuat sesi selesai terakhir dari DB lokal saat startup agar kartu
  /// "Pendakian Terakhir" langsung terisi pada frame pertama tanpa layout shift.
  static Future<void> preloadLastTrip({TrackingRepository? repository}) async {
    AppDatabase? ownedDb;
    try {
      var repo = repository;
      if (repo == null) {
        final file = await defaultAppDatabaseFile();
        ownedDb = openAppDatabase(file);
        repo = DriftTrackingRepository(ownedDb);
      }
      final sessions = await repo.watchSessions().first;
      final completed = sessions
          .where(isMeaningfulCompletedSession)
          .toList()
        ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
      if (completed.isEmpty) {
        _preloadedLastTrip = (session: null, data: null);
        return;
      }
      final latest = completed.first;
      final points = await repo.points(latest.id);
      _preloadedLastTrip = (
        session: latest,
        data: KartuData.fromSession(latest, points),
      );
    } catch (_) {
      // Biarkan _watchSummary() di Beranda menangani fallback saat DB belum siap.
    } finally {
      if (ownedDb != null) {
        DriftTrackingRepository.unregisterDatabase(ownedDb);
        await ownedDb.close();
      }
    }
  }

  static void clearAccountCaches() {
    _preloadedLastTrip = null;
  }

  @visibleForTesting
  static void setPreloadedLastTripForTesting({
    TrackingSession? session,
    KartuData? data,
  }) {
    _preloadedLastTrip =
        session == null && data == null ? null : (session: session, data: data);
  }

  @override
  State<BerandaPage> createState() => _BerandaPageState();
}

class _BerandaPageState extends State<BerandaPage> {
  late final AccountController _account;
  late final bool _ownsAccount;
  late final GroupHikePlanStore _planStore;
  late final UserNotificationsService _notifications;
  late final DateTime Function() _now;

  AppDatabase? _database;
  TrackingRepository? _activeRepository;
  StreamSubscription<List<TrackingSession>>? _sessions;
  TrackingSession? _summarySession;
  KartuData? _summary;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    final shared = widget.accountController == null
        ? SupabaseServices.sharedAccountController
        : null;
    _ownsAccount = widget.accountController == null && shared == null;
    _account = widget.accountController ??
        shared ??
        SupabaseServices.createAccountController();
    _account.initialize();
    _planStore = widget.groupHikePlanStore ?? GroupHikePlanStore.instance;
    unawaited(_planStore.load());
    _notifications =
        widget.notificationsService ?? UserNotificationsService.instance;
    unawaited(_notifications.loadBadgeSeenState());
    _now = widget.now ?? DateTime.now;
    if (widget.repository == null) {
      final preloaded = BerandaPage._preloadedLastTrip;
      if (preloaded != null) {
        _summarySession = preloaded.session;
        _summary = preloaded.data;
      }
    }
    DriftTrackingRepository.historyRevision.addListener(_onHistoryRevisionChanged);
    ActiveAccountScope.activeUserId.addListener(_onActiveAccountChanged);
    unawaited(_watchSummary());
  }

  @override
  void dispose() {
    ActiveAccountScope.activeUserId.removeListener(_onActiveAccountChanged);
    DriftTrackingRepository.historyRevision
        .removeListener(_onHistoryRevisionChanged);
    unawaited(_sessions?.cancel());
    final database = _database;
    if (database != null) {
      DriftTrackingRepository.unregisterDatabase(database);
      unawaited(database.close());
    }
    if (_ownsAccount) _account.dispose();
    super.dispose();
  }

  void _onActiveAccountChanged() {
    if (!mounted) return;
    setState(() {
      _summarySession = null;
      _summary = null;
      _summaryError = null;
    });
    _onHistoryRevisionChanged();
  }

  void _onHistoryRevisionChanged() {
    final repo = _activeRepository;
    if (repo == null || !mounted) return;
    unawaited(() async {
      try {
        final sessions = await repo.watchSessions().first;
        if (!mounted) return;
        await _applySessions(repo, sessions);
      } catch (_) {}
    }());
  }

  Future<TrackingRepository?> _repository() async {
    final injected = widget.repository;
    if (injected != null) return injected;
    try {
      final file = await defaultAppDatabaseFile();
      final database = openAppDatabase(file);
      if (!mounted) {
        await database.close();
        return null;
      }
      _database = database;
      return DriftTrackingRepository(database);
    } catch (_) {
      return null;
    }
  }

  /// Mengikuti sesi di HP supaya ringkasan terisi setelah pendakian selesai
  /// tanpa perlu memuat ulang layar.
  Future<void> _watchSummary() async {
    final repository = await _repository();
    if (!mounted) return;
    if (repository == null) {
      setState(
        () => _summaryError = 'Data pendakian lokal belum dapat dibuka.',
      );
      return;
    }
    _activeRepository = repository;
    _sessions = repository.watchSessions().listen(
      (sessions) => unawaited(_applySessions(repository, sessions)),
      onError: (Object _) {
        if (!mounted) return;
        setState(
          () => _summaryError = 'Data pendakian gagal dibaca dari HP ini.',
        );
      },
    );
  }

  Future<void> _applySessions(
    TrackingRepository repository,
    List<TrackingSession> sessions,
  ) async {
    final completed = sessions
        .where(isMeaningfulCompletedSession)
        .toList()
      ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
    if (completed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _summarySession = null;
        _summary = null;
        _summaryError = null;
      });
      return;
    }
    final session = completed.first;
    if (session.id == _summarySession?.id &&
        session.endedAtUtc == _summarySession?.endedAtUtc &&
        session.distanceM == _summarySession?.distanceM &&
        session.movingSeconds == _summarySession?.movingSeconds &&
        session.elevationGainM == _summarySession?.elevationGainM &&
        _summary != null) {
      return;
    }
    try {
      final points = await repository.points(session.id);
      final data = KartuData.fromSession(session, points);
      if (!mounted) return;
      setState(() {
        _summarySession = session;
        _summary = data;
        _summaryError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _summaryError = 'Data pendakian gagal dibaca dari HP ini.',
      );
    }
  }

  /// Nama gunung dari metadata sesi lokal terlebih dahulu, lalu grup terkait.
  String? _mountainOf(TrackingSession? session) {
    if (session == null || session.isJogging) return null;
    final direct = session.mountainName?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final groupId = session.groupId;
    if (groupId == null) return null;
    for (final remote in _account.groups) {
      if (remote.group.id == groupId) {
        return remote.group.mountain ?? remote.group.name;
      }
    }
    return null;
  }

  List<FeatureEntry> _features(BuildContext context) {
    final fourthTile = widget.featureSet == HomeFeatureSet.withPreparation
        ? FeatureEntry(
            tileKey: const ValueKey<String>('home-feature-persiapan'),
            icon: HiqeoIcons.compass,
            title: 'Persiapan pendakian',
            onTap: () => context.push('/siap-naik'),
          )
        : FeatureEntry(
            tileKey: const ValueKey<String>('home-feature-kontak-darurat'),
            icon: HiqeoIcons.phone,
            title: 'Kontak darurat',
            onTap: () => unawaited(
              openDeviceEmergencyContactsSheet(
                context,
                userId: _account.user?.id,
                safetyRepository: widget.safetyRepository,
              ),
            ),
          );

    return <FeatureEntry>[
      // Kiri atas: Hiqeo Plus
      FeatureEntry(
        tileKey: const ValueKey<String>('home-feature-plus'),
        icon: HiqeoIcons.mountain,
        title: 'Hiqeo Plus',
        onTap: () {
          final plus = PlusScope.maybeOf(context);
          final hasPlus = plus?.hasPlus ?? false;
          final everPurchased = plus?.access.planId != null;
          if (hasPlus || everPurchased) {
            context.push(PlusRoutes.manage);
          } else {
            openPlusPaywall(context);
          }
        },
      ),
      // Kanan atas: SOS (kartu krem)
      FeatureEntry(
        tileKey: const ValueKey<String>('home-feature-sos'),
        icon: HiqeoIcons.warning,
        title: 'SOS',
        onTap: () => context.push('/sos'),
        emphasis: true,
      ),
      // Kiri bawah: Panduan Keselamatan & P3K (100% offline)
      FeatureEntry(
        tileKey: const ValueKey<String>('home-feature-p3k'),
        icon: HiqeoIcons.firstAid,
        title: 'Panduan keselamatan & P3K',
        onTap: () => context.push('/p3k'),
      ),
      // Kanan bawah: Kontak darurat (atau Persiapan pendakian via kHomeFeatureSet)
      fourthTile,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final sessionId = _summarySession?.id;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge(
          <Listenable>[_account, _planStore, _notifications],
        ),
        builder: (context, _) {
          final groupPlan = _planStore.activePlan;
          final soloPlan = _planStore.soloPlan;
          final showGroupPlan =
              groupPlan != null && groupPlan.hasOtherMemberReady;
          final heroTitle = showGroupPlan
              ? groupPlan.mountainName
              : (soloPlan != null
                  ? soloPlan.mountainName
                  : 'Belum ada pendakian');
          final heroMeta = showGroupPlan
              ? '${groupPlan.readyCount} dari ${groupPlan.memberCount} anggota siap · ${groupPlan.groupName}'
              : (soloPlan != null
                  ? 'Pendakian solo'
                  : 'Pilih gunung dan atur persiapan sebelum berangkat');
          final profile = _account.profile;
          final greetingName = profile?.fullName?.trim().isNotEmpty == true
              ? profile!.fullName!.trim()
              : (_account.user?.displayName?.trim().isNotEmpty == true
                  ? _account.user!.displayName!.trim()
                  : (profile?.username?.trim().isNotEmpty == true
                      ? profile!.username!.trim()
                      : 'Pendaki'));
          return ListView(
            padding: EdgeInsets.fromLTRB(
              HiqeoSpacing.lg,
              HiqeoSpacing.xl,
              HiqeoSpacing.lg,
              AppLayout.bottomInset(context),
            ),
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          greetingForHour(_now().hour),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.brightness == Brightness.dark
                                ? colors.textPrimary.withValues(alpha: 0.90)
                                : colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: HiqeoSpacing.xs),
                        Text(
                          'Halo, $greetingName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.displaySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: HiqeoSpacing.md),
                  _BerandaNotificationButton(
                    hasUnread: _notifications.hasUnreadNotifications,
                    onTap: () {
                      unawaited(_notifications.markBadgeSeen());
                      context.push('/notifikasi');
                    },
                  ),
                ],
              ),
              const SizedBox(height: HiqeoSpacing.xl),
              RepaintBoundary(
                child: _HeroCard(
                  title: heroTitle,
                  meta: heroMeta,
                  onPrepare: () => context.push('/siap-naik'),
                ),
              ),
              const SizedBox(height: HiqeoSpacing.xl),
              RepaintBoundary(
                child: LastTripSummaryCard(
                  data: _summary,
                  mountain: _mountainOf(_summarySession),
                  unavailableReason: _summaryError,
                  onViewKartu: sessionId == null
                      ? null
                      : () => context.push(
                            '/kartu?sesi=${Uri.encodeQueryComponent(sessionId)}',
                          ),
                ),
              ),
              const SizedBox(height: HiqeoSpacing.xl),
              ExpandableFeaturesCard(features: _features(context)),
            ],
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.meta,
    required this.onPrepare,
  });

  final String title;
  final String meta;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final muted = colors.onPrimary.withValues(alpha: 0.74);
    return Container(
      padding: const EdgeInsets.all(HiqeoSpacing.xl),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(HiqeoRadius.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'PENDAKIAN BERIKUTNYA',
            style: HiqeoTypography.overline(muted),
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.displayMedium
                ?.copyWith(color: colors.onPrimary),
          ),
          const SizedBox(height: HiqeoSpacing.xs),
          Text(
            meta,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: HiqeoSpacing.xl),
          HiqeoButton(
            label: 'Siapkan pendakian',
            variant: HiqeoButtonVariant.inverse,
            onPressed: onPrepare,
          ),
        ],
      ),
    );
  }
}

class _BerandaNotificationButton extends StatelessWidget {
  const _BerandaNotificationButton({
    required this.hasUnread,
    required this.onTap,
  });

  final bool hasUnread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            HiqeoGlassCircleButton(
              key: const ValueKey<String>('beranda-notif-button'),
              semanticsLabel: hasUnread
                  ? 'Notifikasi, ada pemberitahuan baru'
                  : 'Notifikasi',
              size: 44,
              onTap: onTap,
              child: HiqeoIcon(
                HiqeoIcons.bell,
                size: 20,
                color: colors.textPrimary,
              ),
            ),
            if (hasUnread)
              Positioned(
                top: 1,
                right: 1,
                child: IgnorePointer(
                  child: Container(
                    key: const ValueKey<String>('beranda-notif-red-dot'),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors.notificationBadge,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.background,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
