import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/layout.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/line_icons.dart';
import '../data/mountain_catalog_repository.dart';
import '../domain/mountain_pack.dart';
import 'map_page.dart';
import 'mountain_detail_page.dart';

/// Halaman daftar gunung (akar tab Peta).
class MountainListPage extends StatefulWidget {
  const MountainListPage({
    super.key,
    this.repository,
    this.onOpenMountain,
    this.initialFilter,
  });

  final MountainCatalogRepository? repository;
  final void Function(MountainPack pack)? onOpenMountain;
  final String? initialFilter;

  @override
  State<MountainListPage> createState() => _MountainListPageState();
}

class _MountainListPageState extends State<MountainListPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  late final MountainCatalogRepository _repository;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _searchQuery = '';
  String _selectedFilter = 'Semua';
  bool _isOnline = true;
  late AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _selectedFilter = _normalizeFilter(widget.initialFilter) ?? 'Semua';
    _repository = widget.repository ?? MountainCatalogRepository.instance;
    _repository.addListener(_onRepoChanged);
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _searchController.addListener(_onSearchChanged);

    unawaited(_initData());
  }

  @override
  void didUpdateWidget(MountainListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilter != oldWidget.initialFilter) {
      final normalized = _normalizeFilter(widget.initialFilter);
      if (normalized != null && normalized != _selectedFilter) {
        setState(() => _selectedFilter = normalized);
      }
    }
  }

  static String? _normalizeFilter(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final lower = raw.trim().toLowerCase();
    if (lower == 'terunduh' || lower == 'offline') return 'Terunduh';
    if (lower == 'semua') return 'Semua';
    return raw.trim();
  }

  Future<void> _initData() async {
    final online = await _repository.isOnline();
    if (mounted) setState(() => _isOnline = online);
    await _repository.loadPacks();
    if (mounted) {
      _entranceController.forward();
    }
  }

  void _onRepoChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onSearchChanged() {
    final text = _searchController.text.trim();
    if (text != _searchQuery) {
      setState(() => _searchQuery = text);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _entranceController.dispose();
    _repository.removeListener(_onRepoChanged);
    super.dispose();
  }

  void _openDetail(MountainPack pack) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MountainDetailPage(
          pack: pack,
          repository: _repository,
        ),
      ),
    );
  }

  void _openTrailMap(MountainPack pack) {
    if (!pack.isDownloaded && !pack.isUpdateAvailable) {
      if (pack.isDownloading) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tunggu unduhan peta ${pack.name} selesai sebelum membuka peta jalur.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      unawaited(
        showDialog<void>(
          context: context,
          builder: (dialogCtx) {
            final colors = HiqeoColors.of(dialogCtx);
            return AlertDialog(
              key: const ValueKey<String>('mountain-list-download-required'),
              backgroundColor: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Unduh peta terlebih dahulu'),
              content: Text(
                'Peta ${pack.name} belum selesai diunduh. Unduh paket '
                'petanya dulu agar jalur tampil dengan aman saat offline.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Tutup'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    _openDetail(pack);
                  },
                  child: const Text('Unduh peta'),
                ),
              ],
            );
          },
        ),
      );
      return;
    }
    if (widget.onOpenMountain != null) {
      widget.onOpenMountain!(pack);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapPage(
          initialPackage: pack.package,
          allowStartAscent: false,
        ),
      ),
    );
  }

  Future<void> _startDownload(MountainPack pack) async {
    final online = await _repository.isOnline();
    if (!online) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Butuh internet untuk mengunduh'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      await _repository.startDownload(pack.id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MountainListPage._startDownload failed: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message
                : 'Unduhan belum bisa dimulai. Periksa koneksi lalu coba lagi.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  List<String> _extractProvinces(List<MountainPack> packs) {
    final set = <String>{};
    for (final p in packs) {
      if (p.province.isNotEmpty) set.add(p.province);
    }
    return set.toList();
  }

  List<MountainPack> _filterPacks(List<MountainPack> packs) {
    return packs.where((pack) {
      // 1. Filter Chip
      if (_selectedFilter == 'Terunduh') {
        if (!pack.isDownloaded) return false;
      } else if (_selectedFilter != 'Semua') {
        if (pack.province != _selectedFilter) return false;
      }

      // 2. Search Query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = pack.name.toLowerCase().contains(q);
        final matchProv = pack.province.toLowerCase().contains(q);
        if (!matchName && !matchProv) return false;
      }

      return true;
    }).toList();
  }

  Widget _buildStaggeredItem({
    required Widget child,
    required int index,
    required bool disableAnimations,
  }) {
    if (disableAnimations) return child;

    // Durasi tiap elemen 380 ms, jeda 40 ms + 45 ms * index (maksimal 10 elemen)
    final clampedIdx = index.clamp(0, 10);
    final startMs = 40 + (clampedIdx * 45);
    final endMs = (startMs + 380).clamp(0, 900);
    final startFraction = startMs / 900.0;
    final endFraction = endMs / 900.0;

    final curve = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(startFraction, endFraction, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) {
        final val = curve.value;
        if (val >= 1.0) {
          return child;
        }
        return Opacity(
          opacity: val,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - val)),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = HiqeoColors.of(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final bottomInset = AppLayout.bottomInset(context);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    final allPacks = _repository.packs;
    final provinces = _extractProvinces(allPacks);
    final filterChips = ['Semua', 'Terunduh', ...provinces];
    final filtered = _filterPacks(allPacks);

    final downloadedPacks = filtered.where((p) => p.isDownloaded).toList();
    final availablePacks = filtered.where((p) => !p.isDownloaded).toList();

    int itemCounter = 0;

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            final online = await _repository.isOnline();
            if (mounted) setState(() => _isOnline = online);
            await _repository.loadPacks(forceRefresh: true);
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, safeTop + 8, 16, 0),
                  child: _buildStaggeredItem(
                    index: itemCounter++,
                    disableAnimations: disableAnimations,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Peta',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pilih gunung untuk dibuka',
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),

              // Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildStaggeredItem(
                    index: itemCounter++,
                    disableAnimations: disableAnimations,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: colors.hairline),
                      ),
                      padding: EdgeInsets.only(
                        left: 16,
                        right: _searchQuery.isNotEmpty ? 4 : 16,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              maxLength: 80,
                              style: TextStyle(
                                fontSize: 14,
                                color: colors.textPrimary,
                              ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                counterText: '',
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintText: 'Cari gunung atau daerah',
                                hintStyle: TextStyle(
                                  fontSize: 14,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            Semantics(
                              button: true,
                              label: 'Hapus pencarian',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  unawaited(HapticFeedback.selectionClick());
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: colors.textSecondary,
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
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              // Filter Chips
              SliverToBoxAdapter(
                child: _buildStaggeredItem(
                  index: itemCounter++,
                  disableAnimations: disableAnimations,
                  child: SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filterChips.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final chip = filterChips[index];
                        final active = chip == _selectedFilter;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            unawaited(HapticFeedback.selectionClick());
                            setState(() => _selectedFilter = chip);
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            child: Center(
                              child: Container(
                                height: 36,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color:
                                      active ? colors.primary : colors.hairline,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text(
                                  chip,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: active
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
              ),

              // Offline Banner (jika tidak ada internet)
              if (!_isOnline)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          HiqeoIcon(
                            HiqeoIcons.warning,
                            size: 18,
                            color: colors.warning,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Mode offline: hanya gunung terunduh yang bisa dibuka',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // State Memuat (Skeleton 3 kartu)
              if (_repository.isLoading && allPacks.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SkeletonCard(colors: colors),
                      ),
                      childCount: 3,
                    ),
                  ),
                )
              // State Error
              else if (_repository.error != null && allPacks.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 48,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Daftar gunung tidak bisa dimuat',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () =>
                              _repository.loadPacks(forceRefresh: true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Coba lagi',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              // State Pencarian / Filter Kosong
              else if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(
                          _searchQuery.isNotEmpty
                              ? Icons.search_rounded
                              : Icons.filter_list_off_rounded,
                          size: 40,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'Tidak ada gunung yang cocok'
                              : _selectedFilter == 'Terunduh'
                                  ? 'Belum ada peta gunung yang terunduh'
                                  : _selectedFilter == 'Semua'
                                      ? 'Belum ada data gunung tersedia'
                                      : 'Belum ada gunung di kategori $_selectedFilter',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (_searchQuery.isNotEmpty ||
                            _selectedFilter != 'Semua') ...[
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _selectedFilter = 'Semua';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: colors.hairline,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                _searchQuery.isNotEmpty
                                    ? 'Hapus pencarian'
                                    : 'Tampilkan semua',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              // Daftar Kartu Gunung (Terunduh selalu di atas)
              else ...[
                // Bagian "Terunduh"
                if (downloadedPacks.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: _buildStaggeredItem(
                        index: itemCounter++,
                        disableAnimations: disableAnimations,
                        child: Text(
                          'Terunduh (${downloadedPacks.length})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final pack = downloadedPacks[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildStaggeredItem(
                              index: itemCounter++,
                              disableAnimations: disableAnimations,
                              child: _MountainCard(
                                pack: pack,
                                colors: colors,
                                isOnline: _isOnline,
                                onOpen: () => _openTrailMap(pack),
                                onDownload: () => _startDownload(pack),
                                onTapCard: () => _openDetail(pack),
                              ),
                            ),
                          );
                        },
                        childCount: downloadedPacks.length,
                      ),
                    ),
                  ),
                ],

                // Bagian "Tersedia"
                if (availablePacks.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: _buildStaggeredItem(
                        index: itemCounter++,
                        disableAnimations: disableAnimations,
                        child: Text(
                          'Tersedia (${availablePacks.length})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final pack = availablePacks[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildStaggeredItem(
                              index: itemCounter++,
                              disableAnimations: disableAnimations,
                              child: _MountainCard(
                                pack: pack,
                                colors: colors,
                                isOnline: _isOnline,
                                onOpen: () => _openTrailMap(pack),
                                onDownload: () => _startDownload(pack),
                                onTapCard: () => _openDetail(pack),
                              ),
                            ),
                          );
                        },
                        childCount: availablePacks.length,
                      ),
                    ),
                  ),
                ],
              ],

              // Bottom Spacer
              SliverToBoxAdapter(
                child: SizedBox(height: bottomInset + 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu satu paket gunung sesuai spesifikasi prompt.
class _MountainCard extends StatelessWidget {
  const _MountainCard({
    required this.pack,
    required this.colors,
    required this.isOnline,
    required this.onOpen,
    required this.onDownload,
    required this.onTapCard,
  });

  final MountainPack pack;
  final HiqeoColors colors;
  final bool isOnline;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final VoidCallback onTapCard;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.glassHighlight.withValues(alpha: 0.15),
            offset: const Offset(0, -1),
            blurRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: colors.glassFillFallback,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.glassBorder, width: 1.0),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTapCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Kiri: Thumbnail 64x64
                MountainThumbnail(pack: pack, colors: colors),
                const SizedBox(width: 12),

                // Tengah: Tiga Baris Informasi
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        pack.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pack.subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pack.statusText,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Kanan: Aksi (Belum diunduh / Mengunduh / Terunduh)
                _buildAction(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    switch (pack.status) {
      case MountainDownloadStatus.notDownloaded:
        return Semantics(
          button: true,
          label: 'Unduh paket ${pack.name}',
          child: GestureDetector(
            onTap: onDownload,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.hairline,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: HiqeoIcon(
                HiqeoIcons.download,
                size: 20,
                color: colors.textPrimary,
              ),
            ),
          ),
        );

      case MountainDownloadStatus.downloading:
        return Semantics(
          button: true,
          label: 'Mengunduh ${pack.name} ${(pack.progress * 100).round()}%',
          child: GestureDetector(
            onTap: onTapCard,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween:
                        Tween<double>(begin: pack.progress, end: pack.progress),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, value, _) {
                      return CircularProgressIndicator(
                        value: value,
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation(colors.primary),
                        backgroundColor: colors.hairline,
                      );
                    },
                  ),
                  HiqeoIcon(
                    HiqeoIcons.download,
                    size: 16,
                    color: colors.primary,
                  ),
                ],
              ),
            ),
          ),
        );

      case MountainDownloadStatus.downloaded:
        return Semantics(
          button: true,
          label: 'Buka peta ${pack.name}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              unawaited(HapticFeedback.selectionClick());
              onOpen();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: Center(
                widthFactor: 1.0,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    'Buka',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colors.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

      case MountainDownloadStatus.updateAvailable:
        return Semantics(
          button: true,
          label: 'Perbarui paket ${pack.name}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              unawaited(HapticFeedback.selectionClick());
              onTapCard();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: Center(
                widthFactor: 1.0,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colors.primary, width: 1),
                  ),
                  child: Text(
                    'Perbarui',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

      case MountainDownloadStatus.failed:
        return Semantics(
          button: true,
          label: 'Coba lagi unduh ${pack.name}',
          child: GestureDetector(
            onTap: onDownload,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        );
    }
  }
}

/// Thumbnail 64x64 CustomPainter dengan 3 elips kontur samar dan jalur GPX normalisasi.
class MountainThumbnail extends StatelessWidget {
  const MountainThumbnail({
    super.key,
    required this.pack,
    required this.colors,
  });

  final MountainPack pack;
  final HiqeoColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.hairline, width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: CustomPaint(
          size: const Size(64, 64),
          painter: _MountainThumbnailPainter(
            normalizedPoints: pack.normalizedPoints,
            colors: colors,
          ),
        ),
      ),
    );
  }
}

class _MountainThumbnailPainter extends CustomPainter {
  _MountainThumbnailPainter({
    required this.normalizedPoints,
    required this.colors,
  });

  final List<Offset> normalizedPoints;
  final HiqeoColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Tiga Elips Kontur Samar (textSecondary alfa 0,4)
    final contourPaint = Paint()
      ..color = colors.textSecondary.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Pusat puncak di (32, 22)
    final summit = Offset(w * 0.5, h * 0.35);

    // Kontur 1 (luar)
    canvas.drawOval(
      Rect.fromCenter(center: summit, width: w * 0.75, height: h * 0.45),
      contourPaint,
    );
    // Kontur 2 (tengah)
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(summit.dx, summit.dy + 1),
          width: w * 0.50,
          height: h * 0.30),
      contourPaint,
    );
    // Kontur 3 (puncak dalam)
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(summit.dx, summit.dy + 2),
          width: w * 0.26,
          height: h * 0.16),
      contourPaint,
    );

    // 2. Garis Jalur GPX (primary, 2,6 dp, ujung bulat)
    final trackPaint = Paint()
      ..color = colors.primary
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (normalizedPoints.length >= 2) {
      // Petakan titik normalisasi ke kotak dengan margin 12 dp
      const margin = 12.0;
      final usableW = w - (margin * 2);
      final usableH = h - (margin * 2);

      final first = normalizedPoints.first;
      path.moveTo(margin + (first.dx * usableW), margin + (first.dy * usableH));
      for (var i = 1; i < normalizedPoints.length; i++) {
        final pt = normalizedPoints[i];
        path.lineTo(margin + (pt.dx * usableW), margin + (pt.dy * usableH));
      }
    } else {
      // Jalur sederhana dari bounding box / kurva S ke arah puncak
      path.moveTo(w * 0.28, h * 0.82);
      path.cubicTo(
        w * 0.68,
        h * 0.68,
        w * 0.30,
        h * 0.52,
        summit.dx,
        summit.dy + 2,
      );
    }

    canvas.drawPath(path, trackPaint);
  }

  @override
  bool shouldRepaint(covariant _MountainThumbnailPainter oldDelegate) {
    return oldDelegate.normalizedPoints != normalizedPoints ||
        oldDelegate.colors != colors;
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.colors});

  final HiqeoColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.glassFillFallback,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 16,
                  width: 140,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 12,
                  width: 180,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 12,
                  width: 90,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
