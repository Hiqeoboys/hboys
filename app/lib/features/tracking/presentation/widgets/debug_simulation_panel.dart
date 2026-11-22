import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../design/glass/glass_surface.dart';
import '../../../../design/tokens.dart';
import '../../../../design/typography.dart';
import '../../../trails/data/gpx_loader.dart';
import '../../../../infrastructure/location/location_source.dart';
import '../../application/tracking_controller.dart';

/// Panel kendali simulasi lokasi GPX (khusus `kDebugMode`).
///
/// Menyediakan toggle simulasi, pilihan berkas rute GPX, pilihan kecepatan,
/// serta tombol skenario untuk menguji petunjuk arah dan rekaman jejak tanpa
/// harus berada di gunung:
/// - Mulai di titik awal
/// - Jalan di jalur 400 m
/// - Menyimpang 150 m
/// - Teleport tanpa jejak (100 m)
/// - Jalan kembali
/// - Jeda / Lanjut & Reset
/// - Uji sinyal buruk (akurasi 40 m selama 20 detik)
class DebugSimulationPanel extends StatelessWidget {
  const DebugSimulationPanel({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final controller = TrackingController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final sim = controller.simulatedLocationSource;
        final enabled = controller.simulationEnabled;
        final routeAsset = controller.simulationRouteAsset;
        final multiplier = sim?.speedMultiplier ?? 1;
        final simPaused = sim?.isSimulationPaused ?? false;
        final scenario = sim?.scenarioState ?? SimulationScenarioState.idle;
        final progress = sim?.progress ?? 0.0;
        final percentText =
            '${(progress * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
        final offsetM = sim?.currentOffsetFromTrailM ?? 0.0;
        final poorSignalActive = sim?.isPoorSignalActive ?? false;
        final poorSignalSec = sim?.remainingPoorSignalSeconds.ceil() ?? 0;

        String scenarioLabel;
        switch (scenario) {
          case SimulationScenarioState.idle:
            scenarioLabel = sim?.isCompleted == true
                ? 'Selesai di akhir jalur'
                : 'Mengikuti jalur normal';
          case SimulationScenarioState.walkingRoute400m:
            scenarioLabel = 'Jalan di jalur (+400 m)';
          case SimulationScenarioState.deviatingCurved150m:
            scenarioLabel =
                'Menyimpang melengkung (offset ${offsetM.toStringAsFixed(0)} m)';
          case SimulationScenarioState.deviatedStatic:
            scenarioLabel =
                'Di luar jalur (offset ${offsetM.toStringAsFixed(0)} m)';
          case SimulationScenarioState.walkingBackToTrail:
            scenarioLabel =
                'Jalan kembali ke jalur (sisa ${offsetM.toStringAsFixed(0)} m)';
        }

        return Material(
          color: Colors.transparent,
          child: GlassSurface(
            tier: GlassTier.overMap,
            borderRadius: HiqeoRadius.card,
            padding: const EdgeInsets.all(12),
            child: DefaultTextStyle(
              style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
                fontSize: 11,
                color: colors.textPrimary,
                height: 1.35,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Header
                    Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: enabled
                                ? const Color(0xFF22C55E)
                                : colors.hairline,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Simulasi lokasi (debug)',
                            style: TextStyle(
                              fontWeight: HiqeoTypography.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: onClose,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Toggle simulasi
                    Row(
                      children: <Widget>[
                        const Expanded(
                          child: Text('Lokasi simulasi'),
                        ),
                        SizedBox(
                          height: 28,
                          child: Switch(
                            key: const ValueKey('debug-sim-switch'),
                            value: enabled,
                            onChanged: (val) => unawaited(
                              controller.setSimulationEnabled(val),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Pilihan jalur
                    Row(
                      children: <Widget>[
                        const Text('Jalur: '),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              key: const ValueKey('debug-sim-route-dropdown'),
                              isDense: true,
                              isExpanded: true,
                              value: routeAsset,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                fontWeight: HiqeoTypography.bold,
                                color: colors.textPrimary,
                              ),
                              items: const <DropdownMenuItem<String>>[
                                DropdownMenuItem<String>(
                                  value: GpxLoader.defaultGpxAssetPath,
                                  child: Text(
                                    'tes.gpx (Gn. Ciremai via Apuy)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  unawaited(
                                    controller.setSimulationRouteAsset(val),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Pilihan kecepatan
                    Row(
                      children: <Widget>[
                        const Text('Kecepatan: '),
                        const SizedBox(width: 6),
                        for (final speed in SimulatedLocationSource
                            .supportedSpeedMultipliers) ...<Widget>[
                          GestureDetector(
                            key: ValueKey('debug-sim-speed-${speed}x'),
                            onTap: () => sim?.setSpeedMultiplier(speed),
                            child: Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: multiplier == speed
                                    ? colors.primary
                                    : colors.secondary,
                                borderRadius:
                                    BorderRadius.circular(HiqeoRadius.pill),
                                border: Border.all(color: colors.hairline),
                              ),
                              child: Text(
                                '${speed}x',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: HiqeoTypography.bold,
                                  color: multiplier == speed
                                      ? colors.onPrimary
                                      : colors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Tombol Skenario
                    const Text(
                      'Skenario pengujian:',
                      style: TextStyle(
                        fontWeight: HiqeoTypography.bold,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),

                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        _ScenarioButton(
                          key: const ValueKey('debug-sim-btn-start'),
                          label: 'Mulai di titik awal',
                          icon: Icons.play_arrow_outlined,
                          onTap: () => unawaited(
                            controller.startSimulationAtBeginning(),
                          ),
                        ),
                        _ScenarioButton(
                          key: const ValueKey('debug-sim-btn-walk400'),
                          label: 'Jalan di jalur 400 m',
                          icon: Icons.directions_walk,
                          onTap: () => unawaited(
                            controller.runSimulationWalk400m(),
                          ),
                        ),
                        _ScenarioButton(
                          key: const ValueKey('debug-sim-btn-deviate150'),
                          label: 'Menyimpang 150 m',
                          icon: Icons.turn_right,
                          onTap: () => unawaited(
                            controller.runSimulationCurvedDeviation150m(),
                          ),
                        ),
                        _ScenarioButton(
                          key: const ValueKey('debug-sim-btn-teleport'),
                          label: 'Teleport tanpa jejak',
                          icon: Icons.flash_on_outlined,
                          onTap: () => unawaited(
                            controller.runSimulationTeleport100m(),
                          ),
                        ),
                        _ScenarioButton(
                          key: const ValueKey('debug-sim-btn-walkback'),
                          label: 'Jalan kembali',
                          icon: Icons.replay,
                          onTap: () => unawaited(
                            controller.runSimulationWalkBack(),
                          ),
                        ),
                        _ScenarioButton(
                          key: const ValueKey('debug-sim-btn-poorsignal'),
                          label: poorSignalActive
                              ? 'Sinyal buruk ($poorSignalSec dtk)'
                              : 'Sinyal buruk (20 dtk)',
                          icon: Icons.signal_cellular_connected_no_internet_0_bar,
                          warning: poorSignalActive,
                          onTap: controller.triggerSimulationPoorSignal,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Baris Jeda / Reset
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: GestureDetector(
                            key: const ValueKey('debug-sim-btn-pause'),
                            onTap: controller.toggleSimulationPause,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.secondary,
                                borderRadius:
                                    BorderRadius.circular(HiqeoRadius.pill),
                                border: Border.all(color: colors.hairline),
                              ),
                              child: Text(
                                simPaused ? 'Lanjut' : 'Jeda',
                                style: const TextStyle(
                                  fontWeight: HiqeoTypography.medium,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: GestureDetector(
                            key: const ValueKey('debug-sim-btn-reset'),
                            onTap: controller.resetSimulation,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.secondary,
                                borderRadius:
                                    BorderRadius.circular(HiqeoRadius.pill),
                                border: Border.all(color: colors.hairline),
                              ),
                              child: const Text(
                                'Reset',
                                style: TextStyle(
                                  fontWeight: HiqeoTypography.medium,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Status & Info
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Text('Status: '),
                              Expanded(
                                child: Text(
                                  scenarioLabel,
                                  style: const TextStyle(
                                    fontWeight: HiqeoTypography.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text('Progres jalur: $percentText'),
                              Text(
                                'Noise: ±3 m${poorSignalActive ? " • Akurasi 40 m" : ""}',
                                style: TextStyle(
                                  color: poorSignalActive
                                      ? colors.warningText
                                      : colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScenarioButton extends StatelessWidget {
  const _ScenarioButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.warning = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: warning
              ? colors.warning.withValues(alpha: 0.2)
              : colors.secondary,
          borderRadius: BorderRadius.circular(HiqeoRadius.pill),
          border: Border.all(
            color: warning ? colors.warning : colors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 13,
              color: warning ? colors.warningText : colors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: HiqeoTypography.medium,
                color: warning ? colors.warningText : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
