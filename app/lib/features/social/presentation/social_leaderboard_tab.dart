import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../design/gooey/gooey_selector.dart';
import '../../../design/layout.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_state_view.dart';
import '../../../design/widgets/persistent_avatar_image.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../plus/application/plus_scope.dart';
import '../../profile/presentation/other_user_profile_page.dart';

enum LeaderboardCategory {
  mountains('mountains', 'Gunung paling banyak didaki'),
  distance('distance', 'Jarak paling jauh ditempuh');

  const LeaderboardCategory(this.rpcKey, this.label);
  final String rpcKey;
  final String label;
}

enum LeaderboardPeriod {
  monthly('monthly', 'Bulanan'),
  yearly('yearly', 'Tahunan');

  const LeaderboardPeriod(this.rpcKey, this.label);
  final String rpcKey;
  final String label;
}

enum _LeaderboardLoadState {
  loading,
  ready,
  offline,
  error,
}

@immutable
class LeaderboardRowEntry {
  const LeaderboardRowEntry({
    required this.rank,
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarUrl,
    required this.mountainsCount,
    required this.distanceM,
  });

  final int rank;
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final int mountainsCount;
  final double distanceM;

  String get name =>
      (displayName != null && displayName!.trim().isNotEmpty)
          ? displayName!.trim()
          : '@$username';
}

/// Tab Leaderboard di halaman Sosial (juga dipakai ulang oleh LeaderboardPage).
///
/// - 2 kategori: "Gunung paling banyak didaki" & "Jarak paling jauh ditempuh"
/// - 2 periode per kategori: "Bulanan" & "Tahunan"
/// - Hanya pengguna Paket Mahasiswa & Paket Tahunan yang masuk peringkat;
///   pengguna Gratis & Tiket 1x Naik tetap bisa melihat papan peringkat.
/// - TIDAK PERNAH menampilkan teks "Plus Tahunan" atau "Plus Mahasiswa".
class SocialLeaderboardTab extends StatefulWidget {
  const SocialLeaderboardTab({
    super.key,
    this.isOnlineChecker,
    this.fetchRankingsOverride,
  });

  final Future<bool> Function()? isOnlineChecker;
  final Future<List<LeaderboardRowEntry>> Function(
    LeaderboardCategory category,
    LeaderboardPeriod period,
  )? fetchRankingsOverride;

  @override
  State<SocialLeaderboardTab> createState() => _SocialLeaderboardTabState();
}

class _SocialLeaderboardTabState extends State<SocialLeaderboardTab> {
  LeaderboardCategory _category = LeaderboardCategory.mountains;
  LeaderboardPeriod _period = LeaderboardPeriod.monthly;
  List<LeaderboardRowEntry> _entries = const <LeaderboardRowEntry>[];
  _LeaderboardLoadState _loadState = _LeaderboardLoadState.loading;
  int _loadGeneration = 0;

  String? get _currentUserId =>
      SupabaseServices.clientOrNull?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<bool> _isOnline() async {
    final override = widget.isOnlineChecker;
    if (override != null) {
      try {
        return await override();
      } catch (_) {
        return false;
      }
    }
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  List<LeaderboardRowEntry> _parseRows(
    dynamic rows,
    LeaderboardCategory category,
  ) {
    final parsed = <LeaderboardRowEntry>[];
    if (rows is! List) return parsed;
    for (final raw in rows) {
      if (raw is! Map) continue;
      final scoreValue = (raw['score_value'] as num?)?.toDouble();
      final mountainsCount = (raw['mountains_count'] as num?)?.toInt() ??
          (category == LeaderboardCategory.mountains && scoreValue != null
              ? scoreValue.round()
              : 0);
      final distanceM = (raw['total_distance_m'] as num?)?.toDouble() ??
          (category == LeaderboardCategory.distance && scoreValue != null
              ? scoreValue
              : 0);
      final displayName = raw['display_name']?.toString();
      final rawUsername = raw['username']?.toString().trim();
      final username = (rawUsername != null && rawUsername.isNotEmpty)
          ? rawUsername
          : (displayName != null && displayName.trim().isNotEmpty
              ? displayName.trim().toLowerCase().replaceAll(' ', '')
              : 'pendaki');
      parsed.add(
        LeaderboardRowEntry(
          rank: (raw['rank_pos'] as num?)?.toInt() ??
              (raw['rank_no'] as num?)?.toInt() ??
              (parsed.length + 1),
          userId: raw['user_id']?.toString() ?? '',
          username: username,
          displayName: displayName,
          avatarUrl: raw['avatar_url']?.toString(),
          mountainsCount: mountainsCount,
          distanceM: distanceM,
        ),
      );
    }
    return parsed;
  }

  Future<void> _load() async {
    final gen = ++_loadGeneration;
    final category = _category;
    final period = _period;

    if (mounted) {
      setState(() => _loadState = _LeaderboardLoadState.loading);
    }

    final online = await _isOnline();
    if (!mounted || gen != _loadGeneration) return;
    if (!online) {
      setState(() {
        _entries = const <LeaderboardRowEntry>[];
        _loadState = _LeaderboardLoadState.offline;
      });
      return;
    }

    final overrideFetcher = widget.fetchRankingsOverride;
    if (overrideFetcher != null) {
      try {
        final parsed = await overrideFetcher(category, period);
        if (!mounted || gen != _loadGeneration) return;
        setState(() {
          _entries = parsed;
          _loadState = _LeaderboardLoadState.ready;
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('SocialLeaderboardTab override load failed: $e');
        }
        final stillOnline = await _isOnline();
        if (!mounted || gen != _loadGeneration) return;
        setState(() {
          _entries = const <LeaderboardRowEntry>[];
          _loadState = stillOnline
              ? _LeaderboardLoadState.error
              : _LeaderboardLoadState.offline;
        });
      }
      return;
    }

    final client = SupabaseServices.clientOrNull;
    if (client == null) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _entries = const <LeaderboardRowEntry>[];
        _loadState = _LeaderboardLoadState.error;
      });
      return;
    }

    try {
      dynamic rows;
      try {
        rows = await client.rpc(
          'leaderboard_rankings',
          params: <String, dynamic>{
            'p_category': category.rpcKey,
            'p_period': period.rpcKey,
          },
        ).timeout(const Duration(seconds: 10));
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') rethrow;
        rows = await client.rpc(
          'leaderboard_rankings',
          params: <String, dynamic>{
            'p_metric': category.rpcKey,
            'p_period': period.rpcKey,
          },
        ).timeout(const Duration(seconds: 10));
      }
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _entries = _parseRows(rows, category);
        _loadState = _LeaderboardLoadState.ready;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SocialLeaderboardTab load failed: $e');
      }
      final stillOnline = await _isOnline();
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _entries = const <LeaderboardRowEntry>[];
        _loadState = stillOnline
            ? _LeaderboardLoadState.error
            : _LeaderboardLoadState.offline;
      });
    }
  }

  String _formatMetric(LeaderboardRowEntry entry) {
    if (_category == LeaderboardCategory.mountains) {
      return '${entry.mountainsCount} gunung';
    }
    return '${(entry.distanceM / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final plus = PlusScope.maybeOf(context);
    final isRankedEligible = plus?.hasFullSocialAccess ?? false;
    final bottomInset = AppLayout.bottomInset(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 10, 16, bottomInset + 24),
        children: <Widget>[
          // 1. Kategori Leaderboard
          Row(
            children: <Widget>[
              for (final cat in LeaderboardCategory.values) ...<Widget>[
                Expanded(
                  child: GestureDetector(
                    key: ValueKey('lb-cat-${cat.rpcKey}'),
                    onTap: () {
                      if (_category == cat) return;
                      setState(() => _category = cat);
                      unawaited(_load());
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _category == cat ? colors.primary : colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              _category == cat ? colors.primary : colors.hairline,
                        ),
                      ),
                      child: Text(
                        cat.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _category == cat
                              ? colors.onPrimary
                              : colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                if (cat == LeaderboardCategory.mountains)
                  const SizedBox(width: 8),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // 2. Periode Bulanan / Tahunan
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.hairline),
            ),
            child: GooeySelector<LeaderboardPeriod>(
              key: const ValueKey<String>('lb-period-selector'),
              axis: Axis.horizontal,
              expandItems: true,
              gap: 4,
              borderRadius: 16,
              indicatorColor: colors.primary,
              itemPadding: const EdgeInsets.symmetric(
                vertical: 11,
                horizontal: 8,
              ),
              selected: _period,
              onChanged: (p) {
                if (_period == p) return;
                setState(() => _period = p);
                unawaited(_load());
              },
              items: <GooeySelectorItem<LeaderboardPeriod>>[
                for (final p in LeaderboardPeriod.values)
                  GooeySelectorItem<LeaderboardPeriod>(
                    value: p,
                    semanticsLabel: p.label,
                    builder: (context, state) => Center(
                      key: ValueKey('lb-period-${p.rpcKey}'),
                      child: Text(
                        p.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color.lerp(
                            colors.textSecondary,
                            colors.onPrimary,
                            state.coverage,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (!isRankedEligible) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.hairline),
              ),
              child: Text(
                'Kamu dapat melihat papan peringkat. Tingkatkan langganan untuk ikut masuk peringkat pendaki.',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
            ),
          ],

          const SizedBox(height: 14),

          if (_loadState == _LeaderboardLoadState.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_loadState == _LeaderboardLoadState.offline)
            HiqeoStateView(
              icon: Icons.wifi_off_rounded,
              title: 'Papan peringkat belum bisa dimuat',
              message: 'Papan peringkat hanya tersedia saat online.',
              isError: true,
              actionLabel: 'Coba lagi',
              onAction: () => unawaited(_load()),
            )
          else if (_loadState == _LeaderboardLoadState.error)
            HiqeoStateView(
              icon: Icons.cloud_off_rounded,
              title: 'Gagal memuat papan peringkat',
              message:
                  'Gagal memuat papan peringkat. Periksa sinyal lalu coba lagi.',
              isError: true,
              actionLabel: 'Coba lagi',
              onAction: () => unawaited(_load()),
            )
          else if (_entries.isEmpty)
            const HiqeoStateView(
              icon: Icons.emoji_events_outlined,
              title: 'Belum ada data peringkat',
              message:
                  'Belum ada data peringkat di periode ini. Selesaikan pendakian pertamamu untuk masuk papan peringkat!',
            )
          else
            for (final entry in _entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: entry.userId == _currentUserId
                      ? colors.primary.withValues(alpha: 0.10)
                      : colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: entry.userId == _currentUserId
                          ? colors.primary
                          : colors.hairline,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: entry.userId.isEmpty
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => OtherUserProfilePage(
                                  userId: entry.userId,
                                  initialName: entry.displayName,
                                  initialUsername: entry.username,
                                  initialAvatarUrl: entry.avatarUrl,
                                ),
                              ),
                            ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 28,
                        child: Text(
                          '#${entry.rank}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: entry.rank <= 3
                                ? colors.primary
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PersistentAvatarImage(
                        cacheKey: 'user:${entry.userId}',
                        avatarUrl: entry.avatarUrl,
                        size: 38,
                        backgroundColor: colors.hairline,
                        fallback: Center(
                          child: Text(
                            entry.name.isNotEmpty
                                ? entry.name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              '@${entry.username}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatMetric(entry),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
