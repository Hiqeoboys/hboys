import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../design/app_theme.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/line_icons.dart';
import '../../tracking/application/tracking_controller.dart';

/// Splash selalu bernuansa biru gelap, tidak mengikuti tema aplikasi.
class SplashPage extends StatefulWidget {
  const SplashPage({
    super.key,
    this.initializer,
    this.minimumDuration = const Duration(milliseconds: 1400),
    this.onReady,
  });

  /// Pekerjaan lokal yang benar-benar ditunggu. Bawaannya membuka basis data
  /// rekaman; galatnya dicatat pengendali dan layar lain menampilkannya.
  final Future<void> Function()? initializer;

  /// Waktu tampil minimum supaya splash tidak berkedip.
  final Duration minimumDuration;

  /// Kait uji: menggantikan navigasi ke Beranda.
  final VoidCallback? onReady;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final Completer<void> _minimumDone = Completer<void>();
  Timer? _minimumTimer;

  @override
  void initState() {
    super.initState();
    if (widget.minimumDuration <= Duration.zero) {
      _minimumDone.complete();
    } else {
      _minimumTimer = Timer(widget.minimumDuration, () {
        if (!_minimumDone.isCompleted) _minimumDone.complete();
      });
    }
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      await (widget.initializer ?? TrackingController.instance.initialize)();
    } on Object {
      // Pengendali sudah menyimpan galatnya; splash tetap lanjut agar layar
      // tujuan bisa menampilkan keadaan sebenarnya.
    }
    await _minimumDone.future;
    if (!mounted) return;
    final onReady = widget.onReady;
    if (onReady != null) {
      onReady();
      return;
    }
    context.go('/beranda');
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    if (!_minimumDone.isCompleted) _minimumDone.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dark = AltracqColors.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: altracqDarkTheme,
        child: Scaffold(
          backgroundColor: dark.background,
          body: Stack(
            children: <Widget>[
              const Positioned.fill(child: CustomPaint(painter: _ContourPainter())),
              Align(
                alignment: const Alignment(0, -0.26),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: dark.textPrimary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: dark.glassBorder,
                            width: AltracqGlass.borderWidth,
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Center(
                          child: AltracqIcon(
                            AltracqIcons.mountain,
                            size: 52,
                            color: dark.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Altracq',
                        style: AltracqTypography.textTheme.displayLarge
                            ?.copyWith(color: dark.textPrimary),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Pendamping pendakian yang tetap bekerja tanpa sinyal.',
                        textAlign: TextAlign.center,
                        style: AltracqTypography.textTheme.bodyLarge
                            ?.copyWith(color: dark.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 48,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 140,
                        height: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            backgroundColor:
                                dark.textPrimary.withValues(alpha: 0.18),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              dark.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Menyiapkan data lokal di HP',
                        style: AltracqTypography.textTheme.bodySmall
                            ?.copyWith(color: dark.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lingkaran kontur tipis yang memusat pada blok logo.
class _ContourPainter extends CustomPainter {
  const _ContourPainter();

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    const dark = AltracqColors.dark;
    final center = ui.Offset(size.width / 2, size.height * 0.37);
    final paint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = dark.textPrimary.withValues(alpha: 0.07);
    for (final factor in <double>[0.33, 0.52, 0.72, 0.95]) {
      canvas.drawCircle(center, size.width * factor, paint);
    }
  }

  @override
  bool shouldRepaint(_ContourPainter oldDelegate) => false;
}
