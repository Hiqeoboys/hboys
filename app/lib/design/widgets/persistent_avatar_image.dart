import 'dart:async';

import 'package:flutter/material.dart';

import '../../infrastructure/cache/avatar_disk_cache.dart';
import '../../infrastructure/cache/public_profile_cache_service.dart';
import '../../infrastructure/storage/media_url_normalizer.dart';
import 'persistent_media_image.dart';

/// Widget avatar melingkar dengan cache disk persisten ([AvatarDiskCache]) dan
/// resolusi profil dinamis ([PublicProfileCacheService]) agar foto pengguna &
/// komunitas langsung tampil, segera berubah saat profil diperbarui, dan tetap
/// muncul ketika perangkat offline tanpa berkedip kosong.
class PersistentAvatarImage extends StatelessWidget {
  const PersistentAvatarImage({
    super.key,
    required this.cacheKey,
    this.avatarUrl,
    required this.size,
    required this.fallback,
    this.backgroundColor,
    this.border,
    this.resolveFromProfileCache = true,
  });

  final String cacheKey;
  final String? avatarUrl;
  final double size;
  final Widget fallback;
  final Color? backgroundColor;
  final BoxBorder? border;
  final bool resolveFromProfileCache;

  @override
  Widget build(BuildContext context) {
    final diskCache = AvatarDiskCache.instance;
    final profileCache = PublicProfileCacheService.instance;
    final listenable = resolveFromProfileCache
        ? Listenable.merge(<Listenable>[profileCache, diskCache])
        : diskCache;

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final effectiveUrl = resolveFromProfileCache
            ? profileCache.resolveAvatarUrl(cacheKey, fallback: avatarUrl)
            : MediaUrlNormalizer.normalize(avatarUrl);
        final cachedFile = diskCache.cachedFileFor(cacheKey, effectiveUrl);

        if (effectiveUrl != null &&
            diskCache.needsDownload(cacheKey, effectiveUrl)) {
          unawaited(diskCache.ensureCached(cacheKey, effectiveUrl));
        }

        final decodeWidth = (size * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(48, 256);
        final Widget content;
        if (cachedFile != null) {
          content = Image.file(
            cachedFile,
            width: size,
            height: size,
            cacheWidth: decodeWidth,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => diskCache.markFileMissing(cacheKey),
              );
              if (effectiveUrl != null && effectiveUrl.isNotEmpty) {
                return PersistentMediaImage(
                  url: effectiveUrl,
                  width: size,
                  height: size,
                  cacheWidth: decodeWidth,
                  fit: BoxFit.cover,
                  enableRetryOnTap: false,
                  placeholder: fallback,
                  errorBuilder: (_) => fallback,
                );
              }
              return fallback;
            },
          );
        } else if (effectiveUrl != null && effectiveUrl.isNotEmpty) {
          content = PersistentMediaImage(
            url: effectiveUrl,
            width: size,
            height: size,
            cacheWidth: decodeWidth,
            fit: BoxFit.cover,
            enableRetryOnTap: false,
            placeholder: fallback,
            errorBuilder: (_) => fallback,
          );
        } else {
          content = fallback;
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: backgroundColor,
            border: border,
          ),
          clipBehavior: Clip.antiAlias,
          child: content,
        );
      },
    );
  }
}
