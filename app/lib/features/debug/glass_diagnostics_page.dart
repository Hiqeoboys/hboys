import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../core/config/supabase_config.dart';
import '../../design/glass/glass_surface.dart';
import '../../design/tokens.dart';
import '../../design/widgets/line_icons.dart';

/// Apakah layar diagnostik "Uji kaca" boleh dibuka.
///
/// Secara baku HANYA aktif pada [kDebugMode]. Untuk menguji di HP pada mode
/// profile/release (`flutter run --profile`/`--release`), aktifkan secara
/// eksplisit dengan `--dart-define=ENABLE_GLASS_DIAGNOSTICS=true`.
const bool kEnableGlassDiagnostics =
    kDebugMode || bool.fromEnvironment('ENABLE_GLASS_DIAGNOSTICS');

/// Rute debug untuk layar diagnostik efek kaca.
const String kGlassDiagnosticsRoute = '/debug/uji-kaca';

/// Layar diagnostik efek kaca (glassmorphism) untuk membandingkan varian
/// [BackdropFilter] V1 sampai V6 pada perangkat asli.
class GlassDiagnosticsPage extends StatefulWidget {
  const GlassDiagnosticsPage({super.key});

  @override
  State<GlassDiagnosticsPage> createState() => _GlassDiagnosticsPageState();
}

class _GlassDiagnosticsPageState extends State<GlassDiagnosticsPage> {
  bool _v6UseTextureView = false;
  TileMode _v3TileMode = TileMode.mirror;
  int _mapKeySeed = 0;

  @override
  void initState() {
    super.initState();
    GlassConfig.detectFromDevice().then((_) {
      if (mounted) setState(() {});
    });
  }

  bool get _canRenderLiveMapbox {
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    return SupabaseConfig.mapboxAccessToken.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final isDark = colors.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Kembali',
          icon: HiqeoIcon(HiqeoIcons.chevronLeft, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Uji kaca',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
      ),
      body: BackdropGroup(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: <Widget>[
            _buildDeviceInfoCard(colors, theme),
            const SizedBox(height: 16),
            Text(
              'Perbandingan varian V1–V5',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Amati apakah garis warna dan teks "UJI BACA" di belakang '
              'tampak buram (blur bekerja) atau terbaca tajam (blur gagal).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            // V1 dan V2 berdampingan
            Row(
              children: <Widget>[
                Expanded(
                  child: _VariantTile(
                    label: 'V1',
                    subtitle: 'BackdropFilter polos (sigma 24)',
                    glassBuilder: (child) => ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          color: colors.glassFillSafe.withValues(alpha: 0.45),
                          padding: const EdgeInsets.all(12),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _VariantTile(
                    label: 'V2',
                    subtitle: 'RepaintBoundary + ClipRRect',
                    glassBuilder: (child) => RepaintBoundary(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  colors.glassFillSafe.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: colors.glassBorder),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // V3 (tileMode mirror / decal) dan V4 (BackdropFilter.grouped)
            Row(
              children: <Widget>[
                Expanded(
                  child: _VariantTile(
                    label: 'V3',
                    subtitle: _v3TileMode == TileMode.mirror
                        ? 'tileMode: mirror'
                        : 'tileMode: decal',
                    headerAction: GestureDetector(
                      onTap: () {
                        setState(() {
                          _v3TileMode = _v3TileMode == TileMode.mirror
                              ? TileMode.decal
                              : TileMode.mirror;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Ganti',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),
                    glassBuilder: (child) => RepaintBoundary(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(
                            sigmaX: 24,
                            sigmaY: 24,
                            tileMode: _v3TileMode,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  colors.glassFillSafe.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: colors.glassBorder),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _VariantTile(
                    label: 'V4',
                    subtitle: 'BackdropFilter.grouped',
                    glassBuilder: (child) => RepaintBoundary(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter.grouped(
                          filter: ui.ImageFilter.compose(
                            outer: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                            inner: const ColorFilter.matrix(kGlassSaturate150),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  colors.glassFillSafe.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: colors.glassBorder),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // V5 (fill aman tanpa BackdropFilter) dan GlassSurface tier panel
            Row(
              children: <Widget>[
                Expanded(
                  child: _VariantTile(
                    label: 'V5',
                    subtitle: 'Tanpa blur (fill aman)',
                    glassBuilder: (child) => GlassSurface(
                      tier: GlassTier.panel,
                      borderRadius: 20,
                      blurEnabledOverride: false,
                      padding: const EdgeInsets.all(12),
                      child: child,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _VariantTile(
                    label: 'Panel',
                    subtitle: 'GlassSurface aktif',
                    glassBuilder: (child) => GlassSurface(
                      tier: GlassTier.panel,
                      borderRadius: 20,
                      padding: const EdgeInsets.all(12),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'V6: BackdropFilter di atas peta Mapbox',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _v6UseTextureView
                            ? 'Mode peta: TextureView (textureView: true)'
                            : 'Mode peta: SurfaceView baku (textureView: false)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _v6UseTextureView = !_v6UseTextureView;
                      _mapKeySeed++;
                    });
                  },
                  child: Text(
                    _v6UseTextureView ? 'Pakai SurfaceView' : 'Uji TextureView',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 240,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (_canRenderLiveMapbox)
                      mapbox.MapWidget(
                        key: ValueKey<String>(
                          'v6-map-$_mapKeySeed-$_v6UseTextureView',
                        ),
                        textureView: _v6UseTextureView,
                        styleUri: isDark
                            ? mapbox.MapboxStyles.DARK
                            : mapbox.MapboxStyles.OUTDOORS,
                        onMapCreated: (map) {
                          unawaited(
                            map
                                .setCamera(
                                  mapbox.CameraOptions(
                                    center: mapbox.Point(
                                      coordinates: mapbox.Position(
                                        110.445,
                                        -7.540,
                                      ),
                                    ),
                                    zoom: 12.5,
                                  ),
                                )
                                .catchError((Object _) {}),
                          );
                        },
                      )
                    else
                      const _StripedTestBackdrop(
                        label: 'MAPBOX SIMULASI\n(buka di HP Android/iOS)',
                      ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: 24,
                                  sigmaY: 24,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: colors.glassFillSafe
                                        .withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(18),
                                    border:
                                        Border.all(color: colors.glassBorder),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        'V6 (V1 atas peta)',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          color: colors.textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        _v6UseTextureView
                                            ? 'textureView: true'
                                            : 'textureView: false',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GlassSurface(
                              tier: GlassTier.overMap,
                              borderRadius: 18,
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'Tier overMap',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: colors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Fill rapat 92% (baku)',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoCard(HiqeoColors colors, ThemeData theme) {
    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Informasi perangkat & mesin render',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _InfoRow(
            label: 'Model',
            value: GlassConfig.detectedDeviceLabel ?? 'Tidak terdeteksi',
          ),
          _InfoRow(
            label: 'OS',
            value: GlassConfig.detectedOsLabel ?? 'Tidak terdeteksi',
          ),
          _InfoRow(label: 'Build', value: GlassConfig.buildModeLabel),
          _InfoRow(label: 'Renderer', value: GlassConfig.activeRendererLabel),
          _InfoRow(
            label: 'Varian aktif',
            value: GlassConfig.activeVariant.name,
          ),
          _InfoRow(
            label: 'Blur di atas peta',
            value: GlassConfig.overMapBlurEnabled ? 'Aktif' : 'Nonaktif (aman)',
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantTile extends StatelessWidget {
  const _VariantTile({
    required this.label,
    required this.subtitle,
    required this.glassBuilder,
    this.headerAction,
  });

  final String label;
  final String subtitle;
  final Widget Function(Widget child) glassBuilder;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 152,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const _StripedTestBackdrop(label: 'UJI BACA\nTEKS TAJAM 1234'),
            Padding(
              padding: const EdgeInsets.all(10),
              child: glassBuilder(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (headerAction != null) headerAction!,
                      ],
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StripedTestBackdrop extends StatelessWidget {
  const _StripedTestBackdrop({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CustomPaint(
          painter: _StripePainter(
            stripeA: colors.primary,
            stripeB: colors.warning,
            stripeC: colors.background,
            stripeD: colors.secondary,
          ),
        ),
        Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              backgroundColor: colors.surface.withValues(alpha: 0.72),
            ),
          ),
        ),
      ],
    );
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter({
    required this.stripeA,
    required this.stripeB,
    required this.stripeC,
    required this.stripeD,
  });

  final Color stripeA;
  final Color stripeB;
  final Color stripeC;
  final Color stripeD;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = <Color>[stripeA, stripeB, stripeC, stripeD];
    const stripeWidth = 18.0;
    int idx = 0;
    for (double x = -size.height;
        x < size.width + size.height;
        x += stripeWidth) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + stripeWidth, 0)
        ..lineTo(x + stripeWidth - size.height * 0.5, size.height)
        ..lineTo(x - size.height * 0.5, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = palette[idx % palette.length]);
      idx++;
    }
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) =>
      oldDelegate.stripeA != stripeA ||
      oldDelegate.stripeB != stripeB ||
      oldDelegate.stripeC != stripeC ||
      oldDelegate.stripeD != stripeD;
}
