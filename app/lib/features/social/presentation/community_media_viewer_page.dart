import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../design/app_theme.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../../../design/widgets/persistent_media_image.dart';
import '../../../infrastructure/cache/hiqeo_media_cache_service.dart';
import '../../../infrastructure/network/hiqeo_http_overrides.dart';
import '../../../infrastructure/storage/media_url_normalizer.dart';
import '../../chat/presentation/chat_room_chrome.dart';
import '../data/community_media_tools.dart';
import '../data/community_service.dart';
import '../data/moderation_service.dart';
import 'community_chat_page.dart';

/// Membuka viewer media layar penuh dengan animasi transisi mulus (`Hero` + fade).
Future<void> openCommunityMediaViewer(
  BuildContext context, {
  required CommunityMessage message,
  String? currentUserId,
  Uint8List? initialThumbnailBytes,
  CommunityVideoThumbnailCache? thumbnailCache,
  Future<void> Function(CommunityMessage msg)? onReportMedia,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => CommunityMediaViewerPage(
        message: message,
        currentUserId: currentUserId,
        initialThumbnailBytes: initialThumbnailBytes,
        thumbnailCache: thumbnailCache,
        onReportMedia: onReportMedia,
      ),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: child,
        );
      },
    ),
  );
}

/// Viewer layar penuh (latar `#000000`, tanpa pemotongan) untuk foto & video
/// Ruang Obrolan Komunitas dengan header Liquid Glass 3 elemen.
class CommunityMediaViewerPage extends StatefulWidget {
  const CommunityMediaViewerPage({
    super.key,
    required this.message,
    this.currentUserId,
    this.initialThumbnailBytes,
    this.thumbnailCache,
    this.onReportMedia,
    this.photoChildBuilder,
    this.videoControllerBuilder,
    this.nowUtcOverride,
    this.saveToGalleryOverride,
    this.shareFileOverride,
  });

  final CommunityMessage message;
  final String? currentUserId;
  final Uint8List? initialThumbnailBytes;
  final CommunityVideoThumbnailCache? thumbnailCache;
  final Future<void> Function(CommunityMessage msg)? onReportMedia;

  /// Hook opsional untuk uji widget tanpa ketergantungan jaringan / platform.
  final Widget Function(BuildContext context)? photoChildBuilder;
  final VideoPlayerController? Function(String url)? videoControllerBuilder;
  final DateTime? nowUtcOverride;
  final Future<String?> Function({
    required String name,
    required String mimeType,
    String? filePath,
    Uint8List? bytes,
  })? saveToGalleryOverride;
  final Future<void> Function(String filePath)? shareFileOverride;

  @override
  State<CommunityMediaViewerPage> createState() =>
      _CommunityMediaViewerPageState();
}

class _CommunityMediaViewerPageState extends State<CommunityMediaViewerPage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  late final AnimationController _zoomAnimController;
  Animation<Matrix4>? _zoomAnimation;
  Offset? _doubleTapLocalPosition;

  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoPlaying = false;
  bool _videoMuted = false;
  bool _hasPlayedOnce = false;
  Duration _videoTotal = Duration.zero;
  Duration _videoPosition = Duration.zero;
  String _remainingBadgeText = '';

  Uint8List? _coverBytes;
  bool _chromeVisible = true;
  bool _menuOpen = false;
  bool _busyAction = false;
  double _dragOffsetY = 0;

  String? _topToastText;
  bool _topToastIsError = false;
  Timer? _topToastTimer;

  bool get _isVideo =>
      widget.message.messageType == CommunityMessageType.video;

  bool get _canReport =>
      widget.currentUserId == null ||
      widget.message.senderId != widget.currentUserId;

  @override
  void initState() {
    super.initState();
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_zoomAnimation != null) {
          _transformController.value = _zoomAnimation!.value;
        }
      });

    final thumbCache =
        widget.thumbnailCache ?? CommunityVideoThumbnailCache.instance;
    _coverBytes = widget.initialThumbnailBytes ??
        (widget.message.mediaUrl != null
            ? thumbCache.getMemoryBytes(
                widget.message.mediaUrl!,
                messageId: widget.message.id,
              )
            : null);

    _remainingBadgeText = formatVideoDurationSeconds(
      widget.message.mediaDurationSec ?? 0,
    );

    if (_isVideo) {
      unawaited(_initVideoAndCover());
    }
  }

  @override
  void dispose() {
    _topToastTimer?.cancel();
    _zoomAnimController.dispose();
    _transformController.dispose();
    final vc = _videoController;
    if (vc != null) {
      vc.removeListener(_onVideoTick);
      unawaited(vc.dispose().catchError((Object _) {}));
    }
    super.dispose();
  }

  Future<void> _initVideoAndCover() async {
    final rawUrl = widget.message.mediaUrl;
    final url = MediaUrlNormalizer.normalize(rawUrl) ?? rawUrl;
    if (url == null || url.isEmpty) return;

    final thumbCache =
        widget.thumbnailCache ?? CommunityVideoThumbnailCache.instance;
    if (_coverBytes == null) {
      final cached = await thumbCache.resolveThumbnail(
        videoUrl: url,
        thumbnailUrl: MediaUrlNormalizer.normalize(
          widget.message.mediaThumbnailUrl,
        ),
        messageId: widget.message.id,
      );
      if (mounted && cached != null) {
        setState(() => _coverBytes = cached);
      }
    }

    VideoPlayerController? controller;
    try {
      if (widget.videoControllerBuilder != null) {
        controller = widget.videoControllerBuilder!(url);
      } else {
        final source =
            await HiqeoMediaCacheService.instance.resolvePlayableVideoSource(
          url,
        );
        if (!mounted) return;
        if (source.file != null) {
          controller = VideoPlayerController.file(source.file!);
        } else {
          final streamUrl = source.streamUrl ?? url;
          controller = VideoPlayerController.networkUrl(
            Uri.parse(streamUrl),
            httpHeaders: const <String, String>{
              'User-Agent': HiqeoHttpOverrides.userAgent,
            },
          );
        }
      }
      if (controller == null) return;
      await controller.initialize().timeout(const Duration(seconds: 15));
      if (!mounted) {
        unawaited(controller.dispose().catchError((Object _) {}));
        return;
      }
      _videoController = controller;
      controller.addListener(_onVideoTick);
      await controller.setVolume(_videoMuted ? 0.0 : 1.0);
      await controller.play();
      if (!mounted) return;
      _hasPlayedOnce = true;
      _syncVideoState(controller);
    } catch (_) {
      _videoController = null;
      if (controller != null) {
        controller.removeListener(_onVideoTick);
        unawaited(controller.dispose().catchError((Object _) {}));
      }
    }
  }

  void _onVideoTick() {
    final c = _videoController;
    if (c == null || !mounted) return;
    final val = c.value;
    if (val.isPlaying) _hasPlayedOnce = true;

    // Ketika video selesai memutar, kembalikan ke posisi awal & total durasi asli.
    if (_hasPlayedOnce &&
        val.isInitialized &&
        !val.isPlaying &&
        val.duration > Duration.zero &&
        val.position >= val.duration - const Duration(milliseconds: 120)) {
      _hasPlayedOnce = false;
      unawaited(
        c.seekTo(Duration.zero).then((_) async {
          await c.pause();
          if (mounted) _syncVideoState(c);
        }),
      );
      return;
    }

    _syncVideoState(c);
  }

  void _syncVideoState(VideoPlayerController c) {
    final v = c.value;
    final nextBadge = formatVideoRemainingBadge(
      total: v.duration,
      position: v.position,
      isPlaying: v.isPlaying,
      fallbackTotalSec: widget.message.mediaDurationSec,
    );
    if (!mounted) return;
    if (_videoInitialized == v.isInitialized &&
        _videoPlaying == v.isPlaying &&
        _videoTotal == v.duration &&
        _videoPosition == v.position &&
        _remainingBadgeText == nextBadge) {
      return;
    }
    setState(() {
      _videoInitialized = v.isInitialized;
      _videoPlaying = v.isPlaying;
      _videoTotal = v.duration;
      _videoPosition = v.position;
      _remainingBadgeText = nextBadge;
    });
  }

  Future<void> _togglePlayPause() async {
    final c = _videoController;
    if (c == null || !_videoInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      if (c.value.duration > Duration.zero &&
          c.value.position >= c.value.duration - const Duration(milliseconds: 120)) {
        await c.seekTo(Duration.zero);
      }
      _hasPlayedOnce = true;
      await c.play();
    }
  }

  Future<void> _toggleMute() async {
    final c = _videoController;
    final nextMuted = !_videoMuted;
    setState(() => _videoMuted = nextMuted);
    if (c != null) {
      await c.setVolume(nextMuted ? 0.0 : 1.0);
    }
  }

  void _toggleChrome() {
    setState(() {
      if (_menuOpen) {
        _menuOpen = false;
      } else {
        _chromeVisible = !_chromeVisible;
      }
    });
  }

  void _handleDoubleTapZoom() {
    if (_isVideo) return;
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final Matrix4 target;
    if (currentScale > 1.05) {
      target = Matrix4.identity();
    } else {
      const zoom = 2.5;
      final tap = _doubleTapLocalPosition ?? Offset.zero;
      target = Matrix4.identity()
        ..translateByDouble(-tap.dx * (zoom - 1), -tap.dy * (zoom - 1), 0, 1)
        ..scaleByDouble(zoom, zoom, 1, 1);
    }
    _zoomAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: target,
    ).animate(
      CurvedAnimation(parent: _zoomAnimController, curve: Curves.easeOutCubic),
    );
    _zoomAnimController.forward(from: 0);
  }

  void _showTopToast(String message, {bool isError = false}) {
    if (!mounted) return;
    _topToastTimer?.cancel();
    setState(() {
      _topToastText = message;
      _topToastIsError = isError;
    });
    _topToastTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _topToastText = null);
    });
  }

  Future<File?> _resolveLocalMediaFile() async {
    final rawUrl = widget.message.mediaUrl;
    final url = MediaUrlNormalizer.normalize(rawUrl) ?? rawUrl;
    if (url == null || url.isEmpty) return null;
    if (!MediaUrlNormalizer.isNetworkUrl(url)) {
      final direct = File(url);
      if (await direct.exists()) return direct;
    }

    final cached = await HiqeoMediaCacheService.instance.resolveMediaFile(url);
    if (cached != null && await cached.exists()) {
      return cached;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    final res = await http.get(
      uri,
      headers: const <String, String>{
        'User-Agent': HiqeoHttpOverrides.userAgent,
      },
    ).timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300 || res.bodyBytes.isEmpty) {
      return null;
    }
    final dir = await getTemporaryDirectory();
    final ext = _isVideo
        ? (p.extension(uri.path).isNotEmpty ? p.extension(uri.path) : '.mp4')
        : (p.extension(uri.path).isNotEmpty ? p.extension(uri.path) : '.webp');
    final outFile = File(p.join(dir.path, 'hiqeo_${widget.message.id}$ext'));
    await outFile.writeAsBytes(res.bodyBytes, flush: true);
    return outFile;
  }

  Future<void> _saveToGallery() async {
    if (_busyAction) return;
    setState(() {
      _menuOpen = false;
      _busyAction = true;
    });
    try {
      final file = await _resolveLocalMediaFile();
      if (file == null) {
        _showTopToast('Media belum tersedia untuk disimpan.', isError: true);
        return;
      }
      final ext = p.extension(file.path).toLowerCase();
      final mime = _isVideo
          ? (ext == '.webm' ? 'video/webm' : 'video/mp4')
          : (ext == '.png'
              ? 'image/png'
              : ext == '.webp'
                  ? 'image/webp'
                  : 'image/jpeg');
      final fileName = 'Hiqeo_${widget.message.id}$ext';
      final saveFn = widget.saveToGalleryOverride ??
          CommunityMediaChannel.saveMediaToGallery;
      final saved = await saveFn(
        name: fileName,
        mimeType: mime,
        filePath: file.path,
      );
      if (!mounted) return;
      if (saved != null && saved.isNotEmpty) {
        _showTopToast('Media disimpan ke galeri.');
      } else {
        _showTopToast(
          'Gagal menyimpan langsung ke galeri. Gunakan menu Bagikan.',
          isError: true,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityMediaViewer._saveToGallery failed: $e');
      }
      _showTopToast('Media belum bisa disimpan ke galeri.', isError: true);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _shareMedia() async {
    if (_busyAction) return;
    setState(() {
      _menuOpen = false;
      _busyAction = true;
    });
    try {
      final file = await _resolveLocalMediaFile();
      if (file == null) {
        _showTopToast('Media tidak tersedia untuk dibagikan.', isError: true);
        return;
      }
      if (widget.shareFileOverride != null) {
        await widget.shareFileOverride!(file.path);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: <XFile>[XFile(file.path)],
            subject: 'Media Komunitas Hiqeo',
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityMediaViewer._shareMedia failed: $e');
      }
      _showTopToast('Media belum bisa dibagikan saat ini.', isError: true);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _reportMedia() async {
    setState(() => _menuOpen = false);
    if (widget.onReportMedia != null) {
      await widget.onReportMedia!(widget.message);
      return;
    }
    final msg = widget.message;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (_) => CommunityReportDialog(
        title: 'Laporkan media',
        subtitle: 'Laporkan media dari ${msg.senderName} ke tim moderasi.',
        onSubmit: (reason, details) => ModerationService.instance.submitReport(
          targetType: ModerationTargetType.communityMessage,
          targetId: msg.id,
          communityId: msg.communityId,
          reportedUserId: msg.senderId,
          reason: reason,
          details: details,
          messageExcerpt: msg.content ?? '[${msg.messageType.name}]',
        ),
      ),
    );
    if (submitted == true) {
      _showTopToast('Laporan dikirim ke tim moderasi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final dragProgress = (_dragOffsetY / 220.0).clamp(0.0, 1.0);
    final backdropAlpha = (1.0 - dragProgress * 0.65).clamp(0.25, 1.0);
    final mediaScale = 1.0 - dragProgress * 0.14;
    final photoScale = _transformController.value.getMaxScaleOnAxis();
    final canDragDismiss = _isVideo || photoScale <= 1.02;
    final timestampText = formatCommunityMediaTimestamp(
      widget.message.createdAt,
      widget.nowUtcOverride,
    );

    return Theme(
      data: hiqeoDarkTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: PopScope(
          canPop: !_menuOpen,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _menuOpen) {
              setState(() => _menuOpen = false);
            }
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // Latar hitam murni #000000 saat diam
                Positioned.fill(
                  child: ColoredBox(
                    key: const ValueKey<String>('media-viewer-backdrop'),
                    color: Colors.black.withValues(alpha: backdropAlpha),
                  ),
                ),

                // Konten Media Utama (tap kosong -> toggle UI, geser bawah -> tutup)
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey<String>('media-viewer-canvas-tap'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleChrome,
                    onDoubleTapDown: (d) =>
                        _doubleTapLocalPosition = d.localPosition,
                    onDoubleTap: _isVideo ? null : _handleDoubleTapZoom,
                    onVerticalDragUpdate: canDragDismiss
                        ? (details) {
                            final next = (_dragOffsetY + details.delta.dy)
                                .clamp(0.0, 420.0);
                            if (next != _dragOffsetY) {
                              setState(() => _dragOffsetY = next);
                            }
                          }
                        : null,
                    onVerticalDragEnd: canDragDismiss
                        ? (details) {
                            final velocity = details.primaryVelocity ?? 0;
                            if (_dragOffsetY > 110 || velocity > 650) {
                              Navigator.of(context).pop();
                            } else {
                              setState(() => _dragOffsetY = 0);
                            }
                          }
                        : null,
                    child: Transform.translate(
                      offset: Offset(0, _dragOffsetY),
                      child: Transform.scale(
                        scale: mediaScale,
                        child: _buildMediaViewport(),
                      ),
                    ),
                  ),
                ),

                // Header Liquid Glass 3 Elemen di Atas (dalam SafeArea)
                Positioned(
                  top: 0,
                  left: 14,
                  right: 14,
                  child: IgnorePointer(
                    ignoring: !_chromeVisible,
                    child: AnimatedOpacity(
                      key: const ValueKey<String>('media-viewer-header-opacity'),
                      opacity: _chromeVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: ChatRoomHeaderBar.topMargin,
                          ),
                          child: SizedBox(
                            height: ChatRoomHeaderBar.height,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                HiqeoBackButton(
                                  key: const ValueKey<String>(
                                    'media-viewer-back-button',
                                  ),
                                  onTap: () => Navigator.of(context).maybePop(),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: HiqeoLiquidGlassSurface(
                                    key: const ValueKey<String>(
                                      'media-viewer-header-pill',
                                    ),
                                    borderRadius: 28,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 7,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          widget.message.senderName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            color: ChatRoomPalette.textPrimary,
                                            height: 1.2,
                                            shadows: ChatRoomPalette
                                                .glassHeaderTextShadows,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          timestampText,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color:
                                                ChatRoomPalette.textSecondary,
                                            height: 1.2,
                                            shadows: ChatRoomPalette
                                                .glassHeaderTextShadows,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                HiqeoGlassCircleButton(
                                  key: const ValueKey<String>(
                                    'media-viewer-hamburger-button',
                                  ),
                                  semanticsLabel: 'Menu media',
                                  onTap: () =>
                                      setState(() => _menuOpen = !_menuOpen),
                                  child: const Icon(
                                    Icons.menu_rounded,
                                    size: 20,
                                    color: ChatRoomPalette.textPrimary,
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

                // Kontrol Pemutar Video Bawah (khusus video)
                if (_isVideo)
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: bottomPad + 14,
                    child: IgnorePointer(
                      ignoring: !_chromeVisible,
                      child: AnimatedOpacity(
                        key: const ValueKey<String>(
                          'media-viewer-controls-opacity',
                        ),
                        opacity: _chromeVisible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 220),
                        child: _buildVideoControlBar(),
                      ),
                    ),
                  ),

                // Toast info/galat melayang
                if (_topToastText != null)
                  Positioned(
                    top: ChatRoomHeaderBar.dropdownTop(topPad),
                    left: 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: () => setState(() => _topToastText = null),
                      child: HiqeoLiquidGlassSurface(
                        borderRadius: 18,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              _topToastIsError
                                  ? Icons.error_outline_rounded
                                  : Icons.check_circle_outline_rounded,
                              size: 18,
                              color: _topToastIsError
                                  ? ChatRoomPalette.destructiveRed
                                  : ChatRoomPalette.statusOnline,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _topToastText!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: ChatRoomPalette.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Menu Dropdown Liquid Glass 12 px di bawah tombol Hamburger
                if (_menuOpen && _chromeVisible) ...<Widget>[
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey<String>(
                        'media-viewer-dropdown-scrim',
                      ),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _menuOpen = false),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Positioned(
                    top: ChatRoomHeaderBar.dropdownTop(topPad),
                    right: 14,
                    child: ChatRoomDropdownMenu(
                      menuKey: const ValueKey<String>(
                        'media-viewer-dropdown-menu',
                      ),
                      entries: <ChatRoomMenuEntry>[
                        ChatRoomMenuEntry.item(
                          key: const ValueKey<String>('media-menu-save'),
                          icon: Icons.download_rounded,
                          label: 'Simpan ke galeri',
                          onTap: () => unawaited(_saveToGallery()),
                        ),
                        ChatRoomMenuEntry.item(
                          key: const ValueKey<String>('media-menu-share'),
                          icon: Icons.share_rounded,
                          label: 'Bagikan',
                          onTap: () => unawaited(_shareMedia()),
                        ),
                        if (_canReport) ...<ChatRoomMenuEntry>[
                          const ChatRoomMenuEntry.divider(),
                          ChatRoomMenuEntry.item(
                            key: const ValueKey<String>('media-menu-report'),
                            icon: Icons.flag_outlined,
                            label: 'Laporkan media',
                            destructive: true,
                            onTap: () => unawaited(_reportMedia()),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaViewport() {
    final url = widget.message.mediaUrl ?? '';
    final heroTag = communityMediaHeroTag(widget.message.id);
    if (_isVideo) {
      final vc = _videoController;
      return Center(
        child: Hero(
          tag: heroTag,
          child: (_videoInitialized && vc != null)
              ? AspectRatio(
                  aspectRatio:
                      vc.value.aspectRatio > 0 ? vc.value.aspectRatio : 16 / 9,
                  child: VideoPlayer(vc),
                )
              : (_coverBytes != null
                  ? Image.memory(_coverBytes!, fit: BoxFit.contain)
                  : const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white70,
                        strokeWidth: 2.2,
                      ),
                    )),
        ),
      );
    }

    final normalizedUrl = MediaUrlNormalizer.normalize(url) ?? url;
    final isLocalFile = !MediaUrlNormalizer.isNetworkUrl(normalizedUrl) &&
        File(normalizedUrl).existsSync();
    final Widget imageWidget = widget.photoChildBuilder?.call(context) ??
        (isLocalFile
            ? Image.file(File(normalizedUrl), fit: BoxFit.contain)
            : PersistentMediaImage(
                url: normalizedUrl,
                fit: BoxFit.contain,
                errorBuilder: (_) => const Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: Colors.white54,
                ),
              ));

    final photoScale = _transformController.value.getMaxScaleOnAxis();
    return InteractiveViewer(
      key: const ValueKey<String>('media-viewer-interactive'),
      transformationController: _transformController,
      panEnabled: photoScale > 1.02,
      minScale: 1.0,
      maxScale: 4.0,
      onInteractionEnd: (_) {
        if (mounted) setState(() {});
      },
      child: Center(
        child: Hero(
          tag: heroTag,
          child: imageWidget,
        ),
      ),
    );
  }

  Widget _buildVideoControlBar() {
    final totalMs = _videoTotal.inMilliseconds;
    final posMs = _videoPosition.inMilliseconds.clamp(
      0,
      totalMs > 0 ? totalMs : 1,
    );
    final progress = totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;

    return HiqeoLiquidGlassSurface(
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const ValueKey<String>('media-viewer-play-pause'),
            visualDensity: VisualDensity.compact,
            onPressed: _togglePlayPause,
            icon: Icon(
              _videoPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: ChatRoomPalette.textPrimary,
              size: 26,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: ChatRoomPalette.textPrimary,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                thumbColor: ChatRoomPalette.textPrimary,
              ),
              child: Slider(
                key: const ValueKey<String>('media-viewer-scrubber'),
                value: progress,
                onChanged: (_videoInitialized && totalMs > 0)
                    ? (v) {
                        final target = Duration(
                          milliseconds: (v * totalMs).round(),
                        );
                        unawaited(_videoController?.seekTo(target));
                      }
                    : null,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey<String>('media-viewer-mute'),
            visualDensity: VisualDensity.compact,
            onPressed: _toggleMute,
            icon: Icon(
              _videoMuted
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              color: ChatRoomPalette.textPrimary,
              size: 21,
            ),
          ),
          Container(
            key: const ValueKey<String>('media-viewer-video-remaining'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _remainingBadgeText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
