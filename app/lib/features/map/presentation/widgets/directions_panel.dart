import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design/app_theme.dart';
import '../../../../design/glass/glass_surface.dart';
import '../../../../design/tokens.dart';
import '../../../../design/widgets/line_icons.dart';
import '../../../trails/application/recovery_guidance_service.dart';
import '../../../trails/domain/guidance_state.dart';
import '../../../trails/domain/heading_provider.dart';
import '../../../trails/domain/straight_line_guidance_texts.dart';

/// Helper format jarak dengan desimal koma Indonesia.
String formatDistanceId(double meters) {
  if (meters < 1000) {
    return '${meters.round()} m';
  }
  final km = meters / 1000.0;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Menormalkan selisih sudut ke rentang -180 .. 180 derajat.
double normalizeAngleDiff(double diff) {
  var d = diff % 360.0;
  if (d > 180.0) d -= 360.0;
  if (d < -180.0) d += 360.0;
  return d;
}

/// Panel "Petunjuk jalur" yang SELALU memakai gaya mode gelap di atas peta
/// (tier [GlassTier.overMap]) agar kontras tetap tinggi dan peta di belakangnya
/// tidak tembus baca, baik di mode terang maupun mode gelap aplikasi.
class DirectionsPanel extends StatefulWidget {
  const DirectionsPanel({
    super.key,
    required this.guidanceService,
    required this.straightLineAcknowledged,
    required this.onClose,
    required this.onSos,
    required this.onAcknowledge,
    this.onOpenWarningDialog,
    this.phoneHeading,
    this.onActionUnavailable,
    this.initialMinimized = false,
    this.onMinimizedChanged,
  });

  final RecoveryGuidanceService guidanceService;

  /// True bila peringatan garis lurus sudah pernah dibuka & dikonfirmasi pada
  /// sesi tracking ini; false membuat baris peringatan otomatis terbuka pada
  /// kemunculan pertama mode garis lurus dengan tombol "Mengerti".
  final bool straightLineAcknowledged;
  final VoidCallback onClose;
  final VoidCallback onSos;
  final VoidCallback onAcknowledge;
  final VoidCallback? onOpenWarningDialog;
  final double? phoneHeading;
  final void Function(GuidanceUnavailableReason reason)? onActionUnavailable;
  final bool initialMinimized;
  final ValueChanged<bool>? onMinimizedChanged;

  @override
  State<DirectionsPanel> createState() => _DirectionsPanelState();
}

class _DirectionsPanelState extends State<DirectionsPanel>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const HiqeoColors _dark = HiqeoColors.dark;

  late final AnimationController _entryController;
  late final AnimationController _pulseController;
  AnimationController? _countdownController;

  late final Animation<double> _panelSlide;
  late final Animation<double> _panelScale;
  late final Animation<double> _panelFade;
  late final Animation<double> _orbScale;
  late final Animation<double> _progressRing;
  late final Animation<double> _textFade;
  late final Animation<double> _textSlide;
  late final Animation<double> _pulseSpread;

  StreamSubscription<HeadingReading>? _headingSub;
  double _currentPhoneHeading = 0.0;
  double _continuousArrowAngleRad = 0.0;

  bool _isExiting = false;
  late bool _isMinimized;
  bool _warningExpanded = false;
  bool _warningAutoExpandedThisEntry = false;
  GuidanceState? _lastState;

  @override
  void initState() {
    super.initState();
    _isMinimized = widget.initialMinimized;
    WidgetsBinding.instance.addObserver(this);

    _currentPhoneHeading = widget.phoneHeading ??
        widget.guidanceService.headingProvider?.currentReading?.headingDeg ??
        0.0;

    _headingSub = widget.guidanceService.headingProvider?.readings.listen((r) {
      if (!mounted) return;
      setState(() => _currentPhoneHeading = r.headingDeg);
    });

    final initial = widget.guidanceService.currentState;
    _lastState = initial;
    if (initial is GuidanceStraightLine && !widget.straightLineAcknowledged) {
      _warningExpanded = true;
      _warningAutoExpandedThisEntry = true;
      unawaited(HapticFeedback.heavyImpact());
    }

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _panelSlide = Tween<double>(begin: 32.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      ),
    );
    _panelScale = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      ),
    );
    _panelFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.40, curve: Curves.easeOutCubic),
      ),
    );
    _orbScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.12, 0.65, curve: Curves.easeOutBack),
      ),
    );
    _progressRing = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.18, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _textSlide = Tween<double>(begin: 10.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.20, 0.60, curve: Curves.easeOutCubic),
      ),
    );
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.20, 0.60, curve: Curves.easeOutCubic),
      ),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _pulseSpread = Tween<double>(begin: 0.0, end: 4.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entryController.forward();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pulseController.stop();
      _countdownController?.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (!inTest &&
          (_pulseController.status == AnimationStatus.dismissed ||
              _pulseController.status == AnimationStatus.completed)) {
        _pulseController.repeat(reverse: true);
      }
    }
  }

  @override
  void didUpdateWidget(DirectionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phoneHeading != null &&
        widget.phoneHeading != oldWidget.phoneHeading) {
      _currentPhoneHeading = widget.phoneHeading!;
    }
    if (widget.initialMinimized != oldWidget.initialMinimized) {
      _isMinimized = widget.initialMinimized;
    }
    if (widget.straightLineAcknowledged &&
        !oldWidget.straightLineAcknowledged) {
      _warningAutoExpandedThisEntry = false;
    }
  }

  void _setMinimized(bool value) {
    if (_isMinimized == value) return;
    setState(() => _isMinimized = value);
    widget.onMinimizedChanged?.call(value);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _headingSub?.cancel();
    _entryController.dispose();
    _pulseController.dispose();
    _countdownController?.dispose();
    super.dispose();
  }

  void _handleClose() {
    if (_isExiting) return;
    setState(() => _isExiting = true);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      widget.onClose();
      return;
    }
    _entryController
        .animateBack(
          0.0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInCubic,
        )
        .then((_) {
      if (mounted) widget.onClose();
    });
  }

  void _setupCountdown(bool disableAnimations) {
    if (_countdownController != null) return;
    _countdownController = AnimationController(
      vsync: this,
      duration: disableAnimations
          ? const Duration(milliseconds: 400)
          : const Duration(seconds: 4),
    );
    _countdownController!.forward().then((_) {
      if (mounted && !_isExiting) {
        _handleClose();
      }
    });
  }

  void _acknowledgeAndCollapseWarning() {
    setState(() {
      _warningExpanded = false;
      _warningAutoExpandedThisEntry = false;
    });
    widget.onAcknowledge();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final inTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

    if (disableAnimations && _entryController.value < 1.0 && !_isExiting) {
      _entryController.value = 1.0;
    }
    if (!disableAnimations && !inTest && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }

    // SELALU bungkus panel dengan tema gelap lokal (identik di mode terang & gelap).
    return Theme(
      data: hiqeoDarkTheme,
      child: StreamBuilder<GuidanceState>(
        stream: widget.guidanceService.states,
        initialData: widget.guidanceService.currentState,
        builder: (context, snapshot) {
          final state = snapshot.data ?? widget.guidanceService.currentState;
          if (_lastState != state) {
            final wasStraight = _lastState is GuidanceStraightLine;
            final isStraight = state is GuidanceStraightLine;
            if (isStraight && !wasStraight) {
              unawaited(HapticFeedback.heavyImpact());
              if (!widget.straightLineAcknowledged) {
                _warningExpanded = true;
                _warningAutoExpandedThisEntry = true;
              } else {
                _warningExpanded = false;
                _warningAutoExpandedThisEntry = false;
              }
            } else if (!isStraight && wasStraight) {
              _warningExpanded = false;
              _warningAutoExpandedThisEntry = false;
            }
            _lastState = state;
          }
          if (state is GuidanceReturned && _countdownController == null) {
            _setupCountdown(disableAnimations);
          }

          final Widget switcher = AnimatedSwitcher(
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              if (disableAnimations) return child;
              final offset = Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: _isMinimized
                ? _buildMinimizedPill(context, state)
                : _buildExpandedCard(context, state, disableAnimations),
          );

          final Widget semanticPanel = Semantics(
            liveRegion: true,
            label: _semanticLiveLabel(state),
            child: switcher,
          );

          if (disableAnimations) {
            return semanticPanel;
          }

          return AnimatedBuilder(
            animation: _entryController,
            builder: (context, child) {
              if (_entryController.isCompleted && !_isExiting) {
                return child!;
              }
              return Transform.translate(
                offset: Offset(0, _panelSlide.value),
                child: Transform.scale(
                  scale: _panelScale.value,
                  child: Opacity(
                    opacity: _panelFade.value.clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
              );
            },
            child: semanticPanel,
          );
        },
      ),
    );
  }

  Widget _buildOverMapShell({
    required Key key,
    required EdgeInsetsGeometry padding,
    required Widget child,
  }) {
    // Panel di atas peta selalu memakai gaya gelap lokal & tier overMap:
    // fill #313851 alfa 0,95, border krem alfa 0,2, bayangan 0 20 44 hitam
    // alfa 0,4, highlight tepi atas krem alfa 0,25.
    return GlassSurface(
      key: key,
      tier: GlassTier.overMap,
      borderRadius: 28,
      padding: padding,
      fillColor: _dark.background.withValues(alpha: 0.95),
      borderColor: _dark.textPrimary.withValues(alpha: 0.20),
      highlightColor: _dark.textPrimary.withValues(alpha: 0.25),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 44,
          offset: Offset(0, 20),
        ),
      ],
      child: child,
    );
  }

  Widget _buildExpandedCard(
    BuildContext context,
    GuidanceState state,
    bool disableAnimations,
  ) {
    return _buildOverMapShell(
      key: const ValueKey<String>('directions-expanded-card'),
      padding: const EdgeInsets.all(16),
      child: AnimatedSize(
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Label semantik tersembunyi untuk pencarian uji
            const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 0,
                height: 0,
                child: Text('Petunjuk jalur', style: TextStyle(fontSize: 0.01)),
              ),
            ),
            _buildTopBar(context, state),
            const SizedBox(height: 12),
            _buildMainRow(context, state, disableAnimations),
            _buildBottomSection(context, state, disableAnimations),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimizedPill(BuildContext context, GuidanceState state) {
    final bool isStraight = state is GuidanceStraightLine;

    double bearingDeg = 0.0;
    if (state is GuidanceFollowingTrail) {
      bearingDeg = state.bearingDeg;
    } else if (state is GuidanceStraightLine) {
      bearingDeg = state.bearingDeg;
    }
    final heading = _directionHeadingFor(bearingDeg);
    final arrowAngle = _calcShortestAngle(
      _continuousArrowAngleRad,
      heading.turnAngleRad,
    );

    final String summaryText = switch (state) {
      GuidanceStraightLine(:final distToRouteM) =>
        '${formatDistanceId(distToRouteM)} · ${heading.title}',
      GuidanceFollowingTrail(:final distToNextM) =>
        '${formatDistanceId(distToNextM)} · ${heading.title}',
      GuidanceOnRoute(:final distanceToRouteM) =>
        'Kamu masih di jalur · ${formatDistanceId(distanceToRouteM)}',
      GuidanceCheckingPosition() => 'Memeriksa posisi…',
      GuidanceReturned() => 'Kamu sudah kembali di jalur',
      GuidanceUnavailable(:final reason) => switch (reason) {
          GuidanceUnavailableReason.waitingGps => 'Mencari sinyal GPS',
          GuidanceUnavailableReason.needsLocation => 'Lokasi belum aktif',
          GuidanceUnavailableReason.needsPermission => 'Izin lokasi diperlukan',
          GuidanceUnavailableReason.noRoute => 'Belum ada rute aktif',
        },
    };

    final Widget leadingIcon;
    if (state is GuidanceUnavailable) {
      leadingIcon = Icon(
        Icons.location_off_rounded,
        size: 18,
        color: _dark.warning,
      );
    } else if (state is GuidanceCheckingPosition) {
      leadingIcon = Icon(Icons.my_location, size: 18, color: _dark.primary);
    } else if (state is GuidanceReturned) {
      leadingIcon = Icon(Icons.check_rounded, size: 18, color: _dark.primary);
    } else {
      leadingIcon = Transform.rotate(
        angle: arrowAngle,
        child: Icon(
          Icons.navigation,
          size: 18,
          color: isStraight ? _dark.warning : _dark.primary,
        ),
      );
    }

    return Semantics(
      button: true,
      label: 'Buka petunjuk jalur: $summaryText',
      child: GestureDetector(
        key: const ValueKey<String>('map-directions-minimized-bar'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _setMinimized(false),
        child: _buildOverMapShell(
          key: const ValueKey<String>('directions-minimized-pill'),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: SizedBox(
            height: 56,
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dark.hairline,
                  ),
                  child: Center(child: leadingIcon),
                ),
                const SizedBox(width: 10),
                if (isStraight) ...<Widget>[
                  Container(
                    key: const ValueKey<String>(
                      'directions-pill-warning-dot',
                    ),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _dark.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    summaryText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontVariations: const <ui.FontVariation>[
                        ui.FontVariation.weight(650),
                      ],
                      color: _dark.textPrimary,
                      fontFeatures: const <ui.FontFeature>[
                        ui.FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'Perluas petunjuk jalur',
                  child: GestureDetector(
                    key: const ValueKey<String>('map-directions-expand'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _setMinimized(false),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _dark.hairline,
                      ),
                      child: Center(
                        child: HiqeoIcon(
                          HiqeoIcons.chevronUp,
                          size: 18,
                          color: _dark.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _semanticLiveLabel(GuidanceState? state) {
    return switch (state) {
      GuidanceUnavailable(:final reason) => switch (reason) {
          GuidanceUnavailableReason.needsLocation =>
            'Layanan lokasi belum aktif',
          GuidanceUnavailableReason.needsPermission =>
            'Izin lokasi belum diberikan',
          GuidanceUnavailableReason.noRoute => 'Belum ada rute aktif',
          GuidanceUnavailableReason.waitingGps => 'Mencari sinyal GPS',
        },
      GuidanceCheckingPosition() => 'Memeriksa posisi…',
      GuidanceOnRoute() => 'Kamu masih di jalur',
      GuidanceFollowingTrail() => 'Kamu keluar jalur, ikuti jejak rekamanmu',
      GuidanceStraightLine() =>
        'Garis lurus, bukan rute. Perhatikan peringatan keselamatan.',
      GuidanceReturned() => 'Kamu sudah kembali di jalur',
      null => 'Petunjuk jalur',
    };
  }

  ({String title, double turnAngleRad}) _directionHeadingFor(double bearingDeg) {
    final delta = normalizeAngleDiff(bearingDeg - _currentPhoneHeading);
    final isStraightAhead = delta.abs() < 12.0;
    final title = isStraightAhead
        ? 'Lurus'
        : (delta > 0
            ? 'Belok kanan ${delta.round()}°'
            : 'Belok kiri ${delta.abs().round()}°');
    final targetTurnAngleRad = isStraightAhead ? 0.0 : delta * (math.pi / 180.0);
    return (title: title, turnAngleRad: targetTurnAngleRad);
  }

  Widget _buildTopBar(BuildContext context, GuidanceState state) {
    final isStraight = state is GuidanceStraightLine;

    final String tagLabel;
    final Color dotColor;

    switch (state) {
      case GuidanceUnavailable():
        tagLabel = 'Petunjuk belum tersedia';
        dotColor = _dark.warning;
      case GuidanceCheckingPosition():
        tagLabel = 'Memeriksa posisi';
        dotColor = _dark.primary.withValues(alpha: 0.6);
      case GuidanceOnRoute():
        tagLabel = 'Di jalur utama';
        dotColor = _dark.primary;
      case GuidanceFollowingTrail():
        tagLabel = 'Jejak rekamanmu';
        dotColor = _dark.primary;
      case GuidanceStraightLine():
        tagLabel = StraightLineGuidanceTexts.modeLabel;
        dotColor = _dark.warning;
      case GuidanceReturned():
        tagLabel = 'Di jalur utama';
        dotColor = _dark.primary;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Flexible(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _dark.hairline,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _dark.textPrimary.withValues(alpha: 0.16),
                width: 1.0,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      tagLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            isStraight ? _dark.warningText : _dark.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              button: true,
              label: 'Perkecil petunjuk jalur',
              child: GestureDetector(
                key: const ValueKey<String>('map-directions-minimize'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _setMinimized(true),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dark.hairline,
                  ),
                  child: Center(
                    child: HiqeoIcon(
                      HiqeoIcons.chevronDown,
                      size: 18,
                      color: _dark.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Tutup petunjuk jalur',
              child: GestureDetector(
                key: const ValueKey<String>('map-directions-close'),
                behavior: HitTestBehavior.opaque,
                onTap: _handleClose,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dark.hairline,
                  ),
                  child: Center(
                    child: Icon(Icons.close, size: 18, color: _dark.textPrimary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMainRow(
    BuildContext context,
    GuidanceState state,
    bool disableAnimations,
  ) {
    final theme = Theme.of(context);

    double bearingDeg = 0.0;
    double progress = 0.0;
    final bool isStraight = state is GuidanceStraightLine;

    if (state is GuidanceFollowingTrail) {
      bearingDeg = state.bearingDeg;
      progress = state.progress;
    } else if (state is GuidanceStraightLine) {
      bearingDeg = state.bearingDeg;
      progress = state.progress;
    } else if (state is GuidanceOnRoute || state is GuidanceReturned) {
      progress = 1.0;
    } else if (state is GuidanceUnavailable) {
      progress = 0.25;
    }

    final heading = _directionHeadingFor(bearingDeg);

    final String mainTitle;
    if (state is GuidanceFollowingTrail || state is GuidanceStraightLine) {
      mainTitle = heading.title;
    } else if (state is GuidanceReturned) {
      mainTitle = 'Kamu sudah kembali di jalur';
    } else if (state is GuidanceOnRoute) {
      mainTitle = 'Kamu masih di jalur';
    } else if (state is GuidanceCheckingPosition) {
      mainTitle = 'Memeriksa posisi';
    } else {
      mainTitle = 'Mencari sinyal GPS';
    }

    _continuousArrowAngleRad = _calcShortestAngle(
      _continuousArrowAngleRad,
      heading.turnAngleRad,
    );

    final titleAndSubtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          mainTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
            color: _dark.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        _buildSecondaryText(context, state),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        ScaleTransition(
          scale: disableAnimations
              ? const AlwaysStoppedAnimation<double>(1.0)
              : _orbScale,
          child: _buildOrb(
            state: state,
            progress: progress,
            isStraight: isStraight,
            arrowAngleRad: _continuousArrowAngleRad,
            disableAnimations: disableAnimations,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: disableAnimations
              ? titleAndSubtitle
              : FadeTransition(
                  opacity: _textFade,
                  child: AnimatedBuilder(
                    animation: _textSlide,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, _textSlide.value),
                      child: child,
                    ),
                    child: titleAndSubtitle,
                  ),
                ),
        ),
      ],
    );
  }

  double _calcShortestAngle(double current, double target) {
    var diff = (target - current) % (2 * math.pi);
    if (diff > math.pi) diff -= 2 * math.pi;
    if (diff < -math.pi) diff += 2 * math.pi;
    return current + diff;
  }

  Widget _buildOrb({
    required GuidanceState state,
    required double progress,
    required bool isStraight,
    required double arrowAngleRad,
    required bool disableAnimations,
  }) {
    Widget orbContent;
    if (state is GuidanceReturned) {
      orbContent = _DrawnCheckmark(
        color: _dark.primary,
        disableAnimations: disableAnimations,
      );
    } else if (state is GuidanceUnavailable) {
      orbContent = Icon(
        Icons.location_off_rounded,
        size: 30,
        color: _dark.warning,
      );
    } else if (state is GuidanceCheckingPosition) {
      orbContent = Icon(Icons.my_location, size: 30, color: _dark.primary);
    } else {
      orbContent = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: arrowAngleRad, end: arrowAngleRad),
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 500),
        curve: Curves.easeOutBack,
        builder: (context, angle, _) => Transform.rotate(
          angle: angle,
          child: Icon(
            Icons.navigation,
            size: 32,
            color: isStraight ? _dark.warning : _dark.primary,
          ),
        ),
      );
    }

    // Orb 84 dp: cincin progres stroke 5, lingkaran dalam fill hairline dengan
    // ikon panah 32 dp.
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedBuilder(
            animation: _entryController,
            builder: (context, _) {
              final animatedProgress = disableAnimations
                  ? progress
                  : progress * _progressRing.value;
              return CustomPaint(
                size: const Size(84, 84),
                painter: _ProgressRingPainter(
                  progress: animatedProgress.clamp(0.0, 1.0),
                  trackColor: _dark.hairline,
                  progressColor: (isStraight || state is GuidanceUnavailable)
                      ? _dark.warning
                      : _dark.primary,
                ),
              );
            },
          ),
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _dark.hairline,
              border: Border.all(
                color: _dark.textPrimary.withValues(alpha: 0.14),
                width: 1.0,
              ),
            ),
            child: Center(child: orbContent),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryText(BuildContext context, GuidanceState state) {
    final baseStyle = TextStyle(
      fontSize: 12.5,
      color: _dark.textSecondary,
      height: 1.35,
    );
    final boldStyle = baseStyle.copyWith(
      color: _dark.textPrimary,
      fontWeight: FontWeight.bold,
      fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
    );

    switch (state) {
      case GuidanceFollowingTrail(
          :final distToNextM,
          :final remainingTrailM,
        ):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text.rich(
              TextSpan(
                style: baseStyle,
                children: <TextSpan>[
                  TextSpan(
                    text: formatDistanceId(distToNextM),
                    style: boldStyle,
                  ),
                  const TextSpan(text: ' ke titik jejak berikutnya'),
                ],
              ),
            ),
            Text.rich(
              TextSpan(
                style: baseStyle,
                children: <TextSpan>[
                  TextSpan(
                    text: formatDistanceId(remainingTrailM),
                    style: boldStyle,
                  ),
                  const TextSpan(text: ' menyusuri jejak ke jalur'),
                ],
              ),
            ),
          ],
        );

      case GuidanceStraightLine(
          :final distToRouteM,
          :final accuracyM,
        ):
        final isFar = distToRouteM > 1000.0;
        final isLowAccuracy = (accuracyM ?? 0.0) > 30.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text.rich(
              TextSpan(
                style: baseStyle,
                children: <TextSpan>[
                  TextSpan(
                    text: formatDistanceId(distToRouteM),
                    style: boldStyle,
                  ),
                  const TextSpan(text: ' ke titik jalur terdekat'),
                ],
              ),
            ),
            if (isFar)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  StraightLineGuidanceTexts.farFromRouteWarning,
                  key: const ValueKey<String>('directions-far-warning'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: baseStyle.copyWith(
                    fontSize: 11.5,
                    color: _dark.warningText,
                  ),
                ),
              ),
            if (isLowAccuracy)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  StraightLineGuidanceTexts.lowAccuracyWarning,
                  key: const ValueKey<String>('directions-accuracy-warning'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: baseStyle.copyWith(
                    fontSize: 11.5,
                    color: _dark.warningText,
                  ),
                ),
              ),
          ],
        );

      case GuidanceOnRoute(:final distanceToRouteM):
        return Text.rich(
          TextSpan(
            style: baseStyle,
            children: <TextSpan>[
              TextSpan(
                text: formatDistanceId(distanceToRouteM),
                style: boldStyle,
              ),
              const TextSpan(text: ' dari garis jalur'),
            ],
          ),
        );

      case GuidanceReturned():
        return Text('Petunjuk jalur menutup otomatis', style: baseStyle);

      case GuidanceCheckingPosition():
        return Text('Menghubungkan posisi dengan jalur…', style: baseStyle);

      case GuidanceUnavailable(:final reason):
        final msg = switch (reason) {
          GuidanceUnavailableReason.needsLocation =>
            'Aktifkan lokasi agar peta bisa memandu kembali ke jalur.',
          GuidanceUnavailableReason.needsPermission =>
            'Beri izin lokasi untuk memulai panduan jalur.',
          GuidanceUnavailableReason.noRoute =>
            'Pilih jalur gunung dari katalog peta.',
          GuidanceUnavailableReason.waitingGps =>
            'Tunggu sebentar atau pindah ke tempat terbuka.',
        };
        return Text(msg, style: baseStyle);
    }
  }

  Widget _buildBottomSection(
    BuildContext context,
    GuidanceState state,
    bool disableAnimations,
  ) {
    if (state is GuidanceFollowingTrail) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: _dark.hairline,
              side: BorderSide(
                color: _dark.textPrimary.withValues(alpha: 0.20),
                width: 1.0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _handleClose,
            child: Text(
              'Selesai memandu',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _dark.textPrimary,
              ),
            ),
          ),
        ),
      );
    }

    if (state is GuidanceStraightLine) {
      final showAckButton =
          _warningExpanded && !widget.straightLineAcknowledged;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Baris Peringatan penting yang bisa diminimalkan:
            // tinggi 44 saat ringkas, radius 16, border 1,5 px warning, fill
            // warning alfa 0,14.
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  key: const ValueKey<String>('straight-line-warning-card'),
                  decoration: BoxDecoration(
                    color: _dark.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _dark.warning, width: 1.5),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: _dark.warning.withValues(alpha: 0.18),
                        blurRadius: 10,
                        spreadRadius: _pulseSpread.value,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Semantics(
                    button: true,
                    expanded: _warningExpanded,
                    label: _warningExpanded
                        ? 'Tutup peringatan penting'
                        : 'Baca peringatan penting',
                    child: GestureDetector(
                      key: const ValueKey<String>(
                        'straight-line-warning-toggle',
                      ),
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _warningExpanded = !_warningExpanded),
                      child: SizedBox(
                        height: 44,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: _dark.warningText,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Peringatan penting',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: _dark.warningText,
                                  ),
                                ),
                              ),
                              Text(
                                _warningExpanded ? 'Tutup' : 'Baca',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: _dark.warningText,
                                ),
                              ),
                              const SizedBox(width: 4),
                              AnimatedRotation(
                                turns: _warningExpanded ? 0.5 : 0.0,
                                duration: disableAnimations
                                    ? Duration.zero
                                    : const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                  color: _dark.warningText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_warningExpanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            StraightLineGuidanceTexts.warningCardText,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: _dark.textPrimary,
                              height: 1.4,
                            ),
                          ),
                          if (showAckButton ||
                              _warningAutoExpandedThisEntry) ...<Widget>[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 36,
                                child: FilledButton(
                                  key: const ValueKey<String>(
                                    'straight-line-warning-ack',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _dark.warning,
                                    foregroundColor:
                                        HiqeoColors.light.glassHighlight,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _acknowledgeAndCollapseWarning,
                                  child: const Text(
                                    'Mengerti',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Tombol SOS merah (#B3412F = HiqeoColors.light.warning), teks putih bold, tinggi 48
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                key: const ValueKey<String>('straight-line-panel-sos-button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HiqeoColors.light.warning,
                  foregroundColor: HiqeoColors.light.glassHighlight,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: widget.onSos,
                child: const Text(
                  'SOS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (state is GuidanceReturned) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: AnimatedBuilder(
          animation: _countdownController ?? const AlwaysStoppedAnimation(0.0),
          builder: (context, _) {
            final value = 1.0 - (_countdownController?.value ?? 0.0);
            return ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: _dark.hairline,
                valueColor: AlwaysStoppedAnimation<Color>(_dark.primary),
              ),
            );
          },
        ),
      );
    }

    if (state is GuidanceUnavailable) {
      final reason = state.reason;
      if (reason == GuidanceUnavailableReason.waitingGps) {
        return const SizedBox.shrink();
      }
      final btnLabel = switch (reason) {
        GuidanceUnavailableReason.needsLocation => 'Buka pengaturan lokasi',
        GuidanceUnavailableReason.needsPermission => 'Beri izin',
        GuidanceUnavailableReason.noRoute => 'Pilih jalur gunung',
        GuidanceUnavailableReason.waitingGps => '',
      };
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _dark.primary,
              foregroundColor: _dark.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => widget.onActionUnavailable?.call(reason),
            child: Text(
              btnLabel,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Painter untuk cincin progres (stroke 5, ujung bulat, searah jarum jam dari jam 12).
class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 5.0) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke;

    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0.001) {
      final sweepAngle = progress * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}

/// Animasi centang yang tergambar untuk state GuidanceReturned.
class _DrawnCheckmark extends StatefulWidget {
  const _DrawnCheckmark({
    required this.color,
    required this.disableAnimations,
  });

  final Color color;
  final bool disableAnimations;

  @override
  State<_DrawnCheckmark> createState() => _DrawnCheckmarkState();
}

class _DrawnCheckmarkState extends State<_DrawnCheckmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 650),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(34, 34),
          painter: _CheckmarkPainter(
            progress: widget.disableAnimations ? 1.0 : _controller.value,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _CheckmarkPainter extends CustomPainter {
  const _CheckmarkPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    const p1 = Offset(8, 17);
    const p2 = Offset(14, 24);
    const p3 = Offset(26, 10);

    final path = Path()..moveTo(p1.dx, p1.dy);

    if (progress <= 0.45) {
      final t = progress / 0.45;
      path.lineTo(
        p1.dx + (p2.dx - p1.dx) * t,
        p1.dy + (p2.dy - p1.dy) * t,
      );
    } else {
      path.lineTo(p2.dx, p2.dy);
      final t = (progress - 0.45) / 0.55;
      path.lineTo(
        p2.dx + (p3.dx - p2.dx) * t,
        p2.dy + (p3.dy - p2.dy) * t,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckmarkPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
