import 'dart:io';

import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/infrastructure/database/app_database.dart';
import 'package:nama_app/infrastructure/database/database_connection.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_group_repository.dart';

import '../generated_migrations/schema.dart';

final t0 = DateTime.utc(2027, 6, 1, 8);

const _expectedTables = [
  'members',
  'groups',
  'invitations',
  'messages',
  'media',
  'track_points',
  'sessions',
  'outbox',
  'sos_events',
  'emergency_contacts',
];

const _expectedIndexes = [
  'invitations_invitee_status',
  'invitations_one_pending',
  'messages_group_sent',
  'media_message',
  'sessions_started',
  'track_points_session_time',
  'outbox_due',
  'outbox_order',
  'sos_status_created',
  'contacts_user',
];

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('skema v1 yang dibuat runtime sama dengan snapshot drift', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    try {
      await verifier.migrateAndValidate(db, 1);
    } finally {
      await db.close();
    }
  });

  test('database baru berisi 10 tabel, indeks, foreign key, dan versi 1',
      () async {
    final db = openInMemoryAppDatabase();
    try {
      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final tableNames =
          tables.map((row) => row.read<String>('name')).toSet();
      expect(tableNames, containsAll(_expectedTables));

      final indexes = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
          .get();
      final indexNames =
          indexes.map((row) => row.read<String>('name')).toSet();
      expect(indexNames, containsAll(_expectedIndexes));

      final version =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 1);

      final foreignKeys =
          await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(foreignKeys.read<int>('foreign_keys'), 1);
    } finally {
      await db.close();
    }
  });

  test('data bertahan setelah file database ditutup dan dibuka ulang',
      () async {
    final dir = await Directory.systemTemp.createTemp('nama_migrasi_');
    final file = File('${dir.path}/app.sqlite');

    var db = openAppDatabase(file);
    try {
      final repo = DriftGroupRepository(db);
      await repo.saveGroup(
        Group(
          id: 'g1',
          name: 'Sukamaju',
          ownerId: 'owner_01',
          createdAtUtc: t0,
        ),
      );
      await repo.saveMember(
        GroupMember(
          groupId: 'g1',
          userId: 'budi_99',
          username: 'budi_99',
          joinedAtUtc: t0,
        ),
      );
      await db.close();

      db = openAppDatabase(file);
      final reopened = DriftGroupRepository(db);
      expect((await reopened.findGroup('g1'))!.name, 'Sukamaju');
      expect((await reopened.membersOf('g1')).single.username, 'budi_99');

      final version =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 1);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
