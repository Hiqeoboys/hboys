import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/hiqeo_button.dart';
import '../../design/widgets/line_icons.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/database_connection.dart';
import '../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../infrastructure/supabase/supabase_services.dart';
import '../auth/application/account_controller.dart';
import '../groups/application/group_key_manager.dart';
import '../groups/application/group_selection.dart';
import '../kartu/domain/kartu_data.dart';
import '../tracking/domain/tracking_repository.dart';
import '../tracking/domain/tracking_session.dart';
import 'expandable_features_card.dart';
import 'last_trip_summary_card.dart';

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
    this.now,
  });

  /// Disuntikkan untuk uji; produksi memakai layanan Supabase yang tersedia.
  final AccountController? accountController;

  /// Disuntikkan untuk uji; produksi membuka basis data perangkat.
  final TrackingRepository? repository;
  final DateTime Function()? now;

  @override
  State<BerandaPage> createState() => _BerandaPageState();
}

class _BerandaPageState extends State<BerandaPage> {
  late final AccountController _account;
  late final bool _ownsAccount;
  late final DateTime Function() _now;

  AppDatabase? _database;
  StreamSubscription<List<TrackingSession>>? _sessions;
  TrackingSession? _summarySession;
  KartuData? _summary;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _ownsAccount = widget.accountController == null;
    _account = widget.accountController ?? SupabaseServices.createAccountController();
    _account.initialize();
    _now = widget.now ?? DateTime.now;
    unawaited(_watchSummary());
  }

  @override
  void dispose() {
    unawaited(_sessions?.cancel());
    final database = _database;
    if (database != null) unawaited(database.close());
    if (_ownsAccount) _account.dispose();
    super.dispose();
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
        .where((session) => session.status == TrackingSessionStatus.completed)
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
    if (session.id == _summarySession?.id && _summary != null) return;
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

  /// Nama gunung hanya disebut bila sesi memang tertaut grup yang dikenal.
  String? _mountainOf(TrackingSession? session) {
    final groupId = session?.groupId;
    if (groupId == null) return null;
    for (final remote in _account.groups) {
      if (remote.group.id == groupId) {
        return remote.group.mountain ?? remote.group.name;
      }
    }
    return null;
  }

  List<FeatureEntry> _features(BuildContext context) => <FeatureEntry>[
        FeatureEntry(
          icon: HiqeoIcons.activity,
          title: 'Pelacakan',
          subtitle: 'Jarak, pace, elevasi',
          onTap: () => context.go('/lacak'),
        ),
        FeatureEntry(
          icon: HiqeoIcons.map,
          title: 'Peta offline',
          subtitle: 'Topografi per gunung',
          onTap: () => context.go('/peta'),
        ),
        FeatureEntry(
          icon: HiqeoIcons.trail,
          title: 'Jalur terverifikasi',
          subtitle: 'Pos, air, area bahaya',
          onTap: () => context.go('/peta'),
        ),
        FeatureEntry(
          icon: HiqeoIcons.compass,
          title: 'Kompas',
          subtitle: 'Bearing dan jarak',
          onTap: () => context.go('/peta'),
        ),
        FeatureEntry(
          icon: HiqeoIcons.group,
          title: 'Grup chat',
          subtitle: 'Teks, suara, gambar',
          onTap: () => context.go('/grup'),
        ),
        FeatureEntry(
          icon: HiqeoIcons.pin,
          title: 'Lokasi terakhir',
          subtitle: 'Posisi tiap anggota',
          onTap: () => context.go('/grup'),
        ),
        FeatureEntry(
          icon: HiqeoIcons.image,
          title: 'Kartu pendakian',
          subtitle: 'Foto dan ringkasan',
          onTap: () => context.push('/kartu'),
        ),
        FeatureEntry(
          icon: HiqeoIcons.warning,
          title: 'SOS',
          subtitle: 'Tekan-tahan 3 detik',
          onTap: () => context.push('/sos'),
          emphasis: true,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final sessionId = _summarySession?.id;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: _account,
        builder: (context, _) {
          final next = nextHikeOf(_account.groups);
          final keyStatus =
              next == null ? null : _account.keyStatusFor(next.group.id);
          final profile = _account.profile;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              HiqeoSpacing.lg,
              HiqeoSpacing.xl,
              HiqeoSpacing.lg,
              HiqeoSpacing.xl + bottomInset,
            ),
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    greetingForHour(_now().hour),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: HiqeoSpacing.xs),
                  Text(
                    'Halo, ${profile?.username ?? 'Pendaki'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.displaySmall,
                  ),
                ],
              ),
              const SizedBox(height: HiqeoSpacing.xl),
              _HeroCard(
                title: next?.group.mountain ?? next?.group.name ?? 'Belum ada pendakian',
                meta: next == null
                    ? 'Belum ada rombongan. Siapkan pendakian untuk mulai.'
                    : nextHikeMeta(keyStatus),
                onPrepare: () => context.push('/siap-naik'),
              ),
              const SizedBox(height: HiqeoSpacing.xl),
              LastTripSummaryCard(
                data: _summary,
                mountain: _mountainOf(_summarySession),
                unavailableReason: _summaryError,
                onViewKartu: sessionId == null
                    ? null
                    : () => context.push(
                          '/kartu?sesi=${Uri.encodeQueryComponent(sessionId)}',
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
