import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/layout.dart';
import '../../../design/glass/glass_surface.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../application/offline_pack_service.dart';
import '../data/mountain_catalog_repository.dart';
import '../domain/map_package.dart';
import '../domain/mountain_pack.dart';
import 'map_page.dart';

/// Halaman detail informasi paket gunung, jalur pendakian, dan unduhan peta offline.
class MountainDetailPage extends StatefulWidget {
  const MountainDetailPage({
    super.key,
    required this.pack,
    this.repository,
    this.offlineService,
  });

  final MountainPack pack;
  final MountainCatalogRepository? repository;
  final OfflinePackService? offlineService;

  @override
  State<MountainDetailPage> createState() => _MountainDetailPageState();
}

class _MountainDetailPageState extends State<MountainDetailPage>
    with SingleTickerProviderStateMixin {
  late MountainPack _pack;
  late final MountainCatalogRepository _repository;
  late final OfflinePackService _offlineService;

  StreamSubscription<OfflineDownloadProgress>? _progressSub;
  bool _isDownloading = false;
  bool _isPaused = false;
  double _progressFraction = 0.0;
  int _completedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  String? _selectedTrailId;

  late final AnimationController _cardEntranceController;
  late final Animation<double> _cardSlideAnimation;
  late final Animation<double> _cardFadeAnimation;

  @override
  void initState() {
    super.initState();
    _pack = widget.pack;
    _repository = widget.repository ?? MountainCatalogRepository.instance;
    _offlineService = widget.offlineService ?? OfflinePackService.instance;

    _totalBytes = _pack.sizeMb * 1024 * 1024;
    _progressFraction = _pack.progress;
    _isDownloading = _pack.isDownloading;
    _selectedTrailId =
        _pack.package.trails.isNotEmpty ? _pack.package.trails.first.id : null;

    _cardEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _cardSlideAnimation = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _cardEntranceController,
        curve: Curves.easeOutCubic,
      ),
    );
    _cardFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardEntranceController,
        curve: Curves.easeOutCubic,
      ),
    );

    _cardEntranceController.forward();

    _repository.addListener(_onRepoChanged);
    _listenProgress();
    _checkInitialStatus();
  }

  @override
  void dispose() {
    _cardEntranceController.dispose();
    _progressSub?.cancel();
    _repository.removeListener(_onRepoChanged);
    super.dispose();
  }

  void _onRepoChanged() {
    if (!mounted) return;
    final updated = _repository.packs.firstWhere(
      (p) => p.id == _pack.id,
      orElse: () => _pack,
    );
    setState(() {
      _pack = updated;
      _isDownloading = updated.isDownloading;
      _progressFraction = updated.progress;
    });
  }

  void _listenProgress() {
    _progressSub?.cancel();
    _progressSub = _offlineService.progressStream(_pack.id).listen((event) {
      if (!mounted) return;
      setState(() {
        _progressFraction = event.fraction;
        _completedBytes = event.completedBytes;
        _totalBytes = event.totalBytes;
        if (event.fraction >= 1.0) {
          _isDownloading = false;
          _isPaused = false;
          _pack = _pack.copyWith(
            status: MountainDownloadStatus.downloaded,
            progress: 1.0,
          );
          unawaited(_repository.markDownloaded(_pack.id));
          unawaited(HapticFeedback.lightImpact());
        }
      });
    }, onError: (Object err) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _isPaused = false;
        _errorMessage = err.toString();
        _pack = _pack.copyWith(
          status: MountainDownloadStatus.failed,
          failureReason: err.toString(),
        );
      });
    });
  }

  Future<void> _checkInitialStatus() async {
    final serviceStatus =
        await _offlineService.getStatus(_pack.id, remoteVersion: _pack.version);
    final savedProg = await _offlineService.getSavedProgress(_pack.id);
    final errorMsg = await _offlineService.getFailureReason(_pack.id);
    final savedTrailId = await _repository.getLastSelectedTrailId(_pack.id);

    // Sinkronkan status dengan katalog: jika gunung sudah terunduh di daftar
    // maupun layanan offline, tombol WAJIB menampilkan "Buka peta".
    final repoPack = _repository.packs.where((p) => p.id == _pack.id);
    final alreadyDownloaded = _pack.isDownloaded ||
        (repoPack.isNotEmpty && repoPack.first.isDownloaded) ||
        serviceStatus == MountainDownloadStatus.downloaded ||
        serviceStatus == MountainDownloadStatus.updateAvailable;
    final effectiveStatus = alreadyDownloaded
        ? MountainDownloadStatus.downloaded
        : serviceStatus;

    if (!mounted) return;
    setState(() {
      if (savedTrailId != null &&
          _pack.package.trails.any((t) => t.id == savedTrailId)) {
        _selectedTrailId = savedTrailId;
      }
      if (effectiveStatus == MountainDownloadStatus.downloading &&
          savedProg > 0 &&
          savedProg < 1.0) {
        _isPaused = true;
        _isDownloading = true;
        _progressFraction = savedProg;
      }
      _errorMessage = errorMsg;
      _pack = _pack.copyWith(
        status: effectiveStatus,
        progress: alreadyDownloaded
            ? 1.0
            : (savedProg > 0 ? savedProg : _pack.progress),
        failureReason: errorMsg,
      );
    });
  }

  Future<void> _handleDownload({bool ignoreMobileData = false}) async {
    unawaited(HapticFeedback.lightImpact());
    final check = await _offlineService.checkPreDownload(_pack);

    if (check == PreDownloadCheckResult.noInternet) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Butuh internet untuk mengunduh')),
      );
      return;
    }

    if (check == PreDownloadCheckResult.insufficientDiskSpace) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ruang penyimpanan tidak mencukupi (dibutuhkan ${(widget.pack.sizeMb * 1.5).toStringAsFixed(0)} MB).',
          ),
        ),
      );
      return;
    }

    if (!ignoreMobileData && check == PreDownloadCheckResult.mobileDataWarning) {
      final proceed = await _showMobileDataConfirmationDialog();
      if (proceed != true) return;
    }

    setState(() {
      _isDownloading = true;
      _isPaused = false;
      _errorMessage = null;
      _pack = _pack.copyWith(
        status: MountainDownloadStatus.downloading,
        progress: _progressFraction > 0 ? _progressFraction : 0.05,
      );
    });

    try {
      await _offlineService.startDownload(_pack, ignoreMobileData: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _isPaused = false;
        _errorMessage = e.toString();
        _pack = _pack.copyWith(
          status: MountainDownloadStatus.failed,
          failureReason: e.toString(),
        );
      });
    }
  }

  Future<void> _handlePauseResume() async {
    unawaited(HapticFeedback.lightImpact());
    if (_isPaused) {
      // Lanjutkan unduhan
      setState(() {
        _isPaused = false;
        _isDownloading = true;
      });
      try {
        await _offlineService.startDownload(_pack, ignoreMobileData: true);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _isPaused = false;
          _errorMessage = e.toString();
          _pack = _pack.copyWith(
            status: MountainDownloadStatus.failed,
            failureReason: e.toString(),
          );
        });
      }
    } else {
      // Jeda unduhan
      setState(() {
        _isPaused = true;
      });
      await _offlineService.pauseDownload(_pack.id);
    }
  }

  Future<void> _handleCancel() async {
    unawaited(HapticFeedback.lightImpact());
    await _offlineService.cancelDownload(_pack.id);
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _isPaused = false;
      _progressFraction = 0.0;
      _completedBytes = 0;
      _errorMessage = null;
      _pack = _pack.copyWith(
        status: MountainDownloadStatus.notDownloaded,
        progress: 0.0,
      );
    });
  }

  Future<void> _handleDelete() async {
    unawaited(HapticFeedback.lightImpact());
    final confirmed = await _showDeleteConfirmationDialog();
    if (confirmed != true) return;

    await _offlineService.deletePack(_pack.id);
    await _repository.markDeleted(_pack.id);
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _isPaused = false;
      _progressFraction = 0.0;
      _completedBytes = 0;
      _pack = _pack.copyWith(
        status: MountainDownloadStatus.notDownloaded,
        progress: 0.0,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Peta offline ${_pack.name} telah dihapus.')),
    );
  }

  Future<bool?> _showMobileDataConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unduh lewat data seluler?'),
        content: Text(
          'Kamu memakai data seluler. Lanjutkan unduh ${_pack.sizeMb} MB?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Tunggu Wi-Fi'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showDeleteConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus peta offline?'),
        content: Text(
          'Peta offline ${_pack.name} akan dihapus dari penyimpanan lokal. Berkas jalur dan ubin peta tidak dapat diakses tanpa internet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _selectTrail(MapTrail trail) {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _selectedTrailId = trail.id);
    unawaited(_repository.saveSelectedTrailId(_pack.id, trail.id));
  }

  void _openTrailMap() {
    if (_isDownloading || (!_pack.isDownloaded && !_pack.isUpdateAvailable)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unduh peta gunung sampai selesai sebelum membuka peta jalur.',
          ),
        ),
      );
      return;
    }
    unawaited(HapticFeedback.lightImpact());
    MapTrail? selectedTrail;
    if (_pack.package.trails.isNotEmpty) {
      selectedTrail = _pack.package.trails.firstWhere(
        (t) => t.id == _selectedTrailId,
        orElse: () => _pack.package.trails.first,
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapPage(
          initialPackage: _pack.package,
          initialTrail: selectedTrail,
          allowStartAscent: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final padding = MediaQuery.paddingOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final topSafe = math.max(padding.top, viewPadding.top);
    final extraTopPadding =
        12.0 + math.max(0.0, viewPadding.top - padding.top);
    final bottomInset = math.max(
      AppLayout.bottomInset(context),
      padding.bottom,
    );
    final heroHeight = math.max(248.0, topSafe + 208.0);

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: colors.background,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Hero Section: ilustrasi topografi tanpa tombol kembali di dalamnya
              SliverToBoxAdapter(
                child: SizedBox(
                  height: heroHeight,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      // Ilustrasi Topografi CustomPainter
                      Positioned.fill(
                        child: CustomPaint(
                          painter: TopographicHeroPainter(
                            colors: colors,
                            normalizedPoints: _pack.normalizedPoints,
                          ),
                        ),
                      ),
                      // Fade Gradien Bawah (120 dp)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 120,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                colors.background.withValues(alpha: 0.0),
                                colors.background,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

          // Judul, Subjudul, Jalur Pendakian & Card Aksi Peta Offline (di bawah daftar jalur)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _pack.name,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _pack.subtitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Baris 3 Kartu Info (Ketinggian, Jalur, Ukuran)
                  Row(
                    children: [
                      Expanded(
                        child: _InfoStatCard(
                          label: 'KETINGGIAN',
                          value: _pack.formattedElevation,
                          colors: colors,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InfoStatCard(
                          label: 'JALUR',
                          value: '${_pack.trailCount} Jalur',
                          colors: colors,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InfoStatCard(
                          label: 'UKURAN',
                          value: '${_pack.sizeMb} MB',
                          colors: colors,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Bagian Jalur Pendakian
                  Text(
                    'JALUR PENDAKIAN',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Kartu Daftar Jalur (radius 24, tinggi baris 52 dp, dapat dipilih)
                  _RouteListCard(
                    key: const ValueKey('mountain-route-list-card'),
                    trails: _pack.package.trails,
                    selectedTrailId: _selectedTrailId,
                    onSelectTrail: _selectTrail,
                    colors: colors,
                  ),
                  const SizedBox(height: 16),

                  // Card "Tersedia offline / Buka peta" di bawah daftar jalur agar tidak menutupi pilihan jalur
                  AnimatedBuilder(
                    animation: _cardEntranceController,
                    builder: (context, child) {
                      final opacity = _cardFadeAnimation.value;
                      final slideY = _cardSlideAnimation.value;
                      if (opacity >= 1.0 && slideY == 0.0) {
                        return child!;
                      }
                      return Transform.translate(
                        offset: Offset(0, slideY),
                        child: Opacity(
                          opacity: opacity,
                          child: child,
                        ),
                      );
                    },
                    child: _DockedActionCard(
                      key: const ValueKey('mountain-action-card'),
                      pack: _pack,
                      colors: colors,
                      isDownloading: _isDownloading,
                      isPaused: _isPaused,
                      progressFraction: _progressFraction,
                      completedBytes: _completedBytes,
                      totalBytes: _totalBytes,
                      errorMessage: _errorMessage,
                      onDownload: () => _handleDownload(),
                      onPauseResume: _handlePauseResume,
                      onCancel: _handleCancel,
                      onOpen: _openTrailMap,
                      onDelete: _handleDelete,
                      onRetry: () => _handleDownload(),
                    ),
                  ),
                  SizedBox(
                    key: const ValueKey('mountain-detail-bottom-spacer'),
                    height: bottomInset + 64,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // Tombol kembali Liquid Glass tetap diam / pinned di pojok kiri atas layar
      Positioned(
        top: 0,
        left: 0,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, extraTopPadding, 16, 0),
            child: HiqeoBackButton(
              key: const ValueKey('mountain-detail-back-button'),
              onTap: () {
                unawaited(HapticFeedback.lightImpact());
                Navigator.of(context).maybePop();
              },
            ),
          ),
        ),
      ),
    ],
  ),
    );
  }
}

/// Kartu mini statistik info (Ketinggian, Jalur, Ukuran).
class _InfoStatCard extends StatelessWidget {
  const _InfoStatCard({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final HiqeoColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 22,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu daftar jalur pendakian (radius 24, baris 52 dp, dapat dipilih).
class _RouteListCard extends StatelessWidget {
  const _RouteListCard({
    super.key,
    required this.trails,
    required this.colors,
    this.selectedTrailId,
    this.onSelectTrail,
  });

  final List<MapTrail> trails;
  final HiqeoColors colors;
  final String? selectedTrailId;
  final ValueChanged<MapTrail>? onSelectTrail;

  @override
  Widget build(BuildContext context) {
    if (trails.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.hairline, width: 1),
        ),
        child: Center(
          child: Text(
            'Belum ada data jalur pendakian',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.hairline, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < trails.length; i++) ...[
            Builder(
              builder: (context) {
                final trail = trails[i];
                final isSelected = trail.id == selectedTrailId;

                return Material(
                  color: isSelected
                      ? colors.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  child: InkWell(
                    key: ValueKey('route-row-${trail.id}'),
                    onTap: onSelectTrail != null ? () => onSelectTrail!(trail) : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 52),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.terrain_rounded,
                              size: 20,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                trail.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: colors.primary,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (i < trails.length - 1)
              Divider(
                color: colors.hairline,
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ],
      ),
    );
  }
}

/// Action Card di dalam area gulir dengan permukaan kaca ringan tanpa blur pass.
class _DockedActionCard extends StatelessWidget {
  const _DockedActionCard({
    super.key,
    required this.pack,
    required this.colors,
    required this.isDownloading,
    required this.isPaused,
    required this.progressFraction,
    required this.completedBytes,
    required this.totalBytes,
    required this.errorMessage,
    required this.onDownload,
    required this.onPauseResume,
    required this.onCancel,
    required this.onOpen,
    required this.onDelete,
    required this.onRetry,
  });

  final MountainPack pack;
  final HiqeoColors colors;
  final bool isDownloading;
  final bool isPaused;
  final double progressFraction;
  final int completedBytes;
  final int totalBytes;
  final String? errorMessage;
  final VoidCallback onDownload;
  final VoidCallback onPauseResume;
  final VoidCallback onCancel;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: _buildStateContent(context),
      ),
    );
  }

  Widget _buildStateContent(BuildContext context) {
    // 1. State: Downloading (sedang mengunduh / terjeda)
    if (isDownloading) {
      final pct = (progressFraction * 100).clamp(0, 100).round();
      final completedMb = (completedBytes / (1024 * 1024)).toStringAsFixed(1);
      final totalMb = pack.sizeMb;

      return Column(
        key: const ValueKey('state_downloading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isPaused ? 'Unduhan terjeda' : 'Mengunduh peta',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress Bar 8 dp
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressFraction.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: colors.hairline,
              valueColor: AlwaysStoppedAnimation(colors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$completedMb MB dari $totalMb MB',
            style: TextStyle(
              fontSize: 12.5,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HairlineButton(
                  label: isPaused ? 'Lanjut' : 'Jeda',
                  icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  colors: colors,
                  onPressed: onPauseResume,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HairlineButton(
                  label: 'Batal',
                  icon: Icons.close_rounded,
                  colors: colors,
                  onPressed: onCancel,
                ),
              ),
            ],
          ),
        ],
      );
    }

    // 2. State: Downloaded (tersedia offline)
    if (pack.isDownloaded) {
      return Column(
        key: const ValueKey('state_downloaded'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: colors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tersedia offline',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${pack.sizeMb} MB · diperbarui baru saja',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          HiqeoButton(
            label: 'Buka peta',
            leading: Icon(Icons.map_rounded, color: colors.onPrimary, size: 20),
            onPressed: onOpen,
          ),
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Text(
                  'Hapus unduhan',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 3. State: Update Available (pembaruan tersedia)
    if (pack.isUpdateAvailable) {
      return Column(
        key: const ValueKey('state_update_available'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Pembaruan tersedia',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Versi peta terbaru tersedia untuk diunduh.',
            style: TextStyle(
              fontSize: 12.5,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          HiqeoButton(
            label: 'Perbarui peta',
            leading: Icon(Icons.system_update_alt_rounded, color: colors.onPrimary, size: 20),
            onPressed: onDownload,
          ),
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Text(
                  'Buka versi lama',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 4. State: Failed (unduhan gagal)
    if (pack.isFailed || errorMessage != null) {
      final msg = errorMessage ?? pack.failureReason ?? 'Gagal mengunduh peta offline.';
      return Column(
        key: const ValueKey('state_failed'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error, size: 22),
              const SizedBox(width: 8),
              Text(
                'Unduhan gagal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            msg,
            style: TextStyle(
              fontSize: 12.5,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          HiqeoButton(
            label: 'Coba lagi',
            leading: Icon(Icons.refresh_rounded, color: colors.onPrimary, size: 20),
            onPressed: onRetry,
          ),
        ],
      );
    }

    // 5. State: Not Downloaded (belum diunduh)
    return Column(
      key: const ValueKey('state_not_downloaded'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Peta offline',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${pack.sizeMb} MB · zoom sampai 16 · disarankan lewat Wi-Fi',
          style: TextStyle(
            fontSize: 12.5,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        HiqeoButton(
          label: 'Unduh peta',
          leading: HiqeoIcon(HiqeoIcons.download, color: colors.onPrimary),
          onPressed: onDownload,
        ),
      ],
    );
  }
}

/// Tombol bergaris hairline 44 dp.
class _HairlineButton extends StatelessWidget {
  const _HairlineButton({
    required this.label,
    required this.icon,
    required this.colors,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final HiqeoColors colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.hairline, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: colors.textPrimary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CustomPainter untuk ilustrasi topografi pada Hero Section (tinggi 248 dp).
///
/// Menggambar:
/// 1. 5 elips kontur ketinggian samar
/// 2. Garis jalur GPX dinormalkan dengan halo latar belakang 9 dp dan stroke utama 4 dp
/// 3. Titik awal (lingkaran padat) dan titik akhir/puncak (lingkaran berlubang/ring)
class TopographicHeroPainter extends CustomPainter {
  TopographicHeroPainter({
    required this.colors,
    required this.normalizedPoints,
  });

  final HiqeoColors colors;
  final List<Offset> normalizedPoints;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Latar belakang permukaan samar
    final bgPaint = Paint()..color = colors.surface.withValues(alpha: 0.35);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // 1. Gambar 5 elips kontur samar
    final contourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final contours = [
      (Offset(w * 0.50, h * 0.52), w * 0.46, h * 0.40, 0.15),
      (Offset(w * 0.52, h * 0.49), w * 0.38, h * 0.32, 0.20),
      (Offset(w * 0.54, h * 0.46), w * 0.30, h * 0.24, 0.25),
      (Offset(w * 0.56, h * 0.43), w * 0.22, h * 0.17, 0.30),
      (Offset(w * 0.58, h * 0.40), w * 0.14, h * 0.10, 0.35),
    ];

    for (final c in contours) {
      contourPaint.color = colors.textSecondary.withValues(alpha: c.$4);
      canvas.drawOval(
        Rect.fromCenter(center: c.$1, width: c.$2 * 2, height: c.$3 * 2),
        contourPaint,
      );
    }

    // 2. Garis jalur GPX
    final path = Path();
    if (normalizedPoints.isNotEmpty) {
      const paddingX = 40.0;
      const paddingTop = 36.0;
      final usableW = w - (paddingX * 2);
      final usableH = h - (paddingTop + 50.0);

      final pts = normalizedPoints.map((p) {
        return Offset(paddingX + (p.dx * usableW), paddingTop + (p.dy * usableH));
      }).toList();

      path.moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }

      // Halo latar belakang (9 dp)
      final haloPaint = Paint()
        ..color = colors.background
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, haloPaint);

      // Garis jalur utama (4 dp)
      final linePaint = Paint()
        ..color = colors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, linePaint);

      // Titik awal (dot lingkaran padat ~8 dp)
      final startPoint = pts.first;
      final startPaint = Paint()..color = colors.primary;
      canvas.drawCircle(startPoint, 4.5, startPaint);
      canvas.drawCircle(
        startPoint,
        6.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colors.background,
      );

      // Titik akhir / puncak (ring stroke lingkaran berlubang)
      final endPoint = pts.last;
      final endRingPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = colors.primary;
      canvas.drawCircle(endPoint, 6.0, endRingPaint);
      canvas.drawCircle(endPoint, 2.0, Paint()..color = colors.primary);
    } else {
      // Jalur fallback kurva halus jika tidak ada koordinat
      path.moveTo(w * 0.20, h * 0.75);
      path.quadraticBezierTo(w * 0.40, h * 0.65, w * 0.48, h * 0.50);
      path.quadraticBezierTo(w * 0.55, h * 0.38, w * 0.65, h * 0.32);

      canvas.drawPath(
        path,
        Paint()
          ..color = colors.background
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9.0
          ..strokeCap = StrokeCap.round,
      );

      canvas.drawPath(
        path,
        Paint()
          ..color = colors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round,
      );

      canvas.drawCircle(Offset(w * 0.20, h * 0.75), 4.5, Paint()..color = colors.primary);
      canvas.drawCircle(
        Offset(w * 0.65, h * 0.32),
        6.0,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = colors.primary,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TopographicHeroPainter oldDelegate) {
    return oldDelegate.colors != colors ||
        oldDelegate.normalizedPoints != normalizedPoints;
  }
}
