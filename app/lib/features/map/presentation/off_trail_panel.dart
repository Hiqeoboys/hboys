import 'package:flutter/material.dart';

import '../../map/domain/map_package.dart';
import '../../tracking/domain/track_point.dart';
import '../../trails/domain/off_trail_detector.dart';

class OffTrailPanel extends StatefulWidget {
  const OffTrailPanel({
    super.key,
    required this.trail,
    required this.latestPoint,
  });

  final MapTrail? trail;
  final TrackPoint? latestPoint;

  @override
  State<OffTrailPanel> createState() => _OffTrailPanelState();
}

class _OffTrailPanelState extends State<OffTrailPanel> {
  OffTrailDetector? _detector;
  TrailState _state = TrailState.onTrail;
  double? _distanceM;
  DateTime? _lastTimestamp;

  @override
  void initState() {
    super.initState();
    _resetDetector();
    _consumeLatest();
  }

  @override
  void didUpdateWidget(covariant OffTrailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trail?.id != widget.trail?.id) {
      _resetDetector();
    }
    _consumeLatest();
  }

  void _resetDetector() {
    final trail = widget.trail;
    _detector = trail != null && trail.points.length >= 2
        ? OffTrailDetector(trail: trail.points)
        : null;
    _state = TrailState.onTrail;
    _distanceM = null;
    _lastTimestamp = null;
  }

  void _consumeLatest() {
    final detector = _detector;
    final point = widget.latestPoint;
    if (detector == null || point == null) return;
    if (_lastTimestamp == point.timestampUtc) return;
    _lastTimestamp = point.timestampUtc;
    _state = detector.update(point.position);
    _distanceM = detector.lastDistanceM;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trail = widget.trail;
    final point = widget.latestPoint;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.alt_route, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Deteksi keluar jalur',
                      style: theme.textTheme.titleMedium),
                ),
                if (trail != null) _verificationBadge(theme, trail),
              ],
            ),
            const SizedBox(height: 12),
            if (trail == null)
              Text(
                'Pilih paket dan jalur untuk mengaktifkan deteksi.',
                style: theme.textTheme.bodyMedium,
              )
            else if (trail.points.length < 2)
              Text(
                'Jalur tidak punya cukup titik untuk deteksi.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              Text(
                trail.name,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Sumber: ${trail.source}',
                style: theme.textTheme.bodySmall,
              ),
              if (!trail.isVerified) ...[
                const SizedBox(height: 8),
                Text(
                  'Jalur belum terverifikasi lapangan. Jangan jadikan satu-'
                  'satunya acuan navigasi.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              _statusRow(theme, hasPoint: point != null),
              const SizedBox(height: 12),
              if (point == null)
                Text(
                  'Menunggu titik GPS pertama.',
                  style: theme.textTheme.bodySmall,
                )
              else
                Text(
                  'Akurasi GPS titik terakhir ±'
                  '${point.accuracyM.toStringAsFixed(0)} m. Akurasi buruk dapat '
                  'memicu peringatan palsu.',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              Text(
                'Ambang: keluar bila >50 m selama 3 titik; kembali bila <30 m. '
                'Hanya peringatan visual, bukan alarm keselamatan.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _verificationBadge(ThemeData theme, MapTrail trail) {
    if (trail.isVerified) {
      return Chip(
        label: Text(
          'Terverifikasi',
          style: theme.textTheme.labelSmall,
        ),
        backgroundColor: theme.colorScheme.secondaryContainer,
        visualDensity: VisualDensity.compact,
      );
    }
    return Chip(
      label: Text(
        'Belum terverifikasi',
        style: theme.textTheme.labelSmall,
      ),
      backgroundColor: theme.colorScheme.errorContainer,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _statusRow(ThemeData theme, {required bool hasPoint}) {
    if (!hasPoint) {
      return Row(
        children: [
          Icon(Icons.gps_not_fixed, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            'Menunggu GPS',
            key: const ValueKey('off-trail-status'),
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }
    final (icon, label, color) = switch (_state) {
      TrailState.onTrail => (
          Icons.check_circle_outline,
          'Di jalur',
          theme.colorScheme.primary,
        ),
      TrailState.offTrail => (
          Icons.warning_amber_rounded,
          'Di luar jalur',
          theme.colorScheme.error,
        ),
    };
    final distance = _distanceM;
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          key: const ValueKey('off-trail-status'),
          style: theme.textTheme.titleSmall?.copyWith(color: color),
        ),
        if (distance != null && distance.isFinite) ...[
          const SizedBox(width: 12),
          Text(
            '${distance.toStringAsFixed(0)} m dari jalur',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
