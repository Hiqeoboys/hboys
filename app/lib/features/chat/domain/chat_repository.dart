import 'chat_message.dart';
import 'media_attachment.dart';

abstract interface class ChatRepository {
  Future<void> saveMessage(ChatMessage message);
  Future<ChatMessage?> findMessage(String messageId);

  /// Pesan terbaru sebuah grup, diurutkan dari yang paling lama ke terbaru.
  /// [beforeUtc] bersifat eksklusif untuk memuat halaman sebelumnya.
  Future<List<ChatMessage>> recentMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeUtc,
  });

  Stream<List<ChatMessage>> watchMessages(String groupId, {int limit = 50});

  Future<void> saveMedia(MediaAttachment media);
  Future<List<MediaAttachment>> mediaForMessage(String messageId);
}
