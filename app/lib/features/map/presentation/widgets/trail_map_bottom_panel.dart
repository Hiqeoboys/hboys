import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design/glass/glass_surface.dart';
import '../../../../design/tokens.dart';
import '../../domain/map_package.dart';

/// Panel bawah kaca di layar peta jalur sesuai spesifikasi prompt.
class TrailMapBottomPanel extends StatefulWidget {
  const TrailMapBottomPanel({
    super.key,
    required this.trails,
    required this.selectedTrail,
    required this.onSelectTrail,
    required this.onStartTracking,
    this.onStartDescent,
    this.showStartTracking = true,
    this.startButtonLabel = 'Mulai tracking',
    this.isSelectionOpen = false,
    this.onToggleSelection,
    this.isTrackingLocked = false,
    this.trackingLockNote,
  });

  final List<MapTrail> trails;
  final MapTrail? selectedTrail;
  final ValueChanged<MapTrail> onSelectTrail;
  final VoidCallback onStartTracking;
  final VoidCallback? onStartDescent;
  final bool showStartTracking;
  final String startButtonLabel;
  final bool isSelectionOpen;
  final VoidCallback? onToggleSelection;
  final bool isTrackingLocked;
  final String? trackingLockNote;

  @override
  State<TrailMapBottomPanel> createState() => TrailMapBottomPanelState();
}

class TrailMapBottomPanelState extends State<TrailMapBottomPanel>
    with SingleTickerProviderStateMixin {
  late bool _isOpen;
  late AnimationController _controller;
  late Animation<double> _heightAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _chevronAnimation;

  bool _isJalurPressed = false;
  bool _isStartPressed = false;
  bool _isDescentPressed = false;

  @override
  void initState() {
    super.initState();
    _isOpen = widget.isSelectionOpen;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    // Wadah tinggi 0 saat tertutup dan 56 dp saat terbuka (12 dp pad atas + 32 chip + 12 jarak ke tombol)
    _heightAnimation = Tween<double>(begin: 0.0, end: 56.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Cubic(0.2, 0.8, 0.2, 1.0),
      ),
    );

    // Opasitas 240 ms
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.easeIn),
      ),
    );

    // Chevron berputar 180 derajat (math.pi rad) 320 ms
    _chevronAnimation = Tween<double>(begin: 0.0, end: math.pi).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Cubic(0.2, 0.8, 0.2, 1.0),
      ),
    );

    if (_isOpen) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(TrailMapBottomPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelectionOpen != oldWidget.isSelectionOpen) {
      if (widget.isSelectionOpen != _isOpen) {
        toggleSelection();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void toggleSelection() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
    widget.onToggleSelection?.call();
  }

  void closeSelection() {
    if (_isOpen) {
      setState(() {
        _isOpen = false;
        _controller.reverse();
      });
      widget.onToggleSelection?.call();
    }
  }

  static String _formatDecimal(double val) {
    return val.toStringAsFixed(1).replaceAll('.', ',');
  }

  static String _formatGrouped(int val) {
    final digits = val.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return val < 0 ? '-$buffer' : buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final hasMultipleTrails = widget.trails.length > 1;

    // Nilai statistik dari jalur terpilih
    final trail = widget.selectedTrail;
    final distM = trail?.distanceM ?? trail?.effectiveDistanceM ?? 4400;
    final gainM = (trail?.elevationGainM ?? 1101).round();
    final maxElevM = (trail?.maxElevationM ?? 3078).round();

    final distText = '${_formatDecimal(distM / 1000)} km';
    final gainText = '+${_formatGrouped(gainM)} m';
    final maxElevText = '${_formatGrouped(maxElevM)} mdpl';

    return GlassSurface(
      tier: GlassTier.overMap,
      borderRadius: 28,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Baris Statistik (3 kolom sama lebar, crossfade 260 ms)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Row(
              key: ValueKey<String>('${trail?.id}_$distText'),
              children: [
                Expanded(
                  child: _StatColumn(
                    label: 'Jarak',
                    value: distText,
                    colors: colors,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatColumn(
                    label: 'Tanjakan',
                    value: gainText,
                    colors: colors,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatColumn(
                    label: 'Elevasi maks',
                    value: maxElevText,
                    colors: colors,
                  ),
                ),
              ],
            ),
          ),

          // 2. Bagian Pilihan Jalur (hanya bila >1 jalur, di ATAS baris tombol)
          if (hasMultipleTrails)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final h = _heightAnimation.value;
                if (h <= 0.0) return const SizedBox.shrink();

                return SizedBox(
                  height: h,
                  child: Opacity(
                    opacity: _opacityAnimation.value,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.trails.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final t = widget.trails[index];
                          final isSelected = t.id == trail?.id;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              widget.onSelectTrail(t);
                            },
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 44,
                                minHeight: 44,
                              ),
                              child: Center(
                                child: Container(
                                  height: 32,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? colors.primary
                                        : colors.hairline,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    t.name,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? colors.onPrimary
                                          : colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),

          // Jarak ke baris tombol (8 dp untuk mengimbangi area sentuh 44 dp)
          const SizedBox(height: 8),

          // 3. Baris pilihan jalur (jika >1 jalur) agar tombol "Mulai tracking"
          //    dan "Mulai turun" selalu lega berdampingan.
          if (hasMultipleTrails) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => setState(() => _isJalurPressed = true),
                onTapUp: (_) => setState(() => _isJalurPressed = false),
                onTapCancel: () => setState(() => _isJalurPressed = false),
                onTap: () {
                  HapticFeedback.selectionClick();
                  toggleSelection();
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  child: Center(
                    widthFactor: 1.0,
                    child: AnimatedScale(
                      scale: _isJalurPressed ? 0.97 : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: colors.hairline,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                trail?.name ?? 'Pilih Jalur',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            AnimatedBuilder(
                              animation: _chevronAnimation,
                              builder: (context, _) => Transform.rotate(
                                angle: _chevronAnimation.value,
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],

          if (widget.showStartTracking &&
              widget.isTrackingLocked &&
              widget.trackingLockNote != null &&
              widget.trackingLockNote!.trim().isNotEmpty) ...[
            Container(
              key: const ValueKey('map-tracking-lock-note'),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colors.warning.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_clock_outlined,
                    size: 16,
                    color: colors.warningText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.trackingLockNote!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.warningText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 4. Baris Tombol Aksi: saat dibuka dari Siapkan Pendakian menampilkan
          //    tombol mulai pendakian + turun; dari tab Peta hanya "Mulai turun".
          Row(
            children: [
              if (widget.showStartTracking) ...[
                // Tombol Utama ("Mulai tracking" / "Mulai pendakian")
                Expanded(
                  child: GestureDetector(
                    key: const ValueKey('map-start-tracking-button'),
                    onTapDown: widget.isTrackingLocked
                        ? null
                        : (_) => setState(() => _isStartPressed = true),
                    onTapUp: widget.isTrackingLocked
                        ? null
                        : (_) => setState(() => _isStartPressed = false),
                    onTapCancel: widget.isTrackingLocked
                        ? null
                        : () => setState(() => _isStartPressed = false),
                    onTap:
                        widget.isTrackingLocked ? null : widget.onStartTracking,
                    child: AnimatedScale(
                      scale: !widget.isTrackingLocked && _isStartPressed
                          ? 0.97
                          : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: widget.isTrackingLocked
                              ? colors.secondary
                              : colors.primary,
                          border: widget.isTrackingLocked
                              ? Border.all(color: colors.hairline)
                              : null,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.isTrackingLocked
                                  ? Icons.lock_outline_rounded
                                  : Icons.directions_walk_rounded,
                              size: 19,
                              color: widget.isTrackingLocked
                                  ? colors.textPrimary.withValues(alpha: 0.88)
                                  : colors.onPrimary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.startButtonLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: widget.isTrackingLocked
                                      ? colors.textPrimary.withValues(alpha: 0.88)
                                      : colors.onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.onStartDescent != null) const SizedBox(width: 8),
              ],
              if (widget.onStartDescent != null) ...[
                // Tombol "Mulai turun" (membalik jalur GPX, tanpa merekam)
                Expanded(
                  child: GestureDetector(
                    key: const ValueKey('map-start-descent-button'),
                    onTapDown: (_) => setState(() => _isDescentPressed = true),
                    onTapUp: (_) => setState(() => _isDescentPressed = false),
                    onTapCancel: () =>
                        setState(() => _isDescentPressed = false),
                    onTap: widget.onStartDescent,
                    child: AnimatedScale(
                      scale: _isDescentPressed ? 0.97 : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: widget.showStartTracking
                              ? colors.hairline
                              : colors.primary,
                          borderRadius: BorderRadius.circular(26),
                          border: widget.showStartTracking
                              ? Border.all(
                                  color: colors.primary.withValues(alpha: 0.25),
                                )
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.trending_down_rounded,
                              size: 19,
                              color: widget.showStartTracking
                                  ? colors.textPrimary
                                  : colors.onPrimary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Mulai turun',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: widget.showStartTracking
                                      ? colors.textPrimary
                                      : colors.onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final HiqeoColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
