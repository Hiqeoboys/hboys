import 'emergency_contact.dart';
import 'sos_event.dart';

abstract interface class SafetyRepository {
  Future<void> saveSosEvent(SosEvent event);
  Future<SosEvent?> findSosEvent(String id);
  Future<List<SosEvent>> activeSosEvents();
  Stream<List<SosEvent>> watchSosEvents();

  /// Hanya SOS berstatus aktif yang bisa dibatalkan. Mengembalikan `false`
  /// jika tidak ada event aktif dengan [id] tersebut.
  Future<bool> cancelSosEvent(String id, DateTime nowUtc);

  Future<void> saveContact(EmergencyContact contact);
  Future<List<EmergencyContact>> contactsOf(String userId);
  Stream<List<EmergencyContact>> watchContacts(String userId);
  Future<void> deleteContact(String id);
}
