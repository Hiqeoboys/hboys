import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../../../design/tokens.dart';
import '../../../design/widgets/altracq_button.dart';
import '../../../design/widgets/altracq_sheet.dart';
import '../domain/compass_calibration.dart';

/// Membuka sheet kompas dengan sensor nyata dan koreksi arah manual.
Future<void> showCompassSheet(
  BuildContext context, {
  Stream<CompassEvent>? events,
  CompassOffsetStore? offsetStore,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.74,
        minChildSize: 0.42,
        maxChildSize: 0.92,
        builder: (context, scrollController) => CompassSheetBody(
          events: events,
          offsetStore: offsetStore,
          scrollController: scrollController,
        ),
      ),
    ),
  );
}

class CompassSheetBody extends StatefulWidget {
  const CompassSheetBody({
    super.key,
    this.events,
    this.offsetStore,
    this.scrollController,
  });

  final Stream<CompassEvent>? events;
  final CompassOffsetStore? offsetStore;
  final ScrollController? scrollController;

  @override
  State<CompassSheetBody> createState() => _CompassSheetBodyState();
}

class _CompassSheetBodyState extends State<CompassSheetBody> {
  late final CompassOffsetStore _store;
  final TextEditingController _reference = TextEditingController();
  StreamSubscription<CompassEvent>? _subscription;
  CompassEvent? _last;
  double _offsetDegrees = 0;
  bool _hasStream = false;
  bool _waiting = true;
  String? _error;
  String? _inputError;
  String? _savedMessage;

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

  Future<void> _saveCorrection() async {
    final raw = _rawHeading;
    final reference = double.tryParse(
      _reference.text.trim().replaceAll(',', '.'),
    );
    if (raw == null) {
      setState(() {
        _inputError = 'Heading mentah belum tersedia; tunggu data kompas.';
        _savedMessage = null;
      });
      return;
    }
    if (reference == null || !reference.isFinite) {
      setState(() {
        _inputError = 'Masukkan arah acuan berupa angka derajat.';
        _savedMessage = null;
      });
      return;
    }
    final offset = offsetForReference(
      rawHeadingDegrees: raw,
      referenceHeadingDegrees: reference,
    );
    try {
      await _store.writeOffsetDegrees(offset);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _inputError = 'Gagal menyimpan koreksi: $error';
        _savedMessage = null;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _offsetDegrees = offset;
      _inputError = null;
      _savedMessage = 'Koreksi tersimpan.';
      _reference.clear();
    });
  }

  Future<void> _resetCorrection() async {
    try {
      await _store.writeOffsetDegrees(0);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _inputError = 'Gagal mereset koreksi: $error';
        _savedMessage = null;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _offsetDegrees = 0;
      _inputError = null;
      _savedMessage = 'Koreksi direset.';
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final raw = _rawHeading;
    final corrected = raw == null ? null : applyHeadingOffset(raw, _offsetDegrees);
    // Arah dibulatkan setelah dinormalisasi supaya 359,7° tampil sebagai 0°,
    // bukan 360°.
    final displayHeading = corrected == null
        ? null
        : normalizeHeading(corrected.roundToDouble());
    final accuracy = _last?.accuracy;

    return AltracqSheet(
      title: 'Kompas',
      subtitle: 'Arah perangkat dan koreksi manual',
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: <Widget>[
          if (!_hasStream)
            const _CompassNotice(
              text: 'Sensor kompas tidak tersedia di platform ini.',
            )
          else if (_error != null)
            _CompassNotice(text: _error!, isError: true)
          else if (_waiting)
            const _CompassNotice(text: 'Menunggu data kompas…')
          else if (corrected == null)
            const _CompassNotice(
              text: 'Perangkat tidak melaporkan heading kompas.',
            )
          else ...<Widget>[
            Center(
              child: SizedBox(
                width: 190,
                height: 190,
                child: Semantics(
                  label:
                      'Kompas, arah ${displayHeading!.toStringAsFixed(0)} derajat',
                  child: CustomPaint(
                    painter: _CompassRosePainter(
                      headingDegrees: corrected,
                      outlineColor: colors.hairline,
                      needleColor: colors.primary,
                      secondaryColor: colors.textSecondary,
                      labelStyle: theme.textTheme.labelMedium!.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AltracqSpacing.sm),
            Center(
              child: Text(
                '${displayHeading.toStringAsFixed(0)}° '
                '${_cardinal(displayHeading)}',
                key: const ValueKey('compass-heading'),
                style: theme.textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: 2),
            Center(
              child: Text(
                _accuracyText(accuracy),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: AltracqSpacing.xl),
          Container(height: 1, color: colors.hairline),
          const SizedBox(height: AltracqSpacing.lg),
          Text('Koreksi arah manual', style: theme.textTheme.titleMedium),
          const SizedBox(height: AltracqSpacing.xs),
          Text(
            'Pegang perangkat ke arah acuan yang Anda ketahui, lalu masukkan '
            'arah acuan itu. Koreksi hanya menggeser heading, bukan '
            'mengkalibrasi sensor.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AltracqSpacing.md),
          TextField(
            controller: _reference,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Arah acuan (derajat)',
              helperText: '0 = utara, 90 = timur',
              helperStyle: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
              filled: true,
              fillColor: colors.surface.withValues(alpha: 0.6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AltracqRadius.floating),
                borderSide: BorderSide(color: colors.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AltracqRadius.floating),
                borderSide: BorderSide(color: colors.hairline),
              ),
            ),
          ),
          if (_inputError != null) ...<Widget>[
            const SizedBox(height: AltracqSpacing.xs),
            Text(
              _inputError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.warningText,
              ),
            ),
          ],
          if (_savedMessage != null) ...<Widget>[
            const SizedBox(height: AltracqSpacing.xs),
            Text(
              _savedMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AltracqSpacing.md),
          AltracqButton(
            label: 'Simpan koreksi',
            onPressed: raw == null ? null : _saveCorrection,
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _offsetDegrees == 0
                      ? 'Belum ada koreksi.'
                      : 'Koreksi tersimpan ${_formatSignedOffset(_offsetDegrees)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: _offsetDegrees == 0 ? null : _resetCorrection,
                child: const Text('Reset koreksi'),
              ),
            ],
          ),
          const SizedBox(height: AltracqSpacing.md),
          Text(
            'Kalibrasi sensor mengikuti panduan OS: gerakkan perangkat '
            'membentuk angka 8. Aplikasi tidak menjalankan kalibrasi sensor. '
            'Akurasi yang dilaporkan Android bersifat kasar, dan arah utara '
            'sebenarnya bergantung pada acuan yang Anda masukkan.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSignedOffset(double offset) {
    final signed = offset > 180 ? offset - 360 : offset;
    final prefix = signed > 0 ? '+' : '';
    return '$prefix${signed.toStringAsFixed(1).replaceAll('.', ',')}°';
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

class _CompassNotice extends StatelessWidget {
  const _CompassNotice({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AltracqSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AltracqRadius.floating),
        border: Border.all(
          color: isError ? colors.warning : colors.hairline,
        ),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isError ? colors.warningText : colors.textPrimary,
        ),
      ),
    );
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
    canvas.drawPath(northNeedle, Paint()..color = needleColor);
    final southNeedle = Path()
      ..moveTo(0, radius * 0.66)
      ..lineTo(7, -8)
      ..lineTo(0, -2)
      ..close();
    canvas.drawPath(
      southNeedle,
      Paint()..color = secondaryColor.withValues(alpha: 0.5),
    );
    canvas.drawCircle(Offset.zero, 3, Paint()..color = secondaryColor);
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
