import 'dart:math' as math;

import 'package:geo_utils/geo_utils.dart';

import '../../map/domain/mountain_pack_data.dart';
import '../../tracking/domain/tracking_session.dart';
import '../../trails/domain/track_route.dart';
import 'hike_analytics.dart';

/// Statistik terukur untuk satu segmen jalur pada satu sesi.
class TrailSegmentMetric {
  const TrailSegmentMetric({
    required this.index,
    required this.label,
    required this.distanceM,
    required this.elevationGainM,
    required this.elevationLossM,
    required this.avgGradePercent,
    required this.durationSeconds,
    required this.paceSecondsPerKm,
    required this.vamMPerHour,
    this.isEstimatedFromSummary = false,
  });

  final int index;
  final String label;
  final double distanceM;
  final double elevationGainM;
  final double elevationLossM;
  final double avgGradePercent;
  final int durationSeconds;
  final double? paceSecondsPerKm;
  final double? vamMPerHour;
  final bool isEstimatedFromSummary;

  /// Indeks beban segmen untuk menentukan segmen terberat pada sesi tunggal.
  double get difficultyScore {
    final safeDist = math.max(100.0, distanceM);
    final positiveGrade = math.max(0.0, (elevationGainM / safeDist) * 100.0);
    return positiveGrade * 10.0 + elevationGainM * 0.25;
  }
}

/// Pasangan segmen sesi terbaru vs sesi pembanding sebelumnya (bila ada).
class SegmentDeltaRow {
  const SegmentDeltaRow({
    required this.index,
    required this.label,
    required this.latest,
    this.previous,
  });

  final int index;
  final String label;
  final TrailSegmentMetric latest;
  final TrailSegmentMetric? previous;

  /// Positif berarti lebih lambat (detik lebih lama), negatif berarti lebih cepat.
  int? get deltaSeconds =>
      previous == null ? null : latest.durationSeconds - previous!.durationSeconds;
}

/// Kumpulan perbandingan segmen jalur per gunung/jalur.
class TrailComparisonGroup {
  const TrailComparisonGroup({
    required this.routeKey,
    required this.routeTitle,
    this.gpxAssetPath,
    required this.sessions,
    required this.latestSession,
    this.previousSession,
    required this.segments,
    required this.usedWaypoints,
    this.hardestSegmentIndex,
    this.mostStableSegmentIndex,
  });

  final String routeKey;
  final String routeTitle;
  final String? gpxAssetPath;
  final List<TrackingSession> sessions;
  final TrackingSession latestSession;
  final TrackingSession? previousSession;
  final List<SegmentDeltaRow> segments;
  final bool usedWaypoints;
  final int? hardestSegmentIndex;
  final int? mostStableSegmentIndex;

  bool get hasMultiSessionComparison => previousSession != null;

  int? get totalDeltaSeconds {
    if (!hasMultiSessionComparison) return null;
    var sum = 0;
    var hasAny = false;
    for (final row in segments) {
      final delta = row.deltaSeconds;
      if (delta != null) {
        sum += delta;
        hasAny = true;
      }
    }
    return hasAny ? sum : null;
  }

  SegmentDeltaRow? get hardestSegment => _findRow(hardestSegmentIndex);
  SegmentDeltaRow? get mostStableSegment => _findRow(mostStableSegmentIndex);

  SegmentDeltaRow? _findRow(int? index) {
    if (index == null) return null;
    for (final row in segments) {
      if (row.index == index) return row;
    }
    return null;
  }
}

class _SegmentSpan {
  const _SegmentSpan({
    required this.label,
    required this.startFrac,
    required this.endFrac,
  });

  final String label;
  final double startFrac;
  final double endFrac;
}

/// Pembangun segmen jalur otomatis dari titik GPS sesi dan pos GPX gunung.
class TrailSegmentComparisonBuilder {
  const TrailSegmentComparisonBuilder._();

  static List<TrailComparisonGroup> buildGroups(
    List<HikeSample> samples, {
    Map<String, List<TrackWaypoint>> waypointsByRouteKey =
        const <String, List<TrackWaypoint>>{},
  }) {
    if (samples.isEmpty) return const <TrailComparisonGroup>[];

    final hikingSamples = samples
        .where((s) => !s.session.isJogging)
        .toList(growable: false);
    final activeSamples = hikingSamples.isNotEmpty ? hikingSamples : samples;

    final grouped = <String, List<HikeSample>>{};
    for (final sample in activeSamples) {
      final key = routeKeyForSession(sample.session);
      grouped.putIfAbsent(key, () => <HikeSample>[]).add(sample);
    }

    final result = <TrailComparisonGroup>[];
    for (final entry in grouped.entries) {
      final key = entry.key;
      final groupSamples = List<HikeSample>.from(entry.value)
        ..sort(
          (a, b) => b.session.startedAtUtc.compareTo(a.session.startedAtUtc),
        );

      final latestSample = groupSamples.first;
      final previousSample = groupSamples.length >= 2 ? groupSamples[1] : null;
      final waypoints = waypointsByRouteKey[key] ?? const <TrackWaypoint>[];
      final spans = _buildSpans(
        waypoints: waypoints,
        isJogging: latestSample.session.isJogging,
      );

      final latestMetrics = _sliceSample(latestSample, spans);
      final prevMetrics =
          previousSample == null ? null : _sliceSample(previousSample, spans);

      final rows = <SegmentDeltaRow>[
        for (var i = 0; i < spans.length; i++)
          SegmentDeltaRow(
            index: i,
            label: spans[i].label,
            latest: latestMetrics[i],
            previous: prevMetrics?[i],
          ),
      ];

      int? hardestIdx;
      int? mostStableIdx;
      if (previousSample == null && latestMetrics.length >= 2) {
        hardestIdx = _pickHardestIndex(latestMetrics);
        mostStableIdx = _pickMostStableIndex(latestMetrics, exclude: hardestIdx);
      }

      result.add(
        TrailComparisonGroup(
          routeKey: key,
          routeTitle: _routeTitleForSession(latestSample.session),
          gpxAssetPath: resolveGpxAssetPath(latestSample.session),
          sessions: groupSamples.map((s) => s.session).toList(growable: false),
          latestSession: latestSample.session,
          previousSession: previousSample?.session,
          segments: rows,
          usedWaypoints: _hasUsableWaypoints(waypoints),
          hardestSegmentIndex: hardestIdx,
          mostStableSegmentIndex: mostStableIdx,
        ),
      );
    }

    result.sort((a, b) {
      if (a.hasMultiSessionComparison != b.hasMultiSessionComparison) {
        return a.hasMultiSessionComparison ? -1 : 1;
      }
      return b.latestSession.startedAtUtc
          .compareTo(a.latestSession.startedAtUtc);
    });
    return result;
  }

  static String routeKeyForSession(TrackingSession session) {
    final trailId = session.trailId?.trim().toLowerCase() ?? '';
    final mountain = session.mountainName?.trim().toLowerCase() ?? '';
    final trail = session.trailName?.trim().toLowerCase() ?? '';
    if (trailId.isNotEmpty) {
      return 'trail:$trailId';
    }
    if (mountain.isNotEmpty) {
      return 'route:$mountain|$trail';
    }
    return 'session:${session.id}';
  }

  static String? resolveGpxAssetPath(TrackingSession session) {
    final trailId = session.trailId?.trim().toLowerCase() ?? '';
    final mountainName = session.mountainName?.trim().toLowerCase() ?? '';
    final trailName = session.trailName?.trim().toLowerCase() ?? '';
    if (trailId.isEmpty && mountainName.isEmpty) return null;

    final packs = MountainPackData.createDefaultPacks();
    for (final pack in packs) {
      for (final trail in pack.package.trails) {
        if (trailId.isNotEmpty && trail.id.toLowerCase() == trailId) {
          return trail.gpxAssetPath ?? pack.gpxAssetPath;
        }
        if (trailName.isNotEmpty &&
            trail.name.toLowerCase() == trailName &&
            (mountainName.isEmpty ||
                pack.name.toLowerCase().contains(mountainName))) {
          return trail.gpxAssetPath ?? pack.gpxAssetPath;
        }
      }
      if (mountainName.isNotEmpty &&
          pack.name.toLowerCase().contains(mountainName)) {
        return pack.gpxAssetPath ??
            (pack.package.trails.isNotEmpty
                ? pack.package.trails.first.gpxAssetPath
                : null);
      }
    }
    return null;
  }

  static String _routeTitleForSession(TrackingSession session) {
    final mountain = session.mountainName?.trim() ?? '';
    final trail = session.trailName?.trim() ?? '';
    if (mountain.isNotEmpty && trail.isNotEmpty) {
      return '$mountain · $trail';
    }
    if (mountain.isNotEmpty) return mountain;
    if (trail.isNotEmpty) return trail;
    return session.isJogging ? 'Sesi Jogging' : 'Pendakian Terakhir';
  }

  static bool _hasUsableWaypoints(List<TrackWaypoint> waypoints) =>
      _filteredStopWaypoints(waypoints).isNotEmpty;

  static List<({String name, double frac})> _filteredStopWaypoints(
    List<TrackWaypoint> waypoints,
  ) {
    if (waypoints.length < 2) return const <({String name, double frac})>[];
    final maxDist = waypoints.fold<double>(
      0.0,
      (prev, w) => math.max(prev, w.distanceFromStartM),
    );
    if (maxDist < 400) return const <({String name, double frac})>[];

    final sorted = List<TrackWaypoint>.from(waypoints)
      ..sort((a, b) => a.distanceFromStartM.compareTo(b.distanceFromStartM));

    final stops = <({String name, double frac})>[];
    var lastFrac = 0.0;
    for (final wp in sorted) {
      final frac = (wp.distanceFromStartM / maxDist).clamp(0.0, 1.0);
      if (frac <= 0.08 || frac >= 0.92) continue;
      if (frac - lastFrac < 0.10) continue;
      final cleanName = wp.name.trim();
      if (cleanName.isEmpty) continue;
      stops.add((name: cleanName, frac: frac));
      lastFrac = frac;
      if (stops.length >= 4) break;
    }
    return stops;
  }

  static List<_SegmentSpan> _buildSpans({
    required List<TrackWaypoint> waypoints,
    required bool isJogging,
  }) {
    final stops = _filteredStopWaypoints(waypoints);
    if (stops.isNotEmpty) {
      final spans = <_SegmentSpan>[];
      var prevLabel = 'Start';
      var prevFrac = 0.0;
      for (final stop in stops) {
        spans.add(
          _SegmentSpan(
            label: '$prevLabel – ${stop.name}',
            startFrac: prevFrac,
            endFrac: stop.frac,
          ),
        );
        prevLabel = stop.name;
        prevFrac = stop.frac;
      }
      spans.add(
        _SegmentSpan(
          label: '$prevLabel – Puncak',
          startFrac: prevFrac,
          endFrac: 1.0,
        ),
      );
      return spans;
    }

    if (isJogging) {
      return const <_SegmentSpan>[
        _SegmentSpan(label: 'KM Awal (0–25%)', startFrac: 0.0, endFrac: 0.25),
        _SegmentSpan(label: 'Segmen 2 (25–50%)', startFrac: 0.25, endFrac: 0.50),
        _SegmentSpan(label: 'Segmen 3 (50–75%)', startFrac: 0.50, endFrac: 0.75),
        _SegmentSpan(label: 'Segmen Akhir (75–100%)', startFrac: 0.75, endFrac: 1.0),
      ];
    }

    return const <_SegmentSpan>[
      _SegmentSpan(label: 'Start – Pos 1', startFrac: 0.0, endFrac: 0.25),
      _SegmentSpan(label: 'Pos 1 – Pos 2', startFrac: 0.25, endFrac: 0.50),
      _SegmentSpan(label: 'Pos 2 – Pos 3', startFrac: 0.50, endFrac: 0.75),
      _SegmentSpan(label: 'Menuju Puncak', startFrac: 0.75, endFrac: 1.0),
    ];
  }

  static List<TrailSegmentMetric> _sliceSample(
    HikeSample sample,
    List<_SegmentSpan> spans,
  ) {
    final points = sample.points;
    final session = sample.session;

    if (points.length >= 4) {
      final cumulative = <double>[0.0];
      for (var i = 1; i < points.length; i++) {
        cumulative.add(
          cumulative.last +
              distanceMeters(points[i - 1].position, points[i].position),
        );
      }
      final totalDist = cumulative.last;
      if (totalDist >= 100) {
        final dist = List<double>.filled(spans.length, 0.0);
        final gain = List<double>.filled(spans.length, 0.0);
        final loss = List<double>.filled(spans.length, 0.0);
        final dur = List<double>.filled(spans.length, 0.0);

        for (var i = 1; i < points.length; i++) {
          final prev = points[i - 1];
          final curr = points[i];
          final stepDist = cumulative[i] - cumulative[i - 1];
          final dt = curr.timestampUtc
                  .difference(prev.timestampUtc)
                  .inMilliseconds /
              1000.0;
          if (stepDist <= 0 && (dt <= 0 || dt > 120)) continue;

          final midFrac = ((cumulative[i] + cumulative[i - 1]) / 2.0) / totalDist;
          var spanIdx = spans.length - 1;
          for (var s = 0; s < spans.length; s++) {
            if (midFrac <= spans[s].endFrac || s == spans.length - 1) {
              spanIdx = s;
              break;
            }
          }

          dist[spanIdx] += stepDist;
          if (dt > 0 && dt <= 120) {
            dur[spanIdx] += dt;
          }
          final eleA = prev.altitudeM;
          final eleB = curr.altitudeM;
          if (eleA != null && eleB != null) {
            final dEle = eleB - eleA;
            if (dEle > 0) {
              gain[spanIdx] += dEle;
            } else if (dEle < 0) {
              loss[spanIdx] += -dEle;
            }
          }
        }

        return <TrailSegmentMetric>[
          for (var s = 0; s < spans.length; s++)
            _buildMetric(
              index: s,
              label: spans[s].label,
              distanceM: dist[s],
              elevationGainM: gain[s],
              elevationLossM: loss[s],
              durationSeconds: dur[s].round(),
              isEstimated: false,
            ),
        ];
      }
    }

    // Fallback merata bila titik GPS belum tersimpan pada sesi lama.
    return <TrailSegmentMetric>[
      for (var s = 0; s < spans.length; s++)
        _buildMetric(
          index: s,
          label: spans[s].label,
          distanceM: session.distanceM * (spans[s].endFrac - spans[s].startFrac),
          elevationGainM:
              session.elevationGainM * (spans[s].endFrac - spans[s].startFrac),
          elevationLossM:
              session.elevationLossM * (spans[s].endFrac - spans[s].startFrac),
          durationSeconds:
              (session.movingSeconds * (spans[s].endFrac - spans[s].startFrac))
                  .round(),
          isEstimated: true,
        ),
    ];
  }

  static TrailSegmentMetric _buildMetric({
    required int index,
    required String label,
    required double distanceM,
    required double elevationGainM,
    required double elevationLossM,
    required int durationSeconds,
    required bool isEstimated,
  }) {
    final avgGradePercent = distanceM > 1
        ? ((elevationGainM - elevationLossM) / distanceM) * 100.0
        : 0.0;
    final pace = (distanceM >= 50 && durationSeconds > 0)
        ? durationSeconds / (distanceM / 1000.0)
        : null;
    final vam = (elevationGainM >= 5 && durationSeconds > 0)
        ? elevationGainM / (durationSeconds / 3600.0)
        : null;
    return TrailSegmentMetric(
      index: index,
      label: label,
      distanceM: distanceM,
      elevationGainM: elevationGainM,
      elevationLossM: elevationLossM,
      avgGradePercent: avgGradePercent,
      durationSeconds: durationSeconds,
      paceSecondsPerKm: pace,
      vamMPerHour: vam,
      isEstimatedFromSummary: isEstimated,
    );
  }

  static int? _pickHardestIndex(List<TrailSegmentMetric> metrics) {
    if (metrics.isEmpty) return null;
    var best = metrics.first;
    for (final m in metrics.skip(1)) {
      if (m.difficultyScore > best.difficultyScore) {
        best = m;
      }
    }
    return best.index;
  }

  static int? _pickMostStableIndex(
    List<TrailSegmentMetric> metrics, {
    int? exclude,
  }) {
    final paced = metrics
        .where((m) => m.paceSecondsPerKm != null)
        .toList(growable: false);
    if (paced.isEmpty) return null;

    final sortedPaces = paced.map((m) => m.paceSecondsPerKm!).toList()..sort();
    final medianPace = sortedPaces[sortedPaces.length ~/ 2];

    TrailSegmentMetric? best;
    var bestDiff = double.infinity;
    for (final m in paced) {
      if (metrics.length > 1 && m.index == exclude) continue;
      final diff = (m.paceSecondsPerKm! - medianPace).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = m;
      }
    }
    return best?.index;
  }
}
