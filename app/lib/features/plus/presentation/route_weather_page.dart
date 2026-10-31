import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/gooey/gooey_selector.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../domain/plus_format.dart';
import '../domain/route_weather.dart';
import '../plus_content_dependencies.dart';
import 'widgets/plus_widgets.dart';

/// D2 Cuaca Rute.
///
/// Prakiraan diambil lewat repositori (kelak backend ber-cache BMKG), lalu
/// disimpan di perangkat. Selama cache masih segar, layar tidak mengunduh
/// ulang; saat unduhan gagal, data tersimpan tetap ditampilkan dengan label
/// "tersimpan offline".
class RouteWeatherPage extends StatefulWidget {
  const RouteWeatherPage({
    super.key,
    required this.routeName,
    this.repository,
    this.cache,
    this.nowUtc,
  });

  final String routeName;
  final RouteWeatherRepository? repository;
  final RouteWeatherCache? cache;
  final DateTime? nowUtc;

  static const Duration refreshInterval = Duration(hours: 12);

  @override
  State<RouteWeatherPage> createState() => _RouteWeatherPageState();
}

class _RouteWeatherPageState extends State<RouteWeatherPage> {
  RouteWeatherForecast? _forecast;
  bool _fromCache = false;
  bool _loading = true;
  String? _error;
  int _selectedDay = 0;

  String get _routeName {
    final name = widget.routeName.trim();
    return name.isEmpty ? 'Rute pendakian' : name;
  }

  DateTime get _nowUtc => widget.nowUtc ?? DateTime.now().toUtc();

  RouteWeatherRepository get _repository =>
      widget.repository ?? PlusContentDependencies.routeWeather;

  RouteWeatherCache get _cache =>
      widget.cache ?? PlusContentDependencies.weatherCache;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    RouteWeatherForecast? cached;
    try {
      cached = await _cache.read(_routeName);
    } catch (_) {
      cached = null;
    }
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _forecast = cached;
        _fromCache = true;
        _selectedDay = _selectedDay.clamp(0, cached!.days.length - 1);
      });
      final age = _nowUtc.difference(cached.fetchedAtUtc);
      if (age >= Duration.zero && age < RouteWeatherPage.refreshInterval) {
        setState(() => _loading = false);
        return;
      }
    }
    try {
      final fresh = await _repository.fetch(
        routeName: _routeName,
        nowLocal: _nowUtc.toLocal(),
      );
      try {
        await _cache.write(fresh);
      } catch (_) {
        // Cache gagal ditulis; data tetap dipakai untuk sesi ini.
      }
      if (!mounted) return;
      setState(() {
        _forecast = fresh;
        _fromCache = false;
        _loading = false;
        _selectedDay = _selectedDay.clamp(0, fresh.days.length - 1);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is RouteWeatherUnavailable
            ? error.message
            : 'Cuaca rute belum dapat dimuat.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final forecast = _forecast;
    final day = forecast == null ||
            forecast.days.isEmpty ||
            _selectedDay >= forecast.days.length
        ? null
        : forecast.days[_selectedDay];

    return PlusScrollPage(
      topBar: PlusTopBar(
        title: 'Cuaca rute',
        subtitle: _routeName,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      children: <Widget>[
        if (forecast == null)
          _emptyOrLoading()
        else ...<Widget>[
          _DayTabs(
            days: forecast.days,
            selected: day?.dateLocal,
            onChanged: (date) {
              final index = forecast.days.indexWhere(
                (item) => item.dateLocal == date,
              );
              if (index >= 0) setState(() => _selectedDay = index);
            },
          ),
          const SizedBox(height: HiqeoSpacing.md),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: day == null
                ? const SizedBox.shrink()
                : _DayContent(
                    key: ValueKey<String>(day.dateLocal.toIso8601String()),
                    day: day,
                  ),
          ),
          const SizedBox(height: HiqeoSpacing.lg),
          _attribution(forecast),
          if (_loading) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: HiqeoSpacing.sm),
                Text(
                  'Memperbarui prakiraan…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: HiqeoColors.of(context).textSecondary,
                      ),
                ),
              ],
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.md),
            PlusNotice(
              icon: HiqeoIcons.warning,
              text: '$_error Data tersimpan tetap dipakai.',
            ),
          ],
        ],
      ],
    );
  }

  Widget _emptyOrLoading() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: HiqeoSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return PlusEmptyState(
      icon: HiqeoIcons.cloud,
      title: 'Cuaca belum tersedia',
      message: _error ??
          'Prakiraan rute belum bisa dimuat. Data cuaca diambil lewat server '
              'dan disimpan di HP ini untuk dipakai tanpa sinyal.',
      action: HiqeoButton(
        label: 'Coba lagi',
        variant: HiqeoButtonVariant.secondary,
        onPressed: _load,
      ),
    );
  }

  Widget _attribution(RouteWeatherForecast forecast) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PlusNotice(
          icon: HiqeoIcons.cloud,
          text: forecast.isOfficial
              ? 'Sumber: BMKG · perkiraan, bukan jaminan. Cuaca gunung dapat '
                  'berubah cepat.'
              : 'Data demo lokal, bukan prakiraan BMKG. Prakiraan resmi nanti '
                  'bersumber dari BMKG dan ditandai "perkiraan".',
        ),
        const SizedBox(height: HiqeoSpacing.xs),
        Text(
          'Diperbarui ${formatDate(forecast.fetchedAtUtc)} '
          '${formatClock(forecast.fetchedAtUtc.toLocal())}'
          '${_fromCache ? ' · tersimpan offline' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _DayTabs extends StatelessWidget {
  const _DayTabs({
    required this.days,
    required this.selected,
    required this.onChanged,
  });

  final List<RouteWeatherDay> days;
  final DateTime? selected;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    return GooeySelector<DateTime>(
      key: const ValueKey('weather-day-tabs'),
      axis: Axis.horizontal,
      items: <GooeySelectorItem<DateTime>>[
        for (final day in days)
          GooeySelectorItem<DateTime>(
            value: day.dateLocal,
            semanticsLabel:
                '${formatDayDate(day.dateLocal)}, ${day.condition.label}',
            builder: (context, state) => Text(
              formatDayShort(day.dateLocal),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Color.lerp(
                      HiqeoColors.of(context).textSecondary,
                      HiqeoColors.of(context).onPrimary,
                      state.coverage,
                    ),
                  ),
            ),
          ),
      ],
      selected: selected ?? days.first.dateLocal,
      gap: 6,
      itemPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onChanged: onChanged,
    );
  }
}

class _DayContent extends StatelessWidget {
  const _DayContent({super.key, required this.day});

  final RouteWeatherDay day;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PlusCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const PlusOverline('Suhu puncak · perkiraan'),
                    const SizedBox(height: HiqeoSpacing.xs),
                    Text(
                      formatTemperature(day.peakTemperatureC),
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: 36,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      day.condition.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: HiqeoSpacing.md,
                  vertical: HiqeoSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(HiqeoRadius.floating),
                ),
                child: Column(
                  children: <Widget>[
                    HiqeoIcon(
                      HiqeoIcons.cloud,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${day.peakRainPercent}%',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      'peluang hujan',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HiqeoSpacing.md),
        PlusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Per 3 jam',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  _LegendDot(color: colors.primary, label: 'Suhu'),
                  const SizedBox(width: HiqeoSpacing.sm),
                  _LegendDot(color: colors.secondary, label: 'Hujan'),
                ],
              ),
              const SizedBox(height: HiqeoSpacing.md),
              SizedBox(
                height: 120,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (final hour in day.hours)
                      Expanded(
                        child: _HourColumn(
                          hour: hour,
                          minTemp: day.hours
                              .map((item) => item.temperatureC)
                              .reduce((a, b) => a < b ? a : b),
                          maxTemp: day.hours
                              .map((item) => item.temperatureC)
                              .reduce((a, b) => a > b ? a : b),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HiqeoSpacing.md),
        PlusCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HiqeoSpacing.lg,
                  HiqeoSpacing.lg,
                  HiqeoSpacing.lg,
                  HiqeoSpacing.sm,
                ),
                child: Text(
                  'Per pos',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              for (var i = 0; i < day.posts.length; i++) ...<Widget>[
                if (i > 0) Divider(color: colors.hairline, height: 1),
                _PostRow(post: day.posts[i]),
              ],
              const SizedBox(height: HiqeoSpacing.sm),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: HiqeoColors.of(context).textSecondary,
              ),
        ),
      ],
    );
  }
}

class _HourColumn extends StatelessWidget {
  const _HourColumn({
    required this.hour,
    required this.minTemp,
    required this.maxTemp,
  });

  final RouteWeatherHour hour;
  final double minTemp;
  final double maxTemp;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final span = (maxTemp - minTemp).abs() < 1 ? 1.0 : maxTemp - minTemp;
    final tempFraction = ((hour.temperatureC - minTemp) / span).clamp(0.0, 1.0);
    final tempHeight = 26 + tempFraction * 34;
    final rainHeight = 4 + (hour.rainPercent / 100) * 30;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${hour.temperatureC.round()}°',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: 7,
                height: tempHeight,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: 4,
                height: rainHeight,
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${hour.rainPercent}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hour.timeLocal.hour.toString().padLeft(2, '0'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  const _PostRow({required this.post});

  final RouteWeatherPost post;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HiqeoSpacing.lg,
        vertical: HiqeoSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(post.name, style: theme.textTheme.titleSmall),
                if (post.altitudeM != null)
                  Text(
                    formatMeters(post.altitudeM!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                formatTemperature(post.temperatureC),
                style: theme.textTheme.titleMedium,
              ),
              Text(
                '${post.condition.label} · ${post.rainPercent}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
