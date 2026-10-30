import 'dart:async';

import 'package:drift/drift.dart';

import '../../../features/safety/domain/emergency_contact.dart';
import '../../../features/safety/domain/safety_repository.dart';
import '../../../features/safety/domain/sos_category.dart';
import '../../../features/safety/domain/sos_event.dart';
import '../app_database.dart';
import '../daos/safety_dao.dart';

class DriftSafetyRepository implements SafetyRepository {
  DriftSafetyRepository(AppDatabase db) : _dao = SafetyDao(db);

  final SafetyDao _dao;

  @override
  Future<void> saveSosEvent(SosEvent event) => _dao.upsertSosEvent(
        SosEventsCompanion.insert(
          id: event.id,
          authorId: event.authorId,
          groupId: Value(event.groupId),
          categoryCode: event.category.code,
          lat: event.lat,
          lon: event.lon,
          accuracyM: Value(event.accuracyM),
          batteryPercent: Value(event.batteryPercent),
          createdAtUtc: event.createdAtUtc.toUtc(),
          receivedAtUtc: event.receivedAtUtc.toUtc(),
          status: Value(event.status.name),
          cancelledAtUtc: Value(event.cancelledAtUtc?.toUtc()),
        ),
      );

  @override
  Future<SosEvent?> findSosEvent(String id) async {
    final row = await _dao.sosEventById(id);
    return row == null ? null : _toSosEvent(row);
  }

  @override
  Future<List<SosEvent>> activeSosEvents() async {
    final rows = await _dao.activeSosEvents();
    return rows.map(_toSosEvent).toList(growable: false);
  }

  @override
  Stream<List<SosEvent>> watchSosEvents() =>
      _dao.watchSosEvents().map((rows) => rows.map(_toSosEvent).toList());

  @override
  Future<bool> cancelSosEvent(String id, DateTime nowUtc) =>
      _dao.cancelSosEvent(id, nowUtc.toUtc());

  @override
  Future<void> saveContact(EmergencyContact contact) => _dao.upsertContact(
        EmergencyContactsCompanion.insert(
          id: contact.id,
          userId: contact.userId,
          name: contact.name,
          phoneE164: contact.phoneE164,
          channel: Value(contact.channel.name),
          consentStatus: Value(contact.consentStatus.name),
          consentAtUtc: Value(contact.consentAtUtc?.toUtc()),
          createdAtUtc: contact.createdAtUtc.toUtc(),
        ),
      );

  @override
  Future<List<EmergencyContact>> contactsOf(String userId) async {
    final rows = await _dao.contactsOf(userId);
    return rows.map(_toContact).toList(growable: false);
  }

  @override
  Stream<List<EmergencyContact>> watchContacts(String userId) =>
      _dao.watchContacts(userId).map(
            (rows) => rows.map(_toContact).toList(growable: false),
          );

  @override
  Future<void> deleteContact(String id) async {
    await _dao.deleteContact(id);
  }

  SosEvent _toSosEvent(SosEventRow row) => SosEvent(
        id: row.id,
        authorId: row.authorId,
        groupId: row.groupId,
        category: SosCategory.fromCode(row.categoryCode),
        lat: row.lat,
        lon: row.lon,
        accuracyM: row.accuracyM,
        batteryPercent: row.batteryPercent,
        createdAtUtc: row.createdAtUtc,
        receivedAtUtc: row.receivedAtUtc,
        status: _sosStatusFromDb(row.status),
        cancelledAtUtc: row.cancelledAtUtc,
      );

  EmergencyContact _toContact(ContactRow row) => EmergencyContact(
        id: row.id,
        userId: row.userId,
        name: row.name,
        phoneE164: row.phoneE164,
        channel: _channelFromDb(row.channel),
        consentStatus: _consentFromDb(row.consentStatus),
        consentAtUtc: row.consentAtUtc,
        createdAtUtc: row.createdAtUtc,
      );

  SosEventStatus _sosStatusFromDb(String value) => switch (value) {
        'active' => SosEventStatus.active,
        'cancelled' => SosEventStatus.cancelled,
        'resolved' => SosEventStatus.resolved,
        _ => throw StateError('Status SOS tidak dikenal: $value'),
      };

  EmergencyContactChannel _channelFromDb(String value) => switch (value) {
        'sms' => EmergencyContactChannel.sms,
        'whatsapp' => EmergencyContactChannel.whatsapp,
        _ => throw StateError('Kanal kontak tidak dikenal: $value'),
      };

  EmergencyContactConsentStatus _consentFromDb(String value) =>
      switch (value) {
        'pending' => EmergencyContactConsentStatus.pending,
        'granted' => EmergencyContactConsentStatus.granted,
        'revoked' => EmergencyContactConsentStatus.revoked,
        _ => throw StateError('Status persetujuan tidak dikenal: $value'),
      };
}
