import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/application/account_controller.dart';
import '../../features/social/data/community_media_tools.dart';

/// Mengelola pembatalan cache media/avatar secara otomatis satu kali setiap kali
/// versi aplikasi bertambah atau skema cache dinaikkan (mis. update APK tanpa uninstall).
class MediaCacheManager {
  MediaCacheManager({
    Future<SharedPreferences> Function()? prefsLoader,
    Future<String> Function()? appVersionReader,
    Future<Directory> Function()? supportDirProvider,
    Future<Directory> Function()? tempDirProvider,
    VoidCallback? onClearImageCache,
  })  : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
        _appVersionReader =
            appVersionReader ?? CommunityMediaChannel.getAppVersion,
        _supportDirProvider =
            supportDirProvider ?? getApplicationSupportDirectory,
        _tempDirProvider = tempDirProvider ?? getTemporaryDirectory,
        _onClearImageCache = onClearImageCache ?? _defaultClearImageCache;

  static final MediaCacheManager instance = MediaCacheManager();

  static const int cacheSchemaVersion = 2;
  static const String _prefKey = 'hiqeo_media_cache_version_v1';

  final Future<SharedPreferences> Function() _prefsLoader;
  final Future<String> Function() _appVersionReader;
  final Future<Directory> Function() _supportDirProvider;
  final Future<Directory> Function() _tempDirProvider;
  final VoidCallback _onClearImageCache;

  static void _defaultClearImageCache() {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
  }

  /// Memeriksa versi cache/aplikasi saat startup. Bila berbeda dari sesi
  /// sebelumnya, membersihkan cache thumbnail, avatar, dan temp media lama
  /// tanpa menyentuh peta offline Mapbox maupun database SQLite.
  Future<bool> ensureCacheUpToDate() async {
    try {
      final prefs = await _prefsLoader();
      final appVersion = await _appVersionReader();
      final targetMarker = '$cacheSchemaVersion|$appVersion';
      final stored = prefs.getString(_prefKey);
      if (stored == targetMarker) {
        return false;
      }

      _onClearImageCache();
      CommunityVideoThumbnailCache.instance.clearMemoryCache();
      AccountController.evictLocalAvatarFileCache();

      if (!kIsWeb) {
        await _clearSupportMediaDirs();
        await _clearTempMediaCaches();
      }

      await prefs.setString(_prefKey, targetMarker);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearSupportMediaDirs() async {
    try {
      final supportDir = await _supportDirProvider();
      for (final folderName in const <String>[
        'community_video_thumbs',
        'avatar_cache',
      ]) {
        final dir = Directory(p.join(supportDir.path, folderName));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (_) {}
  }

  Future<void> _clearTempMediaCaches() async {
    try {
      final tempDir = await _tempDirProvider();
      for (final folderName in const <String>[
        'libCachedImageData',
        'image_cache',
      ]) {
        final dir = Directory(p.join(tempDir.path, folderName));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(followLinks: false)) {
          final name = p.basename(entity.path);
          if (name.startsWith('hiqeo_')) {
            try {
              await entity.delete(recursive: true);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
}
