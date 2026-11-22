import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/chat/presentation/chat_room_chrome.dart';
import '../../infrastructure/cache/avatar_disk_cache.dart';
import '../../infrastructure/storage/media_url_normalizer.dart';
import '../app_theme.dart';
import '../glass/hiqeo_liquid_glass.dart';
import 'account_badges.dart';
import 'hiqeo_back_button.dart';
import 'persistent_media_image.dart';

/// Tag animasi `Hero` konsisten antara foto profil bundar dan viewer layar penuh.
String profileAvatarHeroTag(String key) => 'profile-avatar-$key';

/// Membuka [FullscreenAvatarViewerPage] dengan latar fokus gelap dan transisi mulus.
Future<void> openFullscreenAvatarViewer(
  BuildContext context, {
  required String heroTag,
  required String displayName,
  String? avatarUrl,
  File? localFile,
  String? cacheKey,
  bool isOfficial = false,
  Widget Function(BuildContext context)? photoChildBuilder,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => FullscreenAvatarViewerPage(
        heroTag: heroTag,
        displayName: displayName,
        avatarUrl: avatarUrl,
        localFile: localFile,
        cacheKey: cacheKey,
        isOfficial: isOfficial,
        photoChildBuilder: photoChildBuilder,
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

/// Viewer foto profil layar penuh dengan [InteractiveViewer] (pinch-to-zoom & pan),
/// header Liquid Glass melayang (tombol kembali + nama + lencana terverifikasi),
/// serta pembacaan gambar beresolusi penuh tanpa downscale `cacheWidth`.
class FullscreenAvatarViewerPage extends StatefulWidget {
  const FullscreenAvatarViewerPage({
    super.key,
    required this.heroTag,
    required this.displayName,
    this.avatarUrl,
    this.localFile,
    this.cacheKey,
    this.isOfficial = false,
    this.photoChildBuilder,
  });

  final String heroTag;
  final String displayName;
  final String? avatarUrl;
  final File? localFile;
  final String? cacheKey;
  final bool isOfficial;
  final Widget Function(BuildContext context)? photoChildBuilder;

  @override
  State<FullscreenAvatarViewerPage> createState() =>
      _FullscreenAvatarViewerPageState();
}

class _FullscreenAvatarViewerPageState extends State<FullscreenAvatarViewerPage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  late final AnimationController _zoomAnimController;
  Animation<Matrix4>? _zoomAnimation;
  Offset? _doubleTapLocalPosition;

  bool _chromeVisible = true;
  double _dragOffsetY = 0;

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
  }

  @override
  void dispose() {
    _zoomAnimController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTapZoom() {
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

  Widget _buildFullResolutionImage() {
    if (widget.photoChildBuilder != null) {
      return widget.photoChildBuilder!(context);
    }

    final normalizedUrl = MediaUrlNormalizer.normalize(widget.avatarUrl);
    final local = widget.localFile;
    if (local != null && local.existsSync()) {
      return Image.file(
        local,
        key: const ValueKey<String>('avatar-viewer-image'),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _buildFallbackAvatar(),
      );
    }

    final cacheKey = widget.cacheKey?.trim();
    if (cacheKey != null && cacheKey.isNotEmpty) {
      final cachedFile =
          AvatarDiskCache.instance.cachedFileFor(cacheKey, normalizedUrl);
      if (cachedFile != null && cachedFile.existsSync()) {
        return Image.file(
          cachedFile,
          key: const ValueKey<String>('avatar-viewer-image'),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) {
            if (normalizedUrl != null && normalizedUrl.isNotEmpty) {
              return PersistentMediaImage(
                url: normalizedUrl,
                fit: BoxFit.contain,
                enableRetryOnTap: true,
                errorBuilder: (_) => _buildFallbackAvatar(),
              );
            }
            return _buildFallbackAvatar();
          },
        );
      }
    }

    if (normalizedUrl != null && normalizedUrl.isNotEmpty) {
      return PersistentMediaImage(
        key: const ValueKey<String>('avatar-viewer-network-image'),
        url: normalizedUrl,
        fit: BoxFit.contain,
        enableRetryOnTap: true,
        errorBuilder: (_) => _buildFallbackAvatar(),
      );
    }

    return _buildFallbackAvatar();
  }

  Widget _buildFallbackAvatar() {
    final trimmed = widget.displayName.trim();
    final initial = trimmed.isNotEmpty
        ? String.fromCharCode(trimmed.runes.first).toUpperCase()
        : 'P';
    return Container(
      width: 220,
      height: 220,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF2E3752),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 76,
            fontWeight: FontWeight.w800,
            color: ChatRoomPalette.textPrimary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dragProgress = (_dragOffsetY / 220.0).clamp(0.0, 1.0);
    final backdropAlpha = (1.0 - dragProgress * 0.65).clamp(0.25, 1.0);
    final mediaScale = 1.0 - dragProgress * 0.14;
    final photoScale = _transformController.value.getMaxScaleOnAxis();
    final canDragDismiss = photoScale <= 1.02;

    return Theme(
      data: hiqeoDarkTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).maybePop(),
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned.fill(
                  child: ColoredBox(
                    key: const ValueKey<String>('avatar-viewer-backdrop'),
                    color: Colors.black.withValues(alpha: backdropAlpha),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey<String>('avatar-viewer-canvas-tap'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        setState(() => _chromeVisible = !_chromeVisible),
                    onDoubleTapDown: (d) =>
                        _doubleTapLocalPosition = d.localPosition,
                    onDoubleTap: _handleDoubleTapZoom,
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
                        child: InteractiveViewer(
                          key: const ValueKey<String>(
                            'avatar-viewer-interactive',
                          ),
                          transformationController: _transformController,
                          panEnabled: photoScale > 1.02,
                          minScale: 1.0,
                          maxScale: 4.5,
                          onInteractionEnd: (_) {
                            if (mounted) setState(() {});
                          },
                          child: Center(
                            child: Hero(
                              tag: widget.heroTag,
                              child: _buildFullResolutionImage(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 14,
                  right: 14,
                  child: IgnorePointer(
                    ignoring: !_chromeVisible,
                    child: AnimatedOpacity(
                      key: const ValueKey<String>(
                        'avatar-viewer-header-opacity',
                      ),
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
                                    'avatar-viewer-back-button',
                                  ),
                                  onTap: () =>
                                      Navigator.of(context).maybePop(),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: HiqeoLiquidGlassSurface(
                                    key: const ValueKey<String>(
                                      'avatar-viewer-header-pill',
                                    ),
                                    borderRadius: 28,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Flexible(
                                          child: Text(
                                            widget.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  ChatRoomPalette.textPrimary,
                                              height: 1.2,
                                              shadows: ChatRoomPalette
                                                  .glassHeaderTextShadows,
                                            ),
                                          ),
                                        ),
                                        if (widget.isOfficial) ...<Widget>[
                                          const SizedBox(width: 6),
                                          const OfficialVerifiedBadge(
                                            key: ValueKey<String>(
                                              'avatar-viewer-official-badge',
                                            ),
                                            size: 17,
                                          ),
                                        ],
                                      ],
                                    ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
