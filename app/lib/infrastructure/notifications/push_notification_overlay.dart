import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/safe_url_launcher.dart';
import '../../design/tokens.dart';
import '../../design/widgets/nav_bar_visibility.dart';
import '../../features/map/data/mountain_catalog_repository.dart';
import '../../features/map/domain/map_package.dart';
import '../../features/map/domain/mountain_pack.dart';
import '../../features/map/domain/mountain_pack_data.dart';
import '../../features/preparation/application/packing_list_store.dart';
import '../../features/social/data/community_service.dart';
import '../../features/social/data/social_unread_store.dart';
import 'push_notification_service.dart';

const Set<String> _kShellBranchPaths = <String>{
  '/beranda',
  '/peta',
  '/lacak',
  '/grup',
  '/profil',
};

/// Membuka halaman Peta Jalur Gunung dalam mode tracking otomatis saat anggota
/// grup memulai pendakian bersama.
void openGroupHikeMapFromPlan(GoRouter router, GroupHikePlan plan) {
  final repoPacks = MountainCatalogRepository.instance.packs;
  final candidates = repoPacks.isNotEmpty
      ? repoPacks
      : MountainPackData.createDefaultPacks();
  final targetId = plan.mountainId.trim().toLowerCase();
  final targetName = plan.mountainName.trim().toLowerCase();
  MountainPack selectedPack = candidates.first;
  for (final pack in candidates) {
    if (pack.id.toLowerCase() == targetId ||
        (targetName.isNotEmpty &&
            pack.name.toLowerCase() == targetName)) {
      selectedPack = pack;
      break;
    }
  }
  MapTrail? selectedTrail;
  final trailId = plan.trailId?.trim().toLowerCase() ?? '';
  final trailName = plan.trailName?.trim().toLowerCase() ?? '';
  for (final t in selectedPack.package.trails) {
    if ((trailId.isNotEmpty && t.id.toLowerCase() == trailId) ||
        (trailName.isNotEmpty && t.name.toLowerCase() == trailName)) {
      selectedTrail = t;
      break;
    }
  }
  selectedTrail ??= selectedPack.package.trails.isNotEmpty
      ? selectedPack.package.trails.first
      : null;

  final rootNav = router.routerDelegate.navigatorKey.currentState;
  rootNav?.popUntil((route) => route.settings is Page || route.isFirst);
  NavBarVisibilityController.instance.reset();
  router.go(
    '/peta/jalur',
    extra: <String, dynamic>{
      'package': selectedPack.package,
      'trail': selectedTrail,
      'allowStartAscent': true,
      'autoStartTracking': true,
      'activeGroupId': plan.groupId,
      'activeGroupName': plan.groupName,
      'startButtonLabel': 'Mulai pendakian',
    },
  );
}

/// Melakukan navigasi otomatis saat notifikasi perangkat diketuk (dari
/// foreground, background, maupun terminated state) melalui shell/router utama
/// agar Floating Bottom Navbar tetap utuh.
void dispatchPushNavigation(
  GoRouter router,
  InAppPushNotification notif, {
  BuildContext? dialogContext,
}) {
  final rootNav = router.routerDelegate.navigatorKey.currentState;
  if (rootNav != null) {
    rootNav.popUntil((route) => route.settings is Page || route.isFirst);
  }
  NavBarVisibilityController.instance.reset();

  void pushOverShell(String location) {
    final currentPath = router.routerDelegate.currentConfiguration.uri.path;
    if (!_kShellBranchPaths.contains(currentPath)) {
      router.go('/beranda');
    }
    router.push(location);
  }

  switch (notif.type) {
    case 'hike_started':
      final gid = (notif.groupId ?? notif.targetId ?? '').trim();
      final mountainId = (notif.rawData['mountain_id'] ?? '').trim();
      final plan = GroupHikePlan(
        inviteId: notif.inviteId ?? 'push_$gid',
        groupId: gid,
        groupName: notif.roomName ?? 'Grup Pendakian',
        mountainId: mountainId.isNotEmpty ? mountainId : 'ciremai',
        mountainName: notif.rawData['mountain_name'] ?? 'Gunung',
        trailId: notif.rawData['route_id'] ?? notif.rawData['trail_id'],
        trailName: notif.rawData['trail_name'],
        organizerUserId: notif.senderId ?? '',
        organizerName: notif.senderName ?? 'Ketua Rombongan',
        readyUserIds: const <String>{},
        memberCount: 2,
        status: 'started',
        startedAtUtc: notif.sentAtUtc,
        startedByUserId: notif.rawData['started_by'] ?? notif.senderId,
      );
      if (gid.isNotEmpty && mountainId.isNotEmpty) {
        GroupHikePlanStore.instance.emitHikeStartedFromPush(notif.rawData);
      }
      openGroupHikeMapFromPlan(router, plan);
      return;

    case 'group_chat':
    case 'group_invitation':
    case 'group_hike_cancelled':
      unawaited(SocialUnreadStore.instance.refresh());
      final gid = notif.groupId ?? notif.targetId;
      if (gid != null && gid.isNotEmpty) {
        PushNotificationService.instance.queueSocialIntent(
          SocialNavigationTargetKind.groupRoom,
          gid,
        );
      }
      router.go('/grup');

    case 'group_ready':
      unawaited(SocialUnreadStore.instance.refresh());
      final gid = notif.groupId ?? notif.targetId;
      if (gid != null && gid.isNotEmpty) {
        PushNotificationService.instance.queueSocialIntent(
          SocialNavigationTargetKind.groupRoom,
          gid,
        );
        router.go('/grup');
      } else {
        pushOverShell('/siap-naik');
      }

    case 'community_chat':
    case 'community_mention':
      unawaited(SocialUnreadStore.instance.refresh());
      unawaited(CommunityService.instance.loadCommunities());
      final cid = notif.communityId ?? notif.targetId;
      if (cid != null && cid.isNotEmpty) {
        PushNotificationService.instance.queueSocialIntent(
          SocialNavigationTargetKind.communityRoom,
          cid,
          messageId: notif.messageId,
        );
      }
      router.go('/grup');

    case 'friend_request':
      pushOverShell('/teman');

    case 'sos':
      final gid = notif.groupId;
      if (gid != null && gid.isNotEmpty) {
        PushNotificationService.instance.queueSocialIntent(
          SocialNavigationTargetKind.groupLastLocation,
          gid,
        );
        router.go('/grup');
      } else {
        pushOverShell('/sos');
      }
      if (dialogContext != null &&
          dialogContext.mounted &&
          (notif.rawData['lat']?.isNotEmpty == true ||
              notif.rawData['mountain_name']?.isNotEmpty == true)) {
        unawaited(_showIncomingSosDetailDialog(dialogContext, notif));
      }

    case 'emergency_contact_request':
      router.go('/profil');

    default:
      switch (notif.route) {
        case '/teman':
          pushOverShell('/teman');
        case '/sos':
          pushOverShell('/sos');
        case '/siap-naik':
          pushOverShell('/siap-naik');
        case '/notifikasi':
          pushOverShell('/notifikasi');
        case '/profil':
          router.go('/profil');
        case '/grup':
          router.go('/grup');
        default:
          router.go('/beranda');
      }
  }
}

Future<void> _showIncomingSosDetailDialog(
  BuildContext context,
  InAppPushNotification notif,
) async {
  final lat = notif.rawData['lat']?.trim() ?? '';
  final lon = notif.rawData['lon']?.trim() ?? '';
  final sender = notif.rawData['sender_name']?.trim() ?? 'Pendaki';
  final mountain = notif.rawData['mountain_name']?.trim() ?? '';
  final alt = notif.rawData['altitude_m']?.trim() ?? '';
  final bat = notif.rawData['battery_pct']?.trim() ?? '';

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final colors = HiqeoColors.of(ctx);
      return AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, color: colors.warning, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sinyal SOS Darurat',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$sender membutuhkan bantuan darurat.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (mountain.isNotEmpty) Text('Gunung: $mountain'),
            if (lat.isNotEmpty && lon.isNotEmpty)
              Text('Koordinat: $lat, $lon'),
            if (alt.isNotEmpty) Text('Elevasi: $alt mdpl'),
            if (bat.isNotEmpty) Text('Baterai: $bat%'),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Tutup'),
          ),
          if (lat.isNotEmpty && lon.isNotEmpty)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                final uri = buildSafeGoogleMapsUri(rawLat: lat, rawLon: lon);
                if (uri != null) {
                  unawaited(launchSafeExternalUrl(uri));
                }
              },
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Buka di Peta'),
            ),
        ],
      );
    },
  );
}

class _PushOverlayScope extends InheritedWidget {
  const _PushOverlayScope({required super.child});

  @override
  bool updateShouldNotify(_PushOverlayScope oldWidget) => false;
}

/// Penampung global tanpa overlay visual yang menangani ketukan notifikasi
/// perangkat (dari foreground, background, maupun terminated state) melalui
/// [GoRouter] utama agar Floating Bottom Navbar tetap utuh.
class PushNotificationOverlayHost extends StatefulWidget {
  const PushNotificationOverlayHost({
    super.key,
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  static bool isActiveIn(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_PushOverlayScope>() != null;

  @override
  State<PushNotificationOverlayHost> createState() =>
      _PushNotificationOverlayHostState();
}

class _PushNotificationOverlayHostState
    extends State<PushNotificationOverlayHost> {
  StreamSubscription<InAppPushNotification>? _tapSub;
  StreamSubscription<GroupHikePlan>? _hikeStartedSub;

  @override
  void initState() {
    super.initState();
    final service = PushNotificationService.instance;
    _tapSub = service.onNotificationTap.listen(_handleTap);
    _hikeStartedSub =
        GroupHikePlanStore.instance.onHikeStarted.listen(_handleHikeStarted);

    final currentPath = widget.router.routerDelegate.currentConfiguration.uri.path;
    if (currentPath != '/splash') {
      final initial = service.takePendingInitialTap();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleTap(initial);
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_tapSub?.cancel());
    unawaited(_hikeStartedSub?.cancel());
    super.dispose();
  }

  void _handleHikeStarted(GroupHikePlan plan) {
    if (!mounted) return;
    final currentPath = widget.router.routerDelegate.currentConfiguration.uri.path;
    if (currentPath == '/splash') return;
    openGroupHikeMapFromPlan(widget.router, plan);
  }

  void _handleTap(InAppPushNotification notif) {
    if (!mounted) return;
    final navContext = widget.router.routerDelegate.navigatorKey.currentContext;
    dispatchPushNavigation(
      widget.router,
      notif,
      dialogContext: navContext,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PushOverlayScope(child: widget.child);
  }
}
