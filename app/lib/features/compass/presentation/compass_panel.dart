import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../domain/compass_calibration.dart';

class CompassPanel extends StatefulWidget {
  const CompassPanel({super.key, this.events, this.offsetStore});

  /// Untuk pengujian dan pemakaian ulang stream. Null berarti stream plugin
  /// pada Android/iOS dan tidak tersedia di platform lain.
  final Stream<CompassEvent>? events;
  final CompassOffsetStore? offsetStore;

  @override
  State<CompassPanel> createState() => _CompassPanelState();
}

class _CompassPanelState extends State<CompassPanel> {
  late final CompassOffsetStore _store;
  StreamSubscription<CompassEvent>? _subscription;
  CompassEvent? _last;
  double _offsetDegrees = 0;
  bool _hasStream = false;
  bool _waiting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _store = widget.offsetStore ?? const SharedPreferencesCompassOffsetStore();
    _subscribe();
    unawaited(_loadOffset());
  }

  void _subscribe() {
    final platformSupported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final stream = widget.events ??
        (platformSupported ? FlutterCompass.events : null);
    _hasStream = stream != null;
    if (stream == null) {
      _waiting = false;
      return;
    }
    _subscription = stream.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _last = event;
          _waiting = false;
          _error = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _error = 'Gagal membaca kompas: $error';
          _waiting = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _waiting = false);
      },
    );
  }

  Future<void> _loadOffset() async {
    try {
      final offset = await _store.readOffsetDegrees();
      if (!mounted) return;
      setState(() => _offsetDegrees = normalizeHeading(offset));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Gagal memuat koreksi arah: $error');
    }
  }

  double? get _rawHeading {
    final heading = _last?.heading;
    if (heading == null || !heading.isFinite) return null;
    return heading;
  }

  Future<void> _openCalibration() async {
    final raw = _rawHeading;
    if (raw == null) return;
    var input = '0';
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Koreksi arah manual'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pegang perangkat tetap mengarah ke acuan yang Anda ketahui, '
                'lalu masukkan arah acuan itu (0° = utara, 90° = timur).',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: '0',
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) => input = value,
                decoration: const InputDecoration(
                  labelText: 'Arah acuan (derajat)',
                  helperText: 'Isi 0 hanya jika Anda yakin itu utara sebenarnya.',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ini menggeser heading, bukan mengkalibrasi sensor. Untuk '
                'kalibrasi sensor, gerakkan perangkat membentuk angka 8.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(input.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (!mounted || text == null) return;

    final reference = double.tryParse(text.replaceAll(',', '.'));
    final currentRaw = _rawHeading;
    if (reference == null || !reference.isFinite || currentRaw == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Arah acuan tidak valid.')),
      );
      return;
    }
    final offset = offsetForReference(
      rawHeadingDegrees: currentRaw,
      referenceHeadingDegrees: reference,
    );
    try {
      await _store.writeOffsetDegrees(offset);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan koreksi: $error')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _offsetDegrees = offset);
  }

  Future<void> _resetCalibration() async {
    try {
      await _store.writeOffsetDegrees(0);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mereset koreksi: $error')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _offsetDegrees = 0);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = _rawHeading;
    final corrected = raw == null ? null : applyHeadingOffset(raw, _offsetDegrees);
    final accuracy = _last?.accuracy;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.explore_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Kompas', style: theme.textTheme.titleMedium),
                ),
                if (_offsetDegrees != 0)
                  Text(
                    'Koreksi ${_formatSignedOffset(_offsetDegrees)}',
                    style: theme.textTheme.labelSmall,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_hasStream)
              Text(
                'Sensor kompas tidak tersedia di platform ini.',
                style: theme.textTheme.bodyMedium,
              )
            else if (_error != null)
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              )
            else if (_waiting)
              Text('Menunggu data kompas...', style: theme.textTheme.bodyMedium)
            else if (corrected == null)
              Text(
                'Perangkat tidak melaporkan heading kompas.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              Center(
                child: SizedBox(
                  width: 190,
                  height: 190,
                  child: Semantics(
                    label:
                        'Kompas, arah ${corrected.toStringAsFixed(0)} derajat',
                    child: CustomPaint(
                      painter: _CompassRosePainter(
                        headingDegrees: corrected,
                        outlineColor: theme.colorScheme.outlineVariant,
                        needleColor: theme.colorScheme.error,
                        secondaryColor: theme.colorScheme.onSurfaceVariant,
                        labelStyle: theme.textTheme.labelMedium!.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${corrected.toStringAsFixed(0)}° ${_cardinal(corrected)}',
                  key: const ValueKey('compass-heading'),
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  _accuracyText(accuracy),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Kalibrasi sensor mengikuti panduan OS: gerakkan perangkat '
              'membentuk angka 8. Aplikasi hanya bisa menyimpan koreksi arah '
              'manual; arah utara sebenarnya bergantung pada acuan yang Anda '
              'masukkan.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: raw == null ? null : _openCalibration,
                  icon: const Icon(Icons.tune),
                  label: const Text('Kalibrasi manual'),
                ),
                TextButton(
                  onPressed: _offsetDegrees == 0 ? null : _resetCalibration,
                  child: const Text('Reset koreksi'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatSignedOffset(double offset) {
    final signed = offset > 180 ? offset - 360 : offset;
    final prefix = signed > 0 ? '+' : '';
    return '$prefix${signed.toStringAsFixed(1)}°';
  }

  String _accuracyText(double? accuracy) {
    if (accuracy == null) {
      return 'Akurasi tidak dilaporkan sensor.';
    }
    final quality = compassAccuracyQuality(accuracy);
    final label = switch (quality) {
      CompassAccuracyQuality.high => 'tinggi',
      CompassAccuracyQuality.medium => 'sedang',
      CompassAccuracyQuality.low => 'rendah',
      CompassAccuracyQuality.unknown => 'tidak diketahui',
    };
    return 'Perkiraan galat ±${accuracy.round()}° ($label). '
        'Di Android nilai ini kasar.';
  }

  String _cardinal(double heading) {
    const names = ['U', 'TL', 'T', 'TG', 'S', 'BD', 'B', 'BL'];
    final index = (((normalizeHeading(heading) + 22.5) / 45).floor()) % 8;
    return names[index];
  }
}

class _CompassRosePainter extends CustomPainter {
  _CompassRosePainter({
    required this.headingDegrees,
    required this.outlineColor,
    required this.needleColor,
    required this.secondaryColor,
    required this.labelStyle,
  });

  final double headingDegrees;
  final Color outlineColor;
  final Color needleColor;
  final Color secondaryColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 12;
    if (radius <= 0) return;

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = outlineColor;
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = secondaryColor.withValues(alpha: 0.6);
    canvas.drawCircle(center, radius, outlinePaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-headingDegrees * math.pi / 180);

    for (var index = 0; index < 24; index++) {
      final angle = index * 15 * math.pi / 180;
      final direction = Offset(math.sin(angle), -math.cos(angle));
      final inner = direction * (radius - (index % 6 == 0 ? 14 : 8));
      final outer = direction * (radius - 2);
      canvas.drawLine(inner, outer, tickPaint);
    }

    _label(canvas, 'U', 0, radius - 26);
    _label(canvas, 'T', 90, radius - 26);
    _label(canvas, 'S', 180, radius - 26);
    _label(canvas, 'B', 270, radius - 26);

    final northNeedle = Path()
      ..moveTo(0, -radius * 0.66)
      ..lineTo(-7, 8)
      ..lineTo(0, 2)
      ..close();
    canvas.drawPath(
      northNeedle,
      Paint()..color = needleColor,
    );
    final southNeedle = Path()
      ..moveTo(0, radius * 0.66)
      ..lineTo(7, -8)
      ..lineTo(0, -2)
      ..close();
    canvas.drawPath(
      southNeedle,
      Paint()..color = secondaryColor.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      Offset.zero,
      3,
      Paint()..color = secondaryColor,
    );
    canvas.restore();

    canvas.drawLine(
      Offset(center.dx, center.dy - radius - 7),
      Offset(center.dx, center.dy - radius + 1),
      Paint()
        ..color = needleColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _label(Canvas canvas, String text, double angleDegrees, double radius) {
    final angle = angleDegrees * math.pi / 180;
    final position = Offset(math.sin(angle), -math.cos(angle)) * radius;
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      position - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_CompassRosePainter oldDelegate) =>
      headingDegrees != oldDelegate.headingDegrees ||
      outlineColor != oldDelegate.outlineColor ||
      needleColor != oldDelegate.needleColor ||
      secondaryColor != oldDelegate.secondaryColor ||
      labelStyle != oldDelegate.labelStyle;
}
