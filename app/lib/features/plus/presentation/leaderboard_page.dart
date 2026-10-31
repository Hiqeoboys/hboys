import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/glass/glass_surface.dart';
import '../../../design/gooey/gooey_selector.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../application/plus_navigation.dart';
import '../application/plus_scope.dart';
import '../domain/leaderboard.dart';
import '../plus_content_dependencies.dart';
import 'widgets/leaderboard_consent_sheet.dart';
import 'widgets/plus_widgets.dart';

/// D7/D8 satu layar papan peringkat dengan tab Nasional/Grup.
///
/// Kategori dan periode berada di luar konten sehingga pilihannya bertahan
/// saat tab berganti; hanya isi papan yang dimuat ulang. Papan nasional boleh
/// dilihat semua pengguna, tetapi hanya Plus yang bisa ikut. Semua angka pada
/// tahap ini berasal dari repositori dummy debug.
class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key, this.repository, this.consentStore});

  final LeaderboardRepository? repository;
  final LeaderboardConsentStore? consentStore;

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  LeaderboardScope _scope = LeaderboardScope.national;
  LeaderboardMetric _metric = LeaderboardMetric.totalMountains;
  LeaderboardPeriod _period = LeaderboardPeriod.monthly;

  LeaderboardBoard? _board;
  bool _loading = true;
  String? _error;
  int _loadToken = 0;
  bool _started = false;

  bool? _consentVisible;
  final Set<String> _hiddenNames = <String>{};

  LeaderboardRepository get _repository =>
      widget.repository ?? PlusContentDependencies.leaderboard;

  LeaderboardConsentStore get _consentStore =>
      widget.consentStore ?? PlusContentDependencies.leaderboardConsent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = PlusScope.maybeOf(context)?.leaderboardEnabled ?? false;
    if (!enabled || _started) return;
    _started = true;
    unawaited(_loadConsent());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _loadConsent() async {
    try {
      final visible = await _consentStore.readVisible();
      if (!mounted) return;
      setState(() => _consentVisible = visible);
    } catch (_) {
      // Penyimpanan lokal bermasalah diperlakukan seperti belum menyetujui.
    }
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final board = await _repository.load(
        scope: _scope,
        metric: _metric,
        period: _period,
      );
      if (!mounted || token != _loadToken) return;
      setState(() {
        _board = board;
        _loading = false;
      });
    } on LeaderboardUnavailable catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _error = 'Papan peringkat belum bisa dibuka.';
        _loading = false;
      });
    }
  }

  void _selectScope(LeaderboardScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _board = null;
    });
    unawaited(_load());
  }

  void _selectMetric(LeaderboardMetric metric) {
    if (metric == _metric) return;
    setState(() {
      _metric = metric;
      _board = null;
    });
    unawaited(_load());
  }

  void _selectPeriod(LeaderboardPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _board = null;
    });
    unawaited(_load());
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openConsent() async {
    final board = _board;
    if (board == null) return;
    final hasPlus = PlusScope.maybeOf(context)?.hasPlus ?? false;
    if (!hasPlus) {
      openPlusPaywall(context);
      return;
    }
    final displayName = board.currentUser?.displayName ?? 'Pendaki';
    final result = await showLeaderboardConsentSheet(
      context,
      displayName: displayName,
      storedVisible: _consentVisible,
    );
    if (!mounted || result == null) return;
    try {
      await _consentStore.writeVisible(result);
    } catch (_) {
      if (mounted) _notify('Pilihan belum bisa disimpan di HP ini.');
      return;
    }
    if (!mounted) return;
    setState(() => _consentVisible = result);
    _notify(
      result ? 'Kamu ikut papan nasional.' : 'Nama kamu tidak ditampilkan.',
    );
  }

  Future<void> _openOptions(LeaderboardEntry entry) async {
    final metric = _board?.metric ?? _metric;
    final action = await showModalBottomSheet<_ModerationAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _OptionsSheet(entry: entry, metric: metric),
    );
    if (!mounted || action == null) return;
    try {
      if (action == _ModerationAction.report) {
        final delivered = await _repository.report(entry.displayName);
        if (!mounted) return;
        _notify(
          delivered
              ? 'Laporan terkirim untuk ditinjau.'
              : 'Laporan belum terkirim: server peninjauan belum tersedia.',
        );
      } else {
        final blocked = await _repository.block(entry.displayName);
        if (!mounted) return;
        setState(() => _hiddenNames.add(entry.displayName));
        _notify(
          blocked
              ? '${entry.displayName} diblokir dari papan.'
              : '${entry.displayName} disembunyikan dari papan ini. '
                  'Server belum tersedia.',
        );
      }
    } on LeaderboardUnavailable catch (error) {
      if (mounted) _notify(error.message);
    } catch (_) {
      if (mounted) _notify('Tindakan belum bisa diselesaikan.');
    }
  }

  List<LeaderboardEntry> _visibleEntries(LeaderboardBoard board) =>
      board.entries
          .where((entry) => !_hiddenNames.contains(entry.displayName))
          .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final plus = PlusScope.maybeOf(context);
    final enabled = plus?.leaderboardEnabled ?? false;
    final topBar = PlusTopBar(
      title: 'Leaderboard',
      onBack: () => Navigator.of(context).maybePop(),
    );
    if (!enabled) {
      return PlusScrollPage(
        topBar: topBar,
        children: <Widget>[
          PlusEmptyState(
            icon: HiqeoIcons.trophy,
            title: 'Leaderboard belum tersedia',
            message: 'Papan peringkat dirilis bertahap dan belum aktif di '
                'versi ini.',
          ),
        ],
      );
    }
    final hasPlus = plus?.hasPlus ?? false;
    final selfName = _board?.currentUser?.displayName ?? 'Pendaki';
    return PlusScrollPage(
      topBar: topBar,
      children: <Widget>[
        _Segmented<LeaderboardScope>(
          key: const ValueKey('leaderboard-scope-tabs'),
          options: const <_Segment<LeaderboardScope>>[
            _Segment<LeaderboardScope>(
              value: LeaderboardScope.national,
              label: 'Nasional',
            ),
            _Segment<LeaderboardScope>(
              value: LeaderboardScope.group,
              label: 'Grup',
            ),
          ],
          selected: _scope,
          onChanged: _selectScope,
        ),
        const SizedBox(height: HiqeoSpacing.sm),
        _Segmented<LeaderboardMetric>(
          key: const ValueKey('leaderboard-metric-tabs'),
          options: const <_Segment<LeaderboardMetric>>[
            _Segment<LeaderboardMetric>(
              value: LeaderboardMetric.totalMountains,
              label: 'Total gunung',
            ),
            _Segment<LeaderboardMetric>(
              value: LeaderboardMetric.totalDistance,
              label: 'Total jarak',
            ),
          ],
          selected: _metric,
          onChanged: _selectMetric,
        ),
        const SizedBox(height: HiqeoSpacing.sm),
        _Segmented<LeaderboardPeriod>(
          key: const ValueKey('leaderboard-period-tabs'),
          options: const <_Segment<LeaderboardPeriod>>[
            _Segment<LeaderboardPeriod>(
              value: LeaderboardPeriod.weekly,
              label: 'Mingguan',
            ),
            _Segment<LeaderboardPeriod>(
              value: LeaderboardPeriod.monthly,
              label: 'Bulanan',
            ),
            _Segment<LeaderboardPeriod>(
              value: LeaderboardPeriod.yearly,
              label: 'Tahunan',
            ),
          ],
          selected: _period,
          onChanged: _selectPeriod,
        ),
        const SizedBox(height: HiqeoSpacing.lg),
        ..._body(hasPlus: hasPlus, selfName: selfName),
      ],
    );
  }

  List<Widget> _body({required bool hasPlus, required String selfName}) {
    if (_loading) return const <Widget>[_LoadingCard()];
    final error = _error;
    if (error != null) {
      return <Widget>[
        PlusEmptyState(
          icon: HiqeoIcons.trophy,
          title: 'Papan belum bisa dibuka',
          message: error,
          action: HiqeoButton(
            label: 'Coba lagi',
            variant: HiqeoButtonVariant.secondary,
            onPressed: _load,
          ),
        ),
      ];
    }
    final board = _board;
    if (board == null) return const <Widget>[];
    if (board.entries.isEmpty) {
      return <Widget>[
        PlusEmptyState(
          icon: HiqeoIcons.trophy,
          title: 'Papan masih kosong',
          message: 'Belum ada pendakian yang dihitung untuk kategori dan '
              'periode ini.',
          action: HiqeoButton(
            label: 'Coba lagi',
            variant: HiqeoButtonVariant.secondary,
            onPressed: _load,
          ),
        ),
      ];
    }
    switch (board.scope) {
      case LeaderboardScope.national:
        return _nationalContent(
          board,
          hasPlus: hasPlus,
          selfName: selfName,
        );
      case LeaderboardScope.group:
        return _groupContent(board, hasPlus: hasPlus);
    }
  }

  List<Widget> _nationalContent(
    LeaderboardBoard board, {
    required bool hasPlus,
    required String selfName,
  }) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final visible = _visibleEntries(board);
    final podium = visible.take(3).toList(growable: false);
    final rest = visible.skip(3).toList(growable: false);
    return <Widget>[
      if (podium.isEmpty)
        PlusNotice(
          icon: HiqeoIcons.warning,
          text: 'Semua baris pada papan ini disembunyikan di perangkat.',
        )
      else
        _Podium(
          entries: podium,
          metric: board.metric,
          onOptions: _openOptions,
        ),
      const SizedBox(height: HiqeoSpacing.md),
      if (rest.isNotEmpty)
        _RankList(
          entries: rest,
          metric: board.metric,
          onOptions: _openOptions,
        ),
      if (rest.isNotEmpty) const SizedBox(height: HiqeoSpacing.md),
      _SelfCard(
        hasPlus: hasPlus,
        visible: _consentVisible,
        displayName: selfName,
        onTap: _openConsent,
      ),
      const SizedBox(height: HiqeoSpacing.md),
      Text(
        '10 besar per kategori. Server menghitung ulang dari jejak mentah dan '
        'papan diperbarui terjadwal, bukan real-time.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.textSecondary,
        ),
      ),
    ];
  }

  List<Widget> _groupContent(
    LeaderboardBoard board, {
    required bool hasPlus,
  }) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final entries = _visibleEntries(board);
    final memberCount =
        board.groupMemberCount > 0 ? board.groupMemberCount : entries.length;
    return <Widget>[
      Text(
        '${board.groupName ?? 'Grup'} · $memberCount anggota',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.textSecondary,
        ),
      ),
      const SizedBox(height: HiqeoSpacing.sm),
      for (final entry in entries) ...<Widget>[
        _GroupRow(
          entry: entry,
          metric: board.metric,
          progress: board.progressFor(entry),
        ),
        const SizedBox(height: HiqeoSpacing.sm),
      ],
      Text(
        'Semua anggota ikut bersaing, gratis. Statistik dibagikan ke grup saat '
        'bergabung.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.textSecondary,
        ),
      ),
      if (!hasPlus) ...<Widget>[
        const SizedBox(height: HiqeoSpacing.lg),
        _PlusPromo(onTap: () => openPlusPaywall(context)),
      ],
    ];
  }
}

class _Segment<T> {
  const _Segment({required this.value, required this.label});

  final T value;
  final String label;
}

/// Pemilih selebar layar dengan tiga item yang sama besar.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<_Segment<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const double outer = 4;
        const double gap = 4;
        final count = options.length;
        final width =
            (constraints.maxWidth - outer * 2 - gap * (count - 1)) / count;
        return GlassSurface(
          borderRadius: HiqeoRadius.pill,
          child: GooeySelector<T>(
            axis: Axis.horizontal,
            padding: const EdgeInsets.all(outer),
            gap: gap,
            itemPadding: EdgeInsets.zero,
            borderRadius: HiqeoRadius.pill,
            items: <GooeySelectorItem<T>>[
              for (final option in options)
                GooeySelectorItem<T>(
                  value: option.value,
                  semanticsLabel: option.label,
                  builder: (context, state) => SizedBox(
                    width: width,
                    height: 44,
                    child: Center(
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: HiqeoTypography.bold,
                          color: Color.lerp(
                            colors.textPrimary,
                            colors.onPrimary,
                            state.coverage,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            selected: selected,
            onChanged: onChanged,
          ),
        );
      },
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({
    required this.entries,
    required this.metric,
    required this.onOptions,
  });

  final List<LeaderboardEntry> entries;
  final LeaderboardMetric metric;
  final ValueChanged<LeaderboardEntry> onOptions;

  @override
  Widget build(BuildContext context) {
    LeaderboardEntry? at(int index) =>
        index < entries.length ? entries[index] : null;
    final first = at(0);
    final second = at(1);
    final third = at(2);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: second == null
              ? const SizedBox.shrink()
              : _PodiumCard(
                  entry: second,
                  height: 142,
                  metric: metric,
                  onOptions: onOptions,
                ),
        ),
        const SizedBox(width: HiqeoSpacing.sm),
        Expanded(
          child: first == null
              ? const SizedBox.shrink()
              : _PodiumCard(
                  entry: first,
                  height: 160,
                  metric: metric,
                  onOptions: onOptions,
                ),
        ),
        const SizedBox(width: HiqeoSpacing.sm),
        Expanded(
          child: third == null
              ? const SizedBox.shrink()
              : _PodiumCard(
                  entry: third,
                  height: 142,
                  metric: metric,
                  onOptions: onOptions,
                ),
        ),
      ],
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({
    required this.entry,
    required this.height,
    required this.metric,
    required this.onOptions,
  });

  final LeaderboardEntry entry;
  final double height;
  final LeaderboardMetric metric;
  final ValueChanged<LeaderboardEntry> onOptions;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final first = entry.rank == 1;
    return SizedBox(
      height: height,
      child: PlusCard(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, HiqeoSpacing.md),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: first
                          ? colors.primary
                          : colors.secondary.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${entry.rank}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: first ? colors.onPrimary : colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: HiqeoSpacing.sm),
                  Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    leaderboardValueLabel(metric, entry.value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: _MoreButton(
                key: ValueKey<String>(
                  'leaderboard-more-${entry.displayName}',
                ),
                entry: entry,
                onTap: () => onOptions(entry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankList extends StatelessWidget {
  const _RankList({
    required this.entries,
    required this.metric,
    required this.onOptions,
  });

  final List<LeaderboardEntry> entries;
  final LeaderboardMetric metric;
  final ValueChanged<LeaderboardEntry> onOptions;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return PlusCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: <Widget>[
          for (var index = 0; index < entries.length; index++) ...<Widget>[
            if (index > 0)
              Divider(
                  color: colors.hairline, height: 1, indent: HiqeoSpacing.md),
            SizedBox(
              height: 60,
              child: Row(
                key: ValueKey<String>(
                  'leaderboard-entry-${entries[index].displayName}',
                ),
                children: <Widget>[
                  SizedBox(
                    width: 34,
                    child: Center(
                      child: Text(
                        '${entries[index].rank}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.secondary.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        entries[index].initial,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: HiqeoSpacing.md),
                  Expanded(
                    child: Text(
                      entries[index].displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: HiqeoSpacing.sm),
                  Text(
                    leaderboardValueLabel(metric, entries[index].value),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _MoreButton(
                    key: ValueKey<String>(
                      'leaderboard-more-${entries[index].displayName}',
                    ),
                    entry: entries[index],
                    onTap: () => onOptions(entries[index]),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final LeaderboardEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return Semantics(
      button: true,
      label: 'Opsi untuk ${entry.displayName}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: HiqeoIcon(
              HiqeoIcons.more,
              size: 18,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.entry,
    required this.metric,
    required this.progress,
  });

  final LeaderboardEntry entry;
  final LeaderboardMetric metric;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final highlight = entry.isCurrentUser;
    final foreground = highlight ? colors.onPrimary : colors.textPrimary;
    final secondary = highlight
        ? colors.onPrimary.withValues(alpha: 0.78)
        : colors.textSecondary;
    final track = highlight
        ? colors.onPrimary.withValues(alpha: 0.22)
        : colors.secondary.withValues(alpha: 0.5);
    final fill = highlight ? colors.onPrimary : colors.primary;
    final valueLabel = leaderboardValueLabel(metric, entry.value);
    final name =
        entry.isCurrentUser ? '${entry.displayName} (kamu)' : entry.displayName;
    final content = Padding(
      padding: const EdgeInsets.all(HiqeoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 22,
                child: Text(
                  '${entry.rank}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: secondary,
                  ),
                ),
              ),
              const SizedBox(width: HiqeoSpacing.sm),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
              const SizedBox(width: HiqeoSpacing.sm),
              Text(
                valueLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 6,
            child: LayoutBuilder(
              builder: (context, constraints) => ClipRRect(
                borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: ColoredBox(color: track),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: constraints.maxWidth * progress,
                        color: fill,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: 'Peringkat ${entry.rank}, $name, $valueLabel',
      child: highlight
          ? Container(
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(HiqeoRadius.card),
              ),
              child: content,
            )
          : GlassSurface(
              borderRadius: HiqeoRadius.card,
              child: content,
            ),
    );
  }
}

class _SelfCard extends StatelessWidget {
  const _SelfCard({
    required this.hasPlus,
    required this.visible,
    required this.displayName,
    required this.onTap,
  });

  final bool hasPlus;
  final bool? visible;
  final String displayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final Widget label;
    if (!hasPlus) {
      label = Text(
        'Papan nasional untuk pengguna Plus',
        style: theme.textTheme.titleSmall,
      );
    } else if (visible == null) {
      label = Text('Ikut papan nasional', style: theme.textTheme.titleSmall);
    } else if (visible!) {
      label = Text.rich(
        TextSpan(
          children: <InlineSpan>[
            const TextSpan(text: 'Kamu tampil sebagai '),
            TextSpan(
              text: displayName,
              style: const TextStyle(
                fontWeight: HiqeoTypography.extraBold,
              ),
            ),
          ],
        ),
        style: theme.textTheme.titleSmall,
      );
    } else {
      label = Text(
        'Kamu tidak tampil di papan',
        style: theme.textTheme.titleSmall,
      );
    }
    return PlusCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('leaderboard-self-card'),
          borderRadius: BorderRadius.circular(HiqeoRadius.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: HiqeoSpacing.lg,
              vertical: HiqeoSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Expanded(child: label),
                const SizedBox(width: HiqeoSpacing.sm),
                Text(
                  hasPlus ? 'Kelola' : 'Butuh Plus',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 2),
                HiqeoIcon(
                  HiqeoIcons.chevronRight,
                  size: 16,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlusPromo extends StatelessWidget {
  const _PlusPromo({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return PlusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              HiqeoIcon(HiqeoIcons.trophy, size: 20, color: colors.primary),
              const SizedBox(width: HiqeoSpacing.sm),
              Expanded(
                child: Text(
                  'Ingin bersaing di papan nasional?',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: HiqeoSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                ),
                child: Text(
                  'PLUS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: colors.onPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            'Plus membuka papan nasional untukmu. Kamu tetap bisa melihatnya '
            'dengan akun gratis.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          HiqeoButton(
            key: const ValueKey('leaderboard-plus-cta'),
            label: 'Lihat HIQEO Plus',
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}

enum _ModerationAction { report, block }

class _OptionsSheet extends StatelessWidget {
  const _OptionsSheet({required this.entry, required this.metric});

  final LeaderboardEntry entry;
  final LeaderboardMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(HiqeoSpacing.md),
        child: PlusCard(
          radius: HiqeoRadius.hero,
          padding: const EdgeInsets.all(HiqeoSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(entry.displayName, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text(
                'Peringkat ${entry.rank} · '
                '${leaderboardValueLabel(metric, entry.value)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: HiqeoSpacing.lg),
              HiqeoButton(
                key: const ValueKey('leaderboard-option-report'),
                label: 'Laporkan',
                variant: HiqeoButtonVariant.secondary,
                leading: HiqeoIcon(
                  HiqeoIcons.warning,
                  size: 16,
                  color: colors.textPrimary,
                ),
                onPressed: () =>
                    Navigator.of(context).pop(_ModerationAction.report),
              ),
              const SizedBox(height: HiqeoSpacing.sm),
              HiqeoButton(
                key: const ValueKey('leaderboard-option-block'),
                label: 'Blokir',
                variant: HiqeoButtonVariant.secondary,
                leading: HiqeoIcon(
                  HiqeoIcons.lock,
                  size: 16,
                  color: colors.textPrimary,
                ),
                onPressed: () =>
                    Navigator.of(context).pop(_ModerationAction.block),
              ),
              const SizedBox(height: HiqeoSpacing.sm),
              Text(
                'Laporan dan blokir belum terhubung ke server peninjauan pada '
                'build ini.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              Center(
                child: TextButton(
                  key: const ValueKey('leaderboard-option-cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return PlusCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HiqeoSpacing.xxl),
        child: Center(
          child: Semantics(
            label: 'Memuat papan peringkat',
            child: CircularProgressIndicator(
              color: colors.primary,
              strokeWidth: 2.5,
            ),
          ),
        ),
      ),
    );
  }
}
