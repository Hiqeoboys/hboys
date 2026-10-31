import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/background/page_background.dart';
import '../../../design/glass/glass_surface.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_safety_repository.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../auth/application/account_controller.dart';
import '../../groups/application/group_key_manager.dart';
import '../../groups/application/group_selection.dart';
import '../../groups/domain/group_remote_service.dart';
import '../../map/application/offline_readiness.dart';
import '../../onboarding/permission_service.dart';
import '../../safety/domain/emergency_contact.dart';
import '../../tracking/application/tracking_controller.dart';

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

class SiapNaikPage extends StatefulWidget {
  const SiapNaikPage({
    super.key,
    this.accountController,
    this.contactLoader,
    this.offlineMapCheck,
    this.permissionCheck,
    this.onStartHike,
    this.startFailureMessage,
    this.hikeActive,
  });

  /// Disuntikkan untuk uji; produksi memakai layanan yang tersedia.
  final AccountController? accountController;
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
  late final ContactLoader _contactLoader;
  late final OfflineMapCheck _offlineMapCheck;
  late final PermissionCheck _permissionCheck;

  String? _groupId;
  List<MemberDirectoryEntry> _members = const [];
  bool _membersLoading = false;
  String? _membersError;
  int _rosterGeneration = 0;

  bool? _permissionReady;
  bool _mapReady = false;
  int _mapGeneration = 0;

  String? _contactUserId;
  List<EmergencyContact> _contacts = const [];
  bool _contactsLoading = false;
  bool _contactsFailed = false;
  int _contactGeneration = 0;

  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _ownsAccount = widget.accountController == null;
    _account =
        widget.accountController ?? SupabaseServices.createAccountController();
    _contactLoader = widget.contactLoader ?? _contactsFromDevice;
    _offlineMapCheck = widget.offlineMapCheck ?? defaultOfflineMapReady;
    _permissionCheck =
        widget.permissionCheck ?? () => const PermissionService().check();
    _account.initialize();
    _account.addListener(_onAccountChanged);
    _syncAccount();
    unawaited(_loadPermission());
  }

  @override
  void dispose() {
    _account.removeListener(_onAccountChanged);
    if (_ownsAccount) _account.dispose();
    super.dispose();
  }

  void _onAccountChanged() {
    _syncAccount();
    if (mounted) setState(() {});
  }

  void _syncAccount() {
    final next = nextHikeOf(_account.groups);
    final groupId = next?.group.id;
    if (groupId != _groupId) {
      _groupId = groupId;
      _members = const [];
      _membersError = null;
      _membersLoading = false;
      _rosterGeneration++;
      _mapReady = false;
      _mapGeneration++;
      if (next != null) {
        unawaited(_loadMembers(next.group.id));
        unawaited(_loadMapReady(next.group.mountain, _mapGeneration));
      }
    }
    _syncContacts();
  }

  Future<void> _loadMembers(String groupId) async {
    final generation = ++_rosterGeneration;
    setState(() {
      _membersLoading = true;
      _membersError = null;
    });
    try {
      final members = await _account.membersOf(groupId);
      if (!mounted || generation != _rosterGeneration || _groupId != groupId) {
        return;
      }
      setState(() {
        _members = members;
        _membersLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _rosterGeneration || _groupId != groupId) {
        return;
      }
      setState(() {
        _membersLoading = false;
        _membersError = 'Daftar anggota belum dapat dimuat.';
      });
    }
  }

  Future<void> _loadMapReady(String? mountain, int generation) async {
    var ready = false;
    try {
      ready = await _offlineMapCheck(mountain);
    } catch (_) {
      ready = false;
    }
    if (!mounted || generation != _mapGeneration) return;
    setState(() => _mapReady = ready);
  }

  Future<void> _loadPermission() async {
    var ready = false;
    try {
      final report = await _permissionCheck();
      ready = report.readyForBackground;
    } catch (_) {
      ready = false;
    }
    if (!mounted) return;
    setState(() => _permissionReady = ready);
  }

  void _syncContacts() {
    final userId = _account.user?.id ?? _account.profile?.userId;
    if (userId == _contactUserId) return;
    _contactUserId = userId;
    _contacts = const [];
    _contactsFailed = false;
    _contactsLoading = false;
    _contactGeneration++;
    if (userId != null) unawaited(_loadContacts(userId));
  }

  Future<void> _loadContacts(String userId) async {
    final generation = ++_contactGeneration;
    setState(() => _contactsLoading = true);
    try {
      final contacts = await _contactLoader(userId);
      if (!mounted ||
          generation != _contactGeneration ||
          _contactUserId != userId) {
        return;
      }
      setState(() {
        _contacts = contacts;
        _contactsLoading = false;
      });
    } catch (_) {
      if (!mounted ||
          generation != _contactGeneration ||
          _contactUserId != userId) {
        return;
      }
      setState(() {
        _contactsLoading = false;
        _contactsFailed = true;
      });
    }
  }

  static Future<List<EmergencyContact>> _contactsFromDevice(
    String userId,
  ) async {
    final file = await defaultAppDatabaseFile();
    final database = openAppDatabase(file);
    try {
      return await DriftSafetyRepository(database).contactsOf(userId);
    } finally {
      await database.close();
    }
  }

  Future<void> _startHike() async {
    final active = widget.hikeActive?.call() ?? TrackingController.instance.isRecording;
    if (active) {
      context.go('/lacak');
      return;
    }
    setState(() => _starting = true);
    var started = false;
    try {
      started = await (widget.onStartHike ?? TrackingController.instance.start)();
    } catch (_) {
      started = false;
    }
    if (!mounted) return;
    setState(() => _starting = false);
    if (started) {
      context.go('/lacak');
      return;
    }
    final message = widget.startFailureMessage?.call() ??
        TrackingController.instance.notice ??
        'Rekaman belum bisa dimulai. Periksa izin di layar Lacak.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Buka Lacak',
          onPressed: () => context.go('/lacak'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final next = nextHikeOf(_account.groups);
    final keyStatus =
        next == null ? null : _account.keyStatusFor(next.group.id);
    final checks = readinessChecks(
      groupKeyReady:
          keyStatus?.availability == GroupKeyAvailability.ready,
      mapReady: _mapReady,
      permissionReady: _permissionReady ?? false,
    );
    final selfReady = checks.every((check) => check.ready);
    final totalMembers = _members.isNotEmpty
        ? _members.length
        : (keyStatus?.memberCount ?? 0);
    final readyMembers = selfReady && totalMembers > 0 ? 1 : 0;
    final selfId = _account.user?.id ?? _account.profile?.userId;

    final children = <Widget>[
      _Header(group: next),
      if (next == null) ...<Widget>[
        const SizedBox(height: HiqeoSpacing.xl),
        _EmptyRombongan(account: _account),
      ] else ...<Widget>[
        const SizedBox(height: HiqeoSpacing.lg),
        _ReadinessHero(
          readyMembers: readyMembers,
          totalMembers: totalMembers,
          percent: readinessPercent(
            readyMembers: readyMembers,
            totalMembers: totalMembers,
          ),
        ),
        const SizedBox(height: HiqeoSpacing.lg),
        ..._rosterWidgets(
          checks: checks,
          selfId: selfId,
          totalMembers: totalMembers,
        ),
        const SizedBox(height: HiqeoSpacing.md),
        _ContactCard(
          contact: primaryContact(_contacts),
          total: _contacts.length,
          loading: _contactsLoading,
          failed: _contactsFailed,
        ),
      ],
    ];

    return PageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  HiqeoSpacing.lg,
                  HiqeoSpacing.xl,
                  HiqeoSpacing.lg,
                  0,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(children),
                ),
              ),
              if (next != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      HiqeoSpacing.lg,
                      HiqeoSpacing.lg,
                      HiqeoSpacing.lg,
                      HiqeoSpacing.lg,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          totalMembers <= 0
                              ? 'Kesiapan belum bisa dihitung karena daftar '
                                  'anggota belum termuat.'
                              : 'Anggota lain belum melapor; kesiapan dari '
                                  'perangkat ini.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: HiqeoColors.of(context).textSecondary,
                              ),
                        ),
                        const SizedBox(height: HiqeoSpacing.sm),
                        HiqeoButton(
                          label: _starting ? 'Memulai…' : 'Mulai pendakian',
                          onPressed: _starting ? null : _startHike,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _rosterWidgets({
    required List<ReadinessCheck> checks,
    required String? selfId,
    required int totalMembers,
  }) {
    if (_members.isNotEmpty) {
      return <Widget>[
        for (final member in _members)
          Padding(
            padding: const EdgeInsets.only(bottom: HiqeoSpacing.md),
            child: _MemberCard(
              name: member.username,
              isSelf: member.userId == selfId,
              checks: member.userId == selfId ? checks : const [],
            ),
          ),
      ];
    }
    if (_membersLoading) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.only(bottom: HiqeoSpacing.md),
          child: _RosterNotice(text: 'Memuat anggota…', loading: true),
        ),
      ];
    }
    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: HiqeoSpacing.md),
        child: _RosterNotice(
          text: _membersError ?? 'Daftar anggota belum dimuat.',
          detail: totalMembers > 0
              ? '$totalMembers anggota tercatat menurut kunci grup.'
              : null,
          onRetry: _groupId == null ? null : () => _loadMembers(_groupId!),
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.group});

  final RemoteGroup? group;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final mountain = group?.group.mountain?.trim();
    final subtitle = group == null
        ? 'Belum ada rombongan'
        : (mountain == null || mountain.isEmpty
            ? '${group!.group.name} · nama gunung belum diisi'
            : '$mountain · ${group!.group.name}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'PERSIAPAN · UNDUH SEBELUM BERANGKAT',
          style: HiqeoTypography.overline(colors.textSecondary),
        ),
        const SizedBox(height: HiqeoSpacing.sm),
        Text('Siap naik?', style: theme.textTheme.displaySmall),
        const SizedBox(height: HiqeoSpacing.xs),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ReadinessHero extends StatelessWidget {
  const _ReadinessHero({
    required this.readyMembers,
    required this.totalMembers,
    required this.percent,
  });

  final int readyMembers;
  final int totalMembers;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final fraction = totalMembers <= 0 ? 0.0 : (percent / 100).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HiqeoSpacing.lg,
        vertical: 18,
      ),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(HiqeoRadius.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  readinessHeadline(
                    readyMembers: readyMembers,
                    totalMembers: totalMembers,
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: HiqeoSpacing.md),
              Text(
                totalMembers <= 0 ? '—' : '$percent%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.onPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(HiqeoRadius.pill),
            child: SizedBox(
              height: 8,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(
                    color: colors.onPrimary.withValues(alpha: 0.2),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: fraction,
                      heightFactor: 1,
                      child: ColoredBox(color: colors.onPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.name,
    required this.isSelf,
    required this.checks,
  });

  final String name;
  final bool isSelf;
  final List<ReadinessCheck> checks;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return GlassSurface(
      borderRadius: HiqeoRadius.card,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text.rich(
            TextSpan(
              text: name,
              style: theme.textTheme.titleLarge,
              children: <InlineSpan>[
                if (isSelf)
                  TextSpan(
                    text: ' (kamu)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: HiqeoSpacing.sm,
            runSpacing: HiqeoSpacing.sm,
            children: <Widget>[
              if (isSelf)
                for (final check in checks)
                  _ReadinessChip(label: check.label, ready: check.ready)
              else
                _ReadinessChip(
                  label: 'Belum melapor',
                  ready: false,
                  semanticLabel: 'Kesiapan $name belum dilaporkan',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadinessChip extends StatelessWidget {
  const _ReadinessChip({
    required this.label,
    required this.ready,
    this.semanticLabel,
  });

  final String label;
  final bool ready;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (ready) ...<Widget>[
          HiqeoIcon(
            HiqeoIcons.check,
            size: 14,
            strokeWidth: 2,
            color: colors.textPrimary,
          ),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: HiqeoTypography.medium,
            color: ready ? colors.textPrimary : colors.textSecondary,
          ),
        ),
      ],
    );
    return Semantics(
      label: semanticLabel ?? '$label: ${ready ? 'siap' : 'belum siap'}',
      container: true,
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: ready
              ? null
              : _DashedPillPainter(
                  color: colors.textSecondary.withValues(alpha: 0.55),
                ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: ready
                ? BoxDecoration(
                    color: colors.secondary,
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  )
                : null,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _DashedPillPainter extends CustomPainter {
  const _DashedPillPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 4, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 3;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPillPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.total,
    required this.loading,
    required this.failed,
  });

  final EmergencyContact? contact;
  final int total;
  final bool loading;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final ready = contact?.consentStatus == EmergencyContactConsentStatus.granted;
    final subtitle = loading
        ? 'Memuat kontak…'
        : (failed ? 'Kontak darurat belum dapat dibaca' : contactSubtitle(contact, total));
    return GlassSurface(
      borderRadius: HiqeoRadius.card,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Kontak darurat', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: HiqeoSpacing.md),
          if (loading)
            const _ReadinessChip(
              label: 'Memuat',
              ready: false,
              semanticLabel: 'Kontak darurat masih dimuat',
            )
          else if (contact == null)
            const _ReadinessChip(
              label: 'Belum diatur',
              ready: false,
              semanticLabel: 'Kontak darurat belum diatur',
            )
          else
            _ReadinessChip(
              label: ready ? 'Aktif' : 'Belum aktif',
              ready: ready,
              semanticLabel:
                  ready ? 'Kontak darurat aktif' : 'Kontak darurat belum aktif',
            ),
        ],
      ),
    );
  }
}

class _RosterNotice extends StatelessWidget {
  const _RosterNotice({
    required this.text,
    this.detail,
    this.loading = false,
    this.onRetry,
  });

  final String text;
  final String? detail;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return GlassSurface(
      borderRadius: HiqeoRadius.card,
      padding: const EdgeInsets.all(HiqeoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (loading) ...<Widget>[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: HiqeoSpacing.sm),
              ],
              Expanded(
                child: Text(text, style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          if (detail != null) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.xs),
            Text(
              detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onRetry,
                child: const Text('Muat ulang'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyRombongan extends StatelessWidget {
  const _EmptyRombongan({required this.account});

  final AccountController account;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final signedIn = account.user != null;
    final configured = account.isConfigured;
    final String title;
    final String body;
    final String action;
    final String route;
    if (account.isLoading) {
      title = 'Memuat rombongan…';
      body = 'Menunggu data akun dan grup dari perangkat.';
      action = '';
      route = '';
    } else if (!configured) {
      title = 'Aplikasi berjalan offline';
      body = 'Akun dan grup belum tersambung. Pelacakan, peta, dan SOS tetap '
          'bisa dipakai tanpa internet.';
      action = 'Buka Profil';
      route = '/profil';
    } else if (!signedIn) {
      title = 'Belum masuk';
      body = 'Masuk lewat Profil untuk memuat rombongan dari server.';
      action = 'Buka Profil';
      route = '/profil';
    } else {
      title = 'Belum ada rombongan';
      body = 'Buat grup dulu di tab Grup, lalu kembali untuk memeriksa '
          'kesiapan.';
      action = 'Buka Grup';
      route = '/grup';
    }
    return GlassSurface(
      borderRadius: HiqeoRadius.card,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (account.isLoading) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.lg),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ] else ...<Widget>[
            const SizedBox(height: HiqeoSpacing.xl),
            HiqeoButton(
              label: action,
              onPressed: () => context.go(route),
            ),
          ],
        ],
      ),
    );
  }
}
