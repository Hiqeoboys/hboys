import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/tracking/application/tracking_controller.dart';
import '../../infrastructure/power/power_profile_controller.dart';
import '../../infrastructure/power/power_profile_manager.dart';
import '../motion/visual_effect_policy.dart';
import '../tokens.dart';
import 'background_motion_controller.dart';

/// Kekuatan gradien latar belakang aura (140% sesuai pilihan desain).
const double kBackgroundStrength = 1.4;

/// Opasitas ubin noise pada latar belakang (dinonaktifkan untuk latar bersih).
const double kNoiseOpacity = 0.0;

/// Durasi satu arah pergerakan drift latar belakang (siklus penuh 30 detik).
const Duration kDriftHalfPeriod = Duration(seconds: 15);

/// Vektor pergeseran relatif pusat elips gerak (0,084W, 0,056H).
const Offset kDriftDeltaFraction = Offset(0.084, 0.056);

/// Daftar jenis halaman untuk konfigurasi intensitas dan izin drift.
enum AppBackgroundPage {
  beranda,
  petaDaftar,
  petaPenuh,
  track,
  grup,
  profil,
  pengaturan,
  hiqeoPlus,
  detailGunung,
  lainnya,
}

/// Konfigurasi latar belakang per jenis halaman.
@immutable
class PageBackgroundConfig {
  const PageBackgroundConfig({
    required this.intensity,
    required this.allowDrift,
    this.visible = true,
  });

  /// Pengali opasitas lapisan a, b, dan c (1,0 atau 0,5 pada Track).
  final double intensity;

  /// Apakah halaman ini mengizinkan latar bergerak perlahan.
  final bool allowDrift;

  /// Apakah aura latar terlihat di halaman ini (false pada peta penuh).
  final bool visible;
}

/// Tabel konfigurasi tunggal intensitas dan perilaku latar belakang per halaman.
const Map<AppBackgroundPage, PageBackgroundConfig> kPageBackgroundConfigs =
    <AppBackgroundPage, PageBackgroundConfig>{
  AppBackgroundPage.beranda: PageBackgroundConfig(
    intensity: 1.0,
    allowDrift: true,
  ),
  AppBackgroundPage.petaDaftar: PageBackgroundConfig(
    intensity: 1.0,
    allowDrift: true,
  ),
  AppBackgroundPage.petaPenuh: PageBackgroundConfig(
    intensity: 0.0,
    allowDrift: false,
    visible: false,
  ),
  AppBackgroundPage.track: PageBackgroundConfig(
    intensity: 0.5,
    allowDrift: false,
  ),
  AppBackgroundPage.grup: PageBackgroundConfig(
    intensity: 1.0,
    allowDrift: true,
  ),
  AppBackgroundPage.profil: PageBackgroundConfig(
    intensity: 1.0,
    allowDrift: true,
  ),
  AppBackgroundPage.pengaturan: PageBackgroundConfig(
    intensity: 1.0,
    allowDrift: true,
  ),
  AppBackgroundPage.hiqeoPlus: PageBackgroundConfig(
    intensity: 1.0,
    allowDrift: true,
  ),
  AppBackgroundPage.detailGunung: PageBackgroundConfig(
    intensity: 1.0,
    allowDrift: true,
  ),
  AppBackgroundPage.lainnya: PageBackgroundConfig(
    intensity: 1.0,
    allowDrift: false,
  ),
};

/// Scope penanda keberadaan [AppBackground] agar tidak ada latar bertumpuk.
class AppBackgroundScope extends InheritedWidget {
  const AppBackgroundScope({
    super.key,
    required this.isRoot,
    required super.child,
  });

  final bool isRoot;

  static AppBackgroundScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppBackgroundScope>();

  @override
  bool updateShouldNotify(AppBackgroundScope oldWidget) =>
      isRoot != oldWidget.isRoot;
}

/// Widget latar belakang "aura" utama aplikasi (gradien + noise + gerak pelan).
///
/// Dibuat sekali di kerangka utama (shell) dan dipakai oleh seluruh halaman.
class AppBackground extends StatefulWidget {
  const AppBackground({
    super.key,
    required this.child,
    this.page = AppBackgroundPage.beranda,
    this.showAura = true,
    this.motionController,
    this.trackingController,
    this.powerController,
  });

  final Widget child;
  final AppBackgroundPage page;
  final bool showAura;

  final BackgroundMotionController? motionController;
  final TrackingController? trackingController;
  final PowerProfileController? powerController;

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _driftAnimationController;
  late final AnimationController _resetAnimationController;
  late final AnimationController _intensityAnimationController;

  final ValueNotifier<double> _driftNotifier = ValueNotifier<double>(0.0);
  DateTime _lastDriftUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  double _currentIntensity = 1.0;
  double _targetIntensity = 1.0;

  bool _isDrifting = false;
  bool _isScrolling = false;
  Timer? _scrollResumeTimer;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  late final BackgroundMotionController _motion =
      widget.motionController ?? BackgroundMotionController.instance;
  late final TrackingController _tracking =
      widget.trackingController ?? TrackingController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _driftAnimationController = AnimationController(
      vsync: this,
      duration: kDriftHalfPeriod,
    );

    _resetAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _intensityAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    final config = kPageBackgroundConfigs[widget.page] ??
        kPageBackgroundConfigs[AppBackgroundPage.beranda]!;
    _currentIntensity = widget.showAura ? config.intensity : 0.0;
    _targetIntensity = _currentIntensity;

    _driftAnimationController.addListener(_onDriftTick);
    _motion.addListener(_evaluateDriftConditions);
    _tracking.addListener(_evaluateDriftConditions);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _evaluateDriftConditions();
  }

  @override
  void didUpdateWidget(AppBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page ||
        oldWidget.showAura != widget.showAura) {
      final config = kPageBackgroundConfigs[widget.page] ??
          kPageBackgroundConfigs[AppBackgroundPage.beranda]!;
      final newTarget = widget.showAura ? config.intensity : 0.0;
      if (newTarget != _targetIntensity) {
        _targetIntensity = newTarget;
        _intensityAnimationController.stop();
        final start = _currentIntensity;
        final curve = CurvedAnimation(
          parent: _intensityAnimationController,
          curve: Curves.easeOutCubic,
        );
        void listener() {
          setState(() {
            _currentIntensity =
                ui.lerpDouble(start, _targetIntensity, curve.value) ??
                    _targetIntensity;
          });
        }

        curve.addListener(listener);
        _intensityAnimationController.forward(from: 0.0).then((_) {
          curve.removeListener(listener);
          _intensityAnimationController.reset();
        });
      }
      _evaluateDriftConditions();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _evaluateDriftConditions();
  }

  void _onDriftTick() {
    final now = DateTime.now();
    // Throttle pembaruan: hanya teruskan nilai bila sudah lewat 50 ms (~20 FPS)
    if (now.difference(_lastDriftUpdate).inMilliseconds >= 50) {
      _lastDriftUpdate = now;
      final curvedValue =
          Curves.easeInOut.transform(_driftAnimationController.value);
      _driftNotifier.value = curvedValue;
    }
  }

  void _evaluateDriftConditions() {
    if (!mounted) return;

    final config = kPageBackgroundConfigs[widget.page] ??
        kPageBackgroundConfigs[AppBackgroundPage.beranda]!;

    // 1. Sakelar pengaturan aktif
    final motionEnabled = _motion.enabled;

    // 2. Bukan reduce motion / disableAnimations
    final disableAnimations = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // 3. Aplikasi dalam status resumed
    final isResumed = _lifecycleState == AppLifecycleState.resumed;

    // 4. Halaman aktif termasuk dalam daftar yang mengizinkan drift
    final pageAllows = config.allowDrift && config.visible && widget.showAura;

    // 5. Tidak ada sesi tracking yang aktif merekam
    final isTrackingRecording = _tracking.isRecording;

    // 6. Mode hemat baterai tidak aktif
    final policy = VisualEffectPolicyScope.of(context);
    final isBatterySaver =
        policy.powerProfile == PowerProfile.saver ||
        policy.powerProfile == PowerProfile.critical;

    final inTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    final allMet = motionEnabled &&
        !disableAnimations &&
        isResumed &&
        pageAllows &&
        !isTrackingRecording &&
        !isBatterySaver &&
        !_isScrolling;

    if (allMet) {
      if (!_isDrifting) {
        _isDrifting = true;
        _resetAnimationController.stop();
        if (!inTest) {
          _driftAnimationController.repeat(reverse: true);
        }
      }
    } else if (_isScrolling) {
      // Jeda sementara di tempat agar latar tidak memicu repaint navbar saat 120Hz scroll.
      if (_isDrifting) {
        _isDrifting = false;
        _driftAnimationController.stop();
      }
    } else {
      if (_isDrifting || _driftNotifier.value > 0.0) {
        _isDrifting = false;
        _driftAnimationController.stop();
        _startReturnToZero();
      }
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      _scrollResumeTimer?.cancel();
      if (!_isScrolling) {
        _isScrolling = true;
        if (_isDrifting) {
          _isDrifting = false;
          _driftAnimationController.stop();
        }
      }
    } else if (notification is ScrollEndNotification) {
      _scrollResumeTimer?.cancel();
      _scrollResumeTimer = Timer(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        _isScrolling = false;
        _evaluateDriftConditions();
      });
    }
    return false;
  }

  void _startReturnToZero() {
    final current = _driftNotifier.value;
    if (current == 0.0) return;

    _resetAnimationController.stop();
    _resetAnimationController.reset();
    final anim = Tween<double>(begin: current, end: 0.0).animate(
      CurvedAnimation(
        parent: _resetAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    void resetListener() {
      _driftNotifier.value = anim.value;
    }

    anim.addListener(resetListener);
    _resetAnimationController.forward().then((_) {
      anim.removeListener(resetListener);
      _driftNotifier.value = 0.0;
    });
  }

  @override
  void dispose() {
    _scrollResumeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _driftAnimationController.dispose();
    _resetAnimationController.dispose();
    _intensityAnimationController.dispose();
    _motion.removeListener(_evaluateDriftConditions);
    _tracking.removeListener(_evaluateDriftConditions);
    _driftNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Jika sudah dibungkus oleh AppBackgroundScope leluhur, jangan buat latar ganda
    final existingScope = AppBackgroundScope.maybeOf(context);
    if (existingScope != null && !existingScope.isRoot) {
      return widget.child;
    }

    final colors = HiqeoColors.of(context);

    return AppBackgroundScope(
      isRoot: existingScope == null,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Lapisan latar di dalam RepaintBoundary terisolasi
          RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _AppBackgroundPainter(
                repaint: _driftNotifier,
                colors: colors,
                driftNotifier: _driftNotifier,
                intensity: _currentIntensity,
                showAura: widget.showAura && _currentIntensity > 0.0,
              ),
            ),
          ),
          // Pohon halaman/Navigator di atas latar (menjeda drift selama pengguliran)
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// CustomPainter untuk latar aura Hiqeo.
class _AppBackgroundPainter extends CustomPainter {
  _AppBackgroundPainter({
    required super.repaint,
    required this.colors,
    required this.driftNotifier,
    required this.intensity,
    required this.showAura,
  });

  final HiqeoColors colors;
  final ValueNotifier<double> driftNotifier;
  final double intensity;
  final bool showAura;

  // Parameter terkalibrasi audit kontras WCAG
  static const Offset centerA = Offset(-0.028, -0.112);
  static const double rxA = 0.756; // 0.84 * 0.90
  static const double ryA = 0.567; // 0.63 * 0.90
  static const double opacityA = 0.88;

  static const Offset centerB = Offset(1.082, 1.128);
  static const double rxB = 0.756; // 0.84 * 0.90
  static const double ryB = 0.567; // 0.63 * 0.90
  static const double opacityB = 0.90;

  static const Offset centerC = Offset(0.668, 0.36);
  static const double rxC = 0.70;
  static const double ryC = 0.42;
  static const double opacityC = 0.77;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final rect = Offset.zero & size;

    // 1. Warna dasar background
    canvas.drawRect(rect, Paint()..color = colors.background);

    if (!showAura || intensity <= 0.0) return;

    final t = driftNotifier.value;
    final delta = Offset(
      kDriftDeltaFraction.dx * width,
      kDriftDeltaFraction.dy * height,
    );

    // Hitung posisi berfase: a(t) = t * delta, b(t) = (1 - t) * delta
    final posA = Offset(
      centerA.dx * width + t * delta.dx,
      centerA.dy * height + t * delta.dy,
    );
    final posB = Offset(
      centerB.dx * width + (1.0 - t) * delta.dx,
      centerB.dy * height + (1.0 - t) * delta.dy,
    );
    final posC = Offset(
      centerC.dx * width,
      centerC.dy * height,
    );

    // 2. Lapisan a (cahaya kiri atas)
    _drawRadialEllipse(
      canvas: canvas,
      center: posA,
      rx: rxA * width,
      ry: ryA * height,
      color: colors.blobTopLeft,
      opacity: opacityA * intensity,
    );

    // 3. Lapisan b (bayangan kanan bawah)
    _drawRadialEllipse(
      canvas: canvas,
      center: posB,
      rx: rxB * width,
      ry: ryB * height,
      color: colors.blobBottomRight,
      opacity: opacityB * intensity,
    );

    // 4. Lapisan c (cahaya lembut di tengah, diam)
    _drawRadialEllipse(
      canvas: canvas,
      center: posC,
      rx: rxC * width,
      ry: ryC * height,
      color: colors.surface,
      opacity: opacityC * intensity,
    );
  }

  void _drawRadialEllipse({
    required Canvas canvas,
    required Offset center,
    required double rx,
    required double ry,
    required Color color,
    required double opacity,
  }) {
    if (opacity <= 0.0 || rx <= 0.0 || ry <= 0.0) return;
    final effectiveColor = color.withValues(alpha: color.a * opacity);
    final endColor = effectiveColor.withValues(alpha: 0.0);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(rx, ry);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[effectiveColor, endColor],
        stops: const <double>[0.0, 0.7],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1.0));
    canvas.drawCircle(Offset.zero, 1.0, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AppBackgroundPainter oldDelegate) {
    return oldDelegate.colors != colors ||
        oldDelegate.intensity != intensity ||
        oldDelegate.showAura != showAura;
  }
}
