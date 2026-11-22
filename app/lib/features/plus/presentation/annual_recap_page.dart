import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/background/page_background.dart';
import '../../../design/gooey/gooey_switch.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../kartu/application/kartu_exporter.dart';
import '../../tracking/domain/track_point.dart';
import '../../tracking/domain/tracking_repository.dart';
import '../../tracking/domain/tracking_session.dart';
import '../application/plus_scope.dart';
import '../domain/annual_recap.dart';
import '../domain/hike_analytics.dart';
import 'widgets/annual_recap_card.dart';
import 'widgets/plus_widgets.dart';

/// D5 Rekap Tahunan.
///
/// Layar dan kartunya selalu gelap karena kartu ini juga dibagikan sebagai
/// PNG. Warna tetap diambil dari token gelap lewat [Theme] lokal, bukan
/// warna langsung, sehingga mode terang aplikasi tidak mengubah kartu.
class AnnualRecapPage extends StatefulWidget {
  const AnnualRecapPage({
    super.key,
    this.repository,
    this.exporter = const DeviceKartuExporter(),
    this.nowLocal,
  });

  final TrackingRepository? repository;
  final KartuExporter exporter;
  final DateTime? nowLocal;

  @override
  State<AnnualRecapPage> createState() => _AnnualRecapPageState();
}

class _AnnualRecapPageState extends State<AnnualRecapPage> {
  final GlobalKey _boundaryKey = GlobalKey();

  AppDatabase? _database;
  bool _loading = true;
  String? _error;
  AnnualRecap? _recap;
  bool _hideLocations = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    final database = _database;
    if (database != null) {
      DriftTrackingRepository.unregisterDatabase(database);
      unawaited(database.close());
    }
    super.dispose();
  }

  Future<TrackingRepository?> _openRepository() async {
    final injected = widget.repository;
    if (injected != null) return injected;
    final existing = _database;
    if (existing != null) return DriftTrackingRepository(existing);
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = await _openRepository();
    if (!mounted) return;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = 'Data pendakian lokal belum dapat dibuka.';
      });
      return;
    }
    try {
      final sessions = await repository.watchSessions().first;
      final completed = sessions
          .where((session) => session.status == TrackingSessionStatus.completed)
          .toList()
        ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
      final samples = <HikeSample>[];
      for (final session in completed) {
        List<TrackPoint> points = const <TrackPoint>[];
        try {
          points = await repository.points(session.id);
        } catch (_) {
          points = const <TrackPoint>[];
        }
        samples.add(HikeSample(session: session, points: points));
      }
      if (!mounted) return;
      setState(() {
        _recap = AnnualRecap.build(
          samples: samples,
          nowLocal: widget.nowLocal ?? DateTime.now(),
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Riwayat pendakian belum dapat dibaca.';
      });
    }
  }

  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await widget.exporter.capturePng(_boundaryKey);
      if (!mounted) return;
      if (bytes == null) {
        _notify('Kartu belum bisa dibuat. Coba lagi.');
        return;
      }
      final shared = await widget.exporter.sharePng(
        bytes,
        'hiqeo-rekap-${_recap?.year ?? DateTime.now().year}.png',
      );
      if (!mounted) return;
      _notify(
        shared
            ? 'Kartu siap dibagikan.'
            : 'Lembar berbagi belum bisa dibuka di perangkat ini.',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = Theme.of(context).copyWith(
      extensions: const <ThemeExtension<dynamic>>[HiqeoColors.dark],
    );
    return Theme(
      data: darkTheme,
      child: Builder(
        builder: (context) => PageBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      HiqeoSpacing.lg,
                      HiqeoSpacing.sm,
                      HiqeoSpacing.lg,
                      HiqeoSpacing.sm,
                    ),
                    child: Row(
                      children: <Widget>[
                        PlusCircleButton(
                          icon: HiqeoIcons.chevronLeft,
                          label: 'Kembali',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const Spacer(),
                        const _RecapBadgePill(),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: HiqeoSpacing.lg),
                      child: _content(context),
                    ),
                  ),
                  if (_recap != null && !_recap!.isEmpty)
                    _bottomControls(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: HiqeoSpacing.xxl),
        child: Center(
          child: CircularProgressIndicator(color: HiqeoColors.dark.primary),
        ),
      );
    }
    if (_error != null) {
      return _DarkEmptyState(
        icon: HiqeoIcons.warning,
        title: 'Rekap belum bisa dibuka',
        message: _error!,
        action: HiqeoButton(
          label: 'Coba lagi',
          variant: HiqeoButtonVariant.secondary,
          onPressed: _load,
        ),
      );
    }
    final recap = _recap;
    if (recap == null || recap.isEmpty) {
      return _DarkEmptyState(
        icon: HiqeoIcons.mountain,
        title: 'Belum ada pendakian di ${recap?.year ?? DateTime.now().year}',
        message: 'Rekap terbentuk dari sesi yang selesai dan tersimpan di HP '
            'ini. Selesaikan satu pendakian untuk melihat kartunya.',
        action: HiqeoButton(
          label: 'Mulai pendakian',
          onPressed: () => context.go('/lacak'),
        ),
      );
    }
    final peakBadges = PlusScope.maybeOf(context)?.peakBadgesEnabled ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        RepaintBoundary(
          key: _boundaryKey,
          child: AnnualRecapCard(
            recap: recap,
            hideLocations: _hideLocations,
            peakBadgesEnabled: peakBadges,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HiqeoSpacing.lg,
            HiqeoSpacing.md,
            HiqeoSpacing.lg,
            0,
          ),
          child: PlusNotice(
            icon: HiqeoIcons.lock,
            text: 'Lokasi hanya disembunyikan di gambar kartu. Data GPS dan '
                'riwayat di HP ini tidak diubah.',
          ),
        ),
      ],
    );
  }

  Widget _bottomControls(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HiqeoSpacing.lg,
        HiqeoSpacing.sm,
        HiqeoSpacing.lg,
        HiqeoSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Sembunyikan lokasi di kartu',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              GooeySwitch(
                key: const ValueKey<String>('recap-location-switch'),
                value: _hideLocations,
                onChanged: (value) => setState(() => _hideLocations = value),
                semanticsLabel: 'Sembunyikan lokasi di kartu',
                style: GooeySwitchStyle.recap(HiqeoColors.dark),
              ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          HiqeoButton(
            label: _sharing ? 'Menyiapkan…' : 'Bagikan kartu',
            onPressed: _sharing ? null : _shareCard,
          ),
        ],
      ),
    );
  }
}

class _RecapBadgePill extends StatelessWidget {
  const _RecapBadgePill();

  @override
  Widget build(BuildContext context) {
    const colors = HiqeoColors.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(HiqeoRadius.pill),
            ),
            child: Text(
              'PLUS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    letterSpacing: 1.2,
                    color: colors.onPrimary,
                  ),
            ),
          ),
          const SizedBox(width: HiqeoSpacing.sm),
          Text(
            'Rekap mendalam',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _DarkEmptyState extends StatelessWidget {
  const _DarkEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  final HiqeoIconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    const colors = HiqeoColors.dark;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(HiqeoSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(HiqeoSpacing.lg),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(HiqeoRadius.card),
          border: Border.all(color: colors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: HiqeoIcon(icon, size: 20, color: colors.primary),
              ),
            ),
            const SizedBox(height: HiqeoSpacing.md),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: HiqeoSpacing.xs),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: HiqeoSpacing.md),
            action,
          ],
        ),
      ),
    );
  }
}
