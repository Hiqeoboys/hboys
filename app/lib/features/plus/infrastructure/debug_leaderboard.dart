import 'package:flutter/foundation.dart';

import '../domain/leaderboard.dart';

/// Papan peringkat demo. Angka di bawah hanya untuk memeriksa tata letak di
/// build debug; build rilis memakai [UnavailableLeaderboardRepository].
class DebugLeaderboardRepository implements LeaderboardRepository {
  const DebugLeaderboardRepository({
    this.enabled = kDebugMode,
    this.currentUserName = 'Rani',
  });

  final bool enabled;
  final String currentUserName;

  @override
  Future<LeaderboardBoard> load({
    required LeaderboardScope scope,
    required LeaderboardMetric metric,
    required LeaderboardPeriod period,
  }) async {
    if (!enabled) {
      throw const LeaderboardUnavailable(
        'Papan peringkat demo tidak aktif di build ini.',
      );
    }
    return buildDemoLeaderboard(
      scope: scope,
      metric: metric,
      period: period,
      currentUserName: currentUserName,
    );
  }

  /// Server peninjauan belum ada; laporan tidak dikirim ke mana pun.
  @override
  Future<bool> report(String displayName) async => false;

  /// Penyembunyian baris dilakukan di layar selama sesi ini.
  @override
  Future<bool> block(String displayName) async => false;
}

class UnavailableLeaderboardRepository implements LeaderboardRepository {
  const UnavailableLeaderboardRepository();

  @override
  Future<LeaderboardBoard> load({
    required LeaderboardScope scope,
    required LeaderboardMetric metric,
    required LeaderboardPeriod period,
  }) async {
    throw const LeaderboardUnavailable(
      'Papan peringkat belum tersedia. Coba lagi nanti.',
    );
  }

  @override
  Future<bool> report(String displayName) async {
    throw const LeaderboardUnavailable(
      'Laporan belum bisa dikirim. Server peninjauan belum tersedia.',
    );
  }

  @override
  Future<bool> block(String displayName) async {
    throw const LeaderboardUnavailable(
      'Blokir belum bisa disimpan di server.',
    );
  }
}

@visibleForTesting
LeaderboardBoard buildDemoLeaderboard({
  required LeaderboardScope scope,
  required LeaderboardMetric metric,
  required LeaderboardPeriod period,
  String currentUserName = 'Rani',
}) {
  switch (scope) {
    case LeaderboardScope.national:
      return _national(metric, period, currentUserName);
    case LeaderboardScope.group:
      return _group(metric, period, currentUserName);
  }
}

const List<String> _nationalNames = <String>[
  'Dimas A.',
  'Sari W.',
  'Bayu P.',
  'Nadia R.',
  'Rizky F.',
  'Lia M.',
  'Fajar S.',
  'Maya T.',
  'Rendra K.',
  'Ayu L.',
];

const List<int> _nationalMonthlyMountains = <int>[9, 8, 8, 7, 6, 6, 5, 5, 4, 3];
const List<int> _nationalMonthlyDistance = <int>[
  128400,
  121800,
  118200,
  104500,
  96700,
  93100,
  88600,
  84900,
  79300,
  72800,
];

LeaderboardBoard _national(
  LeaderboardMetric metric,
  LeaderboardPeriod period,
  String currentUserName,
) {
  final distance = metric == LeaderboardMetric.totalDistance;
  final base = distance ? _nationalMonthlyDistance : _nationalMonthlyMountains;
  final entries = <LeaderboardEntry>[
    for (var index = 0; index < _nationalNames.length; index++)
      LeaderboardEntry(
        rank: index + 1,
        displayName: _nationalNames[index],
        value: _scaled(base[index], period, distance: distance),
      ),
  ];
  final selfBase = distance ? 41200 : 2;
  return LeaderboardBoard(
    scope: LeaderboardScope.national,
    metric: metric,
    period: period,
    entries: entries,
    currentUser: LeaderboardEntry(
      rank: 27,
      displayName: currentUserName,
      value: _scaled(selfBase, period, distance: distance),
      isCurrentUser: true,
    ),
  );
}

const List<String> _groupNames = <String>['Rani', 'Dimas', 'Sari', 'Bayu'];
const List<int> _groupMonthlyMountains = <int>[5, 4, 3, 2];
const List<int> _groupMonthlyDistance = <int>[42500, 37800, 30400, 21900];

LeaderboardBoard _group(
  LeaderboardMetric metric,
  LeaderboardPeriod period,
  String currentUserName,
) {
  final distance = metric == LeaderboardMetric.totalDistance;
  final base = distance ? _groupMonthlyDistance : _groupMonthlyMountains;
  final entries = <LeaderboardEntry>[];
  for (var index = 0; index < _groupNames.length; index++) {
    final name = index == 0 ? currentUserName : _groupNames[index];
    entries.add(
      LeaderboardEntry(
        rank: index + 1,
        displayName: name,
        value: _scaled(base[index], period, distance: distance),
        isCurrentUser: index == 0,
      ),
    );
  }
  return LeaderboardBoard(
    scope: LeaderboardScope.group,
    metric: metric,
    period: period,
    entries: entries,
    groupName: 'Rombongan Sabtu',
    groupMemberCount: entries.length,
    currentUser: entries.first,
  );
}

int _scaled(int base, LeaderboardPeriod period, {required bool distance}) {
  switch (period) {
    case LeaderboardPeriod.weekly:
      final scaled = (base * (distance ? 0.26 : 0.34)).round();
      return distance ? scaled : (scaled < 1 ? 1 : scaled);
    case LeaderboardPeriod.monthly:
      return base;
    case LeaderboardPeriod.yearly:
      final scaled = (base * (distance ? 11 : 2.7)).round();
      return distance ? scaled : (scaled < 1 ? 1 : scaled);
  }
}
