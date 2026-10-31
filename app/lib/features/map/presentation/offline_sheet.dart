import 'package:flutter/material.dart';

import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/hiqeo_sheet.dart';
import '../../../design/widgets/line_icons.dart';
import '../application/offline_download_controller.dart';
import '../application/offline_map_service.dart';
import '../domain/map_package.dart';

/// Membuka sheet pengelolaan paket offline di atas layar peta.
Future<void> showOfflineMapSheet(
  BuildContext context, {
  required MapPackageCatalog? catalog,
  required bool loading,
  required String? error,
  required OfflineDownloadController controller,
  required bool mapAvailable,
  required ValueChanged<MountainMapPackage> onSelect,
  required VoidCallback onRetry,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.74,
        minChildSize: 0.42,
        maxChildSize: 0.92,
        builder: (context, scrollController) => OfflineSheetBody(
          catalog: catalog,
          loading: loading,
          error: error,
          controller: controller,
          mapAvailable: mapAvailable,
          onSelect: onSelect,
          onRetry: onRetry,
          scrollController: scrollController,
        ),
      ),
    ),
  );
}

class OfflineSheetBody extends StatelessWidget {
  const OfflineSheetBody({
    super.key,
    required this.catalog,
    required this.loading,
    required this.error,
    required this.controller,
    required this.mapAvailable,
    required this.onSelect,
    required this.onRetry,
    this.scrollController,
  });

  final MapPackageCatalog? catalog;
  final bool loading;
  final String? error;
  final OfflineDownloadController controller;
  final bool mapAvailable;
  final ValueChanged<MountainMapPackage> onSelect;
  final VoidCallback onRetry;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return HiqeoSheet(
      title: 'Peta offline',
      subtitle: 'Unduh area sebelum berangkat',
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: <Widget>[
            Text(
              'Data offline tidak diperbarui otomatis dan harus diunduh ulang '
              'setelah peta berubah.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (!mapAvailable) ...<Widget>[
              const SizedBox(height: HiqeoSpacing.md),
              const _Notice(
                title: 'Mapbox belum aktif',
                body: 'Daftar paket tetap bisa dibaca, tetapi estimasi dan '
                    'unduhan memerlukan Mapbox di Android atau iOS.',
              ),
            ],
            const SizedBox(height: HiqeoSpacing.lg),
            if (loading)
              const _LoadingCatalog()
            else if (error != null)
              _CatalogError(message: error!, onRetry: onRetry)
            else if (catalog == null || catalog!.isEmpty)
              const _EmptyCatalog()
            else ...<Widget>[
              Text(
                'PAKET TERSEDIA',
                style: HiqeoTypography.overline(colors.textSecondary),
              ),
              const SizedBox(height: HiqeoSpacing.sm),
              for (final package in catalog!.packages)
                Padding(
                  padding: const EdgeInsets.only(bottom: HiqeoSpacing.md),
                  child: _PackCard(
                    package: package,
                    selected: controller.package?.id == package.id,
                    onTap: () => onSelect(package),
                  ),
                ),
              if (controller.package != null) ...<Widget>[
                const SizedBox(height: HiqeoSpacing.xs),
                _SelectedPackage(
                  controller: controller,
                  mapAvailable: mapAvailable,
                ),
              ],
            ],
            const SizedBox(height: HiqeoSpacing.xl),
            _FooterNotes(),
          ],
        ),
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  final MountainMapPackage package;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final plan = OfflinePlan.evaluate(package.offline);
    final area = plan.areaKm2.toStringAsFixed(1).replaceAll('.', ',');
    final subtitle = 'Versi ${package.version} · data ${_formatDate(package.dataDateUtc)}'
        '\n±${plan.tileCount} tile · $area km² · zoom '
        '${package.offline.minZoom}-${package.offline.maxZoom}';
    return Semantics(
      button: true,
      selected: selected,
      label: '${package.name}, ${selected ? 'dipilih' : 'pilih paket'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(HiqeoSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? colors.secondary.withValues(alpha: 0.5)
                : colors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(HiqeoRadius.floating),
            border: Border.all(
              color: selected ? colors.primary : colors.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              HiqeoIcon(
                HiqeoIcons.mountain,
                color: colors.textPrimary,
                size: 22,
              ),
              const SizedBox(width: HiqeoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            package.name,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: HiqeoSpacing.sm),
                        _VerifiedBadge(verified: package.verified),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final color = verified ? colors.textSecondary : colors.warningText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        HiqeoIcon(
          verified ? HiqeoIcons.check : HiqeoIcons.warning,
          size: 13,
          strokeWidth: 2,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          verified ? 'Terverifikasi' : 'Belum terverifikasi',
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: HiqeoTypography.medium,
          ),
        ),
      ],
    );
  }
}

class _SelectedPackage extends StatelessWidget {
  const _SelectedPackage({required this.controller, required this.mapAvailable});

  final OfflineDownloadController controller;
  final bool mapAvailable;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final status = controller.status;
    final phase = controller.phase;

    final String statusText;
    var statusReady = false;
    if (status == null) {
      statusText = 'Status penyimpanan belum terbaca dari perangkat.';
    } else if (status.ready) {
      statusReady = true;
      statusText = 'Siap dipakai offline · ${status.completedResources}/'
          '${status.requiredResources} aset tersimpan.';
    } else if (status.hasRegion) {
      statusText = 'Region tersimpan sebagian (${status.completedResources}/'
          '${status.requiredResources} aset); belum siap.';
    } else {
      statusText = 'Belum diunduh di perangkat ini.';
    }

    final estimate = controller.estimate;
    final progress = controller.progress;

    return Container(
      padding: const EdgeInsets.all(HiqeoSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(HiqeoRadius.floating),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              HiqeoIcon(
                statusReady ? HiqeoIcons.check : HiqeoIcons.map,
                size: 18,
                color: statusReady ? colors.textPrimary : colors.textSecondary,
              ),
              const SizedBox(width: HiqeoSpacing.sm),
              Expanded(
                child: Text(
                  statusText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: statusReady ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          if (controller.plan != null && !controller.plan!.canDownload)
            for (final violation in controller.plan!.violations)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  violation.message,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.warningText),
                ),
              ),
          if (estimate != null)
            Text(
              'Perkiraan SDK: transfer ${_formatBytes(estimate.transferBytes)}, '
              'penyimpanan ${_formatBytes(estimate.storageBytes)} '
              '(margin ±${(estimate.errorMargin * 100).round()}%).',
              style: theme.textTheme.bodySmall,
            )
          else if (!statusReady && controller.plan?.canDownload == true)
            Text(
              switch (phase) {
                OfflineDownloadPhase.estimating => 'Menghitung perkiraan byte…',
                OfflineDownloadPhase.error => 'Estimasi SDK tidak tersedia.',
                _ => 'Estimasi byte belum dihitung.',
              },
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          if (controller.error != null) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.xs),
            Text(
              controller.error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.warningText),
            ),
          ],
          if (phase == OfflineDownloadPhase.downloading) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(HiqeoRadius.pill),
              child: LinearProgressIndicator(
                value: progress?.fraction,
                minHeight: 6,
                backgroundColor: colors.hairline,
              ),
            ),
            const SizedBox(height: HiqeoSpacing.xs),
            Text(
              progress == null
                  ? 'Menunggu progres dari SDK…'
                  : '${progress.phase == OfflinePhase.stylePack ? 'Style pack' : 'Tile region'}: '
                      '${progress.completedResources}/${progress.requiredResources} '
                      'aset · ${_formatBytes(progress.completedBytes)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (phase == OfflineDownloadPhase.downloaded) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.sm),
            Text(
              'SDK melaporkan unduhan selesai pada sesi ini. Aplikasi belum '
              'memverifikasi ulang seluruh tile.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: HiqeoSpacing.md),
          HiqeoButton(
            label: !mapAvailable
                ? 'Unduhan butuh Mapbox aktif'
                : switch (phase) {
                    OfflineDownloadPhase.estimating => 'Menghitung…',
                    OfflineDownloadPhase.downloading => 'Mengunduh…',
                    OfflineDownloadPhase.downloaded => 'Selesai diunduh',
                    OfflineDownloadPhase.error => 'Coba lagi',
                    _ => 'Unduh paket',
                  },
            onPressed: mapAvailable && controller.canDownload
                ? controller.download
                : null,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed:
                  mapAvailable && !controller.isBusy ? controller.estimateDownload : null,
              child: const Text('Hitung ulang'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(HiqeoSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(HiqeoRadius.floating),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              HiqeoIcon(HiqeoIcons.mountain, color: colors.textPrimary),
              const SizedBox(width: HiqeoSpacing.md),
              Expanded(
                child: Text(
                  'Belum ada paket gunung',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            'Katalog aplikasi kosong dan tidak membundel data gunung fiktif. '
            'Tambahkan paket dari pipeline data yang sudah diverifikasi; lihat '
            'docs/peta_offline.md untuk format katalog.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCatalog extends StatelessWidget {
  const _LoadingCatalog();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: HiqeoSpacing.md),
        Text('Memuat katalog paket…', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Notice(
      title: 'Katalog paket tidak terbaca',
      body: message,
      onRetry: onRetry,
      isError: true,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.body,
    this.onRetry,
    this.isError = false,
  });

  final String title;
  final String body;
  final VoidCallback? onRetry;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(HiqeoSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(HiqeoRadius.floating),
        border: Border.all(
          color: isError ? colors.warning : colors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: isError ? colors.warningText : colors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (onRetry != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onRetry,
                child: const Text('Muat ulang'),
              ),
            ),
        ],
      ),
    );
  }
}

class _FooterNotes extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Perkiraan tile adalah hitungan alamat tile Web Mercator, bukan '
          'jumlah aset unduhan. Mapbox mengelompokkan tile menjadi tile pack.',
          style: style,
        ),
        const SizedBox(height: HiqeoSpacing.sm),
        Text(
          'Batas Mapbox: maksimum ${MapGuardrails.mapboxTilePackLimit} tile pack '
          'kumulatif untuk semua region; batas ini tidak bisa dihitung dari '
          'jumlah tile dan dapat berubah. Data offline tidak diperbarui '
          'otomatis.',
          style: style,
        ),
        const SizedBox(height: HiqeoSpacing.sm),
        Text(
          'Unduhan memakai kuota data bila tidak ada Wi-Fi. Logo dan atribusi '
          'Mapbox/OpenStreetMap wajib tetap terlihat, termasuk saat memakai '
          'data offline.',
          style: style,
        ),
      ],
    );
  }
}

String _formatDate(DateTime date) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1).replaceAll('.', ',')} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
  return '${(mb / 1024).toStringAsFixed(2).replaceAll('.', ',')} GB';
}
