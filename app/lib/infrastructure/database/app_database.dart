import 'package:drift/drift.dart';

part 'app_database.g.dart';

@DataClassName('MemberRow')
class Members extends Table {
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  TextColumn get username => text().withLength(min: 3, max: 20)();
  TextColumn get role => text().withDefault(const Constant('member'))();
  DateTimeColumn get joinedAtUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {groupId, userId};

  @override
  List<String> get customConstraints => [
        "CHECK (role IN ('owner', 'member'))",
      ];
}

@DataClassName('GroupRow')
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get ownerId => text()();
  TextColumn get mountain => text().nullable()();
  IntColumn get keyVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAtUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('InvitationRow')
@TableIndex(
  name: 'invitations_invitee_status',
  columns: {#inviteeUsername, #status, #expiresAtUtc},
)
@TableIndex.sql(
  "CREATE UNIQUE INDEX invitations_one_pending "
  "ON invitations (group_id, invitee_username) WHERE status = 'pending'",
)
class Invitations extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text()();
  TextColumn get inviterId => text()();
  TextColumn get inviteeUsername => text().withLength(min: 3, max: 20)();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get expiresAtUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (status IN ('pending', 'accepted', 'rejected', "
            "'expired', 'cancelled'))",
      ];
}

@DataClassName('MessageRow')
@TableIndex(name: 'messages_group_sent', columns: {#groupId, #sentAtUtc})
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get authorId => text()();
  IntColumn get seq => integer()();
  TextColumn get groupId => text()();
  IntColumn get typeCode => integer()();
  DateTimeColumn get sentAtUtc => dateTime()();
  DateTimeColumn get receivedAtUtc => dateTime()();
  BlobColumn get payload => blob()();
  BlobColumn get signature => blob().nullable()();
  BoolColumn get isOutgoing => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>>? get uniqueKeys => [
        {authorId, seq},
      ];
}

@DataClassName('MediaRow')
@TableIndex(name: 'media_message', columns: {#messageId})
class Media extends Table {
  TextColumn get id => text()();
  TextColumn get messageId => text()
      .nullable()
      .references(Messages, #id, onDelete: KeyAction.setNull)();
  TextColumn get groupId => text().nullable()();
  TextColumn get kind => text()();
  TextColumn get relativePath => text()();
  TextColumn get mimeType => text()();
  IntColumn get byteSize => integer()();
  DateTimeColumn get createdAtUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (kind IN ('image', 'audio', 'video', 'file'))",
        'CHECK (byte_size >= 0)',
      ];
}

@DataClassName('SessionRow')
@TableIndex(name: 'sessions_started', columns: {#startedAtUtc})
class Sessions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get startedAtUtc => dateTime()();
  DateTimeColumn get endedAtUtc => dateTime().nullable()();
  TextColumn get groupId => text().nullable()();
  TextColumn get trailId => text().nullable()();
  RealColumn get distanceM => real().withDefault(const Constant(0.0))();
  IntColumn get movingSeconds => integer().withDefault(const Constant(0))();
  RealColumn get elevationGainM => real().withDefault(const Constant(0.0))();
  RealColumn get elevationLossM => real().withDefault(const Constant(0.0))();
  TextColumn get status => text().withDefault(const Constant('active'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (distance_m >= 0)',
        'CHECK (moving_seconds >= 0)',
        'CHECK (elevation_gain_m >= 0)',
        'CHECK (elevation_loss_m >= 0)',
        "CHECK (status IN ('active', 'completed'))",
      ];
}

@DataClassName('TrackPointRow')
@TableIndex(
  name: 'track_points_session_time',
  columns: {#sessionId, #recordedAtUtc},
)
class TrackPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get altitudeM => real().nullable()();
  RealColumn get accuracyM => real()();
  RealColumn get speedMps => real().nullable()();
  DateTimeColumn get recordedAtUtc => dateTime()();

  @override
  List<String> get customConstraints => [
        'CHECK (lat BETWEEN -90 AND 90)',
        'CHECK (lon BETWEEN -180 AND 180)',
      ];
}

@DataClassName('OutboxRow')
@TableIndex(name: 'outbox_due', columns: {#nextAttemptAtUtc})
@TableIndex(name: 'outbox_order', columns: {#priority, #enqueuedAtUtc})
class Outbox extends Table {
  TextColumn get messageId => text()();
  BlobColumn get packet => blob()();
  IntColumn get priority => integer()();
  DateTimeColumn get enqueuedAtUtc => dateTime()();
  DateTimeColumn get nextAttemptAtUtc => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  BoolColumn get repeatUntilAck =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {messageId};

  @override
  List<String> get customConstraints => [
        'CHECK (priority >= 0)',
        'CHECK (attempts >= 0)',
      ];
}

@DataClassName('SosEventRow')
@TableIndex(name: 'sos_status_created', columns: {#status, #createdAtUtc})
class SosEvents extends Table {
  TextColumn get id => text()();
  TextColumn get authorId => text()();
  TextColumn get groupId =>
      text().nullable().references(Groups, #id, onDelete: KeyAction.setNull)();
  IntColumn get categoryCode => integer()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  IntColumn get accuracyM => integer().nullable()();
  IntColumn get batteryPercent => integer().nullable()();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get receivedAtUtc => dateTime()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get cancelledAtUtc => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (lat BETWEEN -90 AND 90)',
        'CHECK (lon BETWEEN -180 AND 180)',
        "CHECK (status IN ('active', 'cancelled', 'resolved'))",
      ];
}

@DataClassName('ContactRow')
@TableIndex(name: 'contacts_user', columns: {#userId})
class EmergencyContacts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text().withLength(min: 1)();
  TextColumn get phoneE164 => text().withLength(min: 9, max: 16)();
  TextColumn get channel => text().withDefault(const Constant('sms'))();
  TextColumn get consentStatus =>
      text().withDefault(const Constant('pending'))();
  DateTimeColumn get consentAtUtc => dateTime().nullable()();
  DateTimeColumn get createdAtUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (channel IN ('sms', 'whatsapp'))",
        "CHECK (consent_status IN ('pending', 'granted', 'revoked'))",
      ];
}

@DriftDatabase(
  tables: [
    Members,
    Groups,
    Invitations,
    Messages,
    Media,
    TrackPoints,
    Sessions,
    Outbox,
    SosEvents,
    EmergencyContacts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          // TaskHandler Android dan isolate UI memakai koneksi terpisah.
          // busy_timeout dulu agar pengalihan WAL tidak langsung gagal saat
          // koneksi lain sedang menulis.
          await customStatement('PRAGMA busy_timeout = 5000');
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA synchronous = NORMAL');
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS local_group_messages (
              client_msg_id TEXT PRIMARY KEY,
              group_id TEXT NOT NULL,
              sender_id TEXT NOT NULL,
              sender_name TEXT NOT NULL,
              message_type TEXT NOT NULL CHECK (message_type IN ('text', 'audio')),
              content TEXT,
              local_audio_path TEXT,
              audio_url TEXT,
              audio_duration_sec INTEGER,
              key_version INTEGER NOT NULL DEFAULT 1,
              origin_transport TEXT NOT NULL CHECK (origin_transport IN ('online', 'wifi_direct', 'ble_mesh')),
              sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'sent')),
              client_created_at INTEGER NOT NULL
            )
          ''');
          await customStatement('''
            CREATE INDEX IF NOT EXISTS idx_local_group_messages_group_time
            ON local_group_messages (group_id, client_created_at ASC)
          ''');
          final localMsgCols =
              await customSelect('PRAGMA table_info(local_group_messages)').get();
          final existingMsgColNames = localMsgCols
              .map((row) => row.read<String>('name'))
              .toSet();
          if (!existingMsgColNames.contains('is_deleted')) {
            await customStatement(
              'ALTER TABLE local_group_messages ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (!existingMsgColNames.contains('deleted_at')) {
            await customStatement(
              'ALTER TABLE local_group_messages ADD COLUMN deleted_at INTEGER',
            );
          }
          if (!existingMsgColNames.contains('is_cancelled')) {
            await customStatement(
              'ALTER TABLE local_group_messages ADD COLUMN is_cancelled INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (!existingMsgColNames.contains('cancelled_at')) {
            await customStatement(
              'ALTER TABLE local_group_messages ADD COLUMN cancelled_at INTEGER',
            );
          }
          await customStatement('''
            CREATE TABLE IF NOT EXISTS cached_public_profiles (
              user_id TEXT PRIMARY KEY,
              username TEXT,
              full_name TEXT,
              avatar_url TEXT,
              last_seen_at TEXT,
              updated_at INTEGER NOT NULL
            )
          ''');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS local_member_locations (
              group_id TEXT NOT NULL,
              user_id TEXT NOT NULL,
              display_name TEXT NOT NULL,
              latitude REAL NOT NULL,
              longitude REAL NOT NULL,
              altitude_mdpl INTEGER,
              battery_percent INTEGER,
              accuracy_m INTEGER,
              source_transport TEXT NOT NULL CHECK (source_transport IN ('online', 'wifi_direct', 'ble_mesh')),
              sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'sent')),
              recorded_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (group_id, user_id)
            )
          ''');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS cached_user_profiles (
              user_id TEXT PRIMARY KEY,
              username TEXT,
              display_name TEXT,
              avatar_url TEXT,
              local_avatar_path TEXT,
              email TEXT,
              public_key TEXT,
              username_changed_at TEXT,
              is_profile_complete INTEGER NOT NULL DEFAULT 0,
              is_plus INTEGER NOT NULL DEFAULT 0,
              plus_plan_id TEXT,
              plus_expires_at TEXT,
              updated_at INTEGER NOT NULL
            )
          ''');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS cached_remote_groups (
              owner_user_id TEXT NOT NULL,
              group_id TEXT NOT NULL,
              name TEXT NOT NULL,
              group_owner_id TEXT NOT NULL,
              mountain TEXT,
              avatar_url TEXT,
              key_version INTEGER NOT NULL DEFAULT 1,
              role TEXT NOT NULL,
              member_count INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              joined_at TEXT,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (owner_user_id, group_id)
            )
          ''');
          final cachedGroupCols =
              await customSelect('PRAGMA table_info(cached_remote_groups)').get();
          final existingCachedGroupColNames = cachedGroupCols
              .map((row) => row.read<String>('name'))
              .toSet();
          if (!existingCachedGroupColNames.contains('avatar_url')) {
            await customStatement(
              'ALTER TABLE cached_remote_groups ADD COLUMN avatar_url TEXT',
            );
          }
          if (!existingCachedGroupColNames.contains('joined_at')) {
            await customStatement(
              'ALTER TABLE cached_remote_groups ADD COLUMN joined_at TEXT',
            );
          }
          await customStatement('''
            CREATE TABLE IF NOT EXISTS cached_group_members (
              group_id TEXT NOT NULL,
              user_id TEXT NOT NULL,
              username TEXT NOT NULL,
              display_name TEXT,
              avatar_url TEXT,
              role TEXT NOT NULL,
              public_key TEXT NOT NULL,
              joined_at TEXT NOT NULL,
              last_seen_at TEXT,
              PRIMARY KEY (group_id, user_id)
            )
          ''');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS cached_invitations (
              owner_user_id TEXT NOT NULL,
              invitation_id TEXT NOT NULL,
              group_id TEXT NOT NULL,
              group_name TEXT NOT NULL,
              inviter_username TEXT NOT NULL,
              created_at TEXT NOT NULL,
              expires_at TEXT NOT NULL,
              PRIMARY KEY (owner_user_id, invitation_id)
            )
          ''');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS session_metadata (
              session_id TEXT PRIMARY KEY,
              reached_summit INTEGER NOT NULL DEFAULT 0,
              mountain_name TEXT,
              trail_name TEXT,
              activity_type TEXT NOT NULL DEFAULT 'hiking',
              owner_user_id TEXT
            )
          ''');
          final metaCols = await customSelect('PRAGMA table_info(session_metadata)').get();
          final metaColNames = <String>{
            for (final row in metaCols) row.read<String>('name'),
          };
          if (!metaColNames.contains('activity_type')) {
            await customStatement(
              "ALTER TABLE session_metadata ADD COLUMN activity_type TEXT NOT NULL DEFAULT 'hiking'",
            );
          }
          if (!metaColNames.contains('owner_user_id')) {
            try {
              await customStatement(
                'ALTER TABLE session_metadata ADD COLUMN owner_user_id TEXT',
              );
            } catch (_) {}
          }
          try {
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_session_metadata_owner ON session_metadata (owner_user_id)',
            );
          } catch (_) {}
          await customStatement('''
            CREATE TABLE IF NOT EXISTS local_mesh_acks (
              client_msg_id TEXT PRIMARY KEY,
              acked_at INTEGER NOT NULL
            )
          ''');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS local_hiqeo_emergency_contacts (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              contact_user_id TEXT NOT NULL,
              contact_username TEXT NOT NULL,
              display_name TEXT NOT NULL,
              consent_status TEXT NOT NULL DEFAULT 'pending',
              consent_at_utc INTEGER,
              created_at_utc INTEGER NOT NULL
            )
          ''');
        },
      );
}
