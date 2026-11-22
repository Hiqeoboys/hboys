import 'dart:typed_data';

import 'group_chat_models.dart';

/// Kontrak layanan jarak jauh (Supabase) untuk sinkronisasi Ruang Obrolan E2EE
/// (`group_messages`), Lokasi Terakhir Anggota E2EE (`member_locations`), dan
/// unggah/unduh pesan suara terenkripsi pada bucket privat `group-voice`.
abstract interface class GroupChatRemoteService {
  static const String voiceNotesBucket = 'group-voice';

  Future<List<GroupMessageRecord>> fetchMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeCreatedAtUtc,
  });

  Stream<List<GroupMessageRecord>> watchMessages(String groupId);

  Future<void> upsertMessage(GroupMessageRecord message);

  /// Menyinkronkan kumpulan pesan offline secara idempoten berdasarkan
  /// `unique (group_id, client_id)`.
  Future<int> syncOfflineMessages(List<GroupMessageRecord> messages);

  /// Menghapus pesan milik pengguna sendiri secara soft-delete (`is_deleted = true`)
  /// dan membersihkan konten/voice path di server.
  Future<void> softDeleteMessage({
    required String groupId,
    required String clientMsgId,
  });

  /// Menandai pesan ajakan mendaki di grup sebagai dibatalkan (`is_cancelled = true`).
  Future<void> cancelHikeInviteMessage({
    required String groupId,
    required String clientMsgId,
  });

  /// Mengenkripsi dan mengunggah berkas audio ke `<group_id>/<client_id>.enc`
  /// di bucket privat `group-voice` dan mengembalikan path objek Storage.
  Future<String> uploadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required Uint8List audioBytes,
    int keyVersion = 1,
  });

  /// Mengunduh berkas audio terenkripsi dari bucket `group-voice` dan
  /// mendekripsinya secara lokal dengan kunci grup.
  Future<Uint8List?> downloadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required String storagePath,
    int keyVersion = 1,
  });

  /// Mengubah path Storage menjadi URL putar bertanda tangan bila dibutuhkan.
  Future<String> resolveVoiceNotePlayUrl(String storagePathOrUrl);

  Future<List<MemberLastLocation>> fetchMemberLocations(
    String groupId, {
    required String currentUserId,
  });

  Stream<List<MemberLastLocation>> watchMemberLocations(
    String groupId, {
    required String currentUserId,
  });

  Future<void> upsertMemberLocation({
    required String groupId,
    required MemberLastLocation location,
    int keyVersion = 1,
  });

  Future<int> syncOfflineMemberLocations({
    required String groupId,
    required List<MemberLastLocation> locations,
    int keyVersion = 1,
  });
}

/// Kontrak opsional untuk filter batas masuk (`joined_at`) agar anggota baru
/// tidak menerima pesan sebelum waktu bergabung dan paginasi tetap akurat.
abstract interface class GroupChatSinceFilterRemoteService
    implements GroupChatRemoteService {
  Future<List<GroupMessageRecord>> fetchMessagesSince(
    String groupId, {
    int limit = 40,
    DateTime? beforeCreatedAtUtc,
    DateTime? minCreatedAtUtc,
  });

  Stream<List<GroupMessageRecord>> watchMessagesSince(
    String groupId, {
    DateTime? minCreatedAtUtc,
  });
}
