import 'dart:async';

import 'package:drift/drift.dart';

import '../../../features/safety/domain/emergency_contact.dart';
import '../../../features/safety/domain/safety_repository.dart';
import '../../../features/safety/domain/sos_category.dart';
import '../../../features/safety/domain/sos_event.dart';
import '../app_database.dart';
import '../daos/safety_dao.dart';

class DriftSafetyRepository implements SafetyRepository {
  DriftSafetyRepository(AppDatabase db)
      : _db = db,
        _dao = SafetyDao(db);

  final AppDatabase _db;
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
  Future<void> saveContact(EmergencyContact contact) async {
    if (contact.isHiqeoAccount) {
      await _db.customStatement(
        '''
        INSERT INTO local_hiqeo_emergency_contacts
          (id, user_id, contact_user_id, contact_username, display_name, consent_status, consent_at_utc, created_at_utc)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          display_name = excluded.display_name,
          consent_status = excluded.consent_status,
          consent_at_utc = excluded.consent_at_utc
        ''',
        <Object?>[
          contact.id,
          contact.userId,
          contact.linkedUserId,
          contact.linkedUsername ?? '',
          contact.name,
          contact.consentStatus.name,
          contact.consentAtUtc?.toUtc().millisecondsSinceEpoch,
          contact.createdAtUtc.toUtc().millisecondsSinceEpoch,
        ],
      );
      _db.notifyUpdates(<TableUpdate>{
        TableUpdate.onTable(_db.emergencyContacts),
      });
      return;
    }
    await _dao.upsertContact(
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
  }

  Future<List<EmergencyContact>> _hiqeoContactsOf(String userId) async {
    try {
      final rows = await _db
          .customSelect(
            '''
            SELECT id, user_id, contact_user_id, contact_username, display_name,
                   consent_status, consent_at_utc, created_at_utc
            FROM local_hiqeo_emergency_contacts
            WHERE user_id = ?
            ORDER BY created_at_utc ASC
            ''',
            variables: <Variable<Object>>[Variable.withString(userId)],
          )
          .get();
      return rows.map((row) {
        final consentMs = row.readNullable<int>('consent_at_utc');
        final createdMs = row.read<int>('created_at_utc');
        return EmergencyContact(
          id: row.read<String>('id'),
          userId: row.read<String>('user_id'),
          name: row.read<String>('display_name'),
          phoneE164: '',
          linkedUserId: row.read<String>('contact_user_id'),
          linkedUsername: row.read<String>('contact_username'),
          consentStatus: _consentFromDb(row.read<String>('consent_status')),
          consentAtUtc: consentMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(consentMs, isUtc: true),
          createdAtUtc:
              DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: true),
        );
      }).toList(growable: false);
    } catch (_) {
      return const <EmergencyContact>[];
    }
  }

  @override
  Future<List<EmergencyContact>> contactsOf(String userId) async {
    final phoneRows = await _dao.contactsOf(userId);
    final hiqeoRows = await _hiqeoContactsOf(userId);
    final merged = <EmergencyContact>[
      ...phoneRows.map(_toContact),
      ...hiqeoRows,
    ]..sort((a, b) => a.createdAtUtc.compareTo(b.createdAtUtc));
    return merged;
  }

  @override
  Stream<List<EmergencyContact>> watchContacts(String userId) =>
      _dao.watchContacts(userId).asyncMap((rows) async {
        final hiqeoRows = await _hiqeoContactsOf(userId);
        final merged = <EmergencyContact>[
          ...rows.map(_toContact),
          ...hiqeoRows,
        ]..sort((a, b) => a.createdAtUtc.compareTo(b.createdAtUtc));
        return merged;
      });

  @override
  Future<void> deleteContact(String id) async {
    await _dao.deleteContact(id);
    try {
      await _db.customStatement(
        'DELETE FROM local_hiqeo_emergency_contacts WHERE id = ?',
        <Object?>[id],
      );
      _db.notifyUpdates(<TableUpdate>{
        TableUpdate.onTable(_db.emergencyContacts),
      });
    } catch (_) {}
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
