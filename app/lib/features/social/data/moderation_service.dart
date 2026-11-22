import '../../../infrastructure/supabase/supabase_services.dart';

enum ModerationTargetType {
  groupMessage('group_message'),
  communityMessage('community_message'),
  community('community'),
  userAccount('user_account');

  const ModerationTargetType(this.dbValue);
  final String dbValue;
}

/// Mengirim laporan moderasi (pesan grup, pesan komunitas, komunitas, atau akun
/// pengguna) ke tabel `moderation_reports` Supabase agar pengembang menerima
/// notifikasi melalui trigger webhook / Edge Function.
class ModerationService {
  ModerationService._();

  static final ModerationService instance = ModerationService._();

  static const List<String> defaultReasons = <String>[
    'Spam atau promosi tidak relevan',
    'Ujaran kebencian atau pelecehan',
    'Konten tidak pantas atau berbahaya',
    'Penipuan atau informasi palsu',
    'Lainnya',
  ];

  Future<void> submitReport({
    required ModerationTargetType targetType,
    required String targetId,
    required String reason,
    String? details,
    String? groupId,
    String? communityId,
    String? reportedUserId,
    String? messageExcerpt,
  }) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Masuk akun terlebih dahulu untuk mengirim laporan.');
    }

    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('Alasan laporan tidak boleh kosong.');
    }
    if (trimmedReason.length > 500) {
      throw ArgumentError('Alasan laporan maksimal 500 karakter.');
    }
    final trimmedDetails = details?.trim();
    final safeDetails = trimmedDetails != null && trimmedDetails.length > 500
        ? trimmedDetails.substring(0, 500)
        : trimmedDetails;
    final trimmedExcerpt = messageExcerpt?.trim();
    final safeExcerpt = trimmedExcerpt != null && trimmedExcerpt.length > 500
        ? trimmedExcerpt.substring(0, 500)
        : trimmedExcerpt;

    final metadata = <String, dynamic>{
      if (groupId != null && groupId.isNotEmpty) 'group_id': groupId,
      if (communityId != null && communityId.isNotEmpty)
        'community_id': communityId,
      if (reportedUserId != null && reportedUserId.isNotEmpty)
        'reported_user_id': reportedUserId,
      if (safeDetails != null && safeDetails.isNotEmpty)
        'details': safeDetails,
    };

    final payload = <String, dynamic>{
      'reporter_id': user.id,
      'report_type': targetType.dbValue,
      'target_id': targetId,
      'reason': trimmedReason,
      if (safeExcerpt != null && safeExcerpt.isNotEmpty)
        'content_snippet': safeExcerpt,
      'metadata': metadata,
    };

    await client.from('moderation_reports').insert(payload);
  }
}
