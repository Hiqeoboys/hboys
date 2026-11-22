import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../design/layout.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_state_view.dart';
import '../../../design/widgets/persistent_avatar_image.dart';
import '../../plus/application/plus_scope.dart';
import '../data/community_service.dart';
import '../data/social_unread_store.dart';
import 'community_chat_page.dart';

/// Tab Komunitas (Online-Only) di dalam halaman Sosial.
class SocialCommunityTab extends StatefulWidget {
  const SocialCommunityTab({super.key});

  @override
  State<SocialCommunityTab> createState() => _SocialCommunityTabState();
}

class _SocialCommunityTabState extends State<SocialCommunityTab> {
  final CommunityService _service = CommunityService.instance;
  final SocialUnreadStore _unreadStore = SocialUnreadStore.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    _unreadStore.addListener(_onChanged);
    _unreadStore.ensureRealtimeSubscribed();
    unawaited(_service.loadCommunities());
    unawaited(_unreadStore.refresh());
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    _unreadStore.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openCreateCommunityDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    File? photo;
    var creating = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final colors = HiqeoColors.of(dialogCtx);
        return StatefulBuilder(
          builder: (ctx, setDialogState) => PopScope(
            canPop: !creating,
            child: AlertDialog(
              backgroundColor: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: Text(
                'Buat komunitas baru',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    GestureDetector(
                      onTap: creating
                          ? null
                          : () async {
                              final picked = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                              );
                              if (picked != null) {
                                setDialogState(() => photo = File(picked.path));
                              }
                            },
                      child: Column(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: colors.hairline,
                            backgroundImage:
                                photo != null ? FileImage(photo!) : null,
                            child: photo == null
                                ? Icon(
                                    Icons.add_a_photo_outlined,
                                    color: colors.textPrimary,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Pilih foto profil komunitas',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      enabled: !creating,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Nama komunitas',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      enabled: !creating,
                      maxLines: 3,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        labelText: 'Deskripsi singkat',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (creating) ...<Widget>[
                      const SizedBox(height: 12),
                      Row(
                        key: const ValueKey<String>(
                          'create-community-loading-notice',
                        ),
                        children: <Widget>[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Sedang membuat komunitas...',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: creating ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: creating
                      ? null
                      : () async {
                          if (nameCtrl.text.trim().isEmpty) return;
                          setDialogState(() => creating = true);
                          try {
                            final created = await _service.createCommunity(
                              name: nameCtrl.text,
                              description: descCtrl.text,
                              avatarFile: photo,
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              await Navigator.of(context, rootNavigator: true)
                                  .push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      CommunityChatPage(community: created),
                                ),
                              );
                            }
                          } catch (e) {
                            if (kDebugMode) {
                              debugPrint('SocialCommunityTab create failed: $e');
                            }
                            setDialogState(() => creating = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Komunitas belum bisa dibuat. Periksa koneksi lalu coba lagi.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: Text(creating ? 'Membuat…' : 'Buat'),
                ),
              ],
            ),
          ),
        );
      },
    );
    nameCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _openOrJoinCommunity(CommunitySummary community) async {
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityChatPage(
          community: community,
        ),
      ),
    );
    if (mounted) {
      unawaited(_service.loadCommunities());
      unawaited(_unreadStore.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final plus = PlusScope.maybeOf(context);
    final hasFullSocial = plus?.hasFullSocialAccess ?? false;
    final bottomInset = AppLayout.bottomInset(context);
    final communities = List<CommunitySummary>.of(_service.communities)
      ..sort((a, b) {
        final liveA = _unreadStore.communityPreview(a.id)?.createdAtUtc;
        final liveB = _unreadStore.communityPreview(b.id)?.createdAtUtc;
        final lastA = _latestUtc(a.lastMessageAt, liveA);
        final lastB = _latestUtc(b.lastMessageAt, liveB);
        return compareRoomsByLatestActivity(
          aLastMessageAtUtc: lastA,
          aCreatedAtUtc: a.createdAt,
          bLastMessageAtUtc: lastB,
          bCreatedAtUtc: b.createdAt,
          aId: a.id,
          bId: b.id,
        );
      });

    return RefreshIndicator(
      onRefresh: _service.loadCommunities,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 10, 16, bottomInset + 24),
        children: <Widget>[
          if (hasFullSocial)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                key: const ValueKey('create-community-button'),
                onPressed: _openCreateCommunityDialog,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Buat komunitas'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.hairline),
              ),
              child: Text(
                'Kamu dapat bergabung dan membaca pesan komunitas. Berlangganan Paket Mahasiswa atau Paket Tahunan untuk membuat komunitas dan mengirim pesan.',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
            ),

          if (_service.isLoading && communities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_service.error != null && communities.isEmpty)
            HiqeoStateView(
              icon: Icons.wifi_off_rounded,
              title: 'Komunitas belum bisa dimuat',
              message: _service.error!,
              isError: true,
              actionLabel: 'Coba lagi',
              onAction: () => unawaited(_service.loadCommunities()),
            )
          else if (communities.isEmpty)
            HiqeoStateView(
              icon: Icons.groups_outlined,
              title: 'Belum ada komunitas',
              message:
                  'Belum ada komunitas pendaki. Jadilah yang pertama membuatnya.',
              actionLabel: hasFullSocial ? 'Buat komunitas' : null,
              onAction: hasFullSocial ? _openCreateCommunityDialog : null,
            )
          else
            for (final c in communities)
              Builder(
                builder: (context) {
                  final preview =
                      c.isJoined ? _unreadStore.communityPreview(c.id) : null;
                  final subtitleText = preview != null
                      ? '${preview.snippet} · ${formatSocialTimeShort(preview.createdAtUtc)}'
                      : (c.description.isNotEmpty
                          ? '${c.description}\n${c.memberCount} anggota'
                          : '${c.memberCount} anggota');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: colors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: colors.hairline),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      onTap: () => unawaited(_openOrJoinCommunity(c)),
                      leading: PersistentAvatarImage(
                        cacheKey: 'community_${c.id}',
                        avatarUrl: c.avatarUrl,
                        size: 48,
                        resolveFromProfileCache: false,
                        backgroundColor: colors.hairline,
                        fallback: Center(
                          child: Icon(
                            Icons.groups_rounded,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      title: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          if (preview?.hasUnread ?? false) ...<Widget>[
                            const SizedBox(width: 6),
                            Container(
                              key: ValueKey<String>(
                                'community-unread-dot-${c.id}',
                              ),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        subtitleText,
                        maxLines: preview != null ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: (preview?.hasUnread ?? false)
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: (preview?.hasUnread ?? false)
                              ? colors.textPrimary
                              : colors.textSecondary,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: c.isJoined ? colors.hairline : colors.primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          c.isJoined ? 'Buka' : 'Lihat',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: c.isJoined
                                ? colors.textPrimary
                                : colors.onPrimary,
                          ),
                        ),
                      ),
                    ),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }

  static DateTime? _latestUtc(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return b.isAfter(a) ? b : a;
  }
}
