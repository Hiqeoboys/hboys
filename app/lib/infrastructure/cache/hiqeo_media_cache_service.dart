import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/config/supabase_config.dart';
import '../storage/media_url_normalizer.dart';
import '../supabase/supabase_services.dart';

typedef MediaHttpFetcher = Future<({int statusCode, Uint8List bytes})>
    Function(Uri uri);
typedef MediaEdgeProxyFetcher = Future<({int statusCode, Uint8List bytes})>
    Function(String objectKey);
typedef MediaEdgeGetUrlFetcher = Future<String?> Function(String objectKey);
typedef MediaCacheDirResolver = Future<Directory> Function();

class _FailureBackoff {
  const _FailureBackoff({required this.strikes, required this.retryAfterUtc});

  final int strikes;
  final DateTime retryAfterUtc;
}

/// Cache media persisten offline/online untuk foto profil, avatar komunitas,
/// foto & video obrolan komunitas.
///
/// Menangani kegagalan spesifik Android 14–16 & ISP Indonesia:
/// 1. Upgrade `http://` -> `https://` sebelum mengunduh.
/// 2. Direct HTTPS dengan User-Agent standar & `Connection: close`.
/// 3. Fallback socket IPv4 eksplisit (`Socket.connect(ipv4)` + `SecureSocket.secure`
///    dengan SNI hostname penuh) ketika dual-stack IPv6 perangkat menggantung.
/// 4. Fallback Edge Function `r2-presign` (`action: 'proxy'` dan `'get-url'`)
///    bila domain publik `pub-*.r2.dev` diblokir DNS/ISP atau URL sudah expired.
/// 5. Kegagalan sementara TIDAK pernah disimpan ke disk secara permanen dan hanya
///    dikenai cooldown singkat yang langsung di-reset saat koneksi pulih / tap.
class HiqeoMediaCacheService {
  HiqeoMediaCacheService({
    MediaHttpFetcher? httpFetcher,
    MediaEdgeProxyFetcher? edgeProxyFetcher,
    MediaEdgeGetUrlFetcher? edgeGetUrlFetcher,
    MediaCacheDirResolver? cacheDirResolver,
    DateTime Function()? nowUtc,
  })  : _httpFetcher = httpFetcher,
        _edgeProxyFetcher = edgeProxyFetcher,
        _edgeGetUrlFetcher = edgeGetUrlFetcher,
        _cacheDirResolver = cacheDirResolver,
        _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  static final HiqeoMediaCacheService instance = HiqeoMediaCacheService();

  static const int _maxDiskBytes = 200 * 1024 * 1024;
  static const int _maxDownloadBytes = 25 * 1024 * 1024;
  static const Duration _directTimeout = Duration(seconds: 8);
  static const Duration _proxyTimeout = Duration(seconds: 12);

  final MediaHttpFetcher? _httpFetcher;
  final MediaEdgeProxyFetcher? _edgeProxyFetcher;
  final MediaEdgeGetUrlFetcher? _edgeGetUrlFetcher;
  final MediaCacheDirResolver? _cacheDirResolver;
  final DateTime Function() _nowUtc;

  final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};
  final Map<String, File> _memoryFileCache = <String, File>{};
  final Map<String, _FailureBackoff> _failureBackoffs =
      <String, _FailureBackoff>{};

  Directory? _dir;
  int _r2DevDirectFailCount = 0;
  bool _r2DevDirectBlocked = false;

  @visibleForTesting
  bool get isR2DevDirectBypassedForSession => _r2DevDirectBlocked;

  Future<Directory?> _ensureDir() async {
    if (kIsWeb) return null;
    if (_dir != null) return _dir;
    try {
      final base =
          await (_cacheDirResolver?.call() ?? getApplicationSupportDirectory());
      final dir =
          Directory('${base.path}${Platform.pathSeparator}hiqeo_media_cache_v1');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _dir = dir;
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Menghapus seluruh cooldown error sementara (mis. saat konektivitas kembali
  /// online atau pengguna mengetuk untuk mencoba ulang).
  void clearFailureCooldowns() {
    _failureBackoffs.clear();
  }

  void clearFailureCooldownForUrl(String? url) {
    final normalized = MediaUrlNormalizer.normalize(url);
    if (normalized != null) {
      _failureBackoffs.remove(normalized);
    }
  }

  @visibleForTesting
  void resetSessionState() {
    _inFlight.clear();
    _memoryFileCache.clear();
    _failureBackoffs.clear();
    _dir = null;
    _r2DevDirectFailCount = 0;
    _r2DevDirectBlocked = false;
  }

  /// Cek sinkron O(1) dari indeks memori apakah media sudah siap dirender
  /// pada frame pertama tanpa I/O disk sinkron.
  File? cachedFileSync(String? url) {
    if (kIsWeb) return null;
    final normalized = MediaUrlNormalizer.normalize(url);
    if (normalized == null || !MediaUrlNormalizer.isNetworkUrl(normalized)) {
      return null;
    }
    return _memoryFileCache[normalized];
  }

  /// Menghapus entri memori untuk [url] saat berkas ditemukan rusak/hilang.
  void evictMemoryEntry(String? url) {
    final normalized = MediaUrlNormalizer.normalize(url);
    if (normalized != null) {
      _memoryFileCache.remove(normalized);
    }
  }

  /// Mengembalikan berkas cache persisten untuk [url] (baik saat offline maupun
  /// online). Bila belum tersedia lokal, mengunduh dengan fallback IPv4 & R2
  /// Edge Function lalu menyimpannya secara atomik ke disk.
  Future<File?> resolveMediaFile(
    String? url, {
    bool forceRefresh = false,
  }) async {
    if (kIsWeb) return null;
    final normalized = MediaUrlNormalizer.normalize(url);
    if (normalized == null || !MediaUrlNormalizer.isNetworkUrl(normalized)) {
      return null;
    }

    if (!forceRefresh) {
      final mem = _memoryFileCache[normalized];
      if (mem != null) {
        return mem;
      }
    }

    final dir = await _ensureDir();
    if (dir == null) return null;
    final target = File(
      '${dir.path}${Platform.pathSeparator}${_cacheFileNameFor(normalized)}',
    );
    if (!forceRefresh && target.existsSync() && target.lengthSync() > 0) {
      _memoryFileCache[normalized] = target;
      return target;
    }

    if (forceRefresh) {
      _failureBackoffs.remove(normalized);
    } else {
      final backoff = _failureBackoffs[normalized];
      if (backoff != null && _nowUtc().isBefore(backoff.retryAfterUtc)) {
        return null;
      }
    }

    final existing = _inFlight[normalized];
    if (existing != null) {
      return existing;
    }

    final future = _fetchAndPersist(
      normalized: normalized,
      target: target,
      dir: dir,
      isVideo: _isLikelyVideoUrl(normalized),
    );
    _inFlight[normalized] = future;
    try {
      return await future;
    } finally {
      unawaited(_inFlight.remove(normalized));
    }
  }

  Future<Uint8List?> downloadBytes(
    String? url, {
    bool forceRefresh = false,
  }) async {
    final file = await resolveMediaFile(url, forceRefresh: forceRefresh);
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      evictMemoryEntry(url);
      return null;
    }
  }

  /// Menyelesaikan sumber video yang dapat diputar: mengutamakan berkas cache
  /// lokal agar video tetap memutar saat offline, atau menerbitkan presigned
  /// GET URL segar bila file besar / belum selesai diunduh.
  Future<({File? file, String? streamUrl})> resolvePlayableVideoSource(
    String? url,
  ) async {
    final normalized = MediaUrlNormalizer.normalize(url);
    if (normalized == null || !MediaUrlNormalizer.isNetworkUrl(normalized)) {
      return (file: null, streamUrl: null);
    }

    final syncHit = cachedFileSync(normalized);
    if (syncHit != null) {
      return (file: syncHit, streamUrl: normalized);
    }

    final file = await resolveMediaFile(normalized);
    if (file != null) {
      return (file: file, streamUrl: normalized);
    }

    final objectKey = MediaUrlNormalizer.extractR2ObjectKey(normalized);
    if (objectKey != null) {
      final freshUrl = await _fetchPresignedGetUrl(objectKey);
      if (freshUrl != null && freshUrl.isNotEmpty) {
        return (file: null, streamUrl: freshUrl);
      }
    }
    return (file: null, streamUrl: normalized);
  }

  Future<File?> _fetchAndPersist({
    required String normalized,
    required File target,
    required Directory dir,
    required bool isVideo,
  }) async {
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasAuthority) return null;

    final objectKey = MediaUrlNormalizer.extractR2ObjectKey(normalized);
    final isPresigned = MediaUrlNormalizer.isPresignedOrPrivateR2Url(normalized);
    final isR2Dev = uri.host.toLowerCase().endsWith('.r2.dev');

    Uint8List? downloadedBytes;
    var directFailedNetwork = false;

    // 1. Direct HTTPS (+ fallback IPv4 TLS) jika bukan URL presigned/private R2
    //    dan domain r2.dev belum terdeteksi diblokir pada sesi ini.
    if (!isPresigned && !(isR2Dev && _r2DevDirectBlocked)) {
      final direct = await _tryDirectFetch(uri);
      if (direct.networkError) {
        directFailedNetwork = true;
      } else if (direct.bytes != null &&
          _isValidMediaPayload(direct.bytes!, isVideo: isVideo)) {
        downloadedBytes = direct.bytes;
        if (isR2Dev) {
          _r2DevDirectFailCount = 0;
        }
      }
    }

    // 2. Fallback melalui Edge Function `r2-presign` (`proxy` lalu `get-url`)
    if (downloadedBytes == null && objectKey != null) {
      final proxyRes = await _fetchViaEdgeProxy(objectKey);
      if (proxyRes.statusCode == 200 &&
          _isValidMediaPayload(proxyRes.bytes, isVideo: isVideo)) {
        downloadedBytes = proxyRes.bytes;
        if (directFailedNetwork && isR2Dev) {
          _r2DevDirectFailCount++;
          if (_r2DevDirectFailCount >= 2) {
            _r2DevDirectBlocked = true;
          }
        }
      } else if (proxyRes.statusCode == 413 || proxyRes.statusCode == 0) {
        // Objek > 25 MB atau proxy gagal sementara -> coba fresh presigned GET URL.
        final signedUrl = await _fetchPresignedGetUrl(objectKey);
        if (signedUrl != null && signedUrl.isNotEmpty) {
          final signedUri = Uri.tryParse(signedUrl);
          if (signedUri != null) {
            final signedFetch = await _tryDirectFetch(signedUri);
            if (signedFetch.bytes != null &&
                _isValidMediaPayload(signedFetch.bytes!, isVideo: isVideo)) {
              downloadedBytes = signedFetch.bytes;
            }
          }
        }
      }
    }

    if (downloadedBytes == null || downloadedBytes.isEmpty) {
      _recordFailureBackoff(normalized);
      return null;
    }

    _failureBackoffs.remove(normalized);

    try {
      final tmp = File('${target.path}.tmp.${_nowUtc().microsecondsSinceEpoch}');
      await tmp.writeAsBytes(downloadedBytes, flush: true);
      if (target.existsSync()) {
        try {
          target.deleteSync();
        } catch (_) {}
      }
      await tmp.rename(target.path);
      _memoryFileCache[normalized] = target;
      unawaited(_pruneCacheIfNeeded(dir));
      return target;
    } catch (_) {
      return null;
    }
  }

  void _recordFailureBackoff(String normalized) {
    final prev = _failureBackoffs[normalized];
    final strikes = (prev?.strikes ?? 0) + 1;
    final seconds = switch (strikes) {
      1 => 15,
      2 => 30,
      _ => 120,
    };
    _failureBackoffs[normalized] = _FailureBackoff(
      strikes: strikes,
      retryAfterUtc: _nowUtc().add(Duration(seconds: seconds)),
    );
  }

  Future<({Uint8List? bytes, bool networkError})> _tryDirectFetch(
    Uri uri,
  ) async {
    final injected = _httpFetcher;
    if (injected != null) {
      try {
        final res = await injected(uri).timeout(_directTimeout);
        if (res.statusCode >= 200 && res.statusCode < 300 && res.bytes.isNotEmpty) {
          return (bytes: res.bytes, networkError: false);
        }
        return (bytes: null, networkError: res.statusCode >= 500);
      } catch (_) {
        return (bytes: null, networkError: true);
      }
    }

    try {
      final res = await _defaultHttpGet(uri);
      if (res != null && res.isNotEmpty) {
        return (bytes: res, networkError: false);
      }
    } catch (_) {
      // Lanjut coba koneksi eksplisit IPv4 bila dual-stack/IPv6 gagal.
    }

    try {
      final ipv4Bytes = await _fetchOverExplicitIpv4Tls(uri);
      if (ipv4Bytes != null && ipv4Bytes.isNotEmpty) {
        return (bytes: ipv4Bytes, networkError: false);
      }
    } catch (_) {}

    return (bytes: null, networkError: true);
  }

  Future<Uint8List?> _defaultHttpGet(Uri uri, {int redirectsRemaining = 4}) async {
    final client = HttpClient()
      ..userAgent = 'Hiqeo/1.0 (Android)'
      ..connectionTimeout = _directTimeout
      ..idleTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(uri).timeout(_directTimeout);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.connectionHeader, 'close');
      req.headers.set(HttpHeaders.userAgentHeader, 'Hiqeo/1.0 (Android)');
      req.headers.set(HttpHeaders.acceptHeader, 'image/webp,image/*,*/*');
      final resp = await req.close().timeout(_directTimeout);

      if ((resp.statusCode == HttpStatus.movedTemporarily ||
              resp.statusCode == HttpStatus.movedPermanently ||
              resp.statusCode == HttpStatus.seeOther ||
              resp.statusCode == HttpStatus.temporaryRedirect ||
              resp.statusCode == HttpStatus.permanentRedirect) &&
          redirectsRemaining > 0) {
        final location = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>().catchError((_) {});
        if (location != null && location.isNotEmpty) {
          final nextUri = uri.resolve(location);
          if (nextUri.scheme == 'https') {
            return await _defaultHttpGet(
              nextUri,
              redirectsRemaining: redirectsRemaining - 1,
            );
          }
        }
        return null;
      }

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        await resp.drain<void>().catchError((_) {});
        return null;
      }
      if (resp.contentLength > _maxDownloadBytes) {
        await resp.drain<void>().catchError((_) {});
        return null;
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp.timeout(_directTimeout)) {
        if (builder.length + chunk.length > _maxDownloadBytes) {
          return null;
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } finally {
      client.close(force: true);
    }
  }

  /// Menghindari hang IPv6 Android 14–16 dengan memaksa TCP ke alamat IPv4
  /// hasil lookup, sambil tetap melakukan verifikasi TLS SNI atas [uri.host].
  Future<Uint8List?> _fetchOverExplicitIpv4Tls(Uri uri) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) return null;
    final ipv4Addrs = await InternetAddress.lookup(
      uri.host,
      type: InternetAddressType.IPv4,
    ).timeout(const Duration(seconds: 4));
    if (ipv4Addrs.isEmpty) return null;

    final port = uri.hasPort ? uri.port : 443;
    final tcpSocket = await Socket.connect(
      ipv4Addrs.first,
      port,
      timeout: const Duration(seconds: 6),
    );
    SecureSocket? tlsSocket;
    try {
      tlsSocket = await SecureSocket.secure(
        tcpSocket,
        host: uri.host,
      ).timeout(const Duration(seconds: 6));

      final pathAndQuery =
          uri.hasQuery ? '${uri.path.isEmpty ? '/' : uri.path}?${uri.query}' : (uri.path.isEmpty ? '/' : uri.path);
      final requestStr = 'GET $pathAndQuery HTTP/1.1\r\n'
          'Host: ${uri.host}\r\n'
          'User-Agent: Hiqeo/1.0 (Android)\r\n'
          'Accept: image/webp,image/*,*/*\r\n'
          'Accept-Encoding: identity\r\n'
          'Connection: close\r\n\r\n';
      tlsSocket.add(utf8.encode(requestStr));
      await tlsSocket.flush().timeout(const Duration(seconds: 4));

      final builder = BytesBuilder(copy: false);
      await for (final chunk in tlsSocket.timeout(_directTimeout)) {
        if (builder.length + chunk.length > _maxDownloadBytes + 8192) {
          return null;
        }
        builder.add(chunk);
      }
      final raw = builder.takeBytes();
      return _parseRawHttpResponse(raw);
    } finally {
      try {
        await tlsSocket?.close();
      } catch (_) {
        tlsSocket?.destroy();
      }
      try {
        tcpSocket.destroy();
      } catch (_) {}
    }
  }

  Uint8List? _parseRawHttpResponse(Uint8List raw) {
    final sepIndex = _findHeaderEnd(raw);
    if (sepIndex < 0) return null;
    final headerText = ascii.decode(raw.sublist(0, sepIndex), allowInvalid: true);
    final lines = headerText.split('\r\n');
    if (lines.isEmpty) return null;
    final statusParts = lines.first.split(' ');
    if (statusParts.length < 2) return null;
    final statusCode = int.tryParse(statusParts[1]) ?? 0;
    if (statusCode < 200 || statusCode >= 300) return null;

    var isChunked = false;
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim().toLowerCase();
      if (name == 'transfer-encoding' && value.contains('chunked')) {
        isChunked = true;
      }
    }

    final body = raw.sublist(sepIndex + 4);
    if (!isChunked) {
      return body.isEmpty ? null : body;
    }
    return _decodeChunkedBody(body);
  }

  int _findHeaderEnd(Uint8List bytes) {
    for (var i = 0; i <= bytes.length - 4; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  Uint8List? _decodeChunkedBody(Uint8List body) {
    final out = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < body.length) {
      var lineEnd = -1;
      for (var i = offset; i <= body.length - 2; i++) {
        if (body[i] == 13 && body[i + 1] == 10) {
          lineEnd = i;
          break;
        }
      }
      if (lineEnd < 0) break;
      final sizeLine =
          ascii.decode(body.sublist(offset, lineEnd), allowInvalid: true).trim();
      final semi = sizeLine.indexOf(';');
      final hexStr = (semi >= 0 ? sizeLine.substring(0, semi) : sizeLine).trim();
      final chunkSize = int.tryParse(hexStr, radix: 16);
      if (chunkSize == null || chunkSize < 0) return null;
      offset = lineEnd + 2;
      if (chunkSize == 0) break;
      if (offset + chunkSize > body.length ||
          out.length + chunkSize > _maxDownloadBytes) {
        return null;
      }
      out.add(body.sublist(offset, offset + chunkSize));
      offset += chunkSize + 2;
    }
    final res = out.takeBytes();
    return res.isEmpty ? null : res;
  }

  Future<({int statusCode, Uint8List bytes})> _fetchViaEdgeProxy(
    String objectKey,
  ) async {
    final injected = _edgeProxyFetcher;
    if (injected != null) {
      try {
        return await injected(objectKey).timeout(_proxyTimeout);
      } catch (_) {
        return (statusCode: 0, bytes: Uint8List(0));
      }
    }

    final jwt = SupabaseServices.clientOrNull?.auth.currentSession?.accessToken;
    final baseUrl = SupabaseConfig.url;
    final apiKey = SupabaseConfig.effectiveKey;
    if (jwt == null || jwt.isEmpty || baseUrl.isEmpty || apiKey.isEmpty) {
      return (statusCode: 0, bytes: Uint8List(0));
    }

    final fnUri = Uri.tryParse('$baseUrl/functions/v1/r2-presign');
    if (fnUri == null) return (statusCode: 0, bytes: Uint8List(0));

    final client = HttpClient()
      ..userAgent = 'Hiqeo/1.0 (Android)'
      ..connectionTimeout = _proxyTimeout
      ..idleTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(fnUri).timeout(_proxyTimeout);
      req.headers.set(HttpHeaders.connectionHeader, 'close');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $jwt');
      req.headers.set('apikey', apiKey);
      req.add(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'action': 'proxy',
            'objectKey': objectKey,
          }),
        ),
      );
      final resp = await req.close().timeout(_proxyTimeout);
      if (resp.statusCode != 200) {
        await resp.drain<void>().catchError((_) {});
        return (statusCode: resp.statusCode, bytes: Uint8List(0));
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp.timeout(_proxyTimeout)) {
        if (builder.length + chunk.length > _maxDownloadBytes) {
          return (statusCode: 413, bytes: Uint8List(0));
        }
        builder.add(chunk);
      }
      return (statusCode: 200, bytes: builder.takeBytes());
    } catch (_) {
      return (statusCode: 0, bytes: Uint8List(0));
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _fetchPresignedGetUrl(String objectKey) async {
    final injected = _edgeGetUrlFetcher;
    if (injected != null) {
      try {
        return await injected(objectKey).timeout(_directTimeout);
      } catch (_) {
        return null;
      }
    }

    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentSession == null) return null;
    try {
      final res = await client.functions
          .invoke(
            'r2-presign',
            body: <String, dynamic>{
              'action': 'get-url',
              'objectKey': objectKey,
            },
          )
          .timeout(_directTimeout);
      if (res.status < 200 || res.status >= 300) return null;
      final data = res.data;
      if (data is Map) {
        return MediaUrlNormalizer.normalize(data['downloadUrl']?.toString());
      }
    } catch (_) {}
    return null;
  }

  bool _isLikelyVideoUrl(String url) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.webm');
  }

  bool _isValidMediaPayload(Uint8List bytes, {required bool isVideo}) {
    if (bytes.isEmpty) return false;
    // Tolak respons HTML/JSON error dari proxy atau firewall ISP agar tidak
    // pernah dianggap sebagai gambar/video yang valid.
    final headLen = bytes.length < 32 ? bytes.length : 32;
    final prefix =
        utf8.decode(bytes.sublist(0, headLen), allowMalformed: true).trimLeft().toLowerCase();
    if (prefix.startsWith('<!doctype') ||
        prefix.startsWith('<html') ||
        prefix.startsWith('{"error"')) {
      return false;
    }
    if (isVideo) {
      return bytes.length >= 256;
    }
    return _hasImageMagicBytes(bytes);
  }

  bool _hasImageMagicBytes(Uint8List bytes) {
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return true;
    }
    return false;
  }

  Future<void> _pruneCacheIfNeeded(Directory dir) async {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.tmp'))
          .toList();
      var total = 0;
      for (final f in files) {
        total += f.lengthSync();
      }
      if (total <= _maxDiskBytes) return;
      files.sort(
        (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
      );
      for (final f in files) {
        if (total <= _maxDiskBytes * 0.8) break;
        final len = f.lengthSync();
        try {
          f.deleteSync();
          total -= len;
        } catch (_) {}
      }
    } catch (_) {}
  }

  String _cacheFileNameFor(String normalizedUrl) {
    final digestHex = _sha1Hex(utf8.encode(normalizedUrl));
    final path = (Uri.tryParse(normalizedUrl)?.path ?? '').toLowerCase();
    var ext = 'bin';
    for (final candidate in const <String>[
      '.webp',
      '.jpg',
      '.jpeg',
      '.png',
      '.mp4',
      '.mov',
      '.webm',
    ]) {
      if (path.endsWith(candidate)) {
        ext = candidate.substring(1);
        break;
      }
    }
    return '$digestHex.$ext';
  }

  static String _sha1Hex(List<int> input) {
    int rotl(int n, int bits) =>
        ((n << bits) | (n >>> (32 - bits))) & 0xffffffff;

    final bitLen = input.length * 8;
    final bytes = <int>[...input, 0x80];
    while ((bytes.length % 64) != 56) {
      bytes.add(0);
    }
    for (var shift = 56; shift >= 0; shift -= 8) {
      bytes.add((bitLen >>> shift) & 0xff);
    }

    var h0 = 0x67452301;
    var h1 = 0xefcdab89;
    var h2 = 0x98badcfe;
    var h3 = 0x10325476;
    var h4 = 0xc3d2e1f0;

    final w = List<int>.filled(80, 0);
    for (var i = 0; i < bytes.length; i += 64) {
      for (var j = 0; j < 16; j++) {
        final base = i + j * 4;
        w[j] = ((bytes[base] << 24) |
                (bytes[base + 1] << 16) |
                (bytes[base + 2] << 8) |
                bytes[base + 3]) &
            0xffffffff;
      }
      for (var j = 16; j < 80; j++) {
        w[j] = rotl(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;

      for (var j = 0; j < 80; j++) {
        final int f;
        final int k;
        if (j < 20) {
          f = (b & c) | ((~b & 0xffffffff) & d);
          k = 0x5a827999;
        } else if (j < 40) {
          f = b ^ c ^ d;
          k = 0x6ed9eba1;
        } else if (j < 60) {
          f = (b & c) | (b & d) | (c & d);
          k = 0x8f1bbcdc;
        } else {
          f = b ^ c ^ d;
          k = 0xca62c1d6;
        }
        final temp = (rotl(a, 5) + f + e + k + w[j]) & 0xffffffff;
        e = d;
        d = c;
        c = rotl(b, 30);
        b = a;
        a = temp;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
    }

    String hex32(int v) => (v & 0xffffffff).toRadixString(16).padLeft(8, '0');
    return '${hex32(h0)}${hex32(h1)}${hex32(h2)}${hex32(h3)}${hex32(h4)}';
  }
}
