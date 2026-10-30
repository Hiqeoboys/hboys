import 'package:flutter/material.dart';

import '../application/offline_download_controller.dart';
import '../application/offline_map_service.dart';
import '../domain/map_package.dart';

class OfflinePackagePanel extends StatelessWidget {
  const OfflinePackagePanel({super.key, required this.controller});

  final OfflineDownloadController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final package = controller.package;
        final plan = controller.plan;
        if (package == null || plan == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Pilih paket gunung untuk mengatur unduhan offline.'),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_download_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Unduhan offline',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${package.name} · versi ${package.version} · data '
                  '${_formatDate(package.dataDateUtc)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _metric(
                  theme,
                  'Area',
                  '${plan.areaKm2.toStringAsFixed(1)} km²'
                      ' / batas paket ${package.offline.maxAreaKm2.toStringAsFixed(1)} km²',
                ),
                _metric(
                  theme,
                  'Zoom',
                  '${package.offline.minZoom}-${package.offline.maxZoom} '
                      '(batas aplikasi ${const MapGuardrails().minZoom}-'
                      '${const MapGuardrails().maxZoom})',
                ),
                _metric(
                  theme,
                  'Perkiraan tile',
                  '${plan.tileCount} / batas paket ${package.offline.maxTiles}',
                ),
                _metric(
                  theme,
                  'Estimasi SDK',
                  _estimateText(),
                ),
                if (plan.violations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final violation in plan.violations)
                    Text(
                      violation.message,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Perkiraan tile adalah hitungan alamat tile Web Mercator, '
                  'bukan jumlah aset unduhan. Mapbox mengelompokkan tile '
                  'menjadi tile pack; ukuran byte di atas berasal dari '
                  'estimasi SDK.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (controller.phase == OfflineDownloadPhase.downloading) ...[
                  LinearProgressIndicator(
                    value: controller.progress?.fraction,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _progressText(),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                ],
                if (controller.phase == OfflineDownloadPhase.downloaded) ...[
                  Text(
                    'SDK melaporkan unduhan selesai pada sesi ini. Aplikasi '
                    'belum memverifikasi ulang seluruh tile.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 8),
                ],
                if (controller.error != null) ...[
                  Text(
                    controller.error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed:
                          controller.canDownload ? controller.download : null,
                      icon: const Icon(Icons.download),
                      label: Text(_buttonText()),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: controller.isBusy
                          ? null
                          : controller.estimateDownload,
                      child: const Text('Hitung ulang'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Batas Mapbox: maksimum '
                  '${MapGuardrails.mapboxTilePackLimit} tile pack kumulatif '
                  'untuk semua region. Batas ini tidak bisa dihitung dari '
                  'jumlah tile dan dapat berubah; hubungi Mapbox bila perlu '
                  'lebih. Data offline tidak diperbarui otomatis dan harus '
                  'diunduh ulang. Unduhan memakai kuota data jika tidak ada '
                  'Wi-Fi. Atribusi Mapbox/OpenStreetMap wajib tetap terlihat, '
                  'termasuk saat offline.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _estimateText() {
    final estimate = controller.estimate;
    if (estimate == null) {
      return switch (controller.phase) {
        OfflineDownloadPhase.estimating => 'Menghitung...',
        OfflineDownloadPhase.error => 'Tidak tersedia',
        _ => 'Belum dihitung',
      };
    }
    return 'transfer ${_formatBytes(estimate.transferBytes)}, '
        'penyimpanan ${_formatBytes(estimate.storageBytes)} '
        '(margin ±${(estimate.errorMargin * 100).round()}%)';
  }

  String _progressText() {
    final progress = controller.progress;
    if (progress == null) return 'Menunggu progres dari SDK...';
    final phase = progress.phase == OfflinePhase.stylePack
        ? 'Style pack'
        : 'Tile region';
    final percent = (progress.fraction * 100).toStringAsFixed(0);
    return '$phase: ${progress.completedResources}/'
        '${progress.requiredResources} aset ($percent%), '
        '${_formatBytes(progress.completedBytes)}';
  }

  String _buttonText() {
    return switch (controller.phase) {
      OfflineDownloadPhase.estimating => 'Menghitung...',
      OfflineDownloadPhase.downloading => 'Mengunduh...',
      OfflineDownloadPhase.downloaded => 'Selesai diunduh',
      OfflineDownloadPhase.error => 'Coba lagi',
      _ => 'Unduh paket',
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime date) {
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)}';
  }

  Widget _metric(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
