import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/glass/glass_surface.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/altracq_button.dart';
import '../../design/widgets/line_icons.dart';
import '../../infrastructure/power/power_profile_controller.dart';
import '../../infrastructure/power/power_profile_manager.dart';
import '../../infrastructure/supabase/supabase_services.dart';
import '../auth/application/account_controller.dart';
import '../groups/application/group_key_manager.dart';
import '../groups/domain/group_remote_service.dart';

/// Sapaan menurut jam lokal perangkat (bukan waktu domain).
String greetingForHour(int hour) {
  if (hour < 11) return 'Selamat pagi';
  if (hour < 15) return 'Selamat siang';
  if (hour < 18) return 'Selamat sore';
  return 'Selamat malam';
}

/// Grup terbaru dipakai sebagai "pendakian berikutnya" karena aplikasi belum
/// punya model jadwal pendakian.
RemoteGroup? nextHikeOf(List<RemoteGroup> groups) {
  if (groups.isEmpty) return null;
  return groups.reduce(
    (a, b) => a.group.createdAtUtc.isAfter(b.group.createdAtUtc) ? a : b,
  );
}

/// Ringkasan yang hanya memuat keadaan yang benar-benar diketahui.
String nextHikeMeta(GroupKeyStatus? status) {
  final parts = <String>[];
  final memberCount = status?.memberCount ?? 0;
  if (memberCount > 0) parts.add('$memberCount anggota');
  if (status == null) {
    parts.add('kunci grup belum dimuat');
  } else if (status.availability == GroupKeyAvailability.ready) {
    parts.add('kunci v${status.keyVersion} siap');
  } else {
    parts.add('menunggu kunci v${status.keyVersion}');
  }
  final joined = parts.join(' · ');
  if (joined.isEmpty) return joined;
  return joined[0].toUpperCase() + joined.substring(1);
}

class BerandaPage extends StatefulWidget {
  const BerandaPage({
    super.key,
    this.accountController,
    this.powerController,
    this.now,
  });

  /// Disuntikkan untuk uji; produksi memakai layanan Supabase yang tersedia.
  final AccountController? accountController;
  final PowerProfileController? powerController;
  final DateTime Function()? now;

  @override
  State<BerandaPage> createState() => _BerandaPageState();
}

class _BerandaPageState extends State<BerandaPage> {
  late final AccountController _account;
  late final PowerProfileController _power;
  late final Listenable _state;
  late final bool _ownsAccount;
  late final bool _ownsPower;
  late final DateTime Function() _now;

  @override
  void initState() {
    super.initState();
    _ownsAccount = widget.accountController == null;
    _account = widget.accountController ?? SupabaseServices.createAccountController();
    _account.initialize();
    _ownsPower = widget.powerController == null;
    _power = widget.powerController ?? PowerProfileController();
    if (_ownsPower) unawaited(_power.refresh());
    _now = widget.now ?? DateTime.now;
    _state = Listenable.merge(<Listenable>[_account, _power]);
  }

  @override
  void dispose() {
    if (_ownsAccount) _account.dispose();
    if (_ownsPower) _power.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          final next = nextHikeOf(_account.groups);
          final keyStatus =
              next == null ? null : _account.keyStatusFor(next.group.id);
          final profile = _account.profile;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AltracqSpacing.lg,
              AltracqSpacing.xl,
              AltracqSpacing.lg,
              AltracqSpacing.xl,
            ),
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          greetingForHour(_now().hour),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(height: AltracqSpacing.xs),
                        Text(
                          'Halo, ${profile?.username ?? 'Pendaki'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.displaySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AltracqSpacing.md),
                  _BatteryPill(controller: _power),
                ],
              ),
              const SizedBox(height: AltracqSpacing.xl),
              _HeroCard(
                title: next?.group.mountain ?? next?.group.name ?? 'Belum ada pendakian',
                meta: next == null
                    ? 'Belum ada rombongan. Siapkan pendakian untuk mulai.'
                    : nextHikeMeta(keyStatus),
                onPrepare: () => context.push('/siap-naik'),
              ),
              const SizedBox(height: AltracqSpacing.xl),
              Text('Semua fitur', style: theme.textTheme.titleLarge),
              const SizedBox(height: AltracqSpacing.md),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _features.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AltracqSpacing.md,
                  mainAxisSpacing: AltracqSpacing.md,
                  mainAxisExtent: 140,
                ),
                itemBuilder: (context, index) {
                  final feature = _features[index];
                  return _FeatureCard(
                    feature: feature,
                    onTap: () {
                      if (feature.push) {
                        context.push(feature.route);
                      } else {
                        context.go(feature.route);
                      }
                    },
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Feature {
  const _Feature({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.push = false,
    this.emphasis = false,
  });

  final AltracqIconData icon;
  final String title;
  final String subtitle;
  final String route;
  final bool push;
  final bool emphasis;
}

final List<_Feature> _features = <_Feature>[
  _Feature(
    icon: AltracqIcons.activity,
    title: 'Pelacakan',
    subtitle: 'Jarak, pace, elevasi',
    route: '/lacak',
  ),
  _Feature(
    icon: AltracqIcons.map,
    title: 'Peta offline',
    subtitle: 'Topografi per gunung',
    route: '/peta',
  ),
  _Feature(
    icon: AltracqIcons.trail,
    title: 'Jalur terverifikasi',
    subtitle: 'Pos, air, area bahaya',
    route: '/peta',
  ),
  _Feature(
    icon: AltracqIcons.compass,
    title: 'Kompas',
    subtitle: 'Bearing dan jarak',
    route: '/peta',
  ),
  _Feature(
    icon: AltracqIcons.group,
    title: 'Grup chat',
    subtitle: 'Teks, suara, gambar',
    route: '/grup',
  ),
  _Feature(
    icon: AltracqIcons.pin,
    title: 'Lokasi terakhir',
    subtitle: 'Posisi tiap anggota',
    route: '/grup',
  ),
  _Feature(
    icon: AltracqIcons.image,
    title: 'Kartu pendakian',
    subtitle: 'Foto dan ringkasan',
    route: '/kartu',
    push: true,
  ),
  _Feature(
    icon: AltracqIcons.warning,
    title: 'SOS',
    subtitle: 'Tekan-tahan 3 detik',
    route: '/sos',
    push: true,
    emphasis: true,
  ),
];

class _BatteryPill extends StatelessWidget {
  const _BatteryPill({required this.controller});

  final PowerProfileController controller;

  @override
  Widget build(BuildContext context) {
    final level = controller.levelPercent;
    final label = level == null
        ? 'Baterai tidak terbaca'
        : 'Baterai $level% · ${_profileLabel(controller.profile)}';
    return GlassSurface(
      borderRadius: AltracqRadius.pill,
      padding: const EdgeInsets.symmetric(
        horizontal: AltracqSpacing.lg,
        vertical: AltracqSpacing.sm,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }

  static String _profileLabel(PowerProfile profile) => switch (profile) {
        PowerProfile.normal => 'Normal',
        PowerProfile.saver => 'Hemat',
        PowerProfile.critical => 'Kritis',
      };
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.meta,
    required this.onPrepare,
  });

  final String title;
  final String meta;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final muted = colors.onPrimary.withValues(alpha: 0.74);
    return Container(
      padding: const EdgeInsets.all(AltracqSpacing.xl),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(AltracqRadius.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'PENDAKIAN BERIKUTNYA',
            style: AltracqTypography.overline(muted),
          ),
          const SizedBox(height: AltracqSpacing.sm),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.displayMedium
                ?.copyWith(color: colors.onPrimary),
          ),
          const SizedBox(height: AltracqSpacing.xs),
          Text(
            meta,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: AltracqSpacing.xl),
          AltracqButton(
            label: 'Siapkan pendakian',
            variant: AltracqButtonVariant.inverse,
            onPressed: onPrepare,
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature, required this.onTap});

  final _Feature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final emphasis = feature.emphasis;
    final titleColor = emphasis ? colors.onPrimary : colors.textPrimary;
    final subtitleColor = emphasis
        ? colors.onPrimary.withValues(alpha: 0.74)
        : colors.textSecondary;
    final content = Padding(
      padding: const EdgeInsets.all(AltracqSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: emphasis
                  ? colors.onPrimary.withValues(alpha: 0.14)
                  : colors.secondary.withValues(alpha: 0.62),
            ),
            child: Center(
              child: AltracqIcon(
                feature.icon,
                size: 22,
                color: emphasis ? colors.onPrimary : colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            feature.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(color: titleColor),
          ),
          const SizedBox(height: AltracqSpacing.xs),
          Text(
            feature.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: subtitleColor),
          ),
        ],
      ),
    );

    final surface = emphasis
        ? Container(
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(AltracqRadius.card),
            ),
            child: content,
          )
        : GlassSurface(
            borderRadius: AltracqRadius.card,
            child: content,
          );

    return Semantics(
      button: true,
      label: '${feature.title}. ${feature.subtitle}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: surface,
        ),
      ),
    );
  }
}
