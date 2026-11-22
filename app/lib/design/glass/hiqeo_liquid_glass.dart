import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../motion/visual_effect_policy.dart';
import '../tokens.dart';
import 'glass_config.dart';

/// Token tunggal material Liquid Glass Hiqeo.
///
/// Nilai terkunci agar efek kabur `BackdropFilter` tetap terasa lembut, jernih,
/// dan proporsional tanpa menjadi blok warna solid:
/// - blur `sigmaX = sigmaY = 14` ([HiqeoGlass.blurSigma]),
/// - fill transparan lembut alfa 0,22 (terang) / 0,16 (gelap),
/// - sorotan tepi dalam putih halus + border 1 px,
/// - tanpa bayangan luar ([shadow] kosong).
///
/// Anggaran lapisan blur simultan (R-10 & 120fps):
/// - Maksimal 2–3 permukaan `BackdropFilter` mengambang aktif secara bersamaan
///   per viewport (mis. header bar, bilah input/navbar, serta menu dropdown
///   hamburger atau modal bottom sheet seperti `chat_mute_sheet.dart`).
/// - Overlay sekunder yang menempel pada bilah input (`CommunityReplyPreviewBar`
///   & `CommunityMentionSuggestionsOverlay`) memakai `enableBlur: false` dengan
///   fill semi-opaque yang serasi, sedangkan kartu daftar memakai [HiqeoGlassCard].
abstract final class HiqeoGlassTokens {
  static const double blurSigma = HiqeoGlass.blurSigma;
  static const double saturation = 1.0;
  static const double borderWidth = HiqeoGlass.borderWidth;
  static const List<BoxShadow> shadow = <BoxShadow>[];

  static Color fill(Brightness brightness) => Colors.white.withValues(
        alpha: brightness == Brightness.dark ? 0.16 : 0.22,
      );

  static Color border(Brightness brightness) => Colors.white.withValues(
        alpha: brightness == Brightness.dark ? 0.24 : 0.62,
      );

  static Color innerHighlight(Brightness brightness) => Colors.white.withValues(
        alpha: brightness == Brightness.dark ? 0.18 : 0.48,
      );

  static Color sheenTop(Brightness brightness) => Colors.white.withValues(
        alpha: brightness == Brightness.dark ? 0.12 : 0.28,
      );
}

/// Permukaan Liquid Glass tunggal: `ClipRRect` -> `BackdropFilter(14, 14)` ->
/// fill transparan, kemilau atas halus, dan highlight tepi dalam 0,75 px.
/// Tidak ada wadah solid di belakang blur.
///
/// Bentuk (radius / lingkaran) bebas per komponen; warna, blur, border, dan
/// elevasi selalu dari [HiqeoGlassTokens].
class HiqeoLiquidGlassSurface extends StatelessWidget {
  const HiqeoLiquidGlassSurface({
    super.key,
    this.borderRadius = 24,
    this.shape = BoxShape.rectangle,
    this.padding,
    this.child,
    this.fillColor,
    this.borderColor,
    this.brightness,
    this.emphasized = false,
    this.overMap = false,
    this.enableBlur = true,
    this.blurEnabledOverride,
  });

  final double borderRadius;
  final BoxShape shape;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  /// Penimpaan fill (mis. fill rapat di atas peta).
  final Color? fillColor;

  /// Penimpaan warna border opsional.
  final Color? borderColor;

  /// Memaksa palet terang/gelap (layar berpalet terkunci seperti SOS & Kartu).
  final Brightness? brightness;

  /// Sorotan halus bertint `primary` (mis. tombol kirim saat ada teks).
  final bool emphasized;

  /// Di atas peta Mapbox: tanpa blur kecuali [GlassConfig.overMapBlurEnabled]
  /// aktif, dengan fill rapat [HiqeoColors.glassFillMap].
  final bool overMap;

  /// Mengaktifkan efek `BackdropFilter` untuk elemen mengambang. Matikan
  /// (`false`) untuk varian kaca ringan tanpa blur pass.
  final bool enableBlur;

  /// Penimpaan status blur khusus uji; null mengikuti kebijakan efek.
  final bool? blurEnabledOverride;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final mode = brightness ?? colors.brightness;
    final isCircle = shape == BoxShape.circle;
    final radius = isCircle ? null : BorderRadius.circular(borderRadius);
    final innerRadius = isCircle
        ? null
        : BorderRadius.circular((borderRadius - 1).clamp(0.0, 999.0));
    final clipRadius =
        BorderRadius.circular(isCircle ? 999 : borderRadius);

    final bool blur = enableBlur &&
        (blurEnabledOverride ??
            (VisualEffectPolicyScope.of(context).glassBlur &&
                GlassConfig.shouldUseBlur(
                  overMap ? GlassTier.overMap : GlassTier.panel,
                )));

    var fill = fillColor ??
        (overMap && !blur
            ? colors.glassFillMap
            : (!blur ? colors.glassFillFallback : HiqeoGlassTokens.fill(mode)));
    var border = borderColor ?? HiqeoGlassTokens.border(mode);
    if (emphasized) {
      fill = Color.alphaBlend(colors.primary.withValues(alpha: 0.22), fill);
      border = colors.primary.withValues(alpha: 0.42);
    }

    final Widget innerContent = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: child == null
          ? const SizedBox.shrink()
          : Material(
              type: MaterialType.transparency,
              child: child,
            ),
    );

    final Color topFill = blur
        ? Color.alphaBlend(HiqeoGlassTokens.sheenTop(mode), fill)
        : fill;

    final Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        shape: shape,
        borderRadius: radius,
        gradient: blur
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const <double>[0.0, 0.55, 1.0],
                colors: <Color>[
                  topFill,
                  fill,
                  fill,
                ],
              )
            : null,
        border: Border.all(
          color: border,
          width: HiqeoGlassTokens.borderWidth,
        ),
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: innerRadius,
          border: Border.all(
            color: HiqeoGlassTokens.innerHighlight(mode),
            width: 0.75,
          ),
        ),
        child: innerContent,
      ),
    );

    final Widget filtered = blur
        ? BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: HiqeoGlassTokens.blurSigma,
              sigmaY: HiqeoGlassTokens.blurSigma,
              tileMode: GlassConfig.activeTileMode,
            ),
            child: body,
          )
        : body;

    final Widget clipped = RepaintBoundary(
      child: ClipRRect(
        borderRadius: clipRadius,
        clipBehavior: Clip.antiAlias,
        child: filtered,
      ),
    );

    if (HiqeoGlassTokens.shadow.isEmpty) return clipped;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: radius,
        boxShadow: HiqeoGlassTokens.shadow,
      ),
      child: clipped,
    );
  }
}

/// Tombol bulat Liquid Glass (kembali, menu, kirim, tutup). Ukuran baku 44 px.
class HiqeoGlassCircleButton extends StatelessWidget {
  const HiqeoGlassCircleButton({
    super.key,
    required this.child,
    required this.semanticsLabel,
    this.onTap,
    this.size = 44,
    this.brightness,
    this.emphasized = false,
    this.overMap = false,
  });

  /// Ikon (sudah berwarna) di tengah tombol.
  final Widget child;
  final String semanticsLabel;

  /// `null` menonaktifkan tombol (tanpa efek tekan).
  final VoidCallback? onTap;
  final double size;
  final Brightness? brightness;
  final bool emphasized;
  final bool overMap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticsLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: HiqeoLiquidGlassSurface(
          shape: BoxShape.circle,
          brightness: brightness,
          emphasized: emphasized,
          overMap: overMap,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Kartu kaca ringan untuk konten gulir (tanpa `BackdropFilter`, `BoxShadow`,
/// maupun `saveLayer`) dengan gradien halus dan border kaca 1 px seragam.
class HiqeoGlassCard extends StatelessWidget {
  const HiqeoGlassCard({
    super.key,
    this.borderRadius = 24,
    this.padding,
    this.borderColor,
    this.child,
  });

  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final isDark = colors.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? <Color>[
                  colors.surface.withValues(alpha: 0.90),
                  colors.surface.withValues(alpha: 0.78),
                ]
              : <Color>[
                  colors.surface.withValues(alpha: 0.97),
                  colors.surface.withValues(alpha: 0.91),
                ],
        ),
        border: Border.all(
          color: borderColor ?? colors.glassBorder,
          width: HiqeoGlass.borderWidth,
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}
