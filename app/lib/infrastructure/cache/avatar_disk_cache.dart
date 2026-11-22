import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/hiqeo_http_overrides.dart';
import '../storage/media_url_normalizer.dart';
import 'hiqeo_media_cache_service.dart';

typedef AvatarSupportDirProvider = Future<Directory> Function();
typedef AvatarPrefsLoader = Future<SharedPreferences> Function();
typedef AvatarHttpGetFn = Future<http.Response> Function(
  Uri uri, {
  Map<String, String>? headers,
});

class _DiskAvatarEntry {
  const _DiskAvatarEntry({required this.url, required this.path});

  final String url;
  final String path;

  Map<String, String> toJson() => <String, String>{
        'url': url,
        'path': path,
      };
}

/// Cache gambar avatar persisten pada penyimpanan lokal (`ApplicationSupportDirectory`)
/// yang diindeks berdasarkan `cacheKey + hash(url)` sehingga foto profil teman,
/// anggota grup, pengguna komunitas, dan ikon komunitas tetap tampil tanpa
/// berkedip ketika perangkat offline.
class AvatarDiskCache extends ChangeNotifier {
  AvatarDiskCache({
    AvatarSupportDirProvider? supportDirProvider,
    AvatarPrefsLoader? prefsLoader,
    AvatarHttpGetFn? httpGet,
  })  : _supportDirProvider =
            supportDirProvider ?? getApplicationSupportDirectory,
        _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
        _hasCustomHttpGet = httpGet != null,
        _httpGet = httpGet ?? _defaultHttpGet;

  static final AvatarDiskCache instance = AvatarDiskCache();

  static const String _prefKey = 'hiqeo_avatar_disk_index_v1';
  static const String _folderName = 'avatar_disk_cache';

  final AvatarSupportDirProvider _supportDirProvider;
  final AvatarPrefsLoader _prefsLoader;
  final bool _hasCustomHttpGet;
  final AvatarHttpGetFn _httpGet;

  final Map<String, _DiskAvatarEntry> _entries = <String, _DiskAvatarEntry>{};
  final Map<String, File> _verifiedFiles = <String, File>{};
  final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};
  bool _initialized = false;
  Future<void>? _initFuture;

  static Future<http.Response> _defaultHttpGet(
    Uri uri, {
    Map<String, String>? headers,
  }) =>
      http.get(uri, headers: headers);

  static String _safeKey(String raw) =>
      raw.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  static String _urlHash(String url) {
    // FNV-1a 64-bit hash dalam Dart murni (sinkron & stabil).
    var hash = 0xcbf29ce484222325;
    for (final code in url.codeUnits) {
      hash ^= code;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(12, '0');
  }

  /// Memuat indeks avatar tersimpan dari [SharedPreferences] saat startup.
  Future<void> init() {
    if (_initialized) return Future<void>.value();
    return _initFuture ??= _initOnce();
  }

  Future<void> _initOnce() async {
    try {
      final prefs = await _prefsLoader();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            final key = e.key.toString();
            final val = e.value;
            if (val is! Map) continue;
            final url = val['url']?.toString() ?? '';
            final path = val['path']?.toString() ?? '';
            if (url.isEmpty || path.isEmpty) continue;
            final file = File(path);
            if (await file.exists()) {
              _entries[key] = _DiskAvatarEntry(url: url, path: path);
              _verifiedFiles[key] = file;
            }
          }
        }
      }
      _initialized = true;
      if (_verifiedFiles.isNotEmpty) {
        notifyListeners();
      }
    } catch (_) {
      _initialized = true;
    }
  }

  /// Mengembalikan berkas gambar lokal untuk [cacheKey] secara sinkron jika
  /// sudah terverifikasi di memori (tanpa I/O disk sinkron saat scroll).
  File? cachedFileFor(String cacheKey, String? url) {
    if (kIsWeb) return null;
    final key = cacheKey.trim();
    if (key.isEmpty) return null;

    final entry = _entries[key];
    if (entry == null) return null;
    return _verifiedFiles[key];
  }

  /// Mengembalikan `true` bila [normalizedUrl] perlu diunduh atau diperbarui.
  bool needsDownload(String cacheKey, String? normalizedUrl) {
    if (kIsWeb) return false;
    final key = cacheKey.trim();
    if (key.isEmpty || normalizedUrl == null || normalizedUrl.isEmpty) {
      return false;
    }
    if (!MediaUrlNormalizer.isNetworkUrl(normalizedUrl)) return false;
    final entry = _entries[key];
    if (entry == null || entry.url != normalizedUrl) return true;
    return !_verifiedFiles.containsKey(key);
  }

  /// Menandai berkas avatar hilang (mis. dibersihkan OS) dan mengeluarkannya
  /// dari indeks memori tanpa I/O sinkron di build().
  void markFileMissing(String cacheKey) {
    final key = cacheKey.trim();
    if (key.isEmpty) return;
    final removedVerified = _verifiedFiles.remove(key) != null;
    final removedEntry = _entries.remove(key) != null;
    if (removedVerified || removedEntry) {
      notifyListeners();
    }
  }

  /// Mengunduh (jika perlu) dan menyimpan avatar ke disk dengan deduplikasi
  /// berdasarkan `(cacheKey, normalizedUrl)`.
  Future<File?> ensureCached(String cacheKey, String? rawUrl) async {
    if (kIsWeb) return null;
    await init();

    final key = cacheKey.trim();
    final normalized = MediaUrlNormalizer.normalize(rawUrl);
    if (key.isEmpty ||
        normalized == null ||
        normalized.isEmpty ||
        !MediaUrlNormalizer.isNetworkUrl(normalized) ||
        (MediaUrlNormalizer.isPresignedOrPrivateR2Url(normalized) &&
            MediaUrlNormalizer.extractR2ObjectKey(normalized) == null)) {
      return cachedFileFor(key, normalized);
    }

    final currentEntry = _entries[key];
    if (currentEntry != null && currentEntry.url == normalized) {
      final existing = _verifiedFiles[key] ?? File(currentEntry.path);
      if (await existing.exists()) {
        _verifiedFiles[key] = existing;
        return existing;
      }
    }

    final flightKey = '$key|$normalized';
    final existingFlight = _inFlight[flightKey];
    if (existingFlight != null) return existingFlight;

    final future = _downloadAndPersist(key, normalized, currentEntry);
    _inFlight[flightKey] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(flightKey)?.ignore();
    }
  }

  Future<File?> _downloadAndPersist(
    String key,
    String normalizedUrl,
    _DiskAvatarEntry? previousEntry,
  ) async {
    try {
      final uri = Uri.tryParse(normalizedUrl);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return null;
      }
      final Uint8List? downloaded;
      if (!_hasCustomHttpGet) {
        downloaded =
            await HiqeoMediaCacheService.instance.downloadBytes(normalizedUrl);
      } else {
        final res = await _httpGet(
          uri,
          headers: const <String, String>{
            'User-Agent': HiqeoHttpOverrides.userAgent,
          },
        ).timeout(const Duration(seconds: 15));
        downloaded = (res.statusCode >= 200 &&
                res.statusCode < 300 &&
                res.bodyBytes.isNotEmpty)
            ? res.bodyBytes
            : null;
      }
      if (downloaded == null || downloaded.isEmpty) {
        return null;
      }

      final supportDir = await _supportDirProvider();
      final cacheDir = Directory(p.join(supportDir.path, _folderName));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final fileName = '${_safeKey(key)}_${_urlHash(normalizedUrl)}.img';
      final targetFile = File(p.join(cacheDir.path, fileName));
      await targetFile.writeAsBytes(downloaded, flush: true);

      if (previousEntry != null && previousEntry.path != targetFile.path) {
        final oldFile = File(previousEntry.path);
        try {
          await FileImage(oldFile).evict();
        } catch (_) {}
        try {
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (_) {}
      }

      try {
        await FileImage(targetFile).evict();
        await NetworkImage(normalizedUrl).evict();
      } catch (_) {}

      _entries[key] = _DiskAvatarEntry(
        url: normalizedUrl,
        path: targetFile.path,
      );
      _verifiedFiles[key] = targetFile;
      await _persistIndex();
      notifyListeners();
      return targetFile;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistIndex() async {
    try {
      final prefs = await _prefsLoader();
      final encoded = jsonEncode(<String, dynamic>{
        for (final e in _entries.entries) e.key: e.value.toJson(),
      });
      await prefs.setString(_prefKey, encoded);
    } catch (_) {}
  }

  /// Menghangatkan cache disk untuk banyak profil sekaligus di latar belakang.
  Future<void> warmAll(Map<String, String?> urlsByKey) async {
    if (kIsWeb || urlsByKey.isEmpty) return;
    await init();
    final tasks = <Future<File?>>[];
    for (final entry in urlsByKey.entries) {
      final url = MediaUrlNormalizer.normalize(entry.value);
      if (entry.key.trim().isEmpty || url == null || url.isEmpty) continue;
      if (!needsDownload(entry.key, url)) continue;
      tasks.add(ensureCached(entry.key, url));
      if (tasks.length >= 6) {
        await Future.wait(tasks);
        tasks.clear();
      }
    }
    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }
  }

  Future<void> clearAll() async {
    _entries.clear();
    _verifiedFiles.clear();
    _inFlight.clear();
    _initialized = false;
    _initFuture = null;
    notifyListeners();
    try {
      final prefs = await _prefsLoader();
      await prefs.remove(_prefKey);
    } catch (_) {}
    if (!kIsWeb) {
      try {
        final supportDir = await _supportDirProvider();
        final dir = Directory(p.join(supportDir.path, _folderName));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
}
