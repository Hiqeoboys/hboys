import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/gooey/gooey_selector.dart';
import '../../../design/motion/visual_effect_policy.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../application/plus_navigation.dart';
import '../domain/plus_format.dart';
import '../domain/route_weather.dart';
import '../infrastructure/open_meteo_route_weather.dart';
import '../plus_content_dependencies.dart';
import 'widgets/plus_widgets.dart';

/// D2 Cuaca Rute.
///
/// Mengambil prakiraan nyata langsung dari perangkat via Open-Meteo API
/// (`https://api.open-meteo.com/v1/forecast`, 0 kueri Supabase) dan
/// menyimpannya di cache lokal agar tetap terbaca saat offline di gunung.
class RouteWeatherPage extends StatefulWidget {
  const RouteWeatherPage({
    super.key,
    required this.routeName,
    this.routeContext,
    this.repository,
    this.cache,
    this.nowUtc,
  });

  final String routeName;
  final PlusRouteContext? routeContext;
  final RouteWeatherRepository? repository;
  final RouteWeatherCache? cache;
  final DateTime? nowUtc;

  static const Duration refreshInterval = Duration(hours: 6);

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

  Future<void> _load({bool forceRefresh = false}) async {
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
      if (!forceRefresh &&
          age >= Duration.zero &&
          age < RouteWeatherPage.refreshInterval) {
        setState(() => _loading = false);
        return;
      }
    }
    try {
      final repo = _repository;
      final nowLocal = _nowUtc.toLocal();
      final fresh = repo is OpenMeteoRouteWeatherRepository &&
              widget.routeContext != null
          ? await repo.fetchForContext(
              route: widget.routeContext!,
              nowLocal: nowLocal,
            )
          : await repo.fetch(
              routeName: _routeName,
              nowLocal: nowLocal,
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
                    forecast: forecast,
                    day: day,
                    dayIndex: _selectedDay,
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
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    if (_loading) {
      final barColor = colors.hairline.withValues(alpha: 0.65);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PlusCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 12,
                  width: 110,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 36,
                  width: 96,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 12,
                  width: 210,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
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
                for (var i = 0; i < 3; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Container(
                        height: 14,
                        width: 104,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Container(
                        height: 14,
                        width: 72,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                'Memuat prakiraan cuaca rute…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      );
    }
    return PlusEmptyState(
      icon: HiqeoIcons.cloud,
      title: 'Cuaca belum tersedia',
      message: _error ??
          'Prakiraan cuaca rute belum bisa dimuat. Periksa koneksi internet '
              'lalu coba lagi agar tersimpan untuk dipakai offline.',
      action: HiqeoButton(
        label: 'Coba lagi',
        variant: HiqeoButtonVariant.secondary,
        onPressed: () => unawaited(_load(forceRefresh: true)),
      ),
    );
  }

  Widget _attribution(RouteWeatherForecast forecast) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final String sourceText;
    if (forecast.isOfficial) {
      sourceText = 'Sumber: BMKG · perkiraan, bukan jaminan. Cuaca gunung '
          'dapat berubah cepat.';
    } else if (forecast.isOpenMeteo) {
      sourceText = 'Sumber: Open-Meteo · suhu puncak disesuaikan dengan '
          'ketinggian. Cuaca gunung dapat berubah cepat.';
    } else {
      sourceText = 'Menampilkan perkiraan cuaca lokal. Cuaca gunung dapat '
          'berubah sewaktu-waktu.';
    }
    final relativeAgo = formatRelativeUpdatedAgo(forecast.fetchedAtUtc, _nowUtc);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PlusNotice(
          icon: HiqeoIcons.cloud,
          text: sourceText,
        ),
        const SizedBox(height: HiqeoSpacing.xs),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '$relativeAgo · ${formatDate(forecast.fetchedAtUtc)} '
                '${formatClock(forecast.fetchedAtUtc.toLocal())}'
                '${_fromCache ? ' · tersimpan offline' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey<String>('weather-refresh-btn'),
              onPressed: _loading
                  ? null
                  : () => unawaited(_load(forceRefresh: true)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Text('Perbarui'),
            ),
          ],
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
    final selector = GooeySelector<DateTime>(
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

    if (days.length <= 4) return selector;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: selector,
    );
  }
}

class _DayContent extends StatelessWidget {
  const _DayContent({
    super.key,
    required this.forecast,
    required this.day,
    required this.dayIndex,
  });

  final RouteWeatherForecast forecast;
  final RouteWeatherDay day;
  final int dayIndex;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final alerts = evaluateWeatherSafetyWarnings(
      day,
      currentSummitTempC: dayIndex == 0 ? forecast.currentSummitTempC : null,
      currentWindKmh: dayIndex == 0 ? forecast.currentWindSpeedKmh : null,
    );
    final displayWind =
        dayIndex == 0 ? (forecast.currentWindSpeedKmh ?? day.windSpeedKmh) : day.windSpeedKmh;
    final displayHumidity =
        dayIndex == 0 ? (forecast.currentHumidityPercent ?? day.humidityPercent) : day.humidityPercent;
    final displayUv =
        dayIndex == 0 ? (forecast.currentUvIndex ?? day.uvIndexMax) : day.uvIndexMax;
    final hasMetrics = displayWind != null ||
        displayHumidity != null ||
        displayUv != null ||
        day.sunriseLocal != null ||
        day.sunsetLocal != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final alert in alerts) ...<Widget>[
          PlusCard(
            key: ValueKey<String>('weather-warning-${alert.id}'),
            child: PlusNotice(
              icon: HiqeoIcons.warning,
              warning: true,
              text: '${alert.title}: ${alert.message}',
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
        ],
        PlusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
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
              if (day.basecampTemperatureC != null) ...<Widget>[
                const SizedBox(height: HiqeoSpacing.md),
                Divider(color: colors.hairline, height: 1),
                const SizedBox(height: HiqeoSpacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _ElevationTempChip(
                        key: const ValueKey<String>('weather-basecamp-temp'),
                        label: forecast.basecampElevationM != null
                            ? 'Basecamp (${forecast.basecampElevationM!.round()} mdpl)'
                            : 'Basecamp',
                        temp: dayIndex == 0 &&
                                forecast.currentBasecampTempC != null
                            ? forecast.currentBasecampTempC!
                            : day.basecampTemperatureC!,
                      ),
                    ),
                    const SizedBox(width: HiqeoSpacing.sm),
                    Expanded(
                      child: _ElevationTempChip(
                        key: const ValueKey<String>('weather-summit-temp'),
                        label: forecast.summitElevationM != null
                            ? 'Puncak (${forecast.summitElevationM!.round()} mdpl)'
                            : 'Puncak',
                        temp: dayIndex == 0 &&
                                forecast.currentSummitTempC != null
                            ? forecast.currentSummitTempC!
                            : (day.minTemperatureC ?? day.peakTemperatureC),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (hasMetrics) ...<Widget>[
          const SizedBox(height: HiqeoSpacing.md),
          PlusCard(
            key: const ValueKey<String>('weather-hiker-metrics'),
            child: Wrap(
              spacing: HiqeoSpacing.lg,
              runSpacing: HiqeoSpacing.md,
              children: <Widget>[
                if (displayWind != null)
                  _MetricTile(
                    label: 'Kecepatan angin',
                    value: '${displayWind.round()} km/jam',
                  ),
                if (displayHumidity != null)
                  _MetricTile(
                    label: 'Kelembapan',
                    value: '$displayHumidity%',
                  ),
                if (displayUv != null)
                  _MetricTile(
                    label: 'Indeks UV',
                    value: formatDecimal(displayUv),
                  ),
                if (day.sunriseLocal != null)
                  _MetricTile(
                    label: 'Matahari terbit',
                    value: formatClock(day.sunriseLocal!),
                  ),
                if (day.sunsetLocal != null)
                  _MetricTile(
                    label: 'Matahari terbenam',
                    value: formatClock(day.sunsetLocal!),
                  ),
              ],
            ),
          ),
        ],
        if (dayIndex == 0 && forecast.next24Hours.isNotEmpty) ...<Widget>[
          const SizedBox(height: HiqeoSpacing.md),
          PlusCard(
            key: const ValueKey<String>('weather-24h-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Prakiraan 24 jam ke depan',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: HiqeoSpacing.sm),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: forecast.next24Hours.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final h = forecast.next24Hours[idx];
                      return Container(
                        width: 68,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.hairline),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              formatClock(h.timeLocal),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10.5,
                                color: colors.textSecondary,
                              ),
                            ),
                            Text(
                              formatTemperature(h.temperatureC),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${h.rainPercent}% hujan',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 9.5,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
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

class _ElevationTempChip extends StatelessWidget {
  const _ElevationTempChip({
    super.key,
    required this.label,
    required this.temp,
  });

  final String label;
  final double temp;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatTemperature(temp),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
              _WeatherBar(
                key: ValueKey<String>(
                  'weather-temp-bar-${hour.timeLocal.toIso8601String()}',
                ),
                width: 7,
                height: tempHeight,
                radius: 4,
                color: colors.primary,
              ),
              const SizedBox(width: 2),
              _WeatherBar(
                key: ValueKey<String>(
                  'weather-rain-bar-${hour.timeLocal.toIso8601String()}',
                ),
                width: 4,
                height: rainHeight,
                radius: 3,
                color: colors.secondary,
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

/// Batang grafik yang tumbuh dengan pegas ringan saat hari berganti.
class _WeatherBar extends StatelessWidget {
  const _WeatherBar({
    super.key,
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
  });

  final double width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = VisualEffectPolicyScope.of(context).reduceMotion;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: reduceMotion ? 1 : 0.62, end: 1),
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Container(
        width: width,
        height: height * value,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
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
                Text(
                  post.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
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
          const SizedBox(width: HiqeoSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  formatTemperature(post.temperatureC),
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '${post.condition.label} · ${post.rainPercent}%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
