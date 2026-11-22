import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../motion/visual_effect_policy.dart';
import '../tokens.dart';
import 'glass_config.dart';

export 'glass_config.dart';

/// Matriks warna saturasi 1,5 (150%) untuk efek kaca Hiqeo.
const List<double> kGlassSaturate150 = <double>[
  1.3937, -0.3576, -0.0361, 0, 0,
  -0.1063, 1.1424, -0.0361, 0, 0,
  -0.1063, -0.3576, 1.4639, 0, 0,
  0, 0, 0, 1, 0,
];

/// Komponen kaca tunggal Hiqeo dengan empat tingkatan ([GlassTier]):
/// - [GlassTier.navbar]: bilah navigasi bawah (blur + fill aman).
/// - [GlassTier.panel]: panel dan sheet (blur + fill aman).
/// - [GlassTier.card]: kartu daftar panjang (fill solid + border, TANPA blur).
/// - [GlassTier.overMap]: panel/kontrol di atas peta Mapbox (fill rapat 92%,
///   TANPA blur kecuali [GlassConfig.overMapBlurEnabled] aktif).
///
/// Susunan lapisan (satu Stack di dalam ClipRRect + RepaintBoundary):
/// (a) BackdropFilter (sigma 24, saturasi 1,5) bila aktif,
/// (b) fill aman,
/// (c) overlay pantulan vertikal simetris (alfa 0,10 ke 0 pada 60%),
/// (d) border 1 px [HiqeoColors.glassBorder],
/// (e) highlight tepi atas 1 px [HiqeoColors.glassHighlight],
/// (f) bayangan [HiqeoColors.glassShadow].
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    this.tier,
    this.borderRadius,
    this.padding,
    this.child,
    this.tint,
    this.shape = BoxShape.rectangle,
    this.fillColor,
    this.borderColor,
    this.highlightColor,
    this.boxShadow,
    this.blurEnabledOverride,
    this.useSafeFill = false,
    this.useMapFill = false,
  });

  /// Tingkatan permukaan kaca. Jika null, diturunkan dari [useMapFill]
  /// (`overMap`) atau baku [GlassTier.panel].
  final GlassTier? tier;

  final double? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  /// Tint opsional dari token warna yang dicampur di atas fill kaca.
  final Color? tint;

  final BoxShape shape;

  /// Penimpaan warna fill dari token (mis. panel petunjuk gaya gelap lokal).
  final Color? fillColor;

  /// Penimpaan warna border 1 px.
  final Color? borderColor;

  /// Penimpaan warna highlight tepi atas 1 px.
  final Color? highlightColor;

  /// Penimpaan bayangan luar.
  final List<BoxShadow>? boxShadow;

  /// Penimpaan status blur khusus uji/golden; null mengikuti [GlassConfig] dan
  /// [VisualEffectPolicy].
  final bool? blurEnabledOverride;

  /// Dipertahankan untuk kompatibilitas pemanggil lama; fill aman kini selalu
  /// dipakai pada tier navbar/panel.
  final bool useSafeFill;

  /// Dipertahankan untuk kompatibilitas pemanggil lama; otomatis memetakan ke
  /// [GlassTier.overMap] bila [tier] tidak diisi.
  final bool useMapFill;

  GlassTier get effectiveTier =>
      tier ?? (useMapFill ? GlassTier.overMap : GlassTier.panel);

  double _resolvedRadius(GlassTier resolvedTier) {
    if (borderRadius != null) return borderRadius!;
    return switch (resolvedTier) {
      GlassTier.navbar => HiqeoRadius.navbar,
      GlassTier.panel => HiqeoRadius.hero,
      GlassTier.overMap => HiqeoRadius.hero,
      GlassTier.card => 24.0,
    };
  }

  Color _resolvedFill(
    HiqeoColors colors,
    GlassTier resolvedTier, {
    required bool useBlur,
  }) {
    final Color base = fillColor ??
        switch (resolvedTier) {
          GlassTier.navbar => useBlur ? colors.glassFill : colors.glassFillSafe,
          GlassTier.panel => useBlur ? colors.glassFill : colors.glassFillSafe,
          GlassTier.overMap => colors.glassFillMap,
          GlassTier.card => colors.surface,
        };
    return tint == null ? base : Color.alphaBlend(tint!, base);
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final policyBlur = VisualEffectPolicyScope.of(context).glassBlur;
    final resolvedTier = effectiveTier;
    final isCircle = shape == BoxShape.circle;
    final radiusValue = _resolvedRadius(resolvedTier);
    final radius = isCircle ? null : BorderRadius.circular(radiusValue);
    final clipRadius =
        isCircle ? BorderRadius.circular(999) : BorderRadius.circular(radiusValue);

    final bool useBlur = blurEnabledOverride ??
        (policyBlur && GlassConfig.shouldUseBlur(resolvedTier));

    final effectiveFill = _resolvedFill(
      colors,
      resolvedTier,
      useBlur: useBlur,
    );
    final effectiveBorder = borderColor ?? colors.glassBorder;
    final effectiveHighlight = highlightColor ?? colors.glassHighlight;
    final effectiveShadows = boxShadow ??
        (resolvedTier == GlassTier.card
            ? const <BoxShadow>[]
            : <BoxShadow>[HiqeoGlass.shadow(colors)]);

    final bool showReflection = resolvedTier != GlassTier.card;
    // Gradien pantulan VERTIKAL simetris: putih (terang) / krem (gelap) alfa
    // 0,10 di atas memudar ke transparan pada 60%. Tanpa gradien miring atau
    // bercak radial lokal.
    final Color reflectionBase = colors.brightness == Brightness.dark
        ? HiqeoColors.dark.textPrimary
        : HiqeoColors.light.glassHighlight;

    final ui.ImageFilter blurFilter = ui.ImageFilter.blur(
      sigmaX: HiqeoGlass.blurSigma,
      sigmaY: HiqeoGlass.blurSigma,
      tileMode: GlassConfig.activeTileMode,
    );

    final bool canGroup =
        GlassConfig.activeVariant == GlassBlurVariant.grouped &&
            BackdropGroup.of(context) != null;

    // Susunan presisi: ClipRRect -> BackdropFilter(blur 24) -> Container/Stack.
    // Tidak dibungkus RepaintBoundary luar agar konten bergerak di belakang kaca
    // selalu ter-blur secara realtime di Impeller maupun Skia.
    final Widget surfaceBody = Container(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: radius,
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          // (a) Fill semi-transparan (Mode Terang glassFill / fallback glassFillSafe)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey<String>('glass-surface-fill'),
                decoration: BoxDecoration(
                  color: effectiveFill,
                  shape: shape,
                  borderRadius: radius,
                ),
              ),
            ),
          ),

          // (b) Overlay pantulan vertikal simetris (alfa 0,10 -> 0 pada 60%)
          if (showReflection)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey<String>('glass-surface-reflection'),
                  decoration: BoxDecoration(
                    shape: shape,
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const <double>[0.0, 0.6],
                      colors: <Color>[
                        reflectionBase.withValues(alpha: 0.10),
                        reflectionBase.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // (c) Border halus 1 px glassBorder
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey<String>('glass-surface-border'),
                decoration: BoxDecoration(
                  shape: shape,
                  borderRadius: radius,
                  border: Border.all(
                    color: effectiveBorder,
                    width: HiqeoGlass.borderWidth,
                  ),
                ),
              ),
            ),
          ),

          // (d) Highlight spekular tepi atas 1 px merata kiri ke kanan
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: HiqeoGlass.highlightWidth,
            child: IgnorePointer(
              key: const ValueKey<String>('glass-surface-highlight'),
              child: ColoredBox(color: effectiveHighlight),
            ),
          ),

          // Konten utama
          Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child ?? const SizedBox.shrink(),
          ),
        ],
      ),
    );

    final Widget filteredContent = !useBlur
        ? surfaceBody
        : canGroup
            ? BackdropFilter.grouped(
                filter: blurFilter,
                child: surfaceBody,
              )
            : BackdropFilter(
                filter: blurFilter,
                child: surfaceBody,
              );

    final Widget clipped = isCircle
        ? ClipOval(clipBehavior: Clip.antiAlias, child: filteredContent)
        : ClipRRect(
            borderRadius: clipRadius,
            clipBehavior: Clip.antiAlias,
            child: filteredContent,
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: radius,
        boxShadow: effectiveShadows,
      ),
      child: clipped,
    );
  }
}

/// Alias kompatibilitas untuk permukaan kaca tanpa BackdropFilter.
///
/// Seluruh tampilan kini memakai komponen tunggal [GlassSurface] dengan tier
/// [GlassTier.overMap] (jika [useMapFill] true) atau [GlassTier.card].
class LightweightGlassSurface extends StatelessWidget {
  const LightweightGlassSurface({
    super.key,
    this.borderRadius = HiqeoRadius.card,
    this.padding,
    this.child,
    this.shape = BoxShape.rectangle,
    this.fillColor,
    this.useMapFill = false,
  });

  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Widget? child;
  final BoxShape shape;
  final Color? fillColor;
  final bool useMapFill;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tier: useMapFill ? GlassTier.overMap : GlassTier.card,
      borderRadius: borderRadius,
      padding: padding,
      shape: shape,
      fillColor: fillColor,
      child: child,
    );
  }
}
