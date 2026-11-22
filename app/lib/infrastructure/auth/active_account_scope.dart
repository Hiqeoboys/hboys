import 'package:flutter/foundation.dart';

import '../supabase/supabase_services.dart';

/// Ruang isolasi akun aktif di perangkat.
///
/// Menjamin seluruh riwayat SQLite dan preferensi lokal terpartisi ketat per
/// `user_id` (`'guest'` saat belum login) sehingga pergantian akun tidak pernah
/// membocorkan data akun sebelumnya.
class ActiveAccountScope {
  const ActiveAccountScope._();

  static final ValueNotifier<String?> activeUserId = ValueNotifier<String?>(
    null,
  );

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// Mengembalikan ID pengguna aktif yang sudah dinormalisasi, atau `null`
  /// bila sesi sedang keluar / mode tamu.
  static String? currentUserId() {
    final fromScope = _normalize(activeUserId.value);
    if (fromScope != null) return fromScope;
    try {
      return _normalize(SupabaseServices.clientOrNull?.auth.currentUser?.id);
    } catch (_) {
      return null;
    }
  }

  /// Namespace penyimpanan per pengguna (`'guest'` saat signed out).
  static String storageNamespace([String? userIdOverride]) =>
      _normalize(userIdOverride) ?? currentUserId() ?? 'guest';

  /// Kunci SharedPreferences terpartisi per akun.
  static String namespacedKey(String baseKey, {String? userIdOverride}) =>
      '${baseKey}__u_${storageNamespace(userIdOverride)}';

  /// Memperbarui pengguna aktif dan memberi tahu seluruh pendengar UI/store.
  static void setActiveUserId(String? userId) {
    final normalized = _normalize(userId);
    if (activeUserId.value == normalized) return;
    activeUserId.value = normalized;
  }
}
