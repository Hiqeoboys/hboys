import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:go_router/go_router.dart';

import '../../../design/background/page_background.dart';
import '../../../design/glass/glass_surface.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/offgrid/off_grid_chat_local_store.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../auth/application/account_controller.dart';
import '../../chat/domain/group_chat_models.dart';
import '../../groups/application/group_selection.dart';
import '../../groups/domain/group_remote_service.dart';
import '../../map/application/offline_pack_service.dart';
import '../../map/data/mountain_catalog_repository.dart';
import '../../map/domain/map_package.dart';
import '../../map/domain/mountain_pack.dart';
import '../../map/domain/mountain_pack_data.dart';
import '../../map/presentation/mountain_detail_page.dart';
import '../../onboarding/permission_service.dart';
import '../../plus/application/plus_navigation.dart';
import '../../safety/domain/emergency_contact.dart';
import '../application/packing_list_store.dart';

// Helper domain yang tetap diekspor untuk kompatibilitas pengujian & modul lain.
class ReadinessCheck {
  const ReadinessCheck({required this.label, required this.ready});

  final String label;
  final bool ready;
}

List<ReadinessCheck> readinessChecks({
  required bool groupKeyReady,
  required bool mapReady,
  required bool permissionReady,
}) =>
    <ReadinessCheck>[
      ReadinessCheck(label: 'Kunci grup', ready: groupKeyReady),
      ReadinessCheck(label: 'Peta', ready: mapReady),
      ReadinessCheck(label: 'Izin', ready: permissionReady),
    ];

int readyCheckCount(List<ReadinessCheck> checks) =>
    checks.where((check) => check.ready).length;

String readinessHeadline({
  required int readyMembers,
  required int totalMembers,
}) =>
    totalMembers <= 0
        ? 'Kesiapan belum bisa dihitung'
        : '$readyMembers dari $totalMembers anggota melapor siap';

int readinessPercent({
  required int readyMembers,
  required int totalMembers,
}) {
  if (totalMembers <= 0) return 0;
  return ((readyMembers / totalMembers) * 100).round();
}

String contactConsentText(EmergencyContactConsentStatus status) =>
    switch (status) {
      EmergencyContactConsentStatus.granted => 'sudah menyetujui',
      EmergencyContactConsentStatus.pending => 'menunggu persetujuan',
      EmergencyContactConsentStatus.revoked => 'persetujuan dicabut',
    };

EmergencyContact? primaryContact(List<EmergencyContact> contacts) {
  for (final contact in contacts) {
    if (contact.consentStatus == EmergencyContactConsentStatus.granted) {
      return contact;
    }
  }
  return contacts.isEmpty ? null : contacts.first;
}

String contactSubtitle(EmergencyContact? contact, int total) {
  if (contact == null) return 'Belum ada kontak darurat';
  final extra = total > 1 ? ' · +${total - 1} lainnya' : '';
  return '${contact.name} · ${contactConsentText(contact.consentStatus)}$extra';
}

typedef ContactLoader = Future<List<EmergencyContact>> Function(String userId);
typedef OfflineMapCheck = Future<bool> Function(String? mountain);
typedef PermissionCheck = Future<PermissionReport> Function();
typedef StartHike = Future<bool> Function();

const String kEmptyGroupInviteCopy =
    'Tidak ada grup yang tersedia, masuk grup terlebih dahulu untuk mengajak grup';

/// Halaman Persiapan Pendakian ("Siapkan pendakian") dengan 3 bagian utama:
/// 1. Gunung yang Dipilih (solo langsung membuka peta gunung yang dipilih)
/// 2. Grup yang Dipilih (opsional, tersinkron tunggal dengan Sosial -> Grup)
/// 3. Packing List 2 tahap (otomatis reset ke Tahap 1 setelah sesi pendakian berakhir)
class SiapNaikPage extends StatefulWidget {
  const SiapNaikPage({
    super.key,
    this.accountController,
    this.groupHikePlanStore,
    this.socialGroupsStore,
    this.contactLoader,
    this.offlineMapCheck,
    this.permissionCheck,
    this.onStartHike,
    this.startFailureMessage,
    this.hikeActive,
  });

  final AccountController? accountController;
  final GroupHikePlanStore? groupHikePlanStore;
  final SocialGroupsStore? socialGroupsStore;
  final ContactLoader? contactLoader;
  final OfflineMapCheck? offlineMapCheck;
  final PermissionCheck? permissionCheck;
  final StartHike? onStartHike;
  final String? Function()? startFailureMessage;
  final bool Function()? hikeActive;

  @override
  State<SiapNaikPage> createState() => _SiapNaikPageState();
}

class _SiapNaikPageState extends State<SiapNaikPage> {
  late final AccountController _account;
  late final bool _ownsAccount;
  final PackingListStore _packing = PackingListStore.instance;
  late final GroupHikePlanStore _planStore;
  late final SocialGroupsStore _groupsStore;
  final TextEditingController _customItemCtrl = TextEditingController();

  List<MountainPack> _mountains = MountainPackData.createDefaultPacks();
  Set<String> _downloadedMountainIds = <String>{};
  MountainPack? _selectedMountain;
  MapTrail? _selectedTrail;
  RemoteGroup? _selectedGroup;

  String _packingCategory = 'Semua';
  bool _sendingInvite = false;
  bool _starting = false;
  bool _syncingRemote = false;
  bool _refreshingDownloadStatus = false;
  bool _pendingCatalogRefresh = false;
  bool _requestedInitialRepoLoad = false;
  bool _syncedFromPlan = false;
  Timer? _snackBarTimer;

  List<RemoteGroup> get _syncedGroups =>
      _groupsStore.resolveGroups(_account.groups);

  @override
  void initState() {
    super.initState();
    final catalogPacks = MountainCatalogRepository.instance.packs;
    if (catalogPacks.isNotEmpty) {
      _mountains = catalogPacks;
    }
    _downloadedMountainIds = <String>{
      for (final p in _mountains)
        if (p.isDownloaded || p.isUpdateAvailable) p.id,
    };
    final shared = widget.accountController == null
        ? SupabaseServices.sharedAccountController
        : null;
    _ownsAccount = widget.accountController == null && shared == null;
    _account = widget.accountController ??
        shared ??
        SupabaseServices.createAccountController();
    _planStore = widget.groupHikePlanStore ?? GroupHikePlanStore.instance;
    _groupsStore = widget.socialGroupsStore ?? SocialGroupsStore.instance;

    _account.initialize();
    _account.addListener(_onGroupsOrAccountChanged);
    _groupsStore.addListener(_onGroupsOrAccountChanged);
    _packing.addListener(_onStateChanged);
    _planStore.addListener(_onPlanChanged);
    MountainCatalogRepository.instance.addListener(_onCatalogChanged);
    OfflinePackService.instance.addListener(_onCatalogChanged);
    unawaited(_packing.load());
    unawaited(_refreshDownloadedStatus());
    unawaited(_initSyncedState());
  }

  @override
  void dispose() {
    _snackBarTimer?.cancel();
    _customItemCtrl.dispose();
    _account.removeListener(_onGroupsOrAccountChanged);
    _groupsStore.removeListener(_onGroupsOrAccountChanged);
    _packing.removeListener(_onStateChanged);
    _planStore.removeListener(_onPlanChanged);
    MountainCatalogRepository.instance.removeListener(_onCatalogChanged);
    OfflinePackService.instance.removeListener(_onCatalogChanged);
    if (_ownsAccount) _account.dispose();
    super.dispose();
  }

  void _onCatalogChanged() {
    if (!mounted) return;
    unawaited(_refreshDownloadedStatus());
  }

  Future<void> _refreshDownloadedStatus() async {
    if (_refreshingDownloadStatus) {
      _pendingCatalogRefresh = true;
      return;
    }
    _refreshingDownloadStatus = true;
    try {
      do {
        _pendingCatalogRefresh = false;
        final repo = MountainCatalogRepository.instance;
        if (repo.packs.isNotEmpty) {
          _mountains = repo.packs;
        } else if (!_requestedInitialRepoLoad && !repo.isLoading) {
          _requestedInitialRepoLoad = true;
          unawaited(repo.loadPacks());
        }
        final nextIds = <String>{};
        for (final pack in _mountains) {
          if (await _isMountainMapDownloaded(pack)) {
            nextIds.add(pack.id);
          }
        }
        if (!mounted) return;
        setState(() {
          _downloadedMountainIds = nextIds;
          if (_selectedMountain != null) {
            _applyMountainId(_selectedMountain!.id, _selectedTrail?.id);
          }
        });
      } while (_pendingCatalogRefresh && mounted);
    } finally {
      _refreshingDownloadStatus = false;
    }
  }

  bool _isPackMarkedDownloadedSync(MountainPack pack) =>
      _downloadedMountainIds.contains(pack.id) ||
      pack.isDownloaded ||
      pack.isUpdateAvailable;

  Future<bool> _isMountainMapDownloaded(MountainPack pack) async {
    if (widget.offlineMapCheck != null) {
      return widget.offlineMapCheck!(pack.id);
    }
    for (final repoPack in MountainCatalogRepository.instance.packs) {
      if (repoPack.id == pack.id &&
          (repoPack.isDownloaded || repoPack.isUpdateAvailable)) {
        return true;
      }
    }
    try {
      final status = await OfflinePackService.instance.getStatus(
        pack.id,
        remoteVersion: pack.version,
      );
      return status == MountainDownloadStatus.downloaded ||
          status == MountainDownloadStatus.updateAvailable;
    } catch (_) {
      return pack.isDownloaded || pack.isUpdateAvailable;
    }
  }

  MountainPack _resolveLatestPack(MountainPack pack) {
    for (final repoPack in MountainCatalogRepository.instance.packs) {
      if (repoPack.id == pack.id) return repoPack;
    }
    for (final localPack in _mountains) {
      if (localPack.id == pack.id) return localPack;
    }
    return pack;
  }

  Future<void> _showDownloadMapRequiredDialog(MountainPack pack) async {
    final resolved = _resolveLatestPack(pack);
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final colors = HiqeoColors.of(dialogCtx);
        return AlertDialog(
          key: const ValueKey<String>('siap-naik-download-required-dialog'),
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: <Widget>[
              Icon(
                Icons.download_for_offline_outlined,
                color: colors.warning,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Unduh peta gunung dulu',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Peta offline ${resolved.name} belum tersimpan di perangkat ini. '
            'Unduh petanya terlebih dahulu supaya jalur tetap aman dipakai '
            'meski sinyal hilang di gunung.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: colors.textSecondary,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Nanti'),
            ),
            FilledButton.icon(
              key: const ValueKey<String>('siap-naik-go-download'),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                if (!mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MountainDetailPage(
                      pack: resolved,
                      repository: MountainCatalogRepository.instance,
                    ),
                  ),
                );
                if (mounted) {
                  await _refreshDownloadedStatus();
                }
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Unduh peta'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initSyncedState() async {
    await _groupsStore.load();
    await _planStore.load();
    _syncSelectionFromPlan();
    _ensurePrepRealtime();
    final canRemoteSync = _account.user != null && _account.groupsEnabled;
    if (mounted) {
      setState(() => _syncingRemote = canRemoteSync);
    }
    if (!canRemoteSync) return;

    try {
      await Future<void>.delayed(Duration.zero);
      await _account.refreshGroups().timeout(const Duration(seconds: 8));
      await _loadActivePlan().timeout(const Duration(seconds: 8));
      _ensurePrepRealtime();
    } catch (_) {
      // Tetap tampilkan cache lokal bila jaringan lambat atau offline.
    } finally {
      if (mounted) {
        setState(() => _syncingRemote = false);
      }
    }
  }

  void _ensurePrepRealtime() {
    _planStore.ensureRealtimeSubscribed(
      groupNamesById: <String, String>{
        for (final g in _syncedGroups) g.group.id: g.group.name,
      },
    );
  }

  Future<void> _loadActivePlan() async {
    await _planStore.load();
    final groups = _syncedGroups;
    final groupIds = groups.map((g) => g.group.id).toList();
    if (groupIds.isNotEmpty) {
      await _planStore.refreshForGroups(
        groupIds,
        groupNamesById: <String, String>{
          for (final g in groups) g.group.id: g.group.name,
        },
      );
    }
    _syncSelectionFromPlan();
    if (mounted) setState(() {});
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _onGroupsOrAccountChanged() {
    final groups = _syncedGroups;
    if (_selectedGroup != null &&
        !groups.any((g) => g.group.id == _selectedGroup!.group.id)) {
      _selectedGroup = null;
    }
    final activePlan = _planStore.activePlan;
    if (activePlan != null &&
        (_groupsStore.deletedGroupIds.contains(activePlan.groupId) ||
            (_account.hasSyncedGroupsFromServer &&
                !groups.any((g) => g.group.id == activePlan.groupId)))) {
      unawaited(_planStore.cancelActivePlanRemote());
    }
    _syncSelectionFromPlan();
    if (mounted) setState(() {});
  }

  void _onPlanChanged() {
    _syncSelectionFromPlan();
    if (mounted) setState(() {});
  }

  void _syncSelectionFromPlan() {
    final plan = _planStore.activePlan;
    if (plan != null) {
      _syncedFromPlan = true;
      _applyMountainId(plan.mountainId, plan.trailId);
      for (final g in _syncedGroups) {
        if (g.group.id == plan.groupId) {
          _selectedGroup = g;
          break;
        }
      }
      return;
    }
    final solo = _planStore.soloPlan;
    if (solo != null) {
      _syncedFromPlan = true;
      if (_selectedMountain == null) {
        _applyMountainId(solo.mountainId, solo.trailId);
      }
      return;
    }
    if (_syncedFromPlan) {
      _syncedFromPlan = false;
      _selectedMountain = null;
      _selectedTrail = null;
      _selectedGroup = null;
      _packingCategory = 'Semua';
    }
  }

  void _applyMountainId(String mountainId, String? trailId) {
    for (final pack in _mountains) {
      if (pack.id == mountainId) {
        _selectedMountain = pack;
        MapTrail? matchedTrail;
        if (trailId != null) {
          for (final t in pack.package.trails) {
            if (t.id == trailId) {
              matchedTrail = t;
              break;
            }
          }
        }
        _selectedTrail = matchedTrail ??
            (pack.package.trails.isNotEmpty ? pack.package.trails.first : null);
        break;
      }
    }
  }

  bool get _isLockedByPlan => _planStore.activePlan != null;

  bool get _isStartLockedByGroup {
    final plan = _planStore.activePlan;
    return plan != null && !plan.allMembersReady;
  }

  Future<void> _pickMountainSheet() async {
    if (_isLockedByPlan) return;
    final picked =
        await showModalBottomSheet<({MountainPack pack, MapTrail trail})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = HiqeoColors.of(ctx);
        final safeBottom = MediaQuery.paddingOf(ctx).bottom;
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.72,
          child: GlassSurface(
            tier: GlassTier.panel,
            borderRadius: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: 10),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Pilih gunung & jalur',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      if (_selectedMountain != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedMountain = null;
                              _selectedTrail = null;
                            });
                            unawaited(_planStore.clearSoloPlan());
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('Hapus pilihan'),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.hairline),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + safeBottom),
                    itemCount: _mountains.length,
                    itemBuilder: (_, index) {
                      final pack = _mountains[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.background,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: colors.hairline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 12, 14, 6),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          pack.name,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: colors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (_isPackMarkedDownloadedSync(pack))
                                        Container(
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colors.primary
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              Icon(
                                                Icons.offline_pin_outlined,
                                                size: 13,
                                                color: colors.primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Siap offline',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: colors.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        Container(
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colors.warning
                                                .withValues(alpha: 0.14),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              Icon(
                                                Icons.download_outlined,
                                                size: 13,
                                                color: colors.warningText,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Belum diunduh',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: colors.warningText,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Text(
                                        '${pack.elevationM} mdpl',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              for (final trail in pack.package.trails)
                                ListTile(
                                  dense: true,
                                  leading: Icon(
                                    Icons.terrain_rounded,
                                    size: 18,
                                    color: colors.primary,
                                  ),
                                  title: Text(
                                    trail.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    pack.province,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                  trailing: _selectedTrail?.id == trail.id
                                      ? Icon(
                                          Icons.check_circle_rounded,
                                          color: colors.primary,
                                        )
                                      : Icon(
                                          Icons.chevron_right_rounded,
                                          color: colors.textSecondary,
                                        ),
                                  onTap: () => Navigator.of(ctx).pop(
                                    (pack: pack, trail: trail),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedMountain = picked.pack;
        _selectedTrail = picked.trail;
      });
      if (_selectedGroup == null && _planStore.activePlan == null) {
        unawaited(
          _planStore.setSoloPlan(
            SoloHikePlan(
              mountainId: picked.pack.id,
              mountainName: picked.pack.name,
              trailId: picked.trail.id,
              trailName: picked.trail.name,
            ),
          ),
        );
      }
      final ready = await _isMountainMapDownloaded(picked.pack);
      if (!ready && mounted) {
        await _showDownloadMapRequiredDialog(picked.pack);
      }
    }
  }

  void _showAutoDismissSnackBar(
    SnackBar snackBar, {
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;
    _snackBarTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(snackBar);
    _snackBarTimer = Timer(duration, () {
      if (!mounted) return;
      controller.close();
    });
  }

  Future<void> _sendGroupHikeInvite() async {
    final pack = _selectedMountain;
    final trail = _selectedTrail;
    final remoteGroup = _selectedGroup;
    if (pack == null || remoteGroup == null || _sendingInvite) return;
    if (_planStore.activePlan?.groupId == remoteGroup.group.id) {
      _showAutoDismissSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            'Ajakan pendakian untuk ${remoteGroup.group.name} sudah aktif.',
          ),
        ),
      );
      return;
    }

    setState(() => _sendingInvite = true);
    try {
      final selfId =
          _account.user?.id ?? _account.profile?.userId ?? 'self-local';
      final selfName = _account.profile?.fullName?.trim().isNotEmpty == true
          ? _account.profile!.fullName!.trim()
          : (_account.profile?.username ?? 'Ketua Rombongan');

      int memberCount = 2;
      try {
        final members = await _account.membersOf(remoteGroup.group.id);
        if (members.isNotEmpty) {
          memberCount = members.length;
        }
      } catch (_) {
        final keyStatus = _account.keyStatusFor(remoteGroup.group.id);
        if (keyStatus != null && keyStatus.memberCount > 0) {
          memberCount = keyStatus.memberCount;
        }
      }

      final now = DateTime.now().toUtc();
      final inviteId = generateUuidV4();
      final inviteMsgClientId = generateUuidV4();
      final plan = GroupHikePlan(
        inviteId: inviteId,
        groupId: remoteGroup.group.id,
        groupName: remoteGroup.group.name,
        mountainId: pack.id,
        mountainName: pack.name,
        trailId: trail?.id,
        trailName: trail?.name,
        organizerUserId: selfId,
        organizerName: selfName,
        readyUserIds: <String>{selfId},
        memberCount: memberCount,
        inviteMessageClientId: inviteMsgClientId,
      );

      // 1 baris unik per group_id di `group_hike_prep` -> memicu notifikasi
      // in-app & FCM ke seluruh anggota grup lain (anti duplikasi tombol Siap).
      await _planStore.upsertRemotePlan(plan);

      final msg = GroupMessageRecord(
        clientMsgId: inviteMsgClientId,
        groupId: remoteGroup.group.id,
        senderId: selfId,
        senderName: selfName,
        messageType: GroupMessageType.text,
        content: GroupHikeInviteMessage.encodeInvite(plan),
        originTransport: ChatTransportOrigin.online,
        syncStatus: ChatSyncStatus.pending,
        clientCreatedAtUtc: now,
      );

      AppDatabase? db;
      try {
        db = openAppDatabase(await defaultAppDatabaseFile());
        final store = OffGridChatLocalStore(database: db);
        await store.insertMessageIfAbsent(msg);
      } catch (_) {
        // Abaikan pada environment uji tanpa SQLite disk.
      } finally {
        await db?.close();
      }

      try {
        final chatRemote = SupabaseServices.createGroupChatRemoteService();
        if (chatRemote != null) {
          await chatRemote.upsertMessage(msg);
        }
      } catch (_) {
        // Tetap aman: pesan tersimpan lokal untuk disinkronkan.
      }

      if (!mounted) return;
      _showAutoDismissSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            'Ajakan mendaki ${pack.name} terkirim ke grup ${remoteGroup.group.name}.',
          ),
          action: SnackBarAction(
            label: 'Buka chat',
            onPressed: () => context.go('/grup'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingInvite = false);
    }
  }

  Future<void> _cancelActivePlan() async {
    await _planStore.cancelActivePlanRemote();
    if (!mounted) return;
    setState(() {
      _selectedGroup = null;
    });
  }

  Future<void> _onStartHike() async {
    final plan = _planStore.activePlan;
    if (plan != null && !plan.allMembersReady) {
      return;
    }

    final pack = _selectedMountain;
    if (pack != null) {
      final downloaded = await _isMountainMapDownloaded(pack);
      if (!mounted) return;
      if (!downloaded) {
        await _showDownloadMapRequiredDialog(pack);
        return;
      }
    }

    final resolvedPack = pack != null ? _resolveLatestPack(pack) : null;
    final trail = _selectedTrail ??
        (resolvedPack != null && resolvedPack.package.trails.isNotEmpty
            ? resolvedPack.package.trails.first
            : null);

    if (plan == null && resolvedPack != null && _selectedGroup == null) {
      await _planStore.setSoloPlan(
        SoloHikePlan(
          mountainId: resolvedPack.id,
          mountainName: resolvedPack.name,
          trailId: trail?.id,
          trailName: trail?.name,
          isStarted: true,
        ),
      );
      if (!mounted) return;
    }

    if (widget.onStartHike != null) {
      setState(() => _starting = true);
      var started = false;
      try {
        started = await widget.onStartHike!();
      } catch (_) {
        started = false;
      }
      if (!mounted) return;
      setState(() => _starting = false);
      if (started) {
        context.go('/peta');
        return;
      }
      final msg = widget.startFailureMessage?.call() ??
          'Rekaman belum bisa dimulai. Periksa izin di layar Peta.';
      _showAutoDismissSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(msg),
          action: SnackBarAction(
            label: 'Buka Peta',
            onPressed: () => context.go('/peta'),
          ),
        ),
      );
      return;
    }

    if (resolvedPack != null) {
      context.go(
        '/peta/jalur',
        extra: <String, dynamic>{
          'package': resolvedPack.package,
          'trail': trail,
          'allowStartAscent': true,
          'startButtonLabel': 'Mulai pendakian',
          if (plan != null) 'activeGroupId': plan.groupId,
          if (plan != null) 'activeGroupName': plan.groupName,
        },
      );
    } else {
      context.go('/peta');
    }
  }

  List<String> get _packingCategories {
    final cats = <String>{'Semua'};
    for (final item in _packing.catalog) {
      cats.add(item.category);
    }
    return cats.toList(growable: false);
  }

  List<PackingItem> get _filteredCatalog {
    if (_packingCategory == 'Semua') return _packing.catalog;
    return _packing.catalog
        .where((item) => item.category == _packingCategory)
        .toList(growable: false);
  }

  PlusRouteContext _buildSelectedRouteContext() {
    final mountain = _selectedMountain!;
    final trail = _selectedTrail;
    final summitM = (trail?.maxElevationM ?? mountain.elevationM).toDouble();
    final gainM =
        trail?.elevationGainM ?? (summitM * 0.45).clamp(400.0, 2200.0);
    final basecampM = (summitM - gainM).clamp(300.0, 3500.0).toDouble();
    final center = mountain.package.offline.bounds.center;
    final pts = trail?.points ?? const <LatLng>[];
    final label =
        trail != null ? '${mountain.name} · ${trail.name}' : mountain.name;
    return PlusRouteContext(
      name: label,
      points: pts,
      trailId: trail?.id,
      mountainId: mountain.id,
      trailName: trail?.name,
      gpxAssetPath: trail?.gpxAssetPath ?? mountain.gpxAssetPath,
      distanceM: trail?.distanceM,
      elevationGainM: gainM,
      basecampElevationM: basecampM,
      summitElevationM: summitM,
      basecampCoord: pts.isNotEmpty ? pts.first : center,
      summitCoord: pts.isNotEmpty ? pts.last : center,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final topSafe = MediaQuery.paddingOf(context).top;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final groups = _syncedGroups;
    final activePlan = _planStore.activePlan;
    final lockedByGroup = _isStartLockedByGroup;

    return PageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Konten penuh mengalir bebas di belakang header & tombol Liquid Glass
            ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                topSafe + 70,
                16,
                bottomSafe + (lockedByGroup ? 168 : 112),
              ),
              children: <Widget>[
                Text(
                  'PERSIAPAN PENDAKIAN',
                  style: HiqeoTypography.overline(colors.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Siap naik?',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 16),

                // =======================================================
                // BAGIAN 1: GUNUNG YANG DIPILIH
                // =======================================================
                _SectionCard(
                  stepNumber: '1',
                  title: 'Gunung yang dipilih',
                  subtitle: _isLockedByPlan
                      ? 'Terkunci dari ajakan pendakian grup aktif'
                      : 'Jika solo tanpa grup, langsung membuka peta gunung yang dipilih',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      InkWell(
                        key: const ValueKey('siap-naik-pick-mountain'),
                        borderRadius: BorderRadius.circular(16),
                        onTap: _isLockedByPlan ? null : _pickMountainSheet,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _selectedMountain != null
                                  ? colors.primary
                                  : colors.hairline,
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: HiqeoIcon(
                                    HiqeoIcons.mountain,
                                    size: 20,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      _selectedMountain?.name ??
                                          'Pilih gunung tujuan',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _selectedTrail != null
                                          ? '${_selectedTrail!.name} · ${_selectedMountain!.elevationM} mdpl'
                                          : 'Ketuk untuk memilih gunung & via jalur',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isLockedByPlan)
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 18,
                                  color: colors.textSecondary,
                                )
                              else
                                HiqeoIcon(
                                  HiqeoIcons.chevronRight,
                                  size: 18,
                                  color: colors.textSecondary,
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_selectedMountain != null) ...<Widget>[
                        const SizedBox(height: 10),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: HiqeoButton(
                                key: const ValueKey('siap-naik-cuaca'),
                                label: 'Cuaca rute',
                                variant: HiqeoButtonVariant.secondary,
                                leading: HiqeoIcon(
                                  HiqeoIcons.cloud,
                                  size: 17,
                                  color: colors.textPrimary,
                                ),
                                onPressed: () {
                                  final routeCtx = _buildSelectedRouteContext();
                                  openPlusWeather(
                                    context,
                                    routeCtx.name,
                                    route: routeCtx,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: HiqeoButton(
                                key: const ValueKey('siap-naik-estimasi'),
                                label: 'Estimasi',
                                variant: HiqeoButtonVariant.secondary,
                                leading: HiqeoIcon(
                                  HiqeoIcons.clock,
                                  size: 17,
                                  color: colors.textPrimary,
                                ),
                                onPressed: () => openPlusEstimate(
                                  context,
                                  _buildSelectedRouteContext(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // =======================================================
                // BAGIAN 2: GRUP YANG DIPILIH (OPSIONAL)
                // =======================================================
                _SectionCard(
                  stepNumber: '2',
                  title: 'Grup yang dipilih (Opsional)',
                  subtitle: _syncingRemote
                      ? 'Menyinkronkan daftar grup & rencana pendakian…'
                      : 'Ajak grup untuk mendaki bersama dan pantau kesiapan anggota',
                  child: activePlan != null
                      ? _ActiveGroupPlanBox(
                          plan: activePlan,
                          colors: colors,
                          onOpenChat: () => context.go('/grup'),
                          onCancelInvite: _cancelActivePlan,
                        )
                      : groups.isEmpty
                          ? Container(
                              key: const ValueKey('siap-naik-no-group'),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: colors.hairline),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Icon(
                                    Icons.groups_outlined,
                                    size: 20,
                                    color: colors.textSecondary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      kEmptyGroupInviteCopy,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    ChoiceChip(
                                      label: const Text('Solo (Tanpa grup)'),
                                      selected: _selectedGroup == null,
                                      onSelected: (_) {
                                        setState(() => _selectedGroup = null);
                                        if (_selectedMountain != null) {
                                          unawaited(
                                            _planStore.setSoloPlan(
                                              SoloHikePlan(
                                                mountainId:
                                                    _selectedMountain!.id,
                                                mountainName:
                                                    _selectedMountain!.name,
                                                trailId: _selectedTrail?.id,
                                                trailName: _selectedTrail?.name,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                    for (final g in groups)
                                      ChoiceChip(
                                        key: ValueKey(
                                          'siap-naik-group-${g.group.id}',
                                        ),
                                        label: Text(g.group.name),
                                        selected: _selectedGroup?.group.id ==
                                            g.group.id,
                                        onSelected: (_) => setState(
                                          () => _selectedGroup = g,
                                        ),
                                      ),
                                  ],
                                ),
                                if (_selectedGroup != null) ...<Widget>[
                                  const SizedBox(height: 12),
                                  HiqeoButton(
                                    key: const ValueKey(
                                      'siap-naik-kirim-ajakan',
                                    ),
                                    label: _sendingInvite
                                        ? 'Mengirim ajakan…'
                                        : 'Pilih grup & kirim ajakan',
                                    variant: HiqeoButtonVariant.secondary,
                                    onPressed: (_selectedMountain == null ||
                                            _sendingInvite)
                                        ? null
                                        : _sendGroupHikeInvite,
                                  ),
                                  if (_selectedMountain == null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        'Pilih gunung terlebih dahulu untuk mengirim ajakan ke grup.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                ),

                const SizedBox(height: 14),

                // =======================================================
                // BAGIAN 3: PACKING LIST (2 TAHAP)
                // =======================================================
                _SectionCard(
                  stepNumber: '3',
                  title: 'Daftar perlengkapan',
                  subtitle: _packing.stage1Done
                      ? 'Tahap 2: Ceklis ulang barang yang sudah masuk tas'
                      : 'Tahap 1: Pilih barang yang akan dibawa (termasuk gunung tinggi / bersalju)',
                  trailing: _packing.stage1Done
                      ? TextButton(
                          key: const ValueKey('packing-edit-stage1'),
                          onPressed: _packing.editStage1,
                          child: const Text('Ubah daftar'),
                        )
                      : (_packing.selectedIds.isNotEmpty
                          ? TextButton(
                              onPressed: _packing.clearAll,
                              child: Text(
                                'Reset',
                                style: TextStyle(color: colors.textSecondary),
                              ),
                            )
                          : null),
                  child: _packing.stage1Done
                      ? _buildPackingStage2(colors)
                      : _buildPackingStage1(colors),
                ),
              ],
            ),

            // Header Liquid Glass mengambang (tanpa wadah solid)
            Positioned(
              top: topSafe + 8,
              left: 16,
              right: 16,
              child: Row(
                children: <Widget>[
                  const HiqeoBackButton(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: HiqeoLiquidGlassSurface(
                        key: const ValueKey<String>('siap-naik-glass-header'),
                        borderRadius: HiqeoRadius.pill,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Siapkan pendakian',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: HiqeoTypography.bold,
                              color: colors.textPrimary,
                              shadows: isDark
                                  ? null
                                  : const <Shadow>[
                                      Shadow(
                                        color: Color(0x66FFFFFF),
                                        blurRadius: 3,
                                        offset: Offset(0, 0.5),
                                      ),
                                    ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tombol "Mulai pendakian" Liquid Glass mengambang (tanpa latar solid)
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomSafe + 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (lockedByGroup && activePlan != null) ...<Widget>[
                    HiqeoLiquidGlassSurface(
                      key: const ValueKey<String>('siap-naik-lock-banner'),
                      borderRadius: 18,
                      fillColor: colors.warning.withValues(
                        alpha: isDark ? 0.18 : 0.14,
                      ),
                      borderColor: colors.warning.withValues(alpha: 0.38),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.lock_clock_outlined,
                            size: 16,
                            color: colors.warningText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              activePlan.waitingLockMessage,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.warningText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  HiqeoLiquidGlassSurface(
                    key: const ValueKey<String>('siap-naik-mulai-glass'),
                    borderRadius: HiqeoRadius.pill,
                    fillColor: lockedByGroup
                        ? (isDark
                            ? colors.surface.withValues(alpha: 0.88)
                            : colors.secondary.withValues(alpha: 0.90))
                        : colors.primary.withValues(alpha: 0.88),
                    borderColor: lockedByGroup
                        ? colors.hairline
                        : Colors.white.withValues(alpha: isDark ? 0.22 : 0.45),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: const ValueKey('siap-naik-mulai'),
                        customBorder: const StadiumBorder(),
                        onTap: (_starting || lockedByGroup)
                            ? null
                            : () => unawaited(_onStartHike()),
                        child: SizedBox(
                          height: 54,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              if (lockedByGroup) ...<Widget>[
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 18,
                                  color: colors.textPrimary.withValues(
                                    alpha: isDark ? 0.88 : 0.86,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                _starting ? 'Memulai…' : 'Mulai pendakian',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: HiqeoTypography.bold,
                                  color: lockedByGroup
                                      ? colors.textPrimary.withValues(
                                          alpha: isDark ? 0.88 : 0.86,
                                        )
                                      : colors.onPrimary,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackingStage1(HiqeoColors colors) {
    final categories = _packingCategories;
    final items = _filteredCatalog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const ValueKey('packing-custom-input'),
                controller: _customItemCtrl,
                maxLength: 80,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addCustomItem(),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: 'Tambah barang sendiri…',
                  filled: true,
                  fillColor: colors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.hairline),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: FilledButton(
                key: const ValueKey('packing-custom-add'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: () {
                  unawaited(HapticFeedback.selectionClick());
                  _addCustomItem();
                },
                child: const Icon(Icons.add_rounded, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, idx) {
              final cat = categories[idx];
              final selected = cat == _packingCategory;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  unawaited(HapticFeedback.selectionClick());
                  setState(() => _packingCategory = cat);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  child: Center(
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? colors.primary : colors.surface,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: selected ? colors.primary : colors.hairline,
                        ),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              selected ? colors.onPrimary : colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 270),
          child: Material(
            color: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colors.hairline.withValues(alpha: 0.6),
                ),
                itemBuilder: (_, idx) {
                  final item = items[idx];
                  final checked = _packing.selectedIds.contains(item.id);
                  return CheckboxListTile(
                    key: ValueKey('packing-s1-${item.id}'),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: checked,
                    onChanged: (_) =>
                        unawaited(_packing.toggleSelectItem(item.id)),
                    title: Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: colors.textPrimary,
                        fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    subtitle: Text(
                      item.category,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${_packing.selectedIds.length} barang dipilih',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ),
            FilledButton(
              key: const ValueKey('packing-stage1-done'),
              onPressed: _packing.selectedIds.isEmpty
                  ? null
                  : () => unawaited(_packing.finishStage1()),
              child: const Text('Selesai'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPackingStage2(HiqeoColors colors) {
    final selected = _packing.selectedItems;
    final packedCount = _packing.packedIds.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '$packedCount / ${selected.length} barang sudah diceklis masuk tas',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _packing.allPacked
                      ? colors.successText
                      : colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: selected.isEmpty ? 0 : packedCount / selected.length,
            minHeight: 7,
            backgroundColor: colors.hairline,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              for (var i = 0; i < selected.length; i++) ...<Widget>[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: colors.hairline.withValues(alpha: 0.6),
                  ),
                CheckboxListTile(
                  key: ValueKey('packing-s2-${selected[i].id}'),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _packing.packedIds.contains(selected[i].id),
                  onChanged: (_) =>
                      unawaited(_packing.togglePackedItem(selected[i].id)),
                  title: Text(
                    selected[i].name,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: colors.textPrimary,
                      decoration: _packing.packedIds.contains(selected[i].id)
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pengingat otomatis akan memeriksa daftar ini saat kamu menekan Mulai tracking di halaman Peta.',
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
      ],
    );
  }

  Future<void> _addCustomItem() async {
    final text = _customItemCtrl.text.trim();
    if (text.isEmpty) return;
    _customItemCtrl.clear();
    await _packing.addCustomItem(text);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String stepNumber;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  stepNumber,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: colors.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ActiveGroupPlanBox extends StatelessWidget {
  const _ActiveGroupPlanBox({
    required this.plan,
    required this.colors,
    required this.onOpenChat,
    required this.onCancelInvite,
  });

  final GroupHikePlan plan;
  final HiqeoColors colors;
  final VoidCallback onOpenChat;
  final VoidCallback onCancelInvite;

  @override
  Widget build(BuildContext context) {
    final ready = plan.allMembersReady;
    final accent = ready ? colors.successText : colors.primary;
    final statusBadgeText = ready
        ? 'Semua siap'
        : 'Siap naik ${plan.readyCount}/${plan.memberCount}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                ready ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${plan.groupName} · ${plan.mountainName}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Container(
                key: const ValueKey<String>('siap-naik-readiness-pill'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusBadgeText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ready
                ? 'Semua anggota grup sudah siap (${plan.readyCount}/${plan.memberCount}). Kamu bisa langsung memulai pendakian.'
                : 'Menunggu seluruh anggota grup menekan tombol Siap di chat grup (${plan.readyCount}/${plan.memberCount} siap).',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.38,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onOpenChat,
                icon: const Icon(Icons.forum_outlined, size: 16),
                label: const Text('Buka chat grup'),
              ),
              TextButton.icon(
                key: const ValueKey<String>('siap-naik-cancel-group-invite'),
                onPressed: onCancelInvite,
                style: TextButton.styleFrom(
                  foregroundColor: colors.warningText,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text(
                  'Batalkan ajakan grup',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
