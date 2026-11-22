import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/background/app_background.dart';
import '../../../design/background/page_background.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../../../design/widgets/hiqeo_state_view.dart';
import '../../../design/widgets/nav_bar_visibility.dart';
import '../../../infrastructure/notifications/push_notification_overlay.dart';
import '../../../infrastructure/notifications/push_notification_service.dart';
import '../../safety/presentation/widgets/nearby_sos_modal_overlay.dart';
import '../../social/data/community_service.dart';
import '../../social/data/social_unread_store.dart';
import '../data/user_notifications_service.dart';

/// Mengarahkan pengguna dari item inbox notifikasi ke layar tujuan tanpa
/// merusak struktur tab atau menghilangkan Floating Bottom Navbar.
void navigateFromUserNotification(
  BuildContext context,
  UserNotificationItem item,
) {
  NavBarVisibilityController.instance.reset();

  final data = <String, dynamic>{
    ...item.data,
    'type': item.type,
    if (item.targetId != null && item.targetId!.isNotEmpty)
      'target_id': item.targetId!,
    if (item.roomType != null && item.roomType!.isNotEmpty)
      'room_type': item.roomType!,
    if (item.roomId != null && item.roomId!.isNotEmpty)
      'room_id': item.roomId!,
    if (item.roomType == 'group' &&
        item.roomId != null &&
        item.roomId!.isNotEmpty)
      'group_id': item.roomId!,
    if (item.roomType == 'community' &&
        item.roomId != null &&
        item.roomId!.isNotEmpty)
      'community_id': item.roomId!,
    if (item.messageId != null && item.messageId!.isNotEmpty)
      'message_id': item.messageId!,
  };

  final notif = InAppPushNotification.fromRemoteData(
    id: item.id,
    title: item.title,
    body: item.body,
    data: data,
  );

  final sosMode = notif.rawData['sos_mode']?.trim().toLowerCase();
  final isNearbyOrUnscopedSos = notif.type == 'sos_nearby' ||
      ((notif.type == 'sos' || notif.type == 'sos_alert') &&
          (sosMode == 'nearby' ||
              notif.groupId == null ||
              notif.groupId!.trim().isEmpty));
  if (isNearbyOrUnscopedSos) {
    unawaited(showNearbySosModalOverlay(context, notif));
    return;
  }

  final router = GoRouter.maybeOf(context);
  if (router == null) return;

  switch (notif.type) {
    case 'friend_request':
      router.pushReplacement('/teman');
      return;
    case 'group_ready':
      final gid = notif.groupId ?? notif.targetId;
      if (gid == null || gid.isEmpty) {
        router.pushReplacement('/siap-naik');
        return;
      }
      dispatchPushNavigation(router, notif, dialogContext: context);
      return;
    case 'sos':
    case 'sos_alert':
      dispatchPushNavigation(router, notif, dialogContext: context);
      return;
    case 'community_mention':
      unawaited(SocialUnreadStore.instance.refresh());
      unawaited(CommunityService.instance.loadCommunities());
      dispatchPushNavigation(router, notif, dialogContext: context);
      return;
    case 'group_invitation':
    case 'group_hike_cancelled':
    case 'emergency_contact_request':
      dispatchPushNavigation(router, notif, dialogContext: context);
      return;
    default:
      final rawRoute = item.data['route']?.trim();
      switch (rawRoute) {
        case '/teman':
          router.pushReplacement('/teman');
        case '/sos':
          router.pushReplacement('/sos');
        case '/siap-naik':
          router.pushReplacement('/siap-naik');
        case '/profil':
          router.go('/profil');
        case '/grup':
          router.go('/grup');
        case '/lacak':
          router.go('/lacak');
        case '/peta':
          router.go('/peta');
        default:
          router.go('/beranda');
      }
  }
}

/// Halaman kotak masuk notifikasi Beranda.
///
/// Menampilkan seluruh notifikasi masuk kecuali obrolan grup dan komunitas biasa.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    this.service,
    this.autoLoad = true,
    this.onNavigateItem,
  });

  final UserNotificationsService? service;
  final bool autoLoad;
  final FutureOr<void> Function(BuildContext context, UserNotificationItem item)?
      onNavigateItem;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final UserNotificationsService _service =
      widget.service ?? UserNotificationsService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_service.markBadgeSeen());
      }
    });
    if (widget.autoLoad) {
      _service.ensureRealtimeSubscribed();
      unawaited(_service.loadNotifications());
    }
  }

  Future<void> _onTapItem(UserNotificationItem item) async {
    await _service.markAsRead(item.id);
    if (!mounted) return;
    final handler = widget.onNavigateItem;
    if (handler != null) {
      await handler(context, item);
      return;
    }
    navigateFromUserNotification(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return PageBackground(
      page: AppBackgroundPage.beranda,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: const HiqeoBackButton(inAppBar: true),
          leadingWidth: HiqeoBackButton.appBarWidth,
          title: const Text('Notifikasi'),
          actions: <Widget>[
            ListenableBuilder(
              listenable: _service,
              builder: (context, _) {
                if (_service.unreadCount <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: HiqeoSpacing.sm),
                  child: TextButton(
                    key: const ValueKey<String>('notifications-mark-all-read'),
                    onPressed: () => unawaited(_service.markAllAsRead()),
                    child: Text(
                      'Baca semua',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: HiqeoTypography.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: _service,
          builder: (context, _) {
            final items = _service.items;
            final bottomPad = 24 + MediaQuery.paddingOf(context).bottom;

            if (_service.isLoading && items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: HiqeoSpacing.md),
                    Text(
                      'Memuat notifikasi…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }

            if (_service.loadError != null && items.isEmpty) {
              return RefreshIndicator(
                onRefresh: _service.loadNotifications,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    HiqeoSpacing.lg,
                    64,
                    HiqeoSpacing.lg,
                    bottomPad,
                  ),
                  children: <Widget>[
                    HiqeoStateView(
                      icon: Icons.cloud_off_rounded,
                      title: 'Gagal memuat notifikasi',
                      message: _service.loadError!,
                      isError: true,
                      actionLabel: 'Coba lagi',
                      actionKey: const ValueKey<String>(
                        'notifications-retry-button',
                      ),
                      onAction: () => unawaited(_service.loadNotifications()),
                    ),
                  ],
                ),
              );
            }

            if (items.isEmpty) {
              return RefreshIndicator(
                onRefresh: _service.loadNotifications,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    HiqeoSpacing.lg,
                    64,
                    HiqeoSpacing.lg,
                    bottomPad,
                  ),
                  children: const <Widget>[
                    HiqeoStateView(
                      icon: Icons.notifications_none_rounded,
                      title: 'Belum ada notifikasi',
                      message:
                          'Permintaan teman, undangan grup, sebutan @username, dan info darurat akan muncul di sini.',
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _service.loadNotifications,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  HiqeoSpacing.lg,
                  HiqeoSpacing.sm,
                  HiqeoSpacing.lg,
                  bottomPad,
                ),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: HiqeoSpacing.sm),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _NotificationCard(
                    item: item,
                    onTap: () => unawaited(_onTapItem(item)),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationMeta {
  const _NotificationMeta({
    required this.icon,
    required this.accent,
    required this.categoryLabel,
  });

  final IconData icon;
  final Color accent;
  final String categoryLabel;
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.onTap,
  });

  final UserNotificationItem item;
  final VoidCallback onTap;

  _NotificationMeta _meta(HiqeoColors colors) => switch (item.type) {
        'sos_nearby' => _NotificationMeta(
            icon: Icons.warning_amber_rounded,
            accent: colors.warning,
            categoryLabel: 'SOS Terdekat',
          ),
        'sos' || 'sos_alert' => _NotificationMeta(
            icon: Icons.warning_amber_rounded,
            accent: colors.warning,
            categoryLabel: 'Darurat SOS',
          ),
        'community_mention' => _NotificationMeta(
            icon: Icons.alternate_email_rounded,
            accent: colors.primary,
            categoryLabel: 'Sebutan',
          ),
        'group_invitation' => _NotificationMeta(
            icon: Icons.group_add_rounded,
            accent: colors.primary,
            categoryLabel: 'Undangan grup',
          ),
        'group_ready' || 'group_hike_invite' => _NotificationMeta(
            icon: Icons.terrain_rounded,
            accent: colors.primary,
            categoryLabel: 'Ajakan mendaki',
          ),
        'group_hike_cancelled' || 'hike_cancelled' => _NotificationMeta(
            icon: Icons.event_busy_rounded,
            accent: colors.warningText,
            categoryLabel: 'Ajakan dibatalkan',
          ),
        'friend_request' => _NotificationMeta(
            icon: Icons.person_add_alt_1_rounded,
            accent: colors.primary,
            categoryLabel: 'Pertemanan',
          ),
        'emergency_contact_request' => _NotificationMeta(
            icon: Icons.health_and_safety_rounded,
            accent: colors.warningText,
            categoryLabel: 'Kontak darurat',
          ),
        _ => _NotificationMeta(
            icon: Icons.notifications_none_rounded,
            accent: colors.primary,
            categoryLabel: 'Info sistem',
          ),
      };

  static String _relativeTime(DateTime utc) {
    final diff = DateTime.now().toUtc().difference(utc);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mnt lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays == 1) return 'Kemarin';
    if (diff.inDays < 7) return '${diff.inDays} hari lalu';
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
    final local = utc.toLocal();
    return '${local.day} ${months[local.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final unread = !item.isRead;
    final meta = _meta(colors);

    final bgColor = unread
        ? Color.alphaBlend(
            meta.accent.withValues(alpha: isDark ? 0.10 : 0.055),
            colors.surface,
          )
        : colors.surface.withValues(alpha: isDark ? 0.62 : 0.78);

    final borderColor = unread
        ? meta.accent.withValues(alpha: isDark ? 0.48 : 0.38)
        : colors.hairline;

    final shadows = unread
        ? <BoxShadow>[
            BoxShadow(
              color: meta.accent.withValues(alpha: isDark ? 0.16 : 0.10),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ]
        : const <BoxShadow>[];

    final statusSemantic = unread ? 'Belum dibaca' : 'Sudah dibaca';
    final timeLabel = _relativeTime(item.createdAtUtc);

    return Semantics(
      button: true,
      label: '${item.title}. ${item.body}. $statusSemantic. $timeLabel.',
      child: DecoratedBox(
        key: ValueKey<String>('notif-card-${item.id}'),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: unread ? 1.2 : 1.0,
          ),
          boxShadow: shadows,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: meta.accent.withValues(
                        alpha: unread ? (isDark ? 0.20 : 0.14) : 0.08,
                      ),
                    ),
                    child: Icon(
                      meta.icon,
                      size: 20,
                      color: unread ? meta.accent : colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                meta.categoryLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: unread
                                      ? meta.accent
                                      : colors.textSecondary,
                                  fontWeight: HiqeoTypography.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              timeLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                            if (unread) ...<Widget>[
                              const SizedBox(width: 6),
                              Container(
                                key: ValueKey<String>(
                                  'notif-unread-dot-${item.id}',
                                ),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: meta.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: unread
                                ? HiqeoTypography.bold
                                : HiqeoTypography.medium,
                          ),
                        ),
                        if (item.body.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(
                            item.body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: unread
                                  ? colors.textPrimary.withValues(alpha: 0.86)
                                  : colors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
