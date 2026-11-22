import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../infrastructure/cache/hiqeo_media_cache_service.dart';
import '../tokens.dart';

/// Widget gambar persisten offline & online untuk media komunitas dan avatar.
///
/// Mengunduh gambar lewat [HiqeoMediaCacheService] (dengan fallback IPv4 TLS
/// serta proxy Edge Function `r2-presign`), menyimpannya di disk agar tampil saat
/// offline maupun online, dan menyediakan ketuk-untuk-muat-ulang pada kegagalan
/// sementara.
class PersistentMediaImage extends StatefulWidget {
  const PersistentMediaImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorBuilder,
    this.cacheWidth,
    this.cacheHeight,
    this.enableRetryOnTap = true,
    this.cacheService,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadiusGeometry? borderRadius;
  final Widget? placeholder;
  final Widget Function(BuildContext context)? errorBuilder;
  final int? cacheWidth;
  final int? cacheHeight;
  final bool enableRetryOnTap;
  final HiqeoMediaCacheService? cacheService;

  @override
  State<PersistentMediaImage> createState() => _PersistentMediaImageState();
}

class _PersistentMediaImageState extends State<PersistentMediaImage> {
  File? _file;
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;

  HiqeoMediaCacheService get _service =>
      widget.cacheService ?? HiqeoMediaCacheService.instance;

  @override
  void initState() {
    super.initState();
    _resolve(forceRefresh: false);
  }

  @override
  void didUpdateWidget(covariant PersistentMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.cacheService != widget.cacheService) {
      _file = null;
      _failed = false;
      _resolve(forceRefresh: false);
    }
  }

  void _resolve({required bool forceRefresh}) {
    final url = widget.url?.trim();
    if (url == null || url.isEmpty) {
      setState(() {
        _file = null;
        _loading = false;
        _failed = true;
      });
      return;
    }

    if (!forceRefresh) {
      final syncHit = _service.cachedFileSync(url);
      if (syncHit != null) {
        _file = syncHit;
        _loading = false;
        _failed = false;
        return;
      }
    }

    final gen = ++_generation;
    _loading = true;
    _failed = false;

    unawaited(() async {
      final resolved = await _service.resolveMediaFile(
        url,
        forceRefresh: forceRefresh,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _file = resolved;
        _loading = false;
        _failed = resolved == null;
      });
    }());
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final file = _file;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final int? effectiveCacheWidth = widget.cacheWidth ??
        (widget.width != null && widget.width!.isFinite && widget.width! > 0
            ? (widget.width! * dpr).round().clamp(64, 1080)
            : null);
    final int? effectiveCacheHeight = widget.cacheHeight ??
        (effectiveCacheWidth == null &&
                widget.height != null &&
                widget.height!.isFinite &&
                widget.height! > 0
            ? (widget.height! * dpr).round().clamp(64, 1080)
            : null);

    Widget child;
    if (file != null) {
      child = Image.file(
        file,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: effectiveCacheWidth,
        cacheHeight: effectiveCacheHeight,
        filterQuality:
            effectiveCacheWidth == null ? FilterQuality.high : FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _service.evictMemoryEntry(widget.url);
            unawaited(() async {
              try {
                if (await file.exists()) await file.delete();
              } catch (_) {}
            }());
            setState(() {
              _file = null;
              _failed = true;
            });
          });
          return _buildErrorFallback(context, colors);
        },
      );
    } else if (_failed) {
      child = _buildErrorFallback(context, colors);
    } else {
      child = widget.placeholder ??
          Container(
            width: widget.width,
            height: widget.height,
            color: colors.surface,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
    }

    if (widget.borderRadius != null) {
      child = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: child,
      );
    }
    return child;
  }

  Widget _buildErrorFallback(BuildContext context, HiqeoColors colors) {
    final fallback = widget.errorBuilder?.call(context) ??
        Container(
          width: widget.width,
          height: widget.height,
          color: colors.surface,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.broken_image_outlined,
                  size: 26,
                  color: colors.textSecondary,
                ),
                if (widget.enableRetryOnTap) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Ketuk muat ulang',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

    if (!widget.enableRetryOnTap || _loading) {
      return fallback;
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          _failed = false;
          _loading = true;
        });
        _resolve(forceRefresh: true);
      },
      child: fallback,
    );
  }
}
