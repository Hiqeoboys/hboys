// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $GroupsTable extends Groups with TableInfo<$GroupsTable, GroupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 60),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _mountainMeta =
      const VerificationMeta('mountain');
  @override
  late final GeneratedColumn<String> mountain = GeneratedColumn<String>(
      'mountain', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _keyVersionMeta =
      const VerificationMeta('keyVersion');
  @override
  late final GeneratedColumn<int> keyVersion = GeneratedColumn<int>(
      'key_version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _createdAtUtcMeta =
      const VerificationMeta('createdAtUtc');
  @override
  late final GeneratedColumn<DateTime> createdAtUtc = GeneratedColumn<DateTime>(
      'created_at_utc', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, ownerId, mountain, keyVersion, createdAtUtc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'groups';
  @override
  VerificationContext validateIntegrity(Insertable<GroupRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('mountain')) {
      context.handle(_mountainMeta,
          mountain.isAcceptableOrUnknown(data['mountain']!, _mountainMeta));
    }
    if (data.containsKey('key_version')) {
      context.handle(
          _keyVersionMeta,
          keyVersion.isAcceptableOrUnknown(
              data['key_version']!, _keyVersionMeta));
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
          _createdAtUtcMeta,
          createdAtUtc.isAcceptableOrUnknown(
              data['created_at_utc']!, _createdAtUtcMeta));
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GroupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id'])!,
      mountain: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mountain']),
      keyVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}key_version'])!,
      createdAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}created_at_utc'])!,
    );
  }

  @override
  $GroupsTable createAlias(String alias) {
    return $GroupsTable(attachedDatabase, alias);
  }
}

class GroupRow extends DataClass implements Insertable<GroupRow> {
  final String id;
  final String name;
  final String ownerId;
  final String? mountain;
  final int keyVersion;
  final DateTime createdAtUtc;
  const GroupRow(
      {required this.id,
      required this.name,
      required this.ownerId,
      this.mountain,
      required this.keyVersion,
      required this.createdAtUtc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['owner_id'] = Variable<String>(ownerId);
    if (!nullToAbsent || mountain != null) {
      map['mountain'] = Variable<String>(mountain);
    }
    map['key_version'] = Variable<int>(keyVersion);
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    return map;
  }

  GroupsCompanion toCompanion(bool nullToAbsent) {
    return GroupsCompanion(
      id: Value(id),
      name: Value(name),
      ownerId: Value(ownerId),
      mountain: mountain == null && nullToAbsent
          ? const Value.absent()
          : Value(mountain),
      keyVersion: Value(keyVersion),
      createdAtUtc: Value(createdAtUtc),
    );
  }

  factory GroupRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      mountain: serializer.fromJson<String?>(json['mountain']),
      keyVersion: serializer.fromJson<int>(json['keyVersion']),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'ownerId': serializer.toJson<String>(ownerId),
      'mountain': serializer.toJson<String?>(mountain),
      'keyVersion': serializer.toJson<int>(keyVersion),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
    };
  }

  GroupRow copyWith(
          {String? id,
          String? name,
          String? ownerId,
          Value<String?> mountain = const Value.absent(),
          int? keyVersion,
          DateTime? createdAtUtc}) =>
      GroupRow(
        id: id ?? this.id,
        name: name ?? this.name,
        ownerId: ownerId ?? this.ownerId,
        mountain: mountain.present ? mountain.value : this.mountain,
        keyVersion: keyVersion ?? this.keyVersion,
        createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      );
  GroupRow copyWithCompanion(GroupsCompanion data) {
    return GroupRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      mountain: data.mountain.present ? data.mountain.value : this.mountain,
      keyVersion:
          data.keyVersion.present ? data.keyVersion.value : this.keyVersion,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('ownerId: $ownerId, ')
          ..write('mountain: $mountain, ')
          ..write('keyVersion: $keyVersion, ')
          ..write('createdAtUtc: $createdAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, ownerId, mountain, keyVersion, createdAtUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.ownerId == this.ownerId &&
          other.mountain == this.mountain &&
          other.keyVersion == this.keyVersion &&
          other.createdAtUtc == this.createdAtUtc);
}

class GroupsCompanion extends UpdateCompanion<GroupRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> ownerId;
  final Value<String?> mountain;
  final Value<int> keyVersion;
  final Value<DateTime> createdAtUtc;
  final Value<int> rowid;
  const GroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.mountain = const Value.absent(),
    this.keyVersion = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupsCompanion.insert({
    required String id,
    required String name,
    required String ownerId,
    this.mountain = const Value.absent(),
    this.keyVersion = const Value.absent(),
    required DateTime createdAtUtc,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        ownerId = Value(ownerId),
        createdAtUtc = Value(createdAtUtc);
  static Insertable<GroupRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? ownerId,
    Expression<String>? mountain,
    Expression<int>? keyVersion,
    Expression<DateTime>? createdAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (ownerId != null) 'owner_id': ownerId,
      if (mountain != null) 'mountain': mountain,
      if (keyVersion != null) 'key_version': keyVersion,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? ownerId,
      Value<String?>? mountain,
      Value<int>? keyVersion,
      Value<DateTime>? createdAtUtc,
      Value<int>? rowid}) {
    return GroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      mountain: mountain ?? this.mountain,
      keyVersion: keyVersion ?? this.keyVersion,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (mountain.present) {
      map['mountain'] = Variable<String>(mountain.value);
    }
    if (keyVersion.present) {
      map['key_version'] = Variable<int>(keyVersion.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('ownerId: $ownerId, ')
          ..write('mountain: $mountain, ')
          ..write('keyVersion: $keyVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MembersTable extends Members with TableInfo<$MembersTable, MemberRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta =
      const VerificationMeta('groupId');
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
      'group_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES "groups" (id) ON DELETE CASCADE'));
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _usernameMeta =
      const VerificationMeta('username');
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
      'username', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 3, maxTextLength: 20),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('member'));
  static const VerificationMeta _joinedAtUtcMeta =
      const VerificationMeta('joinedAtUtc');
  @override
  late final GeneratedColumn<DateTime> joinedAtUtc = GeneratedColumn<DateTime>(
      'joined_at_utc', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [groupId, userId, username, role, joinedAtUtc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'members';
  @override
  VerificationContext validateIntegrity(Insertable<MemberRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(_groupIdMeta,
          groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta));
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('username')) {
      context.handle(_usernameMeta,
          username.isAcceptableOrUnknown(data['username']!, _usernameMeta));
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    }
    if (data.containsKey('joined_at_utc')) {
      context.handle(
          _joinedAtUtcMeta,
          joinedAtUtc.isAcceptableOrUnknown(
              data['joined_at_utc']!, _joinedAtUtcMeta));
    } else if (isInserting) {
      context.missing(_joinedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, userId};
  @override
  MemberRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemberRow(
      groupId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}group_id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      username: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}username'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      joinedAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}joined_at_utc'])!,
    );
  }

  @override
  $MembersTable createAlias(String alias) {
    return $MembersTable(attachedDatabase, alias);
  }
}

class MemberRow extends DataClass implements Insertable<MemberRow> {
  final String groupId;
  final String userId;
  final String username;
  final String role;
  final DateTime joinedAtUtc;
  const MemberRow(
      {required this.groupId,
      required this.userId,
      required this.username,
      required this.role,
      required this.joinedAtUtc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['user_id'] = Variable<String>(userId);
    map['username'] = Variable<String>(username);
    map['role'] = Variable<String>(role);
    map['joined_at_utc'] = Variable<DateTime>(joinedAtUtc);
    return map;
  }

  MembersCompanion toCompanion(bool nullToAbsent) {
    return MembersCompanion(
      groupId: Value(groupId),
      userId: Value(userId),
      username: Value(username),
      role: Value(role),
      joinedAtUtc: Value(joinedAtUtc),
    );
  }

  factory MemberRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemberRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      userId: serializer.fromJson<String>(json['userId']),
      username: serializer.fromJson<String>(json['username']),
      role: serializer.fromJson<String>(json['role']),
      joinedAtUtc: serializer.fromJson<DateTime>(json['joinedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'userId': serializer.toJson<String>(userId),
      'username': serializer.toJson<String>(username),
      'role': serializer.toJson<String>(role),
      'joinedAtUtc': serializer.toJson<DateTime>(joinedAtUtc),
    };
  }

  MemberRow copyWith(
          {String? groupId,
          String? userId,
          String? username,
          String? role,
          DateTime? joinedAtUtc}) =>
      MemberRow(
        groupId: groupId ?? this.groupId,
        userId: userId ?? this.userId,
        username: username ?? this.username,
        role: role ?? this.role,
        joinedAtUtc: joinedAtUtc ?? this.joinedAtUtc,
      );
  MemberRow copyWithCompanion(MembersCompanion data) {
    return MemberRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      userId: data.userId.present ? data.userId.value : this.userId,
      username: data.username.present ? data.username.value : this.username,
      role: data.role.present ? data.role.value : this.role,
      joinedAtUtc:
          data.joinedAtUtc.present ? data.joinedAtUtc.value : this.joinedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemberRow(')
          ..write('groupId: $groupId, ')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('role: $role, ')
          ..write('joinedAtUtc: $joinedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(groupId, userId, username, role, joinedAtUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemberRow &&
          other.groupId == this.groupId &&
          other.userId == this.userId &&
          other.username == this.username &&
          other.role == this.role &&
          other.joinedAtUtc == this.joinedAtUtc);
}

class MembersCompanion extends UpdateCompanion<MemberRow> {
  final Value<String> groupId;
  final Value<String> userId;
  final Value<String> username;
  final Value<String> role;
  final Value<DateTime> joinedAtUtc;
  final Value<int> rowid;
  const MembersCompanion({
    this.groupId = const Value.absent(),
    this.userId = const Value.absent(),
    this.username = const Value.absent(),
    this.role = const Value.absent(),
    this.joinedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MembersCompanion.insert({
    required String groupId,
    required String userId,
    required String username,
    this.role = const Value.absent(),
    required DateTime joinedAtUtc,
    this.rowid = const Value.absent(),
  })  : groupId = Value(groupId),
        userId = Value(userId),
        username = Value(username),
        joinedAtUtc = Value(joinedAtUtc);
  static Insertable<MemberRow> custom({
    Expression<String>? groupId,
    Expression<String>? userId,
    Expression<String>? username,
    Expression<String>? role,
    Expression<DateTime>? joinedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (userId != null) 'user_id': userId,
      if (username != null) 'username': username,
      if (role != null) 'role': role,
      if (joinedAtUtc != null) 'joined_at_utc': joinedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MembersCompanion copyWith(
      {Value<String>? groupId,
      Value<String>? userId,
      Value<String>? username,
      Value<String>? role,
      Value<DateTime>? joinedAtUtc,
      Value<int>? rowid}) {
    return MembersCompanion(
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      role: role ?? this.role,
      joinedAtUtc: joinedAtUtc ?? this.joinedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (joinedAtUtc.present) {
      map['joined_at_utc'] = Variable<DateTime>(joinedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembersCompanion(')
          ..write('groupId: $groupId, ')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('role: $role, ')
          ..write('joinedAtUtc: $joinedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InvitationsTable extends Invitations
    with TableInfo<$InvitationsTable, InvitationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InvitationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _groupIdMeta =
      const VerificationMeta('groupId');
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
      'group_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _inviterIdMeta =
      const VerificationMeta('inviterId');
  @override
  late final GeneratedColumn<String> inviterId = GeneratedColumn<String>(
      'inviter_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _inviteeUsernameMeta =
      const VerificationMeta('inviteeUsername');
  @override
  late final GeneratedColumn<String> inviteeUsername = GeneratedColumn<String>(
      'invitee_username', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 3, maxTextLength: 20),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _createdAtUtcMeta =
      const VerificationMeta('createdAtUtc');
  @override
  late final GeneratedColumn<DateTime> createdAtUtc = GeneratedColumn<DateTime>(
      'created_at_utc', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _expiresAtUtcMeta =
      const VerificationMeta('expiresAtUtc');
  @override
  late final GeneratedColumn<DateTime> expiresAtUtc = GeneratedColumn<DateTime>(
      'expires_at_utc', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        groupId,
        inviterId,
        inviteeUsername,
        status,
        createdAtUtc,
        expiresAtUtc
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'invitations';
  @override
  VerificationContext validateIntegrity(Insertable<InvitationRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(_groupIdMeta,
          groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta));
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('inviter_id')) {
      context.handle(_inviterIdMeta,
          inviterId.isAcceptableOrUnknown(data['inviter_id']!, _inviterIdMeta));
    } else if (isInserting) {
      context.missing(_inviterIdMeta);
    }
    if (data.containsKey('invitee_username')) {
      context.handle(
          _inviteeUsernameMeta,
          inviteeUsername.isAcceptableOrUnknown(
              data['invitee_username']!, _inviteeUsernameMeta));
    } else if (isInserting) {
      context.missing(_inviteeUsernameMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
          _createdAtUtcMeta,
          createdAtUtc.isAcceptableOrUnknown(
              data['created_at_utc']!, _createdAtUtcMeta));
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('expires_at_utc')) {
      context.handle(
          _expiresAtUtcMeta,
          expiresAtUtc.isAcceptableOrUnknown(
              data['expires_at_utc']!, _expiresAtUtcMeta));
    } else if (isInserting) {
      context.missing(_expiresAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InvitationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InvitationRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      groupId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}group_id'])!,
      inviterId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}inviter_id'])!,
      inviteeUsername: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}invitee_username'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      createdAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}created_at_utc'])!,
      expiresAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}expires_at_utc'])!,
    );
  }

  @override
  $InvitationsTable createAlias(String alias) {
    return $InvitationsTable(attachedDatabase, alias);
  }
}

class InvitationRow extends DataClass implements Insertable<InvitationRow> {
  final String id;
  final String groupId;
  final String inviterId;
  final String inviteeUsername;
  final String status;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;
  const InvitationRow(
      {required this.id,
      required this.groupId,
      required this.inviterId,
      required this.inviteeUsername,
      required this.status,
      required this.createdAtUtc,
      required this.expiresAtUtc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['group_id'] = Variable<String>(groupId);
    map['inviter_id'] = Variable<String>(inviterId);
    map['invitee_username'] = Variable<String>(inviteeUsername);
    map['status'] = Variable<String>(status);
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    map['expires_at_utc'] = Variable<DateTime>(expiresAtUtc);
    return map;
  }

  InvitationsCompanion toCompanion(bool nullToAbsent) {
    return InvitationsCompanion(
      id: Value(id),
      groupId: Value(groupId),
      inviterId: Value(inviterId),
      inviteeUsername: Value(inviteeUsername),
      status: Value(status),
      createdAtUtc: Value(createdAtUtc),
      expiresAtUtc: Value(expiresAtUtc),
    );
  }

  factory InvitationRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InvitationRow(
      id: serializer.fromJson<String>(json['id']),
      groupId: serializer.fromJson<String>(json['groupId']),
      inviterId: serializer.fromJson<String>(json['inviterId']),
      inviteeUsername: serializer.fromJson<String>(json['inviteeUsername']),
      status: serializer.fromJson<String>(json['status']),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
      expiresAtUtc: serializer.fromJson<DateTime>(json['expiresAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'groupId': serializer.toJson<String>(groupId),
      'inviterId': serializer.toJson<String>(inviterId),
      'inviteeUsername': serializer.toJson<String>(inviteeUsername),
      'status': serializer.toJson<String>(status),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
      'expiresAtUtc': serializer.toJson<DateTime>(expiresAtUtc),
    };
  }

  InvitationRow copyWith(
          {String? id,
          String? groupId,
          String? inviterId,
          String? inviteeUsername,
          String? status,
          DateTime? createdAtUtc,
          DateTime? expiresAtUtc}) =>
      InvitationRow(
        id: id ?? this.id,
        groupId: groupId ?? this.groupId,
        inviterId: inviterId ?? this.inviterId,
        inviteeUsername: inviteeUsername ?? this.inviteeUsername,
        status: status ?? this.status,
        createdAtUtc: createdAtUtc ?? this.createdAtUtc,
        expiresAtUtc: expiresAtUtc ?? this.expiresAtUtc,
      );
  InvitationRow copyWithCompanion(InvitationsCompanion data) {
    return InvitationRow(
      id: data.id.present ? data.id.value : this.id,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      inviterId: data.inviterId.present ? data.inviterId.value : this.inviterId,
      inviteeUsername: data.inviteeUsername.present
          ? data.inviteeUsername.value
          : this.inviteeUsername,
      status: data.status.present ? data.status.value : this.status,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      expiresAtUtc: data.expiresAtUtc.present
          ? data.expiresAtUtc.value
          : this.expiresAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InvitationRow(')
          ..write('id: $id, ')
          ..write('groupId: $groupId, ')
          ..write('inviterId: $inviterId, ')
          ..write('inviteeUsername: $inviteeUsername, ')
          ..write('status: $status, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('expiresAtUtc: $expiresAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, groupId, inviterId, inviteeUsername,
      status, createdAtUtc, expiresAtUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InvitationRow &&
          other.id == this.id &&
          other.groupId == this.groupId &&
          other.inviterId == this.inviterId &&
          other.inviteeUsername == this.inviteeUsername &&
          other.status == this.status &&
          other.createdAtUtc == this.createdAtUtc &&
          other.expiresAtUtc == this.expiresAtUtc);
}

class InvitationsCompanion extends UpdateCompanion<InvitationRow> {
  final Value<String> id;
  final Value<String> groupId;
  final Value<String> inviterId;
  final Value<String> inviteeUsername;
  final Value<String> status;
  final Value<DateTime> createdAtUtc;
  final Value<DateTime> expiresAtUtc;
  final Value<int> rowid;
  const InvitationsCompanion({
    this.id = const Value.absent(),
    this.groupId = const Value.absent(),
    this.inviterId = const Value.absent(),
    this.inviteeUsername = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.expiresAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InvitationsCompanion.insert({
    required String id,
    required String groupId,
    required String inviterId,
    required String inviteeUsername,
    this.status = const Value.absent(),
    required DateTime createdAtUtc,
    required DateTime expiresAtUtc,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        groupId = Value(groupId),
        inviterId = Value(inviterId),
        inviteeUsername = Value(inviteeUsername),
        createdAtUtc = Value(createdAtUtc),
        expiresAtUtc = Value(expiresAtUtc);
  static Insertable<InvitationRow> custom({
    Expression<String>? id,
    Expression<String>? groupId,
    Expression<String>? inviterId,
    Expression<String>? inviteeUsername,
    Expression<String>? status,
    Expression<DateTime>? createdAtUtc,
    Expression<DateTime>? expiresAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (groupId != null) 'group_id': groupId,
      if (inviterId != null) 'inviter_id': inviterId,
      if (inviteeUsername != null) 'invitee_username': inviteeUsername,
      if (status != null) 'status': status,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (expiresAtUtc != null) 'expires_at_utc': expiresAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InvitationsCompanion copyWith(
      {Value<String>? id,
      Value<String>? groupId,
      Value<String>? inviterId,
      Value<String>? inviteeUsername,
      Value<String>? status,
      Value<DateTime>? createdAtUtc,
      Value<DateTime>? expiresAtUtc,
      Value<int>? rowid}) {
    return InvitationsCompanion(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      inviterId: inviterId ?? this.inviterId,
      inviteeUsername: inviteeUsername ?? this.inviteeUsername,
      status: status ?? this.status,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      expiresAtUtc: expiresAtUtc ?? this.expiresAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (inviterId.present) {
      map['inviter_id'] = Variable<String>(inviterId.value);
    }
    if (inviteeUsername.present) {
      map['invitee_username'] = Variable<String>(inviteeUsername.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (expiresAtUtc.present) {
      map['expires_at_utc'] = Variable<DateTime>(expiresAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InvitationsCompanion(')
          ..write('id: $id, ')
          ..write('groupId: $groupId, ')
          ..write('inviterId: $inviterId, ')
          ..write('inviteeUsername: $inviteeUsername, ')
          ..write('status: $status, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('expiresAtUtc: $expiresAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages
    with TableInfo<$MessagesTable, MessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorIdMeta =
      const VerificationMeta('authorId');
  @override
  late final GeneratedColumn<String> authorId = GeneratedColumn<String>(
      'author_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
      'seq', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _groupIdMeta =
      const VerificationMeta('groupId');
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
      'group_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeCodeMeta =
      const VerificationMeta('typeCode');
  @override
  late final GeneratedColumn<int> typeCode = GeneratedColumn<int>(
      'type_code', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _sentAtUtcMeta =
      const VerificationMeta('sentAtUtc');
  @override
  late final GeneratedColumn<DateTime> sentAtUtc = GeneratedColumn<DateTime>(
      'sent_at_utc', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _receivedAtUtcMeta =
      const VerificationMeta('receivedAtUtc');
  @override
  late final GeneratedColumn<DateTime> receivedAtUtc =
      GeneratedColumn<DateTime>('received_at_utc', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
      'payload', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _signatureMeta =
      const VerificationMeta('signature');
  @override
  late final GeneratedColumn<Uint8List> signature = GeneratedColumn<Uint8List>(
      'signature', aliasedName, true,
      type: DriftSqlType.blob, requiredDuringInsert: false);
  static const VerificationMeta _isOutgoingMeta =
      const VerificationMeta('isOutgoing');
  @override
  late final GeneratedColumn<bool> isOutgoing = GeneratedColumn<bool>(
      'is_outgoing', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_outgoing" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        authorId,
        seq,
        groupId,
        typeCode,
        sentAtUtc,
        receivedAtUtc,
        payload,
        signature,
        isOutgoing
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<MessageRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('author_id')) {
      context.handle(_authorIdMeta,
          authorId.isAcceptableOrUnknown(data['author_id']!, _authorIdMeta));
    } else if (isInserting) {
      context.missing(_authorIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
          _seqMeta, seq.isAcceptableOrUnknown(data['seq']!, _seqMeta));
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(_groupIdMeta,
          groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta));
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('type_code')) {
      context.handle(_typeCodeMeta,
          typeCode.isAcceptableOrUnknown(data['type_code']!, _typeCodeMeta));
    } else if (isInserting) {
      context.missing(_typeCodeMeta);
    }
    if (data.containsKey('sent_at_utc')) {
      context.handle(
          _sentAtUtcMeta,
          sentAtUtc.isAcceptableOrUnknown(
              data['sent_at_utc']!, _sentAtUtcMeta));
    } else if (isInserting) {
      context.missing(_sentAtUtcMeta);
    }
    if (data.containsKey('received_at_utc')) {
      context.handle(
          _receivedAtUtcMeta,
          receivedAtUtc.isAcceptableOrUnknown(
              data['received_at_utc']!, _receivedAtUtcMeta));
    } else if (isInserting) {
      context.missing(_receivedAtUtcMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('signature')) {
      context.handle(_signatureMeta,
          signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta));
    }
    if (data.containsKey('is_outgoing')) {
      context.handle(
          _isOutgoingMeta,
          isOutgoing.isAcceptableOrUnknown(
              data['is_outgoing']!, _isOutgoingMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {authorId, seq},
      ];
  @override
  MessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      authorId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author_id'])!,
      seq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}seq'])!,
      groupId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}group_id'])!,
      typeCode: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}type_code'])!,
      sentAtUtc: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}sent_at_utc'])!,
      receivedAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}received_at_utc'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}payload'])!,
      signature: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}signature']),
      isOutgoing: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_outgoing'])!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class MessageRow extends DataClass implements Insertable<MessageRow> {
  final String id;
  final String authorId;
  final int seq;
  final String groupId;
  final int typeCode;
  final DateTime sentAtUtc;
  final DateTime receivedAtUtc;
  final Uint8List payload;
  final Uint8List? signature;
  final bool isOutgoing;
  const MessageRow(
      {required this.id,
      required this.authorId,
      required this.seq,
      required this.groupId,
      required this.typeCode,
      required this.sentAtUtc,
      required this.receivedAtUtc,
      required this.payload,
      this.signature,
      required this.isOutgoing});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['author_id'] = Variable<String>(authorId);
    map['seq'] = Variable<int>(seq);
    map['group_id'] = Variable<String>(groupId);
    map['type_code'] = Variable<int>(typeCode);
    map['sent_at_utc'] = Variable<DateTime>(sentAtUtc);
    map['received_at_utc'] = Variable<DateTime>(receivedAtUtc);
    map['payload'] = Variable<Uint8List>(payload);
    if (!nullToAbsent || signature != null) {
      map['signature'] = Variable<Uint8List>(signature);
    }
    map['is_outgoing'] = Variable<bool>(isOutgoing);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      authorId: Value(authorId),
      seq: Value(seq),
      groupId: Value(groupId),
      typeCode: Value(typeCode),
      sentAtUtc: Value(sentAtUtc),
      receivedAtUtc: Value(receivedAtUtc),
      payload: Value(payload),
      signature: signature == null && nullToAbsent
          ? const Value.absent()
          : Value(signature),
      isOutgoing: Value(isOutgoing),
    );
  }

  factory MessageRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageRow(
      id: serializer.fromJson<String>(json['id']),
      authorId: serializer.fromJson<String>(json['authorId']),
      seq: serializer.fromJson<int>(json['seq']),
      groupId: serializer.fromJson<String>(json['groupId']),
      typeCode: serializer.fromJson<int>(json['typeCode']),
      sentAtUtc: serializer.fromJson<DateTime>(json['sentAtUtc']),
      receivedAtUtc: serializer.fromJson<DateTime>(json['receivedAtUtc']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
      signature: serializer.fromJson<Uint8List?>(json['signature']),
      isOutgoing: serializer.fromJson<bool>(json['isOutgoing']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'authorId': serializer.toJson<String>(authorId),
      'seq': serializer.toJson<int>(seq),
      'groupId': serializer.toJson<String>(groupId),
      'typeCode': serializer.toJson<int>(typeCode),
      'sentAtUtc': serializer.toJson<DateTime>(sentAtUtc),
      'receivedAtUtc': serializer.toJson<DateTime>(receivedAtUtc),
      'payload': serializer.toJson<Uint8List>(payload),
      'signature': serializer.toJson<Uint8List?>(signature),
      'isOutgoing': serializer.toJson<bool>(isOutgoing),
    };
  }

  MessageRow copyWith(
          {String? id,
          String? authorId,
          int? seq,
          String? groupId,
          int? typeCode,
          DateTime? sentAtUtc,
          DateTime? receivedAtUtc,
          Uint8List? payload,
          Value<Uint8List?> signature = const Value.absent(),
          bool? isOutgoing}) =>
      MessageRow(
        id: id ?? this.id,
        authorId: authorId ?? this.authorId,
        seq: seq ?? this.seq,
        groupId: groupId ?? this.groupId,
        typeCode: typeCode ?? this.typeCode,
        sentAtUtc: sentAtUtc ?? this.sentAtUtc,
        receivedAtUtc: receivedAtUtc ?? this.receivedAtUtc,
        payload: payload ?? this.payload,
        signature: signature.present ? signature.value : this.signature,
        isOutgoing: isOutgoing ?? this.isOutgoing,
      );
  MessageRow copyWithCompanion(MessagesCompanion data) {
    return MessageRow(
      id: data.id.present ? data.id.value : this.id,
      authorId: data.authorId.present ? data.authorId.value : this.authorId,
      seq: data.seq.present ? data.seq.value : this.seq,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      typeCode: data.typeCode.present ? data.typeCode.value : this.typeCode,
      sentAtUtc: data.sentAtUtc.present ? data.sentAtUtc.value : this.sentAtUtc,
      receivedAtUtc: data.receivedAtUtc.present
          ? data.receivedAtUtc.value
          : this.receivedAtUtc,
      payload: data.payload.present ? data.payload.value : this.payload,
      signature: data.signature.present ? data.signature.value : this.signature,
      isOutgoing:
          data.isOutgoing.present ? data.isOutgoing.value : this.isOutgoing,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageRow(')
          ..write('id: $id, ')
          ..write('authorId: $authorId, ')
          ..write('seq: $seq, ')
          ..write('groupId: $groupId, ')
          ..write('typeCode: $typeCode, ')
          ..write('sentAtUtc: $sentAtUtc, ')
          ..write('receivedAtUtc: $receivedAtUtc, ')
          ..write('payload: $payload, ')
          ..write('signature: $signature, ')
          ..write('isOutgoing: $isOutgoing')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      authorId,
      seq,
      groupId,
      typeCode,
      sentAtUtc,
      receivedAtUtc,
      $driftBlobEquality.hash(payload),
      $driftBlobEquality.hash(signature),
      isOutgoing);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRow &&
          other.id == this.id &&
          other.authorId == this.authorId &&
          other.seq == this.seq &&
          other.groupId == this.groupId &&
          other.typeCode == this.typeCode &&
          other.sentAtUtc == this.sentAtUtc &&
          other.receivedAtUtc == this.receivedAtUtc &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          $driftBlobEquality.equals(other.signature, this.signature) &&
          other.isOutgoing == this.isOutgoing);
}

class MessagesCompanion extends UpdateCompanion<MessageRow> {
  final Value<String> id;
  final Value<String> authorId;
  final Value<int> seq;
  final Value<String> groupId;
  final Value<int> typeCode;
  final Value<DateTime> sentAtUtc;
  final Value<DateTime> receivedAtUtc;
  final Value<Uint8List> payload;
  final Value<Uint8List?> signature;
  final Value<bool> isOutgoing;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.authorId = const Value.absent(),
    this.seq = const Value.absent(),
    this.groupId = const Value.absent(),
    this.typeCode = const Value.absent(),
    this.sentAtUtc = const Value.absent(),
    this.receivedAtUtc = const Value.absent(),
    this.payload = const Value.absent(),
    this.signature = const Value.absent(),
    this.isOutgoing = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String authorId,
    required int seq,
    required String groupId,
    required int typeCode,
    required DateTime sentAtUtc,
    required DateTime receivedAtUtc,
    required Uint8List payload,
    this.signature = const Value.absent(),
    this.isOutgoing = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        authorId = Value(authorId),
        seq = Value(seq),
        groupId = Value(groupId),
        typeCode = Value(typeCode),
        sentAtUtc = Value(sentAtUtc),
        receivedAtUtc = Value(receivedAtUtc),
        payload = Value(payload);
  static Insertable<MessageRow> custom({
    Expression<String>? id,
    Expression<String>? authorId,
    Expression<int>? seq,
    Expression<String>? groupId,
    Expression<int>? typeCode,
    Expression<DateTime>? sentAtUtc,
    Expression<DateTime>? receivedAtUtc,
    Expression<Uint8List>? payload,
    Expression<Uint8List>? signature,
    Expression<bool>? isOutgoing,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (authorId != null) 'author_id': authorId,
      if (seq != null) 'seq': seq,
      if (groupId != null) 'group_id': groupId,
      if (typeCode != null) 'type_code': typeCode,
      if (sentAtUtc != null) 'sent_at_utc': sentAtUtc,
      if (receivedAtUtc != null) 'received_at_utc': receivedAtUtc,
      if (payload != null) 'payload': payload,
      if (signature != null) 'signature': signature,
      if (isOutgoing != null) 'is_outgoing': isOutgoing,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? authorId,
      Value<int>? seq,
      Value<String>? groupId,
      Value<int>? typeCode,
      Value<DateTime>? sentAtUtc,
      Value<DateTime>? receivedAtUtc,
      Value<Uint8List>? payload,
      Value<Uint8List?>? signature,
      Value<bool>? isOutgoing,
      Value<int>? rowid}) {
    return MessagesCompanion(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      seq: seq ?? this.seq,
      groupId: groupId ?? this.groupId,
      typeCode: typeCode ?? this.typeCode,
      sentAtUtc: sentAtUtc ?? this.sentAtUtc,
      receivedAtUtc: receivedAtUtc ?? this.receivedAtUtc,
      payload: payload ?? this.payload,
      signature: signature ?? this.signature,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (authorId.present) {
      map['author_id'] = Variable<String>(authorId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (typeCode.present) {
      map['type_code'] = Variable<int>(typeCode.value);
    }
    if (sentAtUtc.present) {
      map['sent_at_utc'] = Variable<DateTime>(sentAtUtc.value);
    }
    if (receivedAtUtc.present) {
      map['received_at_utc'] = Variable<DateTime>(receivedAtUtc.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (signature.present) {
      map['signature'] = Variable<Uint8List>(signature.value);
    }
    if (isOutgoing.present) {
      map['is_outgoing'] = Variable<bool>(isOutgoing.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('authorId: $authorId, ')
          ..write('seq: $seq, ')
          ..write('groupId: $groupId, ')
          ..write('typeCode: $typeCode, ')
          ..write('sentAtUtc: $sentAtUtc, ')
          ..write('receivedAtUtc: $receivedAtUtc, ')
          ..write('payload: $payload, ')
          ..write('signature: $signature, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaTable extends Media with TableInfo<$MediaTable, MediaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _messageIdMeta =
      const VerificationMeta('messageId');
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
      'message_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES messages (id) ON DELETE SET NULL'));
  static const VerificationMeta _groupIdMeta =
      const VerificationMeta('groupId');
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
      'group_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _relativePathMeta =
      const VerificationMeta('relativePath');
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
      'relative_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _mimeTypeMeta =
      const VerificationMeta('mimeType');
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
      'mime_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _byteSizeMeta =
      const VerificationMeta('byteSize');
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
      'byte_size', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtUtcMeta =
      const VerificationMeta('createdAtUtc');
  @override
  late final GeneratedColumn<DateTime> createdAtUtc = GeneratedColumn<DateTime>(
      'created_at_utc', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        messageId,
        groupId,
        kind,
        relativePath,
        mimeType,
        byteSize,
        createdAtUtc
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media';
  @override
  VerificationContext validateIntegrity(Insertable<MediaRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(_messageIdMeta,
          messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta));
    }
    if (data.containsKey('group_id')) {
      context.handle(_groupIdMeta,
          groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
          _relativePathMeta,
          relativePath.isAcceptableOrUnknown(
              data['relative_path']!, _relativePathMeta));
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(_mimeTypeMeta,
          mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta));
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(_byteSizeMeta,
          byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta));
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
          _createdAtUtcMeta,
          createdAtUtc.isAcceptableOrUnknown(
              data['created_at_utc']!, _createdAtUtcMeta));
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      messageId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message_id']),
      groupId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}group_id']),
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      relativePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}relative_path'])!,
      mimeType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mime_type'])!,
      byteSize: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}byte_size'])!,
      createdAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}created_at_utc'])!,
    );
  }

  @override
  $MediaTable createAlias(String alias) {
    return $MediaTable(attachedDatabase, alias);
  }
}

class MediaRow extends DataClass implements Insertable<MediaRow> {
  final String id;
  final String? messageId;
  final String? groupId;
  final String kind;
  final String relativePath;
  final String mimeType;
  final int byteSize;
  final DateTime createdAtUtc;
  const MediaRow(
      {required this.id,
      this.messageId,
      this.groupId,
      required this.kind,
      required this.relativePath,
      required this.mimeType,
      required this.byteSize,
      required this.createdAtUtc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || messageId != null) {
      map['message_id'] = Variable<String>(messageId);
    }
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    map['kind'] = Variable<String>(kind);
    map['relative_path'] = Variable<String>(relativePath);
    map['mime_type'] = Variable<String>(mimeType);
    map['byte_size'] = Variable<int>(byteSize);
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    return map;
  }

  MediaCompanion toCompanion(bool nullToAbsent) {
    return MediaCompanion(
      id: Value(id),
      messageId: messageId == null && nullToAbsent
          ? const Value.absent()
          : Value(messageId),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      kind: Value(kind),
      relativePath: Value(relativePath),
      mimeType: Value(mimeType),
      byteSize: Value(byteSize),
      createdAtUtc: Value(createdAtUtc),
    );
  }

  factory MediaRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaRow(
      id: serializer.fromJson<String>(json['id']),
      messageId: serializer.fromJson<String?>(json['messageId']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      kind: serializer.fromJson<String>(json['kind']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'messageId': serializer.toJson<String?>(messageId),
      'groupId': serializer.toJson<String?>(groupId),
      'kind': serializer.toJson<String>(kind),
      'relativePath': serializer.toJson<String>(relativePath),
      'mimeType': serializer.toJson<String>(mimeType),
      'byteSize': serializer.toJson<int>(byteSize),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
    };
  }

  MediaRow copyWith(
          {String? id,
          Value<String?> messageId = const Value.absent(),
          Value<String?> groupId = const Value.absent(),
          String? kind,
          String? relativePath,
          String? mimeType,
          int? byteSize,
          DateTime? createdAtUtc}) =>
      MediaRow(
        id: id ?? this.id,
        messageId: messageId.present ? messageId.value : this.messageId,
        groupId: groupId.present ? groupId.value : this.groupId,
        kind: kind ?? this.kind,
        relativePath: relativePath ?? this.relativePath,
        mimeType: mimeType ?? this.mimeType,
        byteSize: byteSize ?? this.byteSize,
        createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      );
  MediaRow copyWithCompanion(MediaCompanion data) {
    return MediaRow(
      id: data.id.present ? data.id.value : this.id,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      kind: data.kind.present ? data.kind.value : this.kind,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaRow(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('groupId: $groupId, ')
          ..write('kind: $kind, ')
          ..write('relativePath: $relativePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('byteSize: $byteSize, ')
          ..write('createdAtUtc: $createdAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, messageId, groupId, kind, relativePath,
      mimeType, byteSize, createdAtUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaRow &&
          other.id == this.id &&
          other.messageId == this.messageId &&
          other.groupId == this.groupId &&
          other.kind == this.kind &&
          other.relativePath == this.relativePath &&
          other.mimeType == this.mimeType &&
          other.byteSize == this.byteSize &&
          other.createdAtUtc == this.createdAtUtc);
}

class MediaCompanion extends UpdateCompanion<MediaRow> {
  final Value<String> id;
  final Value<String?> messageId;
  final Value<String?> groupId;
  final Value<String> kind;
  final Value<String> relativePath;
  final Value<String> mimeType;
  final Value<int> byteSize;
  final Value<DateTime> createdAtUtc;
  final Value<int> rowid;
  const MediaCompanion({
    this.id = const Value.absent(),
    this.messageId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.kind = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaCompanion.insert({
    required String id,
    this.messageId = const Value.absent(),
    this.groupId = const Value.absent(),
    required String kind,
    required String relativePath,
    required String mimeType,
    required int byteSize,
    required DateTime createdAtUtc,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        kind = Value(kind),
        relativePath = Value(relativePath),
        mimeType = Value(mimeType),
        byteSize = Value(byteSize),
        createdAtUtc = Value(createdAtUtc);
  static Insertable<MediaRow> custom({
    Expression<String>? id,
    Expression<String>? messageId,
    Expression<String>? groupId,
    Expression<String>? kind,
    Expression<String>? relativePath,
    Expression<String>? mimeType,
    Expression<int>? byteSize,
    Expression<DateTime>? createdAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageId != null) 'message_id': messageId,
      if (groupId != null) 'group_id': groupId,
      if (kind != null) 'kind': kind,
      if (relativePath != null) 'relative_path': relativePath,
      if (mimeType != null) 'mime_type': mimeType,
      if (byteSize != null) 'byte_size': byteSize,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaCompanion copyWith(
      {Value<String>? id,
      Value<String?>? messageId,
      Value<String?>? groupId,
      Value<String>? kind,
      Value<String>? relativePath,
      Value<String>? mimeType,
      Value<int>? byteSize,
      Value<DateTime>? createdAtUtc,
      Value<int>? rowid}) {
    return MediaCompanion(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      groupId: groupId ?? this.groupId,
      kind: kind ?? this.kind,
      relativePath: relativePath ?? this.relativePath,
      mimeType: mimeType ?? this.mimeType,
      byteSize: byteSize ?? this.byteSize,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaCompanion(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('groupId: $groupId, ')
          ..write('kind: $kind, ')
          ..write('relativePath: $relativePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('byteSize: $byteSize, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions
    with TableInfo<$SessionsTable, SessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startedAtUtcMeta =
      const VerificationMeta('startedAtUtc');
  @override
  late final GeneratedColumn<DateTime> startedAtUtc = GeneratedColumn<DateTime>(
      'started_at_utc', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _endedAtUtcMeta =
      const VerificationMeta('endedAtUtc');
  @override
  late final GeneratedColumn<DateTime> endedAtUtc = GeneratedColumn<DateTime>(
      'ended_at_utc', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _groupIdMeta =
      const VerificationMeta('groupId');
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
      'group_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _trailIdMeta =
      const VerificationMeta('trailId');
  @override
  late final GeneratedColumn<String> trailId = GeneratedColumn<String>(
      'trail_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _distanceMMeta =
      const VerificationMeta('distanceM');
  @override
  late final GeneratedColumn<double> distanceM = GeneratedColumn<double>(
      'distance_m', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _movingSecondsMeta =
      const VerificationMeta('movingSeconds');
  @override
  late final GeneratedColumn<int> movingSeconds = GeneratedColumn<int>(
      'moving_seconds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _elevationGainMMeta =
      const VerificationMeta('elevationGainM');
  @override
  late final GeneratedColumn<double> elevationGainM = GeneratedColumn<double>(
      'elevation_gain_m', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _elevationLossMMeta =
      const VerificationMeta('elevationLossM');
  @override
  late final GeneratedColumn<double> elevationLossM = GeneratedColumn<double>(
      'elevation_loss_m', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('active'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        startedAtUtc,
        endedAtUtc,
        groupId,
        trailId,
        distanceM,
        movingSeconds,
        elevationGainM,
        elevationLossM,
        status
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(Insertable<SessionRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('started_at_utc')) {
      context.handle(
          _startedAtUtcMeta,
          startedAtUtc.isAcceptableOrUnknown(
              data['started_at_utc']!, _startedAtUtcMeta));
    } else if (isInserting) {
      context.missing(_startedAtUtcMeta);
    }
    if (data.containsKey('ended_at_utc')) {
      context.handle(
          _endedAtUtcMeta,
          endedAtUtc.isAcceptableOrUnknown(
              data['ended_at_utc']!, _endedAtUtcMeta));
    }
    if (data.containsKey('group_id')) {
      context.handle(_groupIdMeta,
          groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta));
    }
    if (data.containsKey('trail_id')) {
      context.handle(_trailIdMeta,
          trailId.isAcceptableOrUnknown(data['trail_id']!, _trailIdMeta));
    }
    if (data.containsKey('distance_m')) {
      context.handle(_distanceMMeta,
          distanceM.isAcceptableOrUnknown(data['distance_m']!, _distanceMMeta));
    }
    if (data.containsKey('moving_seconds')) {
      context.handle(
          _movingSecondsMeta,
          movingSeconds.isAcceptableOrUnknown(
              data['moving_seconds']!, _movingSecondsMeta));
    }
    if (data.containsKey('elevation_gain_m')) {
      context.handle(
          _elevationGainMMeta,
          elevationGainM.isAcceptableOrUnknown(
              data['elevation_gain_m']!, _elevationGainMMeta));
    }
    if (data.containsKey('elevation_loss_m')) {
      context.handle(
          _elevationLossMMeta,
          elevationLossM.isAcceptableOrUnknown(
              data['elevation_loss_m']!, _elevationLossMMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      startedAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}started_at_utc'])!,
      endedAtUtc: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}ended_at_utc']),
      groupId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}group_id']),
      trailId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}trail_id']),
      distanceM: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}distance_m'])!,
      movingSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}moving_seconds'])!,
      elevationGainM: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}elevation_gain_m'])!,
      elevationLossM: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}elevation_loss_m'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class SessionRow extends DataClass implements Insertable<SessionRow> {
  final String id;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;
  final String? groupId;
  final String? trailId;
  final double distanceM;
  final int movingSeconds;
  final double elevationGainM;
  final double elevationLossM;
  final String status;
  const SessionRow(
      {required this.id,
      required this.startedAtUtc,
      this.endedAtUtc,
      this.groupId,
      this.trailId,
      required this.distanceM,
      required this.movingSeconds,
      required this.elevationGainM,
      required this.elevationLossM,
      required this.status});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['started_at_utc'] = Variable<DateTime>(startedAtUtc);
    if (!nullToAbsent || endedAtUtc != null) {
      map['ended_at_utc'] = Variable<DateTime>(endedAtUtc);
    }
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    if (!nullToAbsent || trailId != null) {
      map['trail_id'] = Variable<String>(trailId);
    }
    map['distance_m'] = Variable<double>(distanceM);
    map['moving_seconds'] = Variable<int>(movingSeconds);
    map['elevation_gain_m'] = Variable<double>(elevationGainM);
    map['elevation_loss_m'] = Variable<double>(elevationLossM);
    map['status'] = Variable<String>(status);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      startedAtUtc: Value(startedAtUtc),
      endedAtUtc: endedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAtUtc),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      trailId: trailId == null && nullToAbsent
          ? const Value.absent()
          : Value(trailId),
      distanceM: Value(distanceM),
      movingSeconds: Value(movingSeconds),
      elevationGainM: Value(elevationGainM),
      elevationLossM: Value(elevationLossM),
      status: Value(status),
    );
  }

  factory SessionRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionRow(
      id: serializer.fromJson<String>(json['id']),
      startedAtUtc: serializer.fromJson<DateTime>(json['startedAtUtc']),
      endedAtUtc: serializer.fromJson<DateTime?>(json['endedAtUtc']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      trailId: serializer.fromJson<String?>(json['trailId']),
      distanceM: serializer.fromJson<double>(json['distanceM']),
      movingSeconds: serializer.fromJson<int>(json['movingSeconds']),
      elevationGainM: serializer.fromJson<double>(json['elevationGainM']),
      elevationLossM: serializer.fromJson<double>(json['elevationLossM']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'startedAtUtc': serializer.toJson<DateTime>(startedAtUtc),
      'endedAtUtc': serializer.toJson<DateTime?>(endedAtUtc),
      'groupId': serializer.toJson<String?>(groupId),
      'trailId': serializer.toJson<String?>(trailId),
      'distanceM': serializer.toJson<double>(distanceM),
      'movingSeconds': serializer.toJson<int>(movingSeconds),
      'elevationGainM': serializer.toJson<double>(elevationGainM),
      'elevationLossM': serializer.toJson<double>(elevationLossM),
      'status': serializer.toJson<String>(status),
    };
  }

  SessionRow copyWith(
          {String? id,
          DateTime? startedAtUtc,
          Value<DateTime?> endedAtUtc = const Value.absent(),
          Value<String?> groupId = const Value.absent(),
          Value<String?> trailId = const Value.absent(),
          double? distanceM,
          int? movingSeconds,
          double? elevationGainM,
          double? elevationLossM,
          String? status}) =>
      SessionRow(
        id: id ?? this.id,
        startedAtUtc: startedAtUtc ?? this.startedAtUtc,
        endedAtUtc: endedAtUtc.present ? endedAtUtc.value : this.endedAtUtc,
        groupId: groupId.present ? groupId.value : this.groupId,
        trailId: trailId.present ? trailId.value : this.trailId,
        distanceM: distanceM ?? this.distanceM,
        movingSeconds: movingSeconds ?? this.movingSeconds,
        elevationGainM: elevationGainM ?? this.elevationGainM,
        elevationLossM: elevationLossM ?? this.elevationLossM,
        status: status ?? this.status,
      );
  SessionRow copyWithCompanion(SessionsCompanion data) {
    return SessionRow(
      id: data.id.present ? data.id.value : this.id,
      startedAtUtc: data.startedAtUtc.present
          ? data.startedAtUtc.value
          : this.startedAtUtc,
      endedAtUtc:
          data.endedAtUtc.present ? data.endedAtUtc.value : this.endedAtUtc,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      trailId: data.trailId.present ? data.trailId.value : this.trailId,
      distanceM: data.distanceM.present ? data.distanceM.value : this.distanceM,
      movingSeconds: data.movingSeconds.present
          ? data.movingSeconds.value
          : this.movingSeconds,
      elevationGainM: data.elevationGainM.present
          ? data.elevationGainM.value
          : this.elevationGainM,
      elevationLossM: data.elevationLossM.present
          ? data.elevationLossM.value
          : this.elevationLossM,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('id: $id, ')
          ..write('startedAtUtc: $startedAtUtc, ')
          ..write('endedAtUtc: $endedAtUtc, ')
          ..write('groupId: $groupId, ')
          ..write('trailId: $trailId, ')
          ..write('distanceM: $distanceM, ')
          ..write('movingSeconds: $movingSeconds, ')
          ..write('elevationGainM: $elevationGainM, ')
          ..write('elevationLossM: $elevationLossM, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      startedAtUtc,
      endedAtUtc,
      groupId,
      trailId,
      distanceM,
      movingSeconds,
      elevationGainM,
      elevationLossM,
      status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.id == this.id &&
          other.startedAtUtc == this.startedAtUtc &&
          other.endedAtUtc == this.endedAtUtc &&
          other.groupId == this.groupId &&
          other.trailId == this.trailId &&
          other.distanceM == this.distanceM &&
          other.movingSeconds == this.movingSeconds &&
          other.elevationGainM == this.elevationGainM &&
          other.elevationLossM == this.elevationLossM &&
          other.status == this.status);
}

class SessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<String> id;
  final Value<DateTime> startedAtUtc;
  final Value<DateTime?> endedAtUtc;
  final Value<String?> groupId;
  final Value<String?> trailId;
  final Value<double> distanceM;
  final Value<int> movingSeconds;
  final Value<double> elevationGainM;
  final Value<double> elevationLossM;
  final Value<String> status;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.startedAtUtc = const Value.absent(),
    this.endedAtUtc = const Value.absent(),
    this.groupId = const Value.absent(),
    this.trailId = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.movingSeconds = const Value.absent(),
    this.elevationGainM = const Value.absent(),
    this.elevationLossM = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required DateTime startedAtUtc,
    this.endedAtUtc = const Value.absent(),
    this.groupId = const Value.absent(),
    this.trailId = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.movingSeconds = const Value.absent(),
    this.elevationGainM = const Value.absent(),
    this.elevationLossM = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        startedAtUtc = Value(startedAtUtc);
  static Insertable<SessionRow> custom({
    Expression<String>? id,
    Expression<DateTime>? startedAtUtc,
    Expression<DateTime>? endedAtUtc,
    Expression<String>? groupId,
    Expression<String>? trailId,
    Expression<double>? distanceM,
    Expression<int>? movingSeconds,
    Expression<double>? elevationGainM,
    Expression<double>? elevationLossM,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startedAtUtc != null) 'started_at_utc': startedAtUtc,
      if (endedAtUtc != null) 'ended_at_utc': endedAtUtc,
      if (groupId != null) 'group_id': groupId,
      if (trailId != null) 'trail_id': trailId,
      if (distanceM != null) 'distance_m': distanceM,
      if (movingSeconds != null) 'moving_seconds': movingSeconds,
      if (elevationGainM != null) 'elevation_gain_m': elevationGainM,
      if (elevationLossM != null) 'elevation_loss_m': elevationLossM,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith(
      {Value<String>? id,
      Value<DateTime>? startedAtUtc,
      Value<DateTime?>? endedAtUtc,
      Value<String?>? groupId,
      Value<String?>? trailId,
      Value<double>? distanceM,
      Value<int>? movingSeconds,
      Value<double>? elevationGainM,
      Value<double>? elevationLossM,
      Value<String>? status,
      Value<int>? rowid}) {
    return SessionsCompanion(
      id: id ?? this.id,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      endedAtUtc: endedAtUtc ?? this.endedAtUtc,
      groupId: groupId ?? this.groupId,
      trailId: trailId ?? this.trailId,
      distanceM: distanceM ?? this.distanceM,
      movingSeconds: movingSeconds ?? this.movingSeconds,
      elevationGainM: elevationGainM ?? this.elevationGainM,
      elevationLossM: elevationLossM ?? this.elevationLossM,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (startedAtUtc.present) {
      map['started_at_utc'] = Variable<DateTime>(startedAtUtc.value);
    }
    if (endedAtUtc.present) {
      map['ended_at_utc'] = Variable<DateTime>(endedAtUtc.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (trailId.present) {
      map['trail_id'] = Variable<String>(trailId.value);
    }
    if (distanceM.present) {
      map['distance_m'] = Variable<double>(distanceM.value);
    }
    if (movingSeconds.present) {
      map['moving_seconds'] = Variable<int>(movingSeconds.value);
    }
    if (elevationGainM.present) {
      map['elevation_gain_m'] = Variable<double>(elevationGainM.value);
    }
    if (elevationLossM.present) {
      map['elevation_loss_m'] = Variable<double>(elevationLossM.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('startedAtUtc: $startedAtUtc, ')
          ..write('endedAtUtc: $endedAtUtc, ')
          ..write('groupId: $groupId, ')
          ..write('trailId: $trailId, ')
          ..write('distanceM: $distanceM, ')
          ..write('movingSeconds: $movingSeconds, ')
          ..write('elevationGainM: $elevationGainM, ')
          ..write('elevationLossM: $elevationLossM, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrackPointsTable extends TrackPoints
    with TableInfo<$TrackPointsTable, TrackPointRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackPointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
      'session_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES sessions (id) ON DELETE CASCADE'));
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
      'lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
      'lon', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _altitudeMMeta =
      const VerificationMeta('altitudeM');
  @override
  late final GeneratedColumn<double> altitudeM = GeneratedColumn<double>(
      'altitude_m', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _accuracyMMeta =
      const VerificationMeta('accuracyM');
  @override
  late final GeneratedColumn<double> accuracyM = GeneratedColumn<double>(
      'accuracy_m', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _speedMpsMeta =
      const VerificationMeta('speedMps');
  @override
  late final GeneratedColumn<double> speedMps = GeneratedColumn<double>(
      'speed_mps', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _recordedAtUtcMeta =
      const VerificationMeta('recordedAtUtc');
  @override
  late final GeneratedColumn<DateTime> recordedAtUtc =
      GeneratedColumn<DateTime>('recorded_at_utc', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, sessionId, lat, lon, altitudeM, accuracyM, speedMps, recordedAtUtc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'track_points';
  @override
  VerificationContext validateIntegrity(Insertable<TrackPointRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
          _latMeta, lat.isAcceptableOrUnknown(data['lat']!, _latMeta));
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
          _lonMeta, lon.isAcceptableOrUnknown(data['lon']!, _lonMeta));
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('altitude_m')) {
      context.handle(_altitudeMMeta,
          altitudeM.isAcceptableOrUnknown(data['altitude_m']!, _altitudeMMeta));
    }
    if (data.containsKey('accuracy_m')) {
      context.handle(_accuracyMMeta,
          accuracyM.isAcceptableOrUnknown(data['accuracy_m']!, _accuracyMMeta));
    } else if (isInserting) {
      context.missing(_accuracyMMeta);
    }
    if (data.containsKey('speed_mps')) {
      context.handle(_speedMpsMeta,
          speedMps.isAcceptableOrUnknown(data['speed_mps']!, _speedMpsMeta));
    }
    if (data.containsKey('recorded_at_utc')) {
      context.handle(
          _recordedAtUtcMeta,
          recordedAtUtc.isAcceptableOrUnknown(
              data['recorded_at_utc']!, _recordedAtUtcMeta));
    } else if (isInserting) {
      context.missing(_recordedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrackPointRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackPointRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}session_id'])!,
      lat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lat'])!,
      lon: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lon'])!,
      altitudeM: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}altitude_m']),
      accuracyM: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}accuracy_m'])!,
      speedMps: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}speed_mps']),
      recordedAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}recorded_at_utc'])!,
    );
  }

  @override
  $TrackPointsTable createAlias(String alias) {
    return $TrackPointsTable(attachedDatabase, alias);
  }
}

class TrackPointRow extends DataClass implements Insertable<TrackPointRow> {
  final int id;
  final String sessionId;
  final double lat;
  final double lon;
  final double? altitudeM;
  final double accuracyM;
  final double? speedMps;
  final DateTime recordedAtUtc;
  const TrackPointRow(
      {required this.id,
      required this.sessionId,
      required this.lat,
      required this.lon,
      this.altitudeM,
      required this.accuracyM,
      this.speedMps,
      required this.recordedAtUtc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    if (!nullToAbsent || altitudeM != null) {
      map['altitude_m'] = Variable<double>(altitudeM);
    }
    map['accuracy_m'] = Variable<double>(accuracyM);
    if (!nullToAbsent || speedMps != null) {
      map['speed_mps'] = Variable<double>(speedMps);
    }
    map['recorded_at_utc'] = Variable<DateTime>(recordedAtUtc);
    return map;
  }

  TrackPointsCompanion toCompanion(bool nullToAbsent) {
    return TrackPointsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      lat: Value(lat),
      lon: Value(lon),
      altitudeM: altitudeM == null && nullToAbsent
          ? const Value.absent()
          : Value(altitudeM),
      accuracyM: Value(accuracyM),
      speedMps: speedMps == null && nullToAbsent
          ? const Value.absent()
          : Value(speedMps),
      recordedAtUtc: Value(recordedAtUtc),
    );
  }

  factory TrackPointRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackPointRow(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      altitudeM: serializer.fromJson<double?>(json['altitudeM']),
      accuracyM: serializer.fromJson<double>(json['accuracyM']),
      speedMps: serializer.fromJson<double?>(json['speedMps']),
      recordedAtUtc: serializer.fromJson<DateTime>(json['recordedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'altitudeM': serializer.toJson<double?>(altitudeM),
      'accuracyM': serializer.toJson<double>(accuracyM),
      'speedMps': serializer.toJson<double?>(speedMps),
      'recordedAtUtc': serializer.toJson<DateTime>(recordedAtUtc),
    };
  }

  TrackPointRow copyWith(
          {int? id,
          String? sessionId,
          double? lat,
          double? lon,
          Value<double?> altitudeM = const Value.absent(),
          double? accuracyM,
          Value<double?> speedMps = const Value.absent(),
          DateTime? recordedAtUtc}) =>
      TrackPointRow(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        altitudeM: altitudeM.present ? altitudeM.value : this.altitudeM,
        accuracyM: accuracyM ?? this.accuracyM,
        speedMps: speedMps.present ? speedMps.value : this.speedMps,
        recordedAtUtc: recordedAtUtc ?? this.recordedAtUtc,
      );
  TrackPointRow copyWithCompanion(TrackPointsCompanion data) {
    return TrackPointRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      altitudeM: data.altitudeM.present ? data.altitudeM.value : this.altitudeM,
      accuracyM: data.accuracyM.present ? data.accuracyM.value : this.accuracyM,
      speedMps: data.speedMps.present ? data.speedMps.value : this.speedMps,
      recordedAtUtc: data.recordedAtUtc.present
          ? data.recordedAtUtc.value
          : this.recordedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackPointRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('altitudeM: $altitudeM, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('speedMps: $speedMps, ')
          ..write('recordedAtUtc: $recordedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, sessionId, lat, lon, altitudeM, accuracyM, speedMps, recordedAtUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackPointRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.altitudeM == this.altitudeM &&
          other.accuracyM == this.accuracyM &&
          other.speedMps == this.speedMps &&
          other.recordedAtUtc == this.recordedAtUtc);
}

class TrackPointsCompanion extends UpdateCompanion<TrackPointRow> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<double> lat;
  final Value<double> lon;
  final Value<double?> altitudeM;
  final Value<double> accuracyM;
  final Value<double?> speedMps;
  final Value<DateTime> recordedAtUtc;
  const TrackPointsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.altitudeM = const Value.absent(),
    this.accuracyM = const Value.absent(),
    this.speedMps = const Value.absent(),
    this.recordedAtUtc = const Value.absent(),
  });
  TrackPointsCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required double lat,
    required double lon,
    this.altitudeM = const Value.absent(),
    required double accuracyM,
    this.speedMps = const Value.absent(),
    required DateTime recordedAtUtc,
  })  : sessionId = Value(sessionId),
        lat = Value(lat),
        lon = Value(lon),
        accuracyM = Value(accuracyM),
        recordedAtUtc = Value(recordedAtUtc);
  static Insertable<TrackPointRow> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<double>? altitudeM,
    Expression<double>? accuracyM,
    Expression<double>? speedMps,
    Expression<DateTime>? recordedAtUtc,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (altitudeM != null) 'altitude_m': altitudeM,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (speedMps != null) 'speed_mps': speedMps,
      if (recordedAtUtc != null) 'recorded_at_utc': recordedAtUtc,
    });
  }

  TrackPointsCompanion copyWith(
      {Value<int>? id,
      Value<String>? sessionId,
      Value<double>? lat,
      Value<double>? lon,
      Value<double?>? altitudeM,
      Value<double>? accuracyM,
      Value<double?>? speedMps,
      Value<DateTime>? recordedAtUtc}) {
    return TrackPointsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      altitudeM: altitudeM ?? this.altitudeM,
      accuracyM: accuracyM ?? this.accuracyM,
      speedMps: speedMps ?? this.speedMps,
      recordedAtUtc: recordedAtUtc ?? this.recordedAtUtc,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (altitudeM.present) {
      map['altitude_m'] = Variable<double>(altitudeM.value);
    }
    if (accuracyM.present) {
      map['accuracy_m'] = Variable<double>(accuracyM.value);
    }
    if (speedMps.present) {
      map['speed_mps'] = Variable<double>(speedMps.value);
    }
    if (recordedAtUtc.present) {
      map['recorded_at_utc'] = Variable<DateTime>(recordedAtUtc.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackPointsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('altitudeM: $altitudeM, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('speedMps: $speedMps, ')
          ..write('recordedAtUtc: $recordedAtUtc')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageIdMeta =
      const VerificationMeta('messageId');
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
      'message_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _packetMeta = const VerificationMeta('packet');
  @override
  late final GeneratedColumn<Uint8List> packet = GeneratedColumn<Uint8List>(
      'packet', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
      'priority', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _enqueuedAtUtcMeta =
      const VerificationMeta('enqueuedAtUtc');
  @override
  late final GeneratedColumn<DateTime> enqueuedAtUtc =
      GeneratedColumn<DateTime>('enqueued_at_utc', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _nextAttemptAtUtcMeta =
      const VerificationMeta('nextAttemptAtUtc');
  @override
  late final GeneratedColumn<DateTime> nextAttemptAtUtc =
      GeneratedColumn<DateTime>('next_attempt_at_utc', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _repeatUntilAckMeta =
      const VerificationMeta('repeatUntilAck');
  @override
  late final GeneratedColumn<bool> repeatUntilAck = GeneratedColumn<bool>(
      'repeat_until_ack', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("repeat_until_ack" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        messageId,
        packet,
        priority,
        enqueuedAtUtc,
        nextAttemptAtUtc,
        attempts,
        repeatUntilAck
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(Insertable<OutboxRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_id')) {
      context.handle(_messageIdMeta,
          messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta));
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('packet')) {
      context.handle(_packetMeta,
          packet.isAcceptableOrUnknown(data['packet']!, _packetMeta));
    } else if (isInserting) {
      context.missing(_packetMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('enqueued_at_utc')) {
      context.handle(
          _enqueuedAtUtcMeta,
          enqueuedAtUtc.isAcceptableOrUnknown(
              data['enqueued_at_utc']!, _enqueuedAtUtcMeta));
    } else if (isInserting) {
      context.missing(_enqueuedAtUtcMeta);
    }
    if (data.containsKey('next_attempt_at_utc')) {
      context.handle(
          _nextAttemptAtUtcMeta,
          nextAttemptAtUtc.isAcceptableOrUnknown(
              data['next_attempt_at_utc']!, _nextAttemptAtUtcMeta));
    } else if (isInserting) {
      context.missing(_nextAttemptAtUtcMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('repeat_until_ack')) {
      context.handle(
          _repeatUntilAckMeta,
          repeatUntilAck.isAcceptableOrUnknown(
              data['repeat_until_ack']!, _repeatUntilAckMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageId};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      messageId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message_id'])!,
      packet: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}packet'])!,
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}priority'])!,
      enqueuedAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}enqueued_at_utc'])!,
      nextAttemptAtUtc: attachedDatabase.typeMapping.read(DriftSqlType.dateTime,
          data['${effectivePrefix}next_attempt_at_utc'])!,
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      repeatUntilAck: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}repeat_until_ack'])!,
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final String messageId;
  final Uint8List packet;
  final int priority;
  final DateTime enqueuedAtUtc;
  final DateTime nextAttemptAtUtc;
  final int attempts;
  final bool repeatUntilAck;
  const OutboxRow(
      {required this.messageId,
      required this.packet,
      required this.priority,
      required this.enqueuedAtUtc,
      required this.nextAttemptAtUtc,
      required this.attempts,
      required this.repeatUntilAck});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_id'] = Variable<String>(messageId);
    map['packet'] = Variable<Uint8List>(packet);
    map['priority'] = Variable<int>(priority);
    map['enqueued_at_utc'] = Variable<DateTime>(enqueuedAtUtc);
    map['next_attempt_at_utc'] = Variable<DateTime>(nextAttemptAtUtc);
    map['attempts'] = Variable<int>(attempts);
    map['repeat_until_ack'] = Variable<bool>(repeatUntilAck);
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      messageId: Value(messageId),
      packet: Value(packet),
      priority: Value(priority),
      enqueuedAtUtc: Value(enqueuedAtUtc),
      nextAttemptAtUtc: Value(nextAttemptAtUtc),
      attempts: Value(attempts),
      repeatUntilAck: Value(repeatUntilAck),
    );
  }

  factory OutboxRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      messageId: serializer.fromJson<String>(json['messageId']),
      packet: serializer.fromJson<Uint8List>(json['packet']),
      priority: serializer.fromJson<int>(json['priority']),
      enqueuedAtUtc: serializer.fromJson<DateTime>(json['enqueuedAtUtc']),
      nextAttemptAtUtc: serializer.fromJson<DateTime>(json['nextAttemptAtUtc']),
      attempts: serializer.fromJson<int>(json['attempts']),
      repeatUntilAck: serializer.fromJson<bool>(json['repeatUntilAck']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageId': serializer.toJson<String>(messageId),
      'packet': serializer.toJson<Uint8List>(packet),
      'priority': serializer.toJson<int>(priority),
      'enqueuedAtUtc': serializer.toJson<DateTime>(enqueuedAtUtc),
      'nextAttemptAtUtc': serializer.toJson<DateTime>(nextAttemptAtUtc),
      'attempts': serializer.toJson<int>(attempts),
      'repeatUntilAck': serializer.toJson<bool>(repeatUntilAck),
    };
  }

  OutboxRow copyWith(
          {String? messageId,
          Uint8List? packet,
          int? priority,
          DateTime? enqueuedAtUtc,
          DateTime? nextAttemptAtUtc,
          int? attempts,
          bool? repeatUntilAck}) =>
      OutboxRow(
        messageId: messageId ?? this.messageId,
        packet: packet ?? this.packet,
        priority: priority ?? this.priority,
        enqueuedAtUtc: enqueuedAtUtc ?? this.enqueuedAtUtc,
        nextAttemptAtUtc: nextAttemptAtUtc ?? this.nextAttemptAtUtc,
        attempts: attempts ?? this.attempts,
        repeatUntilAck: repeatUntilAck ?? this.repeatUntilAck,
      );
  OutboxRow copyWithCompanion(OutboxCompanion data) {
    return OutboxRow(
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      packet: data.packet.present ? data.packet.value : this.packet,
      priority: data.priority.present ? data.priority.value : this.priority,
      enqueuedAtUtc: data.enqueuedAtUtc.present
          ? data.enqueuedAtUtc.value
          : this.enqueuedAtUtc,
      nextAttemptAtUtc: data.nextAttemptAtUtc.present
          ? data.nextAttemptAtUtc.value
          : this.nextAttemptAtUtc,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      repeatUntilAck: data.repeatUntilAck.present
          ? data.repeatUntilAck.value
          : this.repeatUntilAck,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('messageId: $messageId, ')
          ..write('packet: $packet, ')
          ..write('priority: $priority, ')
          ..write('enqueuedAtUtc: $enqueuedAtUtc, ')
          ..write('nextAttemptAtUtc: $nextAttemptAtUtc, ')
          ..write('attempts: $attempts, ')
          ..write('repeatUntilAck: $repeatUntilAck')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(messageId, $driftBlobEquality.hash(packet),
      priority, enqueuedAtUtc, nextAttemptAtUtc, attempts, repeatUntilAck);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.messageId == this.messageId &&
          $driftBlobEquality.equals(other.packet, this.packet) &&
          other.priority == this.priority &&
          other.enqueuedAtUtc == this.enqueuedAtUtc &&
          other.nextAttemptAtUtc == this.nextAttemptAtUtc &&
          other.attempts == this.attempts &&
          other.repeatUntilAck == this.repeatUntilAck);
}

class OutboxCompanion extends UpdateCompanion<OutboxRow> {
  final Value<String> messageId;
  final Value<Uint8List> packet;
  final Value<int> priority;
  final Value<DateTime> enqueuedAtUtc;
  final Value<DateTime> nextAttemptAtUtc;
  final Value<int> attempts;
  final Value<bool> repeatUntilAck;
  final Value<int> rowid;
  const OutboxCompanion({
    this.messageId = const Value.absent(),
    this.packet = const Value.absent(),
    this.priority = const Value.absent(),
    this.enqueuedAtUtc = const Value.absent(),
    this.nextAttemptAtUtc = const Value.absent(),
    this.attempts = const Value.absent(),
    this.repeatUntilAck = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxCompanion.insert({
    required String messageId,
    required Uint8List packet,
    required int priority,
    required DateTime enqueuedAtUtc,
    required DateTime nextAttemptAtUtc,
    this.attempts = const Value.absent(),
    this.repeatUntilAck = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : messageId = Value(messageId),
        packet = Value(packet),
        priority = Value(priority),
        enqueuedAtUtc = Value(enqueuedAtUtc),
        nextAttemptAtUtc = Value(nextAttemptAtUtc);
  static Insertable<OutboxRow> custom({
    Expression<String>? messageId,
    Expression<Uint8List>? packet,
    Expression<int>? priority,
    Expression<DateTime>? enqueuedAtUtc,
    Expression<DateTime>? nextAttemptAtUtc,
    Expression<int>? attempts,
    Expression<bool>? repeatUntilAck,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageId != null) 'message_id': messageId,
      if (packet != null) 'packet': packet,
      if (priority != null) 'priority': priority,
      if (enqueuedAtUtc != null) 'enqueued_at_utc': enqueuedAtUtc,
      if (nextAttemptAtUtc != null) 'next_attempt_at_utc': nextAttemptAtUtc,
      if (attempts != null) 'attempts': attempts,
      if (repeatUntilAck != null) 'repeat_until_ack': repeatUntilAck,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxCompanion copyWith(
      {Value<String>? messageId,
      Value<Uint8List>? packet,
      Value<int>? priority,
      Value<DateTime>? enqueuedAtUtc,
      Value<DateTime>? nextAttemptAtUtc,
      Value<int>? attempts,
      Value<bool>? repeatUntilAck,
      Value<int>? rowid}) {
    return OutboxCompanion(
      messageId: messageId ?? this.messageId,
      packet: packet ?? this.packet,
      priority: priority ?? this.priority,
      enqueuedAtUtc: enqueuedAtUtc ?? this.enqueuedAtUtc,
      nextAttemptAtUtc: nextAttemptAtUtc ?? this.nextAttemptAtUtc,
      attempts: attempts ?? this.attempts,
      repeatUntilAck: repeatUntilAck ?? this.repeatUntilAck,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (packet.present) {
      map['packet'] = Variable<Uint8List>(packet.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (enqueuedAtUtc.present) {
      map['enqueued_at_utc'] = Variable<DateTime>(enqueuedAtUtc.value);
    }
    if (nextAttemptAtUtc.present) {
      map['next_attempt_at_utc'] = Variable<DateTime>(nextAttemptAtUtc.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (repeatUntilAck.present) {
      map['repeat_until_ack'] = Variable<bool>(repeatUntilAck.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('messageId: $messageId, ')
          ..write('packet: $packet, ')
          ..write('priority: $priority, ')
          ..write('enqueuedAtUtc: $enqueuedAtUtc, ')
          ..write('nextAttemptAtUtc: $nextAttemptAtUtc, ')
          ..write('attempts: $attempts, ')
          ..write('repeatUntilAck: $repeatUntilAck, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SosEventsTable extends SosEvents
    with TableInfo<$SosEventsTable, SosEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SosEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorIdMeta =
      const VerificationMeta('authorId');
  @override
  late final GeneratedColumn<String> authorId = GeneratedColumn<String>(
      'author_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _groupIdMeta =
      const VerificationMeta('groupId');
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
      'group_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES "groups" (id) ON DELETE SET NULL'));
  static const VerificationMeta _categoryCodeMeta =
      const VerificationMeta('categoryCode');
  @override
  late final GeneratedColumn<int> categoryCode = GeneratedColumn<int>(
      'category_code', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
      'lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
      'lon', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _accuracyMMeta =
      const VerificationMeta('accuracyM');
  @override
  late final GeneratedColumn<int> accuracyM = GeneratedColumn<int>(
      'accuracy_m', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _batteryPercentMeta =
      const VerificationMeta('batteryPercent');
  @override
  late final GeneratedColumn<int> batteryPercent = GeneratedColumn<int>(
      'battery_percent', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtUtcMeta =
      const VerificationMeta('createdAtUtc');
  @override
  late final GeneratedColumn<DateTime> createdAtUtc = GeneratedColumn<DateTime>(
      'created_at_utc', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _receivedAtUtcMeta =
      const VerificationMeta('receivedAtUtc');
  @override
  late final GeneratedColumn<DateTime> receivedAtUtc =
      GeneratedColumn<DateTime>('received_at_utc', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('active'));
  static const VerificationMeta _cancelledAtUtcMeta =
      const VerificationMeta('cancelledAtUtc');
  @override
  late final GeneratedColumn<DateTime> cancelledAtUtc =
      GeneratedColumn<DateTime>('cancelled_at_utc', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        authorId,
        groupId,
        categoryCode,
        lat,
        lon,
        accuracyM,
        batteryPercent,
        createdAtUtc,
        receivedAtUtc,
        status,
        cancelledAtUtc
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sos_events';
  @override
  VerificationContext validateIntegrity(Insertable<SosEventRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('author_id')) {
      context.handle(_authorIdMeta,
          authorId.isAcceptableOrUnknown(data['author_id']!, _authorIdMeta));
    } else if (isInserting) {
      context.missing(_authorIdMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(_groupIdMeta,
          groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta));
    }
    if (data.containsKey('category_code')) {
      context.handle(
          _categoryCodeMeta,
          categoryCode.isAcceptableOrUnknown(
              data['category_code']!, _categoryCodeMeta));
    } else if (isInserting) {
      context.missing(_categoryCodeMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
          _latMeta, lat.isAcceptableOrUnknown(data['lat']!, _latMeta));
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
          _lonMeta, lon.isAcceptableOrUnknown(data['lon']!, _lonMeta));
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('accuracy_m')) {
      context.handle(_accuracyMMeta,
          accuracyM.isAcceptableOrUnknown(data['accuracy_m']!, _accuracyMMeta));
    }
    if (data.containsKey('battery_percent')) {
      context.handle(
          _batteryPercentMeta,
          batteryPercent.isAcceptableOrUnknown(
              data['battery_percent']!, _batteryPercentMeta));
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
          _createdAtUtcMeta,
          createdAtUtc.isAcceptableOrUnknown(
              data['created_at_utc']!, _createdAtUtcMeta));
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('received_at_utc')) {
      context.handle(
          _receivedAtUtcMeta,
          receivedAtUtc.isAcceptableOrUnknown(
              data['received_at_utc']!, _receivedAtUtcMeta));
    } else if (isInserting) {
      context.missing(_receivedAtUtcMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('cancelled_at_utc')) {
      context.handle(
          _cancelledAtUtcMeta,
          cancelledAtUtc.isAcceptableOrUnknown(
              data['cancelled_at_utc']!, _cancelledAtUtcMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SosEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SosEventRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      authorId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author_id'])!,
      groupId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}group_id']),
      categoryCode: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}category_code'])!,
      lat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lat'])!,
      lon: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lon'])!,
      accuracyM: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}accuracy_m']),
      batteryPercent: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}battery_percent']),
      createdAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}created_at_utc'])!,
      receivedAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}received_at_utc'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      cancelledAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}cancelled_at_utc']),
    );
  }

  @override
  $SosEventsTable createAlias(String alias) {
    return $SosEventsTable(attachedDatabase, alias);
  }
}

class SosEventRow extends DataClass implements Insertable<SosEventRow> {
  final String id;
  final String authorId;
  final String? groupId;
  final int categoryCode;
  final double lat;
  final double lon;
  final int? accuracyM;
  final int? batteryPercent;
  final DateTime createdAtUtc;
  final DateTime receivedAtUtc;
  final String status;
  final DateTime? cancelledAtUtc;
  const SosEventRow(
      {required this.id,
      required this.authorId,
      this.groupId,
      required this.categoryCode,
      required this.lat,
      required this.lon,
      this.accuracyM,
      this.batteryPercent,
      required this.createdAtUtc,
      required this.receivedAtUtc,
      required this.status,
      this.cancelledAtUtc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['author_id'] = Variable<String>(authorId);
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    map['category_code'] = Variable<int>(categoryCode);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    if (!nullToAbsent || accuracyM != null) {
      map['accuracy_m'] = Variable<int>(accuracyM);
    }
    if (!nullToAbsent || batteryPercent != null) {
      map['battery_percent'] = Variable<int>(batteryPercent);
    }
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    map['received_at_utc'] = Variable<DateTime>(receivedAtUtc);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || cancelledAtUtc != null) {
      map['cancelled_at_utc'] = Variable<DateTime>(cancelledAtUtc);
    }
    return map;
  }

  SosEventsCompanion toCompanion(bool nullToAbsent) {
    return SosEventsCompanion(
      id: Value(id),
      authorId: Value(authorId),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      categoryCode: Value(categoryCode),
      lat: Value(lat),
      lon: Value(lon),
      accuracyM: accuracyM == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracyM),
      batteryPercent: batteryPercent == null && nullToAbsent
          ? const Value.absent()
          : Value(batteryPercent),
      createdAtUtc: Value(createdAtUtc),
      receivedAtUtc: Value(receivedAtUtc),
      status: Value(status),
      cancelledAtUtc: cancelledAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(cancelledAtUtc),
    );
  }

  factory SosEventRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SosEventRow(
      id: serializer.fromJson<String>(json['id']),
      authorId: serializer.fromJson<String>(json['authorId']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      categoryCode: serializer.fromJson<int>(json['categoryCode']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      accuracyM: serializer.fromJson<int?>(json['accuracyM']),
      batteryPercent: serializer.fromJson<int?>(json['batteryPercent']),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
      receivedAtUtc: serializer.fromJson<DateTime>(json['receivedAtUtc']),
      status: serializer.fromJson<String>(json['status']),
      cancelledAtUtc: serializer.fromJson<DateTime?>(json['cancelledAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'authorId': serializer.toJson<String>(authorId),
      'groupId': serializer.toJson<String?>(groupId),
      'categoryCode': serializer.toJson<int>(categoryCode),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'accuracyM': serializer.toJson<int?>(accuracyM),
      'batteryPercent': serializer.toJson<int?>(batteryPercent),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
      'receivedAtUtc': serializer.toJson<DateTime>(receivedAtUtc),
      'status': serializer.toJson<String>(status),
      'cancelledAtUtc': serializer.toJson<DateTime?>(cancelledAtUtc),
    };
  }

  SosEventRow copyWith(
          {String? id,
          String? authorId,
          Value<String?> groupId = const Value.absent(),
          int? categoryCode,
          double? lat,
          double? lon,
          Value<int?> accuracyM = const Value.absent(),
          Value<int?> batteryPercent = const Value.absent(),
          DateTime? createdAtUtc,
          DateTime? receivedAtUtc,
          String? status,
          Value<DateTime?> cancelledAtUtc = const Value.absent()}) =>
      SosEventRow(
        id: id ?? this.id,
        authorId: authorId ?? this.authorId,
        groupId: groupId.present ? groupId.value : this.groupId,
        categoryCode: categoryCode ?? this.categoryCode,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        accuracyM: accuracyM.present ? accuracyM.value : this.accuracyM,
        batteryPercent:
            batteryPercent.present ? batteryPercent.value : this.batteryPercent,
        createdAtUtc: createdAtUtc ?? this.createdAtUtc,
        receivedAtUtc: receivedAtUtc ?? this.receivedAtUtc,
        status: status ?? this.status,
        cancelledAtUtc:
            cancelledAtUtc.present ? cancelledAtUtc.value : this.cancelledAtUtc,
      );
  SosEventRow copyWithCompanion(SosEventsCompanion data) {
    return SosEventRow(
      id: data.id.present ? data.id.value : this.id,
      authorId: data.authorId.present ? data.authorId.value : this.authorId,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      categoryCode: data.categoryCode.present
          ? data.categoryCode.value
          : this.categoryCode,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      accuracyM: data.accuracyM.present ? data.accuracyM.value : this.accuracyM,
      batteryPercent: data.batteryPercent.present
          ? data.batteryPercent.value
          : this.batteryPercent,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      receivedAtUtc: data.receivedAtUtc.present
          ? data.receivedAtUtc.value
          : this.receivedAtUtc,
      status: data.status.present ? data.status.value : this.status,
      cancelledAtUtc: data.cancelledAtUtc.present
          ? data.cancelledAtUtc.value
          : this.cancelledAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SosEventRow(')
          ..write('id: $id, ')
          ..write('authorId: $authorId, ')
          ..write('groupId: $groupId, ')
          ..write('categoryCode: $categoryCode, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('batteryPercent: $batteryPercent, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('receivedAtUtc: $receivedAtUtc, ')
          ..write('status: $status, ')
          ..write('cancelledAtUtc: $cancelledAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      authorId,
      groupId,
      categoryCode,
      lat,
      lon,
      accuracyM,
      batteryPercent,
      createdAtUtc,
      receivedAtUtc,
      status,
      cancelledAtUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SosEventRow &&
          other.id == this.id &&
          other.authorId == this.authorId &&
          other.groupId == this.groupId &&
          other.categoryCode == this.categoryCode &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.accuracyM == this.accuracyM &&
          other.batteryPercent == this.batteryPercent &&
          other.createdAtUtc == this.createdAtUtc &&
          other.receivedAtUtc == this.receivedAtUtc &&
          other.status == this.status &&
          other.cancelledAtUtc == this.cancelledAtUtc);
}

class SosEventsCompanion extends UpdateCompanion<SosEventRow> {
  final Value<String> id;
  final Value<String> authorId;
  final Value<String?> groupId;
  final Value<int> categoryCode;
  final Value<double> lat;
  final Value<double> lon;
  final Value<int?> accuracyM;
  final Value<int?> batteryPercent;
  final Value<DateTime> createdAtUtc;
  final Value<DateTime> receivedAtUtc;
  final Value<String> status;
  final Value<DateTime?> cancelledAtUtc;
  final Value<int> rowid;
  const SosEventsCompanion({
    this.id = const Value.absent(),
    this.authorId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.categoryCode = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.accuracyM = const Value.absent(),
    this.batteryPercent = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.receivedAtUtc = const Value.absent(),
    this.status = const Value.absent(),
    this.cancelledAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SosEventsCompanion.insert({
    required String id,
    required String authorId,
    this.groupId = const Value.absent(),
    required int categoryCode,
    required double lat,
    required double lon,
    this.accuracyM = const Value.absent(),
    this.batteryPercent = const Value.absent(),
    required DateTime createdAtUtc,
    required DateTime receivedAtUtc,
    this.status = const Value.absent(),
    this.cancelledAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        authorId = Value(authorId),
        categoryCode = Value(categoryCode),
        lat = Value(lat),
        lon = Value(lon),
        createdAtUtc = Value(createdAtUtc),
        receivedAtUtc = Value(receivedAtUtc);
  static Insertable<SosEventRow> custom({
    Expression<String>? id,
    Expression<String>? authorId,
    Expression<String>? groupId,
    Expression<int>? categoryCode,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<int>? accuracyM,
    Expression<int>? batteryPercent,
    Expression<DateTime>? createdAtUtc,
    Expression<DateTime>? receivedAtUtc,
    Expression<String>? status,
    Expression<DateTime>? cancelledAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (authorId != null) 'author_id': authorId,
      if (groupId != null) 'group_id': groupId,
      if (categoryCode != null) 'category_code': categoryCode,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (batteryPercent != null) 'battery_percent': batteryPercent,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (receivedAtUtc != null) 'received_at_utc': receivedAtUtc,
      if (status != null) 'status': status,
      if (cancelledAtUtc != null) 'cancelled_at_utc': cancelledAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SosEventsCompanion copyWith(
      {Value<String>? id,
      Value<String>? authorId,
      Value<String?>? groupId,
      Value<int>? categoryCode,
      Value<double>? lat,
      Value<double>? lon,
      Value<int?>? accuracyM,
      Value<int?>? batteryPercent,
      Value<DateTime>? createdAtUtc,
      Value<DateTime>? receivedAtUtc,
      Value<String>? status,
      Value<DateTime?>? cancelledAtUtc,
      Value<int>? rowid}) {
    return SosEventsCompanion(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      groupId: groupId ?? this.groupId,
      categoryCode: categoryCode ?? this.categoryCode,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      accuracyM: accuracyM ?? this.accuracyM,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      receivedAtUtc: receivedAtUtc ?? this.receivedAtUtc,
      status: status ?? this.status,
      cancelledAtUtc: cancelledAtUtc ?? this.cancelledAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (authorId.present) {
      map['author_id'] = Variable<String>(authorId.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (categoryCode.present) {
      map['category_code'] = Variable<int>(categoryCode.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (accuracyM.present) {
      map['accuracy_m'] = Variable<int>(accuracyM.value);
    }
    if (batteryPercent.present) {
      map['battery_percent'] = Variable<int>(batteryPercent.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (receivedAtUtc.present) {
      map['received_at_utc'] = Variable<DateTime>(receivedAtUtc.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (cancelledAtUtc.present) {
      map['cancelled_at_utc'] = Variable<DateTime>(cancelledAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SosEventsCompanion(')
          ..write('id: $id, ')
          ..write('authorId: $authorId, ')
          ..write('groupId: $groupId, ')
          ..write('categoryCode: $categoryCode, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('batteryPercent: $batteryPercent, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('receivedAtUtc: $receivedAtUtc, ')
          ..write('status: $status, ')
          ..write('cancelledAtUtc: $cancelledAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EmergencyContactsTable extends EmergencyContacts
    with TableInfo<$EmergencyContactsTable, ContactRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmergencyContactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name =
      GeneratedColumn<String>('name', aliasedName, false,
          additionalChecks: GeneratedColumn.checkTextLength(
            minTextLength: 1,
          ),
          type: DriftSqlType.string,
          requiredDuringInsert: true);
  static const VerificationMeta _phoneE164Meta =
      const VerificationMeta('phoneE164');
  @override
  late final GeneratedColumn<String> phoneE164 = GeneratedColumn<String>(
      'phone_e164', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 9, maxTextLength: 16),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _channelMeta =
      const VerificationMeta('channel');
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
      'channel', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('sms'));
  static const VerificationMeta _consentStatusMeta =
      const VerificationMeta('consentStatus');
  @override
  late final GeneratedColumn<String> consentStatus = GeneratedColumn<String>(
      'consent_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _consentAtUtcMeta =
      const VerificationMeta('consentAtUtc');
  @override
  late final GeneratedColumn<DateTime> consentAtUtc = GeneratedColumn<DateTime>(
      'consent_at_utc', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtUtcMeta =
      const VerificationMeta('createdAtUtc');
  @override
  late final GeneratedColumn<DateTime> createdAtUtc = GeneratedColumn<DateTime>(
      'created_at_utc', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        userId,
        name,
        phoneE164,
        channel,
        consentStatus,
        consentAtUtc,
        createdAtUtc
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'emergency_contacts';
  @override
  VerificationContext validateIntegrity(Insertable<ContactRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone_e164')) {
      context.handle(_phoneE164Meta,
          phoneE164.isAcceptableOrUnknown(data['phone_e164']!, _phoneE164Meta));
    } else if (isInserting) {
      context.missing(_phoneE164Meta);
    }
    if (data.containsKey('channel')) {
      context.handle(_channelMeta,
          channel.isAcceptableOrUnknown(data['channel']!, _channelMeta));
    }
    if (data.containsKey('consent_status')) {
      context.handle(
          _consentStatusMeta,
          consentStatus.isAcceptableOrUnknown(
              data['consent_status']!, _consentStatusMeta));
    }
    if (data.containsKey('consent_at_utc')) {
      context.handle(
          _consentAtUtcMeta,
          consentAtUtc.isAcceptableOrUnknown(
              data['consent_at_utc']!, _consentAtUtcMeta));
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
          _createdAtUtcMeta,
          createdAtUtc.isAcceptableOrUnknown(
              data['created_at_utc']!, _createdAtUtcMeta));
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ContactRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContactRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      phoneE164: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone_e164'])!,
      channel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}channel'])!,
      consentStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}consent_status'])!,
      consentAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}consent_at_utc']),
      createdAtUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}created_at_utc'])!,
    );
  }

  @override
  $EmergencyContactsTable createAlias(String alias) {
    return $EmergencyContactsTable(attachedDatabase, alias);
  }
}

class ContactRow extends DataClass implements Insertable<ContactRow> {
  final String id;
  final String userId;
  final String name;
  final String phoneE164;
  final String channel;
  final String consentStatus;
  final DateTime? consentAtUtc;
  final DateTime createdAtUtc;
  const ContactRow(
      {required this.id,
      required this.userId,
      required this.name,
      required this.phoneE164,
      required this.channel,
      required this.consentStatus,
      this.consentAtUtc,
      required this.createdAtUtc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['phone_e164'] = Variable<String>(phoneE164);
    map['channel'] = Variable<String>(channel);
    map['consent_status'] = Variable<String>(consentStatus);
    if (!nullToAbsent || consentAtUtc != null) {
      map['consent_at_utc'] = Variable<DateTime>(consentAtUtc);
    }
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    return map;
  }

  EmergencyContactsCompanion toCompanion(bool nullToAbsent) {
    return EmergencyContactsCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      phoneE164: Value(phoneE164),
      channel: Value(channel),
      consentStatus: Value(consentStatus),
      consentAtUtc: consentAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(consentAtUtc),
      createdAtUtc: Value(createdAtUtc),
    );
  }

  factory ContactRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContactRow(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      phoneE164: serializer.fromJson<String>(json['phoneE164']),
      channel: serializer.fromJson<String>(json['channel']),
      consentStatus: serializer.fromJson<String>(json['consentStatus']),
      consentAtUtc: serializer.fromJson<DateTime?>(json['consentAtUtc']),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'phoneE164': serializer.toJson<String>(phoneE164),
      'channel': serializer.toJson<String>(channel),
      'consentStatus': serializer.toJson<String>(consentStatus),
      'consentAtUtc': serializer.toJson<DateTime?>(consentAtUtc),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
    };
  }

  ContactRow copyWith(
          {String? id,
          String? userId,
          String? name,
          String? phoneE164,
          String? channel,
          String? consentStatus,
          Value<DateTime?> consentAtUtc = const Value.absent(),
          DateTime? createdAtUtc}) =>
      ContactRow(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        phoneE164: phoneE164 ?? this.phoneE164,
        channel: channel ?? this.channel,
        consentStatus: consentStatus ?? this.consentStatus,
        consentAtUtc:
            consentAtUtc.present ? consentAtUtc.value : this.consentAtUtc,
        createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      );
  ContactRow copyWithCompanion(EmergencyContactsCompanion data) {
    return ContactRow(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      phoneE164: data.phoneE164.present ? data.phoneE164.value : this.phoneE164,
      channel: data.channel.present ? data.channel.value : this.channel,
      consentStatus: data.consentStatus.present
          ? data.consentStatus.value
          : this.consentStatus,
      consentAtUtc: data.consentAtUtc.present
          ? data.consentAtUtc.value
          : this.consentAtUtc,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContactRow(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('phoneE164: $phoneE164, ')
          ..write('channel: $channel, ')
          ..write('consentStatus: $consentStatus, ')
          ..write('consentAtUtc: $consentAtUtc, ')
          ..write('createdAtUtc: $createdAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, userId, name, phoneE164, channel,
      consentStatus, consentAtUtc, createdAtUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContactRow &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.phoneE164 == this.phoneE164 &&
          other.channel == this.channel &&
          other.consentStatus == this.consentStatus &&
          other.consentAtUtc == this.consentAtUtc &&
          other.createdAtUtc == this.createdAtUtc);
}

class EmergencyContactsCompanion extends UpdateCompanion<ContactRow> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<String> phoneE164;
  final Value<String> channel;
  final Value<String> consentStatus;
  final Value<DateTime?> consentAtUtc;
  final Value<DateTime> createdAtUtc;
  final Value<int> rowid;
  const EmergencyContactsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.phoneE164 = const Value.absent(),
    this.channel = const Value.absent(),
    this.consentStatus = const Value.absent(),
    this.consentAtUtc = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EmergencyContactsCompanion.insert({
    required String id,
    required String userId,
    required String name,
    required String phoneE164,
    this.channel = const Value.absent(),
    this.consentStatus = const Value.absent(),
    this.consentAtUtc = const Value.absent(),
    required DateTime createdAtUtc,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        userId = Value(userId),
        name = Value(name),
        phoneE164 = Value(phoneE164),
        createdAtUtc = Value(createdAtUtc);
  static Insertable<ContactRow> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<String>? phoneE164,
    Expression<String>? channel,
    Expression<String>? consentStatus,
    Expression<DateTime>? consentAtUtc,
    Expression<DateTime>? createdAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (phoneE164 != null) 'phone_e164': phoneE164,
      if (channel != null) 'channel': channel,
      if (consentStatus != null) 'consent_status': consentStatus,
      if (consentAtUtc != null) 'consent_at_utc': consentAtUtc,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EmergencyContactsCompanion copyWith(
      {Value<String>? id,
      Value<String>? userId,
      Value<String>? name,
      Value<String>? phoneE164,
      Value<String>? channel,
      Value<String>? consentStatus,
      Value<DateTime?>? consentAtUtc,
      Value<DateTime>? createdAtUtc,
      Value<int>? rowid}) {
    return EmergencyContactsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phoneE164: phoneE164 ?? this.phoneE164,
      channel: channel ?? this.channel,
      consentStatus: consentStatus ?? this.consentStatus,
      consentAtUtc: consentAtUtc ?? this.consentAtUtc,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phoneE164.present) {
      map['phone_e164'] = Variable<String>(phoneE164.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (consentStatus.present) {
      map['consent_status'] = Variable<String>(consentStatus.value);
    }
    if (consentAtUtc.present) {
      map['consent_at_utc'] = Variable<DateTime>(consentAtUtc.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmergencyContactsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('phoneE164: $phoneE164, ')
          ..write('channel: $channel, ')
          ..write('consentStatus: $consentStatus, ')
          ..write('consentAtUtc: $consentAtUtc, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $GroupsTable groups = $GroupsTable(this);
  late final $MembersTable members = $MembersTable(this);
  late final $InvitationsTable invitations = $InvitationsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $MediaTable media = $MediaTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $TrackPointsTable trackPoints = $TrackPointsTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $SosEventsTable sosEvents = $SosEventsTable(this);
  late final $EmergencyContactsTable emergencyContacts =
      $EmergencyContactsTable(this);
  late final Index invitationsInviteeStatus = Index(
      'invitations_invitee_status',
      'CREATE INDEX invitations_invitee_status ON invitations (invitee_username, status, expires_at_utc)');
  late final Index invitationsOnePending = Index('invitations_one_pending',
      'CREATE UNIQUE INDEX invitations_one_pending ON invitations (group_id, invitee_username) WHERE status = \'pending\'');
  late final Index messagesGroupSent = Index('messages_group_sent',
      'CREATE INDEX messages_group_sent ON messages (group_id, sent_at_utc)');
  late final Index mediaMessage = Index(
      'media_message', 'CREATE INDEX media_message ON media (message_id)');
  late final Index trackPointsSessionTime = Index('track_points_session_time',
      'CREATE INDEX track_points_session_time ON track_points (session_id, recorded_at_utc)');
  late final Index sessionsStarted = Index('sessions_started',
      'CREATE INDEX sessions_started ON sessions (started_at_utc)');
  late final Index outboxDue = Index(
      'outbox_due', 'CREATE INDEX outbox_due ON outbox (next_attempt_at_utc)');
  late final Index outboxOrder = Index('outbox_order',
      'CREATE INDEX outbox_order ON outbox (priority, enqueued_at_utc)');
  late final Index sosStatusCreated = Index('sos_status_created',
      'CREATE INDEX sos_status_created ON sos_events (status, created_at_utc)');
  late final Index contactsUser = Index('contacts_user',
      'CREATE INDEX contacts_user ON emergency_contacts (user_id)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        groups,
        members,
        invitations,
        messages,
        media,
        sessions,
        trackPoints,
        outbox,
        sosEvents,
        emergencyContacts,
        invitationsInviteeStatus,
        invitationsOnePending,
        messagesGroupSent,
        mediaMessage,
        trackPointsSessionTime,
        sessionsStarted,
        outboxDue,
        outboxOrder,
        sosStatusCreated,
        contactsUser
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('groups',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('members', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('messages',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('media', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('sessions',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('track_points', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('groups',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('sos_events', kind: UpdateKind.update),
            ],
          ),
        ],
      );
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$GroupsTableCreateCompanionBuilder = GroupsCompanion Function({
  required String id,
  required String name,
  required String ownerId,
  Value<String?> mountain,
  Value<int> keyVersion,
  required DateTime createdAtUtc,
  Value<int> rowid,
});
typedef $$GroupsTableUpdateCompanionBuilder = GroupsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> ownerId,
  Value<String?> mountain,
  Value<int> keyVersion,
  Value<DateTime> createdAtUtc,
  Value<int> rowid,
});

final class $$GroupsTableReferences
    extends BaseReferences<_$AppDatabase, $GroupsTable, GroupRow> {
  $$GroupsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MembersTable, List<MemberRow>> _membersRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.members,
          aliasName: 'groups__id__members__group_id');

  $$MembersTableProcessedTableManager get membersRefs {
    final manager = $$MembersTableTableManager($_db, $_db.members)
        .filter((f) => f.groupId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_membersRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$SosEventsTable, List<SosEventRow>>
      _sosEventsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.sosEvents,
              aliasName: 'groups__id__sos_events__group_id');

  $$SosEventsTableProcessedTableManager get sosEventsRefs {
    final manager = $$SosEventsTableTableManager($_db, $_db.sosEvents)
        .filter((f) => f.groupId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sosEventsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$GroupsTableFilterComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mountain => $composableBuilder(
      column: $table.mountain, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get keyVersion => $composableBuilder(
      column: $table.keyVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc, builder: (column) => ColumnFilters(column));

  Expression<bool> membersRefs(
      Expression<bool> Function($$MembersTableFilterComposer f) f) {
    final $$MembersTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.members,
        getReferencedColumn: (t) => t.groupId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MembersTableFilterComposer(
              $db: $db,
              $table: $db.members,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> sosEventsRefs(
      Expression<bool> Function($$SosEventsTableFilterComposer f) f) {
    final $$SosEventsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.sosEvents,
        getReferencedColumn: (t) => t.groupId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SosEventsTableFilterComposer(
              $db: $db,
              $table: $db.sosEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$GroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mountain => $composableBuilder(
      column: $table.mountain, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get keyVersion => $composableBuilder(
      column: $table.keyVersion, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc,
      builder: (column) => ColumnOrderings(column));
}

class $$GroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get mountain =>
      $composableBuilder(column: $table.mountain, builder: (column) => column);

  GeneratedColumn<int> get keyVersion => $composableBuilder(
      column: $table.keyVersion, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc, builder: (column) => column);

  Expression<T> membersRefs<T extends Object>(
      Expression<T> Function($$MembersTableAnnotationComposer a) f) {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.members,
        getReferencedColumn: (t) => t.groupId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MembersTableAnnotationComposer(
              $db: $db,
              $table: $db.members,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> sosEventsRefs<T extends Object>(
      Expression<T> Function($$SosEventsTableAnnotationComposer a) f) {
    final $$SosEventsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.sosEvents,
        getReferencedColumn: (t) => t.groupId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SosEventsTableAnnotationComposer(
              $db: $db,
              $table: $db.sosEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$GroupsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $GroupsTable,
    GroupRow,
    $$GroupsTableFilterComposer,
    $$GroupsTableOrderingComposer,
    $$GroupsTableAnnotationComposer,
    $$GroupsTableCreateCompanionBuilder,
    $$GroupsTableUpdateCompanionBuilder,
    (GroupRow, $$GroupsTableReferences),
    GroupRow,
    PrefetchHooks Function({bool membersRefs, bool sosEventsRefs})> {
  $$GroupsTableTableManager(_$AppDatabase db, $GroupsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> ownerId = const Value.absent(),
            Value<String?> mountain = const Value.absent(),
            Value<int> keyVersion = const Value.absent(),
            Value<DateTime> createdAtUtc = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              GroupsCompanion(
            id: id,
            name: name,
            ownerId: ownerId,
            mountain: mountain,
            keyVersion: keyVersion,
            createdAtUtc: createdAtUtc,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String ownerId,
            Value<String?> mountain = const Value.absent(),
            Value<int> keyVersion = const Value.absent(),
            required DateTime createdAtUtc,
            Value<int> rowid = const Value.absent(),
          }) =>
              GroupsCompanion.insert(
            id: id,
            name: name,
            ownerId: ownerId,
            mountain: mountain,
            keyVersion: keyVersion,
            createdAtUtc: createdAtUtc,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$GroupsTable, GroupRow>(table),
                    $$GroupsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {membersRefs = false, sosEventsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (membersRefs) db.members,
                if (sosEventsRefs) db.sosEvents
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (membersRefs)
                    await $_getPrefetchedDataByColumns<GroupRow, $GroupsTable,
                            MemberRow, $MembersTable>(
                        currentTable: table,
                        referencedTable:
                            $$GroupsTableReferences._membersRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$GroupsTableReferences(db, table, p0).membersRefs,
                        currentColumn: 'id',
                        referencedColumn: 'group_id',
                        typedResults: items),
                  if (sosEventsRefs)
                    await $_getPrefetchedDataByColumns<GroupRow, $GroupsTable,
                            SosEventRow, $SosEventsTable>(
                        currentTable: table,
                        referencedTable:
                            $$GroupsTableReferences._sosEventsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$GroupsTableReferences(db, table, p0)
                                .sosEventsRefs,
                        currentColumn: 'id',
                        referencedColumn: 'group_id',
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$GroupsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $GroupsTable,
    GroupRow,
    $$GroupsTableFilterComposer,
    $$GroupsTableOrderingComposer,
    $$GroupsTableAnnotationComposer,
    $$GroupsTableCreateCompanionBuilder,
    $$GroupsTableUpdateCompanionBuilder,
    (GroupRow, $$GroupsTableReferences),
    GroupRow,
    PrefetchHooks Function({bool membersRefs, bool sosEventsRefs})>;
typedef $$MembersTableCreateCompanionBuilder = MembersCompanion Function({
  required String groupId,
  required String userId,
  required String username,
  Value<String> role,
  required DateTime joinedAtUtc,
  Value<int> rowid,
});
typedef $$MembersTableUpdateCompanionBuilder = MembersCompanion Function({
  Value<String> groupId,
  Value<String> userId,
  Value<String> username,
  Value<String> role,
  Value<DateTime> joinedAtUtc,
  Value<int> rowid,
});

final class $$MembersTableReferences
    extends BaseReferences<_$AppDatabase, $MembersTable, MemberRow> {
  $$MembersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GroupsTable _groupIdTable(_$AppDatabase db) =>
      db.groups.createAlias('members__group_id__groups__id');

  $$GroupsTableProcessedTableManager get groupId {
    final $_column = $_itemColumn<String>('group_id')!;

    final manager = $$GroupsTableTableManager($_db, $_db.groups)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$MembersTableFilterComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get joinedAtUtc => $composableBuilder(
      column: $table.joinedAtUtc, builder: (column) => ColumnFilters(column));

  $$GroupsTableFilterComposer get groupId {
    final $$GroupsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.groupId,
        referencedTable: $db.groups,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$GroupsTableFilterComposer(
              $db: $db,
              $table: $db.groups,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MembersTableOrderingComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get joinedAtUtc => $composableBuilder(
      column: $table.joinedAtUtc, builder: (column) => ColumnOrderings(column));

  $$GroupsTableOrderingComposer get groupId {
    final $$GroupsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.groupId,
        referencedTable: $db.groups,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$GroupsTableOrderingComposer(
              $db: $db,
              $table: $db.groups,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MembersTableAnnotationComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<DateTime> get joinedAtUtc => $composableBuilder(
      column: $table.joinedAtUtc, builder: (column) => column);

  $$GroupsTableAnnotationComposer get groupId {
    final $$GroupsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.groupId,
        referencedTable: $db.groups,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$GroupsTableAnnotationComposer(
              $db: $db,
              $table: $db.groups,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MembersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MembersTable,
    MemberRow,
    $$MembersTableFilterComposer,
    $$MembersTableOrderingComposer,
    $$MembersTableAnnotationComposer,
    $$MembersTableCreateCompanionBuilder,
    $$MembersTableUpdateCompanionBuilder,
    (MemberRow, $$MembersTableReferences),
    MemberRow,
    PrefetchHooks Function({bool groupId})> {
  $$MembersTableTableManager(_$AppDatabase db, $MembersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> groupId = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<String> username = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<DateTime> joinedAtUtc = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MembersCompanion(
            groupId: groupId,
            userId: userId,
            username: username,
            role: role,
            joinedAtUtc: joinedAtUtc,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String groupId,
            required String userId,
            required String username,
            Value<String> role = const Value.absent(),
            required DateTime joinedAtUtc,
            Value<int> rowid = const Value.absent(),
          }) =>
              MembersCompanion.insert(
            groupId: groupId,
            userId: userId,
            username: username,
            role: role,
            joinedAtUtc: joinedAtUtc,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$MembersTable, MemberRow>(table),
                    $$MembersTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({groupId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (groupId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.groupId,
                    referencedTable: $$MembersTableReferences._groupIdTable(db),
                    referencedColumn:
                        $$MembersTableReferences._groupIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$MembersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MembersTable,
    MemberRow,
    $$MembersTableFilterComposer,
    $$MembersTableOrderingComposer,
    $$MembersTableAnnotationComposer,
    $$MembersTableCreateCompanionBuilder,
    $$MembersTableUpdateCompanionBuilder,
    (MemberRow, $$MembersTableReferences),
    MemberRow,
    PrefetchHooks Function({bool groupId})>;
typedef $$InvitationsTableCreateCompanionBuilder = InvitationsCompanion
    Function({
  required String id,
  required String groupId,
  required String inviterId,
  required String inviteeUsername,
  Value<String> status,
  required DateTime createdAtUtc,
  required DateTime expiresAtUtc,
  Value<int> rowid,
});
typedef $$InvitationsTableUpdateCompanionBuilder = InvitationsCompanion
    Function({
  Value<String> id,
  Value<String> groupId,
  Value<String> inviterId,
  Value<String> inviteeUsername,
  Value<String> status,
  Value<DateTime> createdAtUtc,
  Value<DateTime> expiresAtUtc,
  Value<int> rowid,
});

class $$InvitationsTableFilterComposer
    extends Composer<_$AppDatabase, $InvitationsTable> {
  $$InvitationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get groupId => $composableBuilder(
      column: $table.groupId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get inviterId => $composableBuilder(
      column: $table.inviterId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get inviteeUsername => $composableBuilder(
      column: $table.inviteeUsername,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get expiresAtUtc => $composableBuilder(
      column: $table.expiresAtUtc, builder: (column) => ColumnFilters(column));
}

class $$InvitationsTableOrderingComposer
    extends Composer<_$AppDatabase, $InvitationsTable> {
  $$InvitationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get groupId => $composableBuilder(
      column: $table.groupId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get inviterId => $composableBuilder(
      column: $table.inviterId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get inviteeUsername => $composableBuilder(
      column: $table.inviteeUsername,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get expiresAtUtc => $composableBuilder(
      column: $table.expiresAtUtc,
      builder: (column) => ColumnOrderings(column));
}

class $$InvitationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InvitationsTable> {
  $$InvitationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get inviterId =>
      $composableBuilder(column: $table.inviterId, builder: (column) => column);

  GeneratedColumn<String> get inviteeUsername => $composableBuilder(
      column: $table.inviteeUsername, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAtUtc => $composableBuilder(
      column: $table.expiresAtUtc, builder: (column) => column);
}

class $$InvitationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $InvitationsTable,
    InvitationRow,
    $$InvitationsTableFilterComposer,
    $$InvitationsTableOrderingComposer,
    $$InvitationsTableAnnotationComposer,
    $$InvitationsTableCreateCompanionBuilder,
    $$InvitationsTableUpdateCompanionBuilder,
    (
      InvitationRow,
      BaseReferences<_$AppDatabase, $InvitationsTable, InvitationRow>
    ),
    InvitationRow,
    PrefetchHooks Function()> {
  $$InvitationsTableTableManager(_$AppDatabase db, $InvitationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InvitationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InvitationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InvitationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> groupId = const Value.absent(),
            Value<String> inviterId = const Value.absent(),
            Value<String> inviteeUsername = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime> createdAtUtc = const Value.absent(),
            Value<DateTime> expiresAtUtc = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              InvitationsCompanion(
            id: id,
            groupId: groupId,
            inviterId: inviterId,
            inviteeUsername: inviteeUsername,
            status: status,
            createdAtUtc: createdAtUtc,
            expiresAtUtc: expiresAtUtc,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String groupId,
            required String inviterId,
            required String inviteeUsername,
            Value<String> status = const Value.absent(),
            required DateTime createdAtUtc,
            required DateTime expiresAtUtc,
            Value<int> rowid = const Value.absent(),
          }) =>
              InvitationsCompanion.insert(
            id: id,
            groupId: groupId,
            inviterId: inviterId,
            inviteeUsername: inviteeUsername,
            status: status,
            createdAtUtc: createdAtUtc,
            expiresAtUtc: expiresAtUtc,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$InvitationsTable, InvitationRow>(table),
                    BaseReferences<_$AppDatabase, $InvitationsTable,
                        InvitationRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$InvitationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $InvitationsTable,
    InvitationRow,
    $$InvitationsTableFilterComposer,
    $$InvitationsTableOrderingComposer,
    $$InvitationsTableAnnotationComposer,
    $$InvitationsTableCreateCompanionBuilder,
    $$InvitationsTableUpdateCompanionBuilder,
    (
      InvitationRow,
      BaseReferences<_$AppDatabase, $InvitationsTable, InvitationRow>
    ),
    InvitationRow,
    PrefetchHooks Function()>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required String id,
  required String authorId,
  required int seq,
  required String groupId,
  required int typeCode,
  required DateTime sentAtUtc,
  required DateTime receivedAtUtc,
  required Uint8List payload,
  Value<Uint8List?> signature,
  Value<bool> isOutgoing,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> id,
  Value<String> authorId,
  Value<int> seq,
  Value<String> groupId,
  Value<int> typeCode,
  Value<DateTime> sentAtUtc,
  Value<DateTime> receivedAtUtc,
  Value<Uint8List> payload,
  Value<Uint8List?> signature,
  Value<bool> isOutgoing,
  Value<int> rowid,
});

final class $$MessagesTableReferences
    extends BaseReferences<_$AppDatabase, $MessagesTable, MessageRow> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MediaTable, List<MediaRow>> _mediaRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.media,
          aliasName: 'messages__id__media__message_id');

  $$MediaTableProcessedTableManager get mediaRefs {
    final manager = $$MediaTableTableManager($_db, $_db.media)
        .filter((f) => f.messageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mediaRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get authorId => $composableBuilder(
      column: $table.authorId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get groupId => $composableBuilder(
      column: $table.groupId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get typeCode => $composableBuilder(
      column: $table.typeCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get sentAtUtc => $composableBuilder(
      column: $table.sentAtUtc, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get receivedAtUtc => $composableBuilder(
      column: $table.receivedAtUtc, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get signature => $composableBuilder(
      column: $table.signature, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isOutgoing => $composableBuilder(
      column: $table.isOutgoing, builder: (column) => ColumnFilters(column));

  Expression<bool> mediaRefs(
      Expression<bool> Function($$MediaTableFilterComposer f) f) {
    final $$MediaTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.media,
        getReferencedColumn: (t) => t.messageId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaTableFilterComposer(
              $db: $db,
              $table: $db.media,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get authorId => $composableBuilder(
      column: $table.authorId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get groupId => $composableBuilder(
      column: $table.groupId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get typeCode => $composableBuilder(
      column: $table.typeCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get sentAtUtc => $composableBuilder(
      column: $table.sentAtUtc, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get receivedAtUtc => $composableBuilder(
      column: $table.receivedAtUtc,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get signature => $composableBuilder(
      column: $table.signature, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isOutgoing => $composableBuilder(
      column: $table.isOutgoing, builder: (column) => ColumnOrderings(column));
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get authorId =>
      $composableBuilder(column: $table.authorId, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<int> get typeCode =>
      $composableBuilder(column: $table.typeCode, builder: (column) => column);

  GeneratedColumn<DateTime> get sentAtUtc =>
      $composableBuilder(column: $table.sentAtUtc, builder: (column) => column);

  GeneratedColumn<DateTime> get receivedAtUtc => $composableBuilder(
      column: $table.receivedAtUtc, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<Uint8List> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);

  GeneratedColumn<bool> get isOutgoing => $composableBuilder(
      column: $table.isOutgoing, builder: (column) => column);

  Expression<T> mediaRefs<T extends Object>(
      Expression<T> Function($$MediaTableAnnotationComposer a) f) {
    final $$MediaTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.media,
        getReferencedColumn: (t) => t.messageId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaTableAnnotationComposer(
              $db: $db,
              $table: $db.media,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$MessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MessagesTable,
    MessageRow,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (MessageRow, $$MessagesTableReferences),
    MessageRow,
    PrefetchHooks Function({bool mediaRefs})> {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> authorId = const Value.absent(),
            Value<int> seq = const Value.absent(),
            Value<String> groupId = const Value.absent(),
            Value<int> typeCode = const Value.absent(),
            Value<DateTime> sentAtUtc = const Value.absent(),
            Value<DateTime> receivedAtUtc = const Value.absent(),
            Value<Uint8List> payload = const Value.absent(),
            Value<Uint8List?> signature = const Value.absent(),
            Value<bool> isOutgoing = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion(
            id: id,
            authorId: authorId,
            seq: seq,
            groupId: groupId,
            typeCode: typeCode,
            sentAtUtc: sentAtUtc,
            receivedAtUtc: receivedAtUtc,
            payload: payload,
            signature: signature,
            isOutgoing: isOutgoing,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String authorId,
            required int seq,
            required String groupId,
            required int typeCode,
            required DateTime sentAtUtc,
            required DateTime receivedAtUtc,
            required Uint8List payload,
            Value<Uint8List?> signature = const Value.absent(),
            Value<bool> isOutgoing = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion.insert(
            id: id,
            authorId: authorId,
            seq: seq,
            groupId: groupId,
            typeCode: typeCode,
            sentAtUtc: sentAtUtc,
            receivedAtUtc: receivedAtUtc,
            payload: payload,
            signature: signature,
            isOutgoing: isOutgoing,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$MessagesTable, MessageRow>(table),
                    $$MessagesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({mediaRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (mediaRefs) db.media],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (mediaRefs)
                    await $_getPrefetchedDataByColumns<MessageRow,
                            $MessagesTable, MediaRow, $MediaTable>(
                        currentTable: table,
                        referencedTable:
                            $$MessagesTableReferences._mediaRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$MessagesTableReferences(db, table, p0).mediaRefs,
                        currentColumn: 'id',
                        referencedColumn: 'message_id',
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MessagesTable,
    MessageRow,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (MessageRow, $$MessagesTableReferences),
    MessageRow,
    PrefetchHooks Function({bool mediaRefs})>;
typedef $$MediaTableCreateCompanionBuilder = MediaCompanion Function({
  required String id,
  Value<String?> messageId,
  Value<String?> groupId,
  required String kind,
  required String relativePath,
  required String mimeType,
  required int byteSize,
  required DateTime createdAtUtc,
  Value<int> rowid,
});
typedef $$MediaTableUpdateCompanionBuilder = MediaCompanion Function({
  Value<String> id,
  Value<String?> messageId,
  Value<String?> groupId,
  Value<String> kind,
  Value<String> relativePath,
  Value<String> mimeType,
  Value<int> byteSize,
  Value<DateTime> createdAtUtc,
  Value<int> rowid,
});

final class $$MediaTableReferences
    extends BaseReferences<_$AppDatabase, $MediaTable, MediaRow> {
  $$MediaTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MessagesTable _messageIdTable(_$AppDatabase db) =>
      db.messages.createAlias('media__message_id__messages__id');

  $$MessagesTableProcessedTableManager? get messageId {
    final $_column = $_itemColumn<String>('message_id');
    if ($_column == null) return null;
    final manager = $$MessagesTableTableManager($_db, $_db.messages)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$MediaTableFilterComposer extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get groupId => $composableBuilder(
      column: $table.groupId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get relativePath => $composableBuilder(
      column: $table.relativePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mimeType => $composableBuilder(
      column: $table.mimeType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get byteSize => $composableBuilder(
      column: $table.byteSize, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc, builder: (column) => ColumnFilters(column));

  $$MessagesTableFilterComposer get messageId {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.messageId,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableFilterComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MediaTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get groupId => $composableBuilder(
      column: $table.groupId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get relativePath => $composableBuilder(
      column: $table.relativePath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mimeType => $composableBuilder(
      column: $table.mimeType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get byteSize => $composableBuilder(
      column: $table.byteSize, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc,
      builder: (column) => ColumnOrderings(column));

  $$MessagesTableOrderingComposer get messageId {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.messageId,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableOrderingComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MediaTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
      column: $table.relativePath, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc, builder: (column) => column);

  $$MessagesTableAnnotationComposer get messageId {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.messageId,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableAnnotationComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MediaTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MediaTable,
    MediaRow,
    $$MediaTableFilterComposer,
    $$MediaTableOrderingComposer,
    $$MediaTableAnnotationComposer,
    $$MediaTableCreateCompanionBuilder,
    $$MediaTableUpdateCompanionBuilder,
    (MediaRow, $$MediaTableReferences),
    MediaRow,
    PrefetchHooks Function({bool messageId})> {
  $$MediaTableTableManager(_$AppDatabase db, $MediaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> messageId = const Value.absent(),
            Value<String?> groupId = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String> relativePath = const Value.absent(),
            Value<String> mimeType = const Value.absent(),
            Value<int> byteSize = const Value.absent(),
            Value<DateTime> createdAtUtc = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaCompanion(
            id: id,
            messageId: messageId,
            groupId: groupId,
            kind: kind,
            relativePath: relativePath,
            mimeType: mimeType,
            byteSize: byteSize,
            createdAtUtc: createdAtUtc,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> messageId = const Value.absent(),
            Value<String?> groupId = const Value.absent(),
            required String kind,
            required String relativePath,
            required String mimeType,
            required int byteSize,
            required DateTime createdAtUtc,
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaCompanion.insert(
            id: id,
            messageId: messageId,
            groupId: groupId,
            kind: kind,
            relativePath: relativePath,
            mimeType: mimeType,
            byteSize: byteSize,
            createdAtUtc: createdAtUtc,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$MediaTable, MediaRow>(table),
                    $$MediaTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({messageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (messageId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.messageId,
                    referencedTable: $$MediaTableReferences._messageIdTable(db),
                    referencedColumn:
                        $$MediaTableReferences._messageIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$MediaTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MediaTable,
    MediaRow,
    $$MediaTableFilterComposer,
    $$MediaTableOrderingComposer,
    $$MediaTableAnnotationComposer,
    $$MediaTableCreateCompanionBuilder,
    $$MediaTableUpdateCompanionBuilder,
    (MediaRow, $$MediaTableReferences),
    MediaRow,
    PrefetchHooks Function({bool messageId})>;
typedef $$SessionsTableCreateCompanionBuilder = SessionsCompanion Function({
  required String id,
  required DateTime startedAtUtc,
  Value<DateTime?> endedAtUtc,
  Value<String?> groupId,
  Value<String?> trailId,
  Value<double> distanceM,
  Value<int> movingSeconds,
  Value<double> elevationGainM,
  Value<double> elevationLossM,
  Value<String> status,
  Value<int> rowid,
});
typedef $$SessionsTableUpdateCompanionBuilder = SessionsCompanion Function({
  Value<String> id,
  Value<DateTime> startedAtUtc,
  Value<DateTime?> endedAtUtc,
  Value<String?> groupId,
  Value<String?> trailId,
  Value<double> distanceM,
  Value<int> movingSeconds,
  Value<double> elevationGainM,
  Value<double> elevationLossM,
  Value<String> status,
  Value<int> rowid,
});

final class $$SessionsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionsTable, SessionRow> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TrackPointsTable, List<TrackPointRow>>
      _trackPointsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.trackPoints,
              aliasName: 'sessions__id__track_points__session_id');

  $$TrackPointsTableProcessedTableManager get trackPointsRefs {
    final manager = $$TrackPointsTableTableManager($_db, $_db.trackPoints)
        .filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_trackPointsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAtUtc => $composableBuilder(
      column: $table.startedAtUtc, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endedAtUtc => $composableBuilder(
      column: $table.endedAtUtc, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get groupId => $composableBuilder(
      column: $table.groupId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get trailId => $composableBuilder(
      column: $table.trailId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get distanceM => $composableBuilder(
      column: $table.distanceM, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get movingSeconds => $composableBuilder(
      column: $table.movingSeconds, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get elevationGainM => $composableBuilder(
      column: $table.elevationGainM,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get elevationLossM => $composableBuilder(
      column: $table.elevationLossM,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  Expression<bool> trackPointsRefs(
      Expression<bool> Function($$TrackPointsTableFilterComposer f) f) {
    final $$TrackPointsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.trackPoints,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TrackPointsTableFilterComposer(
              $db: $db,
              $table: $db.trackPoints,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAtUtc => $composableBuilder(
      column: $table.startedAtUtc,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endedAtUtc => $composableBuilder(
      column: $table.endedAtUtc, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get groupId => $composableBuilder(
      column: $table.groupId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get trailId => $composableBuilder(
      column: $table.trailId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get distanceM => $composableBuilder(
      column: $table.distanceM, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get movingSeconds => $composableBuilder(
      column: $table.movingSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get elevationGainM => $composableBuilder(
      column: $table.elevationGainM,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get elevationLossM => $composableBuilder(
      column: $table.elevationLossM,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAtUtc => $composableBuilder(
      column: $table.startedAtUtc, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAtUtc => $composableBuilder(
      column: $table.endedAtUtc, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get trailId =>
      $composableBuilder(column: $table.trailId, builder: (column) => column);

  GeneratedColumn<double> get distanceM =>
      $composableBuilder(column: $table.distanceM, builder: (column) => column);

  GeneratedColumn<int> get movingSeconds => $composableBuilder(
      column: $table.movingSeconds, builder: (column) => column);

  GeneratedColumn<double> get elevationGainM => $composableBuilder(
      column: $table.elevationGainM, builder: (column) => column);

  GeneratedColumn<double> get elevationLossM => $composableBuilder(
      column: $table.elevationLossM, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  Expression<T> trackPointsRefs<T extends Object>(
      Expression<T> Function($$TrackPointsTableAnnotationComposer a) f) {
    final $$TrackPointsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.trackPoints,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TrackPointsTableAnnotationComposer(
              $db: $db,
              $table: $db.trackPoints,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SessionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SessionsTable,
    SessionRow,
    $$SessionsTableFilterComposer,
    $$SessionsTableOrderingComposer,
    $$SessionsTableAnnotationComposer,
    $$SessionsTableCreateCompanionBuilder,
    $$SessionsTableUpdateCompanionBuilder,
    (SessionRow, $$SessionsTableReferences),
    SessionRow,
    PrefetchHooks Function({bool trackPointsRefs})> {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<DateTime> startedAtUtc = const Value.absent(),
            Value<DateTime?> endedAtUtc = const Value.absent(),
            Value<String?> groupId = const Value.absent(),
            Value<String?> trailId = const Value.absent(),
            Value<double> distanceM = const Value.absent(),
            Value<int> movingSeconds = const Value.absent(),
            Value<double> elevationGainM = const Value.absent(),
            Value<double> elevationLossM = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SessionsCompanion(
            id: id,
            startedAtUtc: startedAtUtc,
            endedAtUtc: endedAtUtc,
            groupId: groupId,
            trailId: trailId,
            distanceM: distanceM,
            movingSeconds: movingSeconds,
            elevationGainM: elevationGainM,
            elevationLossM: elevationLossM,
            status: status,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required DateTime startedAtUtc,
            Value<DateTime?> endedAtUtc = const Value.absent(),
            Value<String?> groupId = const Value.absent(),
            Value<String?> trailId = const Value.absent(),
            Value<double> distanceM = const Value.absent(),
            Value<int> movingSeconds = const Value.absent(),
            Value<double> elevationGainM = const Value.absent(),
            Value<double> elevationLossM = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SessionsCompanion.insert(
            id: id,
            startedAtUtc: startedAtUtc,
            endedAtUtc: endedAtUtc,
            groupId: groupId,
            trailId: trailId,
            distanceM: distanceM,
            movingSeconds: movingSeconds,
            elevationGainM: elevationGainM,
            elevationLossM: elevationLossM,
            status: status,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$SessionsTable, SessionRow>(table),
                    $$SessionsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({trackPointsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (trackPointsRefs) db.trackPoints],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (trackPointsRefs)
                    await $_getPrefetchedDataByColumns<SessionRow,
                            $SessionsTable, TrackPointRow, $TrackPointsTable>(
                        currentTable: table,
                        referencedTable:
                            $$SessionsTableReferences._trackPointsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SessionsTableReferences(db, table, p0)
                                .trackPointsRefs,
                        currentColumn: 'id',
                        referencedColumn: 'session_id',
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SessionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SessionsTable,
    SessionRow,
    $$SessionsTableFilterComposer,
    $$SessionsTableOrderingComposer,
    $$SessionsTableAnnotationComposer,
    $$SessionsTableCreateCompanionBuilder,
    $$SessionsTableUpdateCompanionBuilder,
    (SessionRow, $$SessionsTableReferences),
    SessionRow,
    PrefetchHooks Function({bool trackPointsRefs})>;
typedef $$TrackPointsTableCreateCompanionBuilder = TrackPointsCompanion
    Function({
  Value<int> id,
  required String sessionId,
  required double lat,
  required double lon,
  Value<double?> altitudeM,
  required double accuracyM,
  Value<double?> speedMps,
  required DateTime recordedAtUtc,
});
typedef $$TrackPointsTableUpdateCompanionBuilder = TrackPointsCompanion
    Function({
  Value<int> id,
  Value<String> sessionId,
  Value<double> lat,
  Value<double> lon,
  Value<double?> altitudeM,
  Value<double> accuracyM,
  Value<double?> speedMps,
  Value<DateTime> recordedAtUtc,
});

final class $$TrackPointsTableReferences
    extends BaseReferences<_$AppDatabase, $TrackPointsTable, TrackPointRow> {
  $$TrackPointsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias('track_points__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager($_db, $_db.sessions)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$TrackPointsTableFilterComposer
    extends Composer<_$AppDatabase, $TrackPointsTable> {
  $$TrackPointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lon => $composableBuilder(
      column: $table.lon, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get altitudeM => $composableBuilder(
      column: $table.altitudeM, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get accuracyM => $composableBuilder(
      column: $table.accuracyM, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get speedMps => $composableBuilder(
      column: $table.speedMps, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get recordedAtUtc => $composableBuilder(
      column: $table.recordedAtUtc, builder: (column) => ColumnFilters(column));

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableFilterComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TrackPointsTableOrderingComposer
    extends Composer<_$AppDatabase, $TrackPointsTable> {
  $$TrackPointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lon => $composableBuilder(
      column: $table.lon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get altitudeM => $composableBuilder(
      column: $table.altitudeM, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get accuracyM => $composableBuilder(
      column: $table.accuracyM, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get speedMps => $composableBuilder(
      column: $table.speedMps, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get recordedAtUtc => $composableBuilder(
      column: $table.recordedAtUtc,
      builder: (column) => ColumnOrderings(column));

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableOrderingComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TrackPointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrackPointsTable> {
  $$TrackPointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumn<double> get altitudeM =>
      $composableBuilder(column: $table.altitudeM, builder: (column) => column);

  GeneratedColumn<double> get accuracyM =>
      $composableBuilder(column: $table.accuracyM, builder: (column) => column);

  GeneratedColumn<double> get speedMps =>
      $composableBuilder(column: $table.speedMps, builder: (column) => column);

  GeneratedColumn<DateTime> get recordedAtUtc => $composableBuilder(
      column: $table.recordedAtUtc, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TrackPointsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TrackPointsTable,
    TrackPointRow,
    $$TrackPointsTableFilterComposer,
    $$TrackPointsTableOrderingComposer,
    $$TrackPointsTableAnnotationComposer,
    $$TrackPointsTableCreateCompanionBuilder,
    $$TrackPointsTableUpdateCompanionBuilder,
    (TrackPointRow, $$TrackPointsTableReferences),
    TrackPointRow,
    PrefetchHooks Function({bool sessionId})> {
  $$TrackPointsTableTableManager(_$AppDatabase db, $TrackPointsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackPointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackPointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackPointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> sessionId = const Value.absent(),
            Value<double> lat = const Value.absent(),
            Value<double> lon = const Value.absent(),
            Value<double?> altitudeM = const Value.absent(),
            Value<double> accuracyM = const Value.absent(),
            Value<double?> speedMps = const Value.absent(),
            Value<DateTime> recordedAtUtc = const Value.absent(),
          }) =>
              TrackPointsCompanion(
            id: id,
            sessionId: sessionId,
            lat: lat,
            lon: lon,
            altitudeM: altitudeM,
            accuracyM: accuracyM,
            speedMps: speedMps,
            recordedAtUtc: recordedAtUtc,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String sessionId,
            required double lat,
            required double lon,
            Value<double?> altitudeM = const Value.absent(),
            required double accuracyM,
            Value<double?> speedMps = const Value.absent(),
            required DateTime recordedAtUtc,
          }) =>
              TrackPointsCompanion.insert(
            id: id,
            sessionId: sessionId,
            lat: lat,
            lon: lon,
            altitudeM: altitudeM,
            accuracyM: accuracyM,
            speedMps: speedMps,
            recordedAtUtc: recordedAtUtc,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$TrackPointsTable, TrackPointRow>(table),
                    $$TrackPointsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (sessionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sessionId,
                    referencedTable:
                        $$TrackPointsTableReferences._sessionIdTable(db),
                    referencedColumn:
                        $$TrackPointsTableReferences._sessionIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$TrackPointsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TrackPointsTable,
    TrackPointRow,
    $$TrackPointsTableFilterComposer,
    $$TrackPointsTableOrderingComposer,
    $$TrackPointsTableAnnotationComposer,
    $$TrackPointsTableCreateCompanionBuilder,
    $$TrackPointsTableUpdateCompanionBuilder,
    (TrackPointRow, $$TrackPointsTableReferences),
    TrackPointRow,
    PrefetchHooks Function({bool sessionId})>;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  required String messageId,
  required Uint8List packet,
  required int priority,
  required DateTime enqueuedAtUtc,
  required DateTime nextAttemptAtUtc,
  Value<int> attempts,
  Value<bool> repeatUntilAck,
  Value<int> rowid,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<String> messageId,
  Value<Uint8List> packet,
  Value<int> priority,
  Value<DateTime> enqueuedAtUtc,
  Value<DateTime> nextAttemptAtUtc,
  Value<int> attempts,
  Value<bool> repeatUntilAck,
  Value<int> rowid,
});

class $$OutboxTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get messageId => $composableBuilder(
      column: $table.messageId, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get packet => $composableBuilder(
      column: $table.packet, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get enqueuedAtUtc => $composableBuilder(
      column: $table.enqueuedAtUtc, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get nextAttemptAtUtc => $composableBuilder(
      column: $table.nextAttemptAtUtc,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get repeatUntilAck => $composableBuilder(
      column: $table.repeatUntilAck,
      builder: (column) => ColumnFilters(column));
}

class $$OutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get messageId => $composableBuilder(
      column: $table.messageId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get packet => $composableBuilder(
      column: $table.packet, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get enqueuedAtUtc => $composableBuilder(
      column: $table.enqueuedAtUtc,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get nextAttemptAtUtc => $composableBuilder(
      column: $table.nextAttemptAtUtc,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get repeatUntilAck => $composableBuilder(
      column: $table.repeatUntilAck,
      builder: (column) => ColumnOrderings(column));
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<Uint8List> get packet =>
      $composableBuilder(column: $table.packet, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<DateTime> get enqueuedAtUtc => $composableBuilder(
      column: $table.enqueuedAtUtc, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAtUtc => $composableBuilder(
      column: $table.nextAttemptAtUtc, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<bool> get repeatUntilAck => $composableBuilder(
      column: $table.repeatUntilAck, builder: (column) => column);
}

class $$OutboxTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OutboxTable,
    OutboxRow,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxRow, BaseReferences<_$AppDatabase, $OutboxTable, OutboxRow>),
    OutboxRow,
    PrefetchHooks Function()> {
  $$OutboxTableTableManager(_$AppDatabase db, $OutboxTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> messageId = const Value.absent(),
            Value<Uint8List> packet = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<DateTime> enqueuedAtUtc = const Value.absent(),
            Value<DateTime> nextAttemptAtUtc = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<bool> repeatUntilAck = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OutboxCompanion(
            messageId: messageId,
            packet: packet,
            priority: priority,
            enqueuedAtUtc: enqueuedAtUtc,
            nextAttemptAtUtc: nextAttemptAtUtc,
            attempts: attempts,
            repeatUntilAck: repeatUntilAck,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String messageId,
            required Uint8List packet,
            required int priority,
            required DateTime enqueuedAtUtc,
            required DateTime nextAttemptAtUtc,
            Value<int> attempts = const Value.absent(),
            Value<bool> repeatUntilAck = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OutboxCompanion.insert(
            messageId: messageId,
            packet: packet,
            priority: priority,
            enqueuedAtUtc: enqueuedAtUtc,
            nextAttemptAtUtc: nextAttemptAtUtc,
            attempts: attempts,
            repeatUntilAck: repeatUntilAck,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$OutboxTable, OutboxRow>(table),
                    BaseReferences<_$AppDatabase, $OutboxTable, OutboxRow>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OutboxTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OutboxTable,
    OutboxRow,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxRow, BaseReferences<_$AppDatabase, $OutboxTable, OutboxRow>),
    OutboxRow,
    PrefetchHooks Function()>;
typedef $$SosEventsTableCreateCompanionBuilder = SosEventsCompanion Function({
  required String id,
  required String authorId,
  Value<String?> groupId,
  required int categoryCode,
  required double lat,
  required double lon,
  Value<int?> accuracyM,
  Value<int?> batteryPercent,
  required DateTime createdAtUtc,
  required DateTime receivedAtUtc,
  Value<String> status,
  Value<DateTime?> cancelledAtUtc,
  Value<int> rowid,
});
typedef $$SosEventsTableUpdateCompanionBuilder = SosEventsCompanion Function({
  Value<String> id,
  Value<String> authorId,
  Value<String?> groupId,
  Value<int> categoryCode,
  Value<double> lat,
  Value<double> lon,
  Value<int?> accuracyM,
  Value<int?> batteryPercent,
  Value<DateTime> createdAtUtc,
  Value<DateTime> receivedAtUtc,
  Value<String> status,
  Value<DateTime?> cancelledAtUtc,
  Value<int> rowid,
});

final class $$SosEventsTableReferences
    extends BaseReferences<_$AppDatabase, $SosEventsTable, SosEventRow> {
  $$SosEventsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GroupsTable _groupIdTable(_$AppDatabase db) =>
      db.groups.createAlias('sos_events__group_id__groups__id');

  $$GroupsTableProcessedTableManager? get groupId {
    final $_column = $_itemColumn<String>('group_id');
    if ($_column == null) return null;
    final manager = $$GroupsTableTableManager($_db, $_db.groups)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$SosEventsTableFilterComposer
    extends Composer<_$AppDatabase, $SosEventsTable> {
  $$SosEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get authorId => $composableBuilder(
      column: $table.authorId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get categoryCode => $composableBuilder(
      column: $table.categoryCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lon => $composableBuilder(
      column: $table.lon, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get accuracyM => $composableBuilder(
      column: $table.accuracyM, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get batteryPercent => $composableBuilder(
      column: $table.batteryPercent,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get receivedAtUtc => $composableBuilder(
      column: $table.receivedAtUtc, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cancelledAtUtc => $composableBuilder(
      column: $table.cancelledAtUtc,
      builder: (column) => ColumnFilters(column));

  $$GroupsTableFilterComposer get groupId {
    final $$GroupsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.groupId,
        referencedTable: $db.groups,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$GroupsTableFilterComposer(
              $db: $db,
              $table: $db.groups,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SosEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $SosEventsTable> {
  $$SosEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get authorId => $composableBuilder(
      column: $table.authorId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get categoryCode => $composableBuilder(
      column: $table.categoryCode,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lon => $composableBuilder(
      column: $table.lon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get accuracyM => $composableBuilder(
      column: $table.accuracyM, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get batteryPercent => $composableBuilder(
      column: $table.batteryPercent,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get receivedAtUtc => $composableBuilder(
      column: $table.receivedAtUtc,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cancelledAtUtc => $composableBuilder(
      column: $table.cancelledAtUtc,
      builder: (column) => ColumnOrderings(column));

  $$GroupsTableOrderingComposer get groupId {
    final $$GroupsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.groupId,
        referencedTable: $db.groups,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$GroupsTableOrderingComposer(
              $db: $db,
              $table: $db.groups,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SosEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SosEventsTable> {
  $$SosEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get authorId =>
      $composableBuilder(column: $table.authorId, builder: (column) => column);

  GeneratedColumn<int> get categoryCode => $composableBuilder(
      column: $table.categoryCode, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumn<int> get accuracyM =>
      $composableBuilder(column: $table.accuracyM, builder: (column) => column);

  GeneratedColumn<int> get batteryPercent => $composableBuilder(
      column: $table.batteryPercent, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc, builder: (column) => column);

  GeneratedColumn<DateTime> get receivedAtUtc => $composableBuilder(
      column: $table.receivedAtUtc, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get cancelledAtUtc => $composableBuilder(
      column: $table.cancelledAtUtc, builder: (column) => column);

  $$GroupsTableAnnotationComposer get groupId {
    final $$GroupsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.groupId,
        referencedTable: $db.groups,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$GroupsTableAnnotationComposer(
              $db: $db,
              $table: $db.groups,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SosEventsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SosEventsTable,
    SosEventRow,
    $$SosEventsTableFilterComposer,
    $$SosEventsTableOrderingComposer,
    $$SosEventsTableAnnotationComposer,
    $$SosEventsTableCreateCompanionBuilder,
    $$SosEventsTableUpdateCompanionBuilder,
    (SosEventRow, $$SosEventsTableReferences),
    SosEventRow,
    PrefetchHooks Function({bool groupId})> {
  $$SosEventsTableTableManager(_$AppDatabase db, $SosEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SosEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SosEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SosEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> authorId = const Value.absent(),
            Value<String?> groupId = const Value.absent(),
            Value<int> categoryCode = const Value.absent(),
            Value<double> lat = const Value.absent(),
            Value<double> lon = const Value.absent(),
            Value<int?> accuracyM = const Value.absent(),
            Value<int?> batteryPercent = const Value.absent(),
            Value<DateTime> createdAtUtc = const Value.absent(),
            Value<DateTime> receivedAtUtc = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime?> cancelledAtUtc = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SosEventsCompanion(
            id: id,
            authorId: authorId,
            groupId: groupId,
            categoryCode: categoryCode,
            lat: lat,
            lon: lon,
            accuracyM: accuracyM,
            batteryPercent: batteryPercent,
            createdAtUtc: createdAtUtc,
            receivedAtUtc: receivedAtUtc,
            status: status,
            cancelledAtUtc: cancelledAtUtc,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String authorId,
            Value<String?> groupId = const Value.absent(),
            required int categoryCode,
            required double lat,
            required double lon,
            Value<int?> accuracyM = const Value.absent(),
            Value<int?> batteryPercent = const Value.absent(),
            required DateTime createdAtUtc,
            required DateTime receivedAtUtc,
            Value<String> status = const Value.absent(),
            Value<DateTime?> cancelledAtUtc = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SosEventsCompanion.insert(
            id: id,
            authorId: authorId,
            groupId: groupId,
            categoryCode: categoryCode,
            lat: lat,
            lon: lon,
            accuracyM: accuracyM,
            batteryPercent: batteryPercent,
            createdAtUtc: createdAtUtc,
            receivedAtUtc: receivedAtUtc,
            status: status,
            cancelledAtUtc: cancelledAtUtc,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$SosEventsTable, SosEventRow>(table),
                    $$SosEventsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({groupId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (groupId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.groupId,
                    referencedTable:
                        $$SosEventsTableReferences._groupIdTable(db),
                    referencedColumn:
                        $$SosEventsTableReferences._groupIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$SosEventsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SosEventsTable,
    SosEventRow,
    $$SosEventsTableFilterComposer,
    $$SosEventsTableOrderingComposer,
    $$SosEventsTableAnnotationComposer,
    $$SosEventsTableCreateCompanionBuilder,
    $$SosEventsTableUpdateCompanionBuilder,
    (SosEventRow, $$SosEventsTableReferences),
    SosEventRow,
    PrefetchHooks Function({bool groupId})>;
typedef $$EmergencyContactsTableCreateCompanionBuilder
    = EmergencyContactsCompanion Function({
  required String id,
  required String userId,
  required String name,
  required String phoneE164,
  Value<String> channel,
  Value<String> consentStatus,
  Value<DateTime?> consentAtUtc,
  required DateTime createdAtUtc,
  Value<int> rowid,
});
typedef $$EmergencyContactsTableUpdateCompanionBuilder
    = EmergencyContactsCompanion Function({
  Value<String> id,
  Value<String> userId,
  Value<String> name,
  Value<String> phoneE164,
  Value<String> channel,
  Value<String> consentStatus,
  Value<DateTime?> consentAtUtc,
  Value<DateTime> createdAtUtc,
  Value<int> rowid,
});

class $$EmergencyContactsTableFilterComposer
    extends Composer<_$AppDatabase, $EmergencyContactsTable> {
  $$EmergencyContactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get phoneE164 => $composableBuilder(
      column: $table.phoneE164, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get channel => $composableBuilder(
      column: $table.channel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get consentStatus => $composableBuilder(
      column: $table.consentStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get consentAtUtc => $composableBuilder(
      column: $table.consentAtUtc, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc, builder: (column) => ColumnFilters(column));
}

class $$EmergencyContactsTableOrderingComposer
    extends Composer<_$AppDatabase, $EmergencyContactsTable> {
  $$EmergencyContactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get phoneE164 => $composableBuilder(
      column: $table.phoneE164, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get channel => $composableBuilder(
      column: $table.channel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get consentStatus => $composableBuilder(
      column: $table.consentStatus,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get consentAtUtc => $composableBuilder(
      column: $table.consentAtUtc,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc,
      builder: (column) => ColumnOrderings(column));
}

class $$EmergencyContactsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EmergencyContactsTable> {
  $$EmergencyContactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phoneE164 =>
      $composableBuilder(column: $table.phoneE164, builder: (column) => column);

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<String> get consentStatus => $composableBuilder(
      column: $table.consentStatus, builder: (column) => column);

  GeneratedColumn<DateTime> get consentAtUtc => $composableBuilder(
      column: $table.consentAtUtc, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
      column: $table.createdAtUtc, builder: (column) => column);
}

class $$EmergencyContactsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $EmergencyContactsTable,
    ContactRow,
    $$EmergencyContactsTableFilterComposer,
    $$EmergencyContactsTableOrderingComposer,
    $$EmergencyContactsTableAnnotationComposer,
    $$EmergencyContactsTableCreateCompanionBuilder,
    $$EmergencyContactsTableUpdateCompanionBuilder,
    (
      ContactRow,
      BaseReferences<_$AppDatabase, $EmergencyContactsTable, ContactRow>
    ),
    ContactRow,
    PrefetchHooks Function()> {
  $$EmergencyContactsTableTableManager(
      _$AppDatabase db, $EmergencyContactsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EmergencyContactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EmergencyContactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EmergencyContactsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> phoneE164 = const Value.absent(),
            Value<String> channel = const Value.absent(),
            Value<String> consentStatus = const Value.absent(),
            Value<DateTime?> consentAtUtc = const Value.absent(),
            Value<DateTime> createdAtUtc = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              EmergencyContactsCompanion(
            id: id,
            userId: userId,
            name: name,
            phoneE164: phoneE164,
            channel: channel,
            consentStatus: consentStatus,
            consentAtUtc: consentAtUtc,
            createdAtUtc: createdAtUtc,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String userId,
            required String name,
            required String phoneE164,
            Value<String> channel = const Value.absent(),
            Value<String> consentStatus = const Value.absent(),
            Value<DateTime?> consentAtUtc = const Value.absent(),
            required DateTime createdAtUtc,
            Value<int> rowid = const Value.absent(),
          }) =>
              EmergencyContactsCompanion.insert(
            id: id,
            userId: userId,
            name: name,
            phoneE164: phoneE164,
            channel: channel,
            consentStatus: consentStatus,
            consentAtUtc: consentAtUtc,
            createdAtUtc: createdAtUtc,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$EmergencyContactsTable, ContactRow>(table),
                    BaseReferences<_$AppDatabase, $EmergencyContactsTable,
                        ContactRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$EmergencyContactsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $EmergencyContactsTable,
    ContactRow,
    $$EmergencyContactsTableFilterComposer,
    $$EmergencyContactsTableOrderingComposer,
    $$EmergencyContactsTableAnnotationComposer,
    $$EmergencyContactsTableCreateCompanionBuilder,
    $$EmergencyContactsTableUpdateCompanionBuilder,
    (
      ContactRow,
      BaseReferences<_$AppDatabase, $EmergencyContactsTable, ContactRow>
    ),
    ContactRow,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$GroupsTableTableManager get groups =>
      $$GroupsTableTableManager(_db, _db.groups);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db, _db.members);
  $$InvitationsTableTableManager get invitations =>
      $$InvitationsTableTableManager(_db, _db.invitations);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$MediaTableTableManager get media =>
      $$MediaTableTableManager(_db, _db.media);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$TrackPointsTableTableManager get trackPoints =>
      $$TrackPointsTableTableManager(_db, _db.trackPoints);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$SosEventsTableTableManager get sosEvents =>
      $$SosEventsTableTableManager(_db, _db.sosEvents);
  $$EmergencyContactsTableTableManager get emergencyContacts =>
      $$EmergencyContactsTableTableManager(_db, _db.emergencyContacts);
}
