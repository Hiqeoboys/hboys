import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/glass/glass_surface.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/account_badges.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../design/widgets/persistent_avatar_image.dart';
import '../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../groups/domain/group.dart';
import '../../groups/domain/group_remote_service.dart';
import '../domain/group_chat_models.dart';

/// Mengubah timestamp `profiles.last_seen_at` menjadi label status kehadiran
/// yang ramah dibaca manusia:
/// - `< 3 menit` -> `"Sedang aktif"`
/// - `< 60 menit` -> `"Aktif X mnt lalu"`
/// - `< 24 jam` -> `"Aktif X jam lalu"`
/// - `>= 24 jam` -> `"Aktif X hari lalu"`
String formatLastActiveLabel(DateTime lastSeenAtUtc, DateTime nowUtc) {
  final mins = nowUtc.difference(lastSeenAtUtc).inMinutes.clamp(0, 999999);
  if (mins < 3) return 'Sedang aktif';
  if (mins < 60) return 'Aktif $mins mnt lalu';
  if (mins < 24 * 60) return 'Aktif ${mins ~/ 60} jam lalu';
  return 'Aktif ${mins ~/ (24 * 60)} hari lalu';
}

/// Menampilkan lembar "Info anggota" dari Ruang Obrolan (melalui ketukan
/// header nama grup/jumlah anggota maupun menu titik tiga kanan atas).
///
/// Mendukung tampilan instan dari cache lokal saat offline, serta menyegarkan
/// daftar anggota di latar bila online.
Future<void> showGroupMembersSheet(
  BuildContext context, {
  required String groupName,
  String? mountain,
  required String currentUserId,
  required List<MemberDirectoryEntry> initialMembers,
  required List<MemberLastLocation> memberLocations,
  required DateTime nowUtc,
  required bool isOnline,
  Future<List<MemberDirectoryEntry>> Function()? onRefreshMembers,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _GroupMembersSheet(
      groupName: groupName,
      mountain: mountain,
      currentUserId: currentUserId,
      initialMembers: initialMembers,
      memberLocations: memberLocations,
      nowUtc: nowUtc,
      isOnline: isOnline,
      onRefreshMembers: onRefreshMembers,
    ),
  );
}

class _GroupMembersSheet extends StatefulWidget {
  const _GroupMembersSheet({
    required this.groupName,
    this.mountain,
    required this.currentUserId,
    required this.initialMembers,
    required this.memberLocations,
    required this.nowUtc,
    required this.isOnline,
    this.onRefreshMembers,
  });

  final String groupName;
  final String? mountain;
  final String currentUserId;
  final List<MemberDirectoryEntry> initialMembers;
  final List<MemberLastLocation> memberLocations;
  final DateTime nowUtc;
  final bool isOnline;
  final Future<List<MemberDirectoryEntry>> Function()? onRefreshMembers;

  @override
  State<_GroupMembersSheet> createState() => _GroupMembersSheetState();
}

class _GroupMembersSheetState extends State<_GroupMembersSheet> {
  late List<MemberDirectoryEntry> _members;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _members = _sortedMembers(widget.initialMembers);
    if (widget.isOnline && _members.isNotEmpty) {
      unawaited(
        PublicProfileCacheService.instance.fetchProfiles(
          _members.map((m) => m.userId),
          forceRefresh: true,
        ),
      );
    }
    if (widget.isOnline && widget.onRefreshMembers != null) {
      unawaited(_refresh());
    }
  }

  List<MemberDirectoryEntry> _sortedMembers(List<MemberDirectoryEntry> input) {
    final copy = List<MemberDirectoryEntry>.of(input);
    copy.sort((a, b) {
      if (a.role != b.role) {
        return a.role == GroupRole.owner ? -1 : 1;
      }
      return a.joinedAtUtc.compareTo(b.joinedAtUtc);
    });
    return copy;
  }

  Future<void> _refresh() async {
    final fetcher = widget.onRefreshMembers;
    if (fetcher == null) return;
    setState(() => _refreshing = true);
    try {
      final latest = await fetcher();
      if (!mounted) return;
      if (latest.isNotEmpty) {
        setState(() => _members = _sortedMembers(latest));
      }
    } catch (_) {
      // Tetap tampilkan data cache lokal.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _formatIndonesianDate(DateTime date) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    final mountain = widget.mountain?.trim();

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: GlassSurface(
          key: const ValueKey<String>('group-members-info-sheet'),
          tier: GlassTier.panel,
          borderRadius: 28,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Info anggota',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (mountain != null && mountain.isNotEmpty)
                              ? '${widget.groupName} · $mountain · ${_members.length} anggota'
                              : '${widget.groupName} · ${_members.length} anggota',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_refreshing)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      key: const ValueKey<String>('group-members-close-btn'),
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
              if (!widget.isOnline) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colors.warning.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      HiqeoIcon(
                        HiqeoIcons.warning,
                        size: 16,
                        color: colors.warningText,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sedang offline · menampilkan daftar anggota terakhir yang tersimpan di HP',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.warningText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (_members.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    'Daftar anggota belum tersedia.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListenableBuilder(
                    listenable: PublicProfileCacheService.instance,
                    builder: (context, _) => ListView.separated(
                      shrinkWrap: true,
                      itemCount: _members.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: colors.hairline,
                      ),
                      itemBuilder: (context, index) {
                        final member = _members[index];
                        final isSelf = member.userId == widget.currentUserId;
                        final isOwner = member.role == GroupRole.owner;
                        final liveLastSeen = PublicProfileCacheService.instance
                                .getCached(member.userId)
                                ?.lastSeenAtUtc ??
                            member.lastSeenAtUtc;
                        final String statusLine;
                        final bool isActiveNow;
                        if (liveLastSeen != null) {
                          statusLine =
                              formatLastActiveLabel(liveLastSeen, widget.nowUtc);
                          isActiveNow = widget.nowUtc
                                  .difference(liveLastSeen)
                                  .inMinutes
                                  .clamp(0, 999999) <
                              3;
                        } else {
                          statusLine =
                              'Bergabung ${_formatIndonesianDate(member.joinedAtUtc.toLocal())}';
                          isActiveNow = false;
                        }

                        return _MemberInfoTile(
                          member: member,
                          isSelf: isSelf,
                          isOwner: isOwner,
                          statusLine: statusLine,
                          isActiveNow: isActiveNow,
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberInfoTile extends StatelessWidget {
  const _MemberInfoTile({
    required this.member,
    required this.isSelf,
    required this.isOwner,
    required this.statusLine,
    required this.isActiveNow,
  });

  final MemberDirectoryEntry member;
  final bool isSelf;
  final bool isOwner;
  final String statusLine;
  final bool isActiveNow;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: PublicProfileCacheService.instance,
      builder: (context, _) {
        final cache = PublicProfileCacheService.instance;
        final name = cache.resolveDisplayName(
          member.userId,
          fallback: member.effectiveDisplayName,
        );
        final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
        final resolvedUsername =
            cache.resolveUsername(member.userId, fallback: member.username) ??
                '';
        final hasUsername = resolvedUsername.trim().isNotEmpty;
        final avatarUrl = cache.resolveAvatarUrl(
          member.userId,
          fallback: member.avatarUrl,
        );
        final isOfficial = cache.resolveIsOfficial(
          member.userId,
          fallback: member.isOfficial,
          usernameFallback: resolvedUsername,
        );

        final fallbackAvatar = Center(
          child: Text(
            initial,
            style: theme.textTheme.titleMedium?.copyWith(
              color: isOwner ? colors.onPrimary : colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        );

        return Padding(
          key: ValueKey<String>('member-info-row-${member.userId}'),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: <Widget>[
              PersistentAvatarImage(
                cacheKey: member.userId,
                avatarUrl: avatarUrl,
                size: 44,
                backgroundColor: isOwner
                    ? colors.primary
                    : colors.secondary.withValues(alpha: 0.6),
                fallback: fallbackAvatar,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            isSelf ? '$name (Kamu)' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        if (isOfficial) ...<Widget>[
                          const SizedBox(width: 4),
                          const OfficialVerifiedBadge(size: 15),
                        ],
                        const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isOwner
                            ? colors.primary.withValues(alpha: 0.16)
                            : colors.secondary.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                      ),
                      child: Text(
                        isOwner ? 'Pemilik' : 'Anggota',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isOwner ? colors.primary : colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    if (isActiveNow) ...<Widget>[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF22C55E),
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(
                        hasUsername
                            ? '@${resolvedUsername.trim()} · $statusLine'
                            : statusLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isActiveNow
                              ? const Color(0xFF22C55E)
                              : colors.textSecondary,
                          fontWeight:
                              isActiveNow ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
      },
    );
  }
}
