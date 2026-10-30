enum MediaKind { image, audio, video, file }

class MediaAttachment {
  const MediaAttachment({
    required this.id,
    required this.kind,
    required this.relativePath,
    required this.mimeType,
    required this.byteSize,
    required this.createdAtUtc,
    this.messageId,
    this.groupId,
  });

  final String id;
  final String? messageId;
  final String? groupId;
  final MediaKind kind;

  /// Path relatif terhadap direktori dokumen aplikasi, bukan path absolut:
  /// lokasi sandbox iOS dapat berubah setelah update/restore.
  final String relativePath;
  final String mimeType;
  final int byteSize;
  final DateTime createdAtUtc;
}
