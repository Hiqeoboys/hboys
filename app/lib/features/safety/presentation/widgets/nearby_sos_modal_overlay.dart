import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/utils/safe_url_launcher.dart';
import '../../../../design/glass/glass_surface.dart';
import '../../../../design/tokens.dart';
import '../../../../design/typography.dart';
import '../../../../infrastructure/notifications/push_notification_service.dart';

/// Memformat jarak dalam meter menjadi teks ringkas berbahasa Indonesia
/// (mis. `450 m` atau `2,3 km`).
String formatNearbySosDistance(double meters) {
  if (!meters.isFinite || meters < 0) return 'Di sekitar Anda';
  if (meters < 1000) return '${meters.round()} m';
  final km = (meters / 1000).toStringAsFixed(1).replaceAll('.', ',');
  return '$km km';
}

double? _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  if (!lat1.isFinite || !lon1.isFinite || !lat2.isFinite || !lon2.isFinite) {
    return null;
  }
  const earthRadiusM = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lon2 - lon1) * math.pi / 180.0;
  final rLat1 = lat1 * math.pi / 180.0;
  final rLat2 = lat2 * math.pi / 180.0;
  final sinHalfLat = math.sin(dLat / 2);
  final sinHalfLon = math.sin(dLon / 2);
  final h = sinHalfLat * sinHalfLat +
      math.cos(rLat1) * math.cos(rLat2) * sinHalfLon * sinHalfLon;
  final c = 2 * math.asin(math.min(1.0, math.sqrt(h)));
  return earthRadiusM * c;
}

/// Menampilkan Card Modal Overlay bergaya Liquid Glass langsung di layar aktif
/// ketika penerima mengetuk notifikasi SOS terdekat radius 5 km (tanpa
/// menavigasi atau meninggalkan layar aktif).
Future<void> showNearbySosModalOverlay(
  BuildContext context,
  InAppPushNotification notif, {
  Future<bool> Function(Uri uri)? urlLauncher,
}) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Tutup detail SOS',
    barrierColor: Colors.black.withValues(alpha: 0.48),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) => _NearbySosModalCard(
      notif: notif,
      urlLauncher: urlLauncher ?? launchSafeExternalUrl,
    ),
    transitionBuilder: (dialogContext, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _NearbySosModalCard extends StatefulWidget {
  const _NearbySosModalCard({
    required this.notif,
    required this.urlLauncher,
  });

  final InAppPushNotification notif;
  final Future<bool> Function(Uri uri) urlLauncher;

  @override
  State<_NearbySosModalCard> createState() => _NearbySosModalCardState();
}

class _NearbySosModalCardState extends State<_NearbySosModalCard> {
  String? _liveDistanceLabel;
  bool _copied = false;
  Timer? _copiedResetTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveLiveDistance());
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _resolveLiveDistance() async {
    final targetLat = double.tryParse(widget.notif.rawData['lat']?.trim() ?? '');
    final targetLon = double.tryParse(widget.notif.rawData['lon']?.trim() ?? '');
    if (targetLat == null || targetLon == null) return;
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null || !mounted) return;
      final dist = _haversineMeters(
        pos.latitude,
        pos.longitude,
        targetLat,
        targetLon,
      );
      if (dist != null && mounted) {
        setState(() => _liveDistanceLabel = formatNearbySosDistance(dist));
      }
    } catch (_) {
      // Tetap gunakan jarak dari payload server bila lokasi belum tersedia.
    }
  }

  String _resolveDistanceText() {
    if (_liveDistanceLabel != null && _liveDistanceLabel!.isNotEmpty) {
      return _liveDistanceLabel!;
    }
    final fromLabel = widget.notif.rawData['distance_label']?.trim() ?? '';
    if (fromLabel.isNotEmpty) return fromLabel;
    final rawMeters = double.tryParse(widget.notif.rawData['distance_m']?.trim() ?? '');
    if (rawMeters != null && rawMeters.isFinite) {
      return formatNearbySosDistance(rawMeters);
    }
    return 'Dalam radius 5 km';
  }

  String _resolveTimeText() {
    final explicit = widget.notif.rawData['sos_time_hhmm']?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final sentLocal = widget.notif.sentAtUtc?.toLocal();
    if (sentLocal != null) {
      final hh = sentLocal.hour.toString().padLeft(2, '0');
      final mm = sentLocal.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    return 'Baru saja';
  }

  Future<void> _copyCoords(String coords) async {
    try {
      await Clipboard.setData(ClipboardData(text: coords));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedResetTimer?.cancel();
    _copiedResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final raw = widget.notif.rawData;
    final lat = raw['lat']?.trim() ?? '';
    final lon = raw['lon']?.trim() ?? '';
    final hasCoords = lat.isNotEmpty && lon.isNotEmpty;
    final coordText = hasCoords ? '$lat, $lon' : 'Belum tersedia';
    final area = (raw['area_label']?.trim().isNotEmpty == true)
        ? raw['area_label']!.trim()
        : (raw['mountain_name']?.trim() ?? '');
    final batteryRaw = raw['battery_pct']?.trim() ?? '';
    final batteryText = batteryRaw.isNotEmpty ? '$batteryRaw%' : 'Tidak diketahui';
    final isNearby = widget.notif.type == 'sos_nearby' ||
        raw['sos_mode'] == 'nearby' ||
        (raw['group_id']?.trim().isEmpty ?? true);

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              type: MaterialType.transparency,
              child: GlassSurface(
                key: const ValueKey<String>('nearby-sos-modal-card'),
                tier: GlassTier.panel,
                borderRadius: 26,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: colors.warning.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.warning.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Icon(
                              Icons.crisis_alert_rounded,
                              color: colors.warning,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  isNearby
                                      ? 'Sinyal SOS Terdekat'
                                      : 'Sinyal SOS Darurat',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: HiqeoTypography.bold,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                Text(
                                  isNearby
                                      ? 'Peringatan radius 5 km'
                                      : (raw['sender_name']?.trim().isNotEmpty == true
                                          ? raw['sender_name']!.trim()
                                          : 'Pendaki'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Tutup',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.close_rounded,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.notif.body,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          height: 1.38,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.background.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors.hairline),
                        ),
                        child: Column(
                          children: <Widget>[
                            _InfoRow(
                              icon: Icons.radar_rounded,
                              label: 'Jarak dari posisimu',
                              value: _resolveDistanceText(),
                            ),
                            const SizedBox(height: 6),
                            _InfoRow(
                              icon: Icons.schedule_rounded,
                              label: 'Waktu SOS',
                              value: _resolveTimeText(),
                            ),
                            const SizedBox(height: 6),
                            _InfoRow(
                              icon: Icons.battery_alert_rounded,
                              label: 'Sisa baterai',
                              value: batteryText,
                            ),
                            if (area.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 6),
                              _InfoRow(
                                icon: Icons.terrain_rounded,
                                label: 'Area',
                                value: area,
                              ),
                            ],
                            const SizedBox(height: 6),
                            _InfoRow(
                              icon: Icons.location_on_outlined,
                              label: 'Koordinat',
                              value: coordText,
                              trailing: hasCoords
                                  ? TextButton.icon(
                                      key: const ValueKey<String>(
                                        'nearby-sos-copy-coords',
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        minimumSize: const Size(0, 36),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () => unawaited(
                                        _copyCoords(coordText),
                                      ),
                                      icon: Icon(
                                        _copied
                                            ? Icons.check_rounded
                                            : Icons.copy_rounded,
                                        size: 15,
                                      ),
                                      label: Text(_copied ? 'Tersalin' : 'Salin'),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton(
                              key: const ValueKey<String>(
                                'nearby-sos-close-btn',
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Tutup'),
                            ),
                          ),
                          if (hasCoords) ...<Widget>[
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                key: const ValueKey<String>(
                                  'nearby-sos-open-maps-btn',
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () {
                                  final uri = buildSafeMapsUri(
                                    rawLat: lat,
                                    rawLon: lon,
                                  );
                                  if (uri != null) {
                                    unawaited(widget.urlLauncher(uri));
                                  }
                                },
                                icon: const Icon(Icons.map_outlined, size: 18),
                                label: const Text('Buka di Maps'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: 16, color: colors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: HiqeoTypography.bold,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
