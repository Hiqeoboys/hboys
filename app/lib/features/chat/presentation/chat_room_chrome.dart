import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/app_theme.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../../../design/widgets/persistent_avatar_image.dart';
import '../../../infrastructure/cache/public_profile_cache_service.dart';

/// Palet warna terpadu untuk Ruang Obrolan Grup & Komunitas Hiqeo.
abstract final class ChatRoomPalette {
  /// Dasar gelap Hiqeo (#242B40) di belakang kontur topografi.
  static const Color canvas = Color(0xFF242B40);

  /// Gelembung keluar (pengirim = pengguna sendiri): alabaster hangat.
  static const Color outgoingFill = Color(0xFFF2EFE9);
  static const Color outgoingText = Color(0xFF1D2436);
  static const Color outgoingMeta = Color(0xB31D2436);
  static const Color outgoingCheck = Color(0xFF2563EB);
  static const Color outgoingMeshCheck = Color(0xFF0F766E);

  /// Gelembung masuk (anggota lain): dark slate semi-transparan + tepi 1 px.
  static const Color incomingFill = Color(0xD92E3752);
  static const Color incomingBorder = Color(0x1FFFFFFF);
  static const Color incomingText = Color(0xFFF8FAFC);
  static const Color incomingMeta = Color(0x94F8FAFC);

  /// Teks & indikator chrome ruang obrolan.
  static const Color textPrimary = Color(0xFFF6F3ED);
  static const Color textSecondary = Color(0xFFB3BCD2);
  static const Color statusOnline = Color(0xFF4ADE80);
  static const Color statusOffline = Color(0xFFF59E0B);
  static const Color statusOfflineText = Color(0xFFFCD34D);
  static const Color badgeE2eeText = Color(0xFFA7F3D0);
  static const Color badgeCommunityText = Color(0xFFBAE6FD);
  static const Color menuDivider = Color(0x1FFFFFFF);

  /// Merah lembut seragam untuk aksi keluar/hapus pada menu dropdown.
  static const Color destructiveRed = Color(0xFFF87171);

  /// Bayangan tipis teks di dalam pil header kaca agar tetap terbaca jelas
  /// saat media terang menggulir di belakang efek blur.
  static const List<Shadow> glassHeaderTextShadows = <Shadow>[
    Shadow(
      color: Color(0x73000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static const List<Color> _senderPastels = <Color>[
    Color(0xFF93C5FD), // sky
    Color(0xFF86EFAC), // mint
    Color(0xFFFDE68A), // sand
    Color(0xFFF9A8D4), // rose
    Color(0xFFC4B5FD), // lavender
    Color(0xFF67E8F9), // cyan
    Color(0xFFFDBA74), // peach
    Color(0xFFA7F3D0), // sage
  ];

  /// Warna pastel lembut yang konsisten per pengirim agar klaster mudah dipindai.
  static Color senderPastel(String senderId) {
    var hash = 2166136261;
    for (var i = 0; i < senderId.length; i++) {
      hash ^= senderId.codeUnitAt(i);
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return _senderPastels[hash % _senderPastels.length];
  }
}

/// Kanvas layar penuh ruang obrolan: tema gelap Hiqeo, dasar `#242B40`,
/// serta garis kontur topografi halus (~4% opasitas) di belakang `Stack` pesan.
class ChatRoomCanvas extends StatelessWidget {
  const ChatRoomCanvas({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: hiqeoDarkTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: ColoredBox(
          key: const ValueKey<String>('chat-room-canvas'),
          color: ChatRoomPalette.canvas,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: ValueKey<String>('chat-room-topo-bg'),
                      painter: _TopographicContourPainter(),
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _TopographicContourPainter extends CustomPainter {
  const _TopographicContourPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true
      ..color = Colors.white.withValues(alpha: 0.04);

    _drawSummitRings(
      canvas,
      paint,
      center: Offset(size.width * 0.88, size.height * 0.16),
      ringCount: 7,
      baseRx: size.width * 0.12,
      baseRy: size.width * 0.09,
      step: size.width * 0.085,
      wobblePhase: 0.4,
    );
    _drawSummitRings(
      canvas,
      paint,
      center: Offset(size.width * 0.08, size.height * 0.54),
      ringCount: 7,
      baseRx: size.width * 0.11,
      baseRy: size.width * 0.14,
      step: size.width * 0.09,
      wobblePhase: 2.1,
    );
    _drawSummitRings(
      canvas,
      paint,
      center: Offset(size.width * 0.82, size.height * 0.88),
      ringCount: 6,
      baseRx: size.width * 0.14,
      baseRy: size.width * 0.10,
      step: size.width * 0.09,
      wobblePhase: 4.0,
    );
  }

  void _drawSummitRings(
    Canvas canvas,
    Paint paint, {
    required Offset center,
    required int ringCount,
    required double baseRx,
    required double baseRy,
    required double step,
    required double wobblePhase,
  }) {
    const segments = 32;
    for (var ring = 0; ring < ringCount; ring++) {
      final rx = baseRx + ring * step;
      final ry = baseRy + ring * step * 0.92;
      final path = Path();
      final points = List<Offset>.generate(segments, (i) {
        final theta = (i / segments) * math.pi * 2;
        final wobble = 1.0 +
            0.09 * math.sin(theta * 3 + wobblePhase + ring * 0.35) +
            0.05 * math.cos(theta * 2 - wobblePhase);
        return Offset(
          center.dx + math.cos(theta) * rx * wobble,
          center.dy + math.sin(theta) * ry * wobble,
        );
      });

      final start = Offset(
        (points.last.dx + points.first.dx) / 2,
        (points.last.dy + points.first.dy) / 2,
      );
      path.moveTo(start.dx, start.dy);
      for (var i = 0; i < segments; i++) {
        final p = points[i];
        final next = points[(i + 1) % segments];
        final mid = Offset((p.dx + next.dx) / 2, (p.dy + next.dy) / 2);
        path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TopographicContourPainter oldDelegate) => false;
}

/// Bilah header melayang seragam (tinggi 56 px) untuk Ruang Obrolan Grup & Komunitas:
/// `[<]  [Pil Kaca: ikon/avatar + judul + titik status + jumlah anggota + lencana]  [≡]`
class ChatRoomHeaderBar extends StatelessWidget {
  const ChatRoomHeaderBar({
    super.key,
    this.backKey,
    this.onBack,
    required this.headerPillKey,
    this.headerTapKey,
    this.headerSemanticsLabel,
    this.onHeaderTap,
    this.avatarUrl,
    this.avatarCacheKey,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    this.isOnline = true,
    this.showPresenceDot = true,
    this.isMuted = false,
    required this.badgeLabel,
    required this.badgeIcon,
    required this.badgeColor,
    required this.menuButtonKey,
    required this.menuSemanticsLabel,
    required this.onMenuTap,
  });

  static const double topMargin = 8.0;
  static const double height = 56.0;
  static const double dropdownGap = 12.0;

  /// Jarak vertikal konsisten (tepat 12 px di bawah baris header) untuk menu dropdown.
  static double dropdownTop(double topPad) =>
      topPad + topMargin + height + dropdownGap;

  /// Padding atas `ListView` pesan agar konten mengalir bebas di belakang header kaca.
  static double listTopPadding(double topPad) =>
      topPad + topMargin + height + 16.0;

  final Key? backKey;
  final VoidCallback? onBack;
  final Key headerPillKey;
  final Key? headerTapKey;
  final String? headerSemanticsLabel;
  final VoidCallback? onHeaderTap;
  final String? avatarUrl;
  final String? avatarCacheKey;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;
  final bool isOnline;
  final bool showPresenceDot;
  final bool isMuted;
  final String badgeLabel;
  final IconData badgeIcon;
  final Color badgeColor;
  final Key menuButtonKey;
  final String menuSemanticsLabel;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    final pill = HiqeoLiquidGlassSurface(
      key: headerPillKey,
      borderRadius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: <Widget>[
          PersistentAvatarImage(
            cacheKey: avatarCacheKey ?? 'room_${title.hashCode}',
            avatarUrl: avatarUrl,
            size: 34,
            resolveFromProfileCache: false,
            backgroundColor: Colors.white.withValues(alpha: 0.14),
            fallback: Center(
              child: Icon(
                fallbackIcon,
                size: 17,
                color: ChatRoomPalette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: ChatRoomPalette.textPrimary,
                          height: 1.2,
                          shadows: ChatRoomPalette.glassHeaderTextShadows,
                        ),
                      ),
                    ),
                    if (isMuted) ...<Widget>[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.notifications_off_outlined,
                        key: ValueKey<String>('chat-header-muted-icon'),
                        size: 14,
                        color: ChatRoomPalette.textSecondary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    if (showPresenceDot) ...<Widget>[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline
                              ? ChatRoomPalette.statusOnline
                              : ChatRoomPalette.statusOffline,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: (!showPresenceDot || isOnline)
                              ? ChatRoomPalette.textSecondary
                              : ChatRoomPalette.statusOfflineText,
                          height: 1.2,
                          shadows: ChatRoomPalette.glassHeaderTextShadows,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                          width: 0.7,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(badgeIcon, size: 9.5, color: badgeColor),
                          const SizedBox(width: 3),
                          Text(
                            badgeLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: badgeColor,
                              letterSpacing: 0.2,
                              height: 1.1,
                              shadows: ChatRoomPalette.glassHeaderTextShadows,
                            ),
                          ),
                        ],
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

    final Widget centerWidget = onHeaderTap == null
        ? pill
        : Semantics(
            button: true,
            label: headerSemanticsLabel ?? title,
            child: GestureDetector(
              key: headerTapKey,
              behavior: HitTestBehavior.opaque,
              onTap: onHeaderTap,
              child: pill,
            ),
          );

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          HiqeoBackButton(
            key: backKey,
            onTap: onBack,
          ),
          const SizedBox(width: 10),
          Expanded(child: centerWidget),
          const SizedBox(width: 10),
          HiqeoGlassCircleButton(
            key: menuButtonKey,
            semanticsLabel: menuSemanticsLabel,
            onTap: onMenuTap,
            child: const Icon(
              Icons.menu_rounded,
              size: 20,
              color: ChatRoomPalette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu entri pada kartu menu dropdown melayang kanan-atas (item atau garis pemisah).
class ChatRoomMenuEntry {
  const ChatRoomMenuEntry.item({
    this.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailingIcon,
    this.enabled = true,
    this.onDisabledTap,
    this.destructive = false,
  }) : isDivider = false;

  const ChatRoomMenuEntry.divider()
      : key = null,
        icon = null,
        label = '',
        subtitle = null,
        trailingIcon = null,
        enabled = true,
        onTap = null,
        onDisabledTap = null,
        destructive = false,
        isDivider = true;

  final Key? key;
  final IconData? icon;
  final String label;
  final String? subtitle;
  final IconData? trailingIcon;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onDisabledTap;
  final bool destructive;
  final bool isDivider;
}

/// Kartu menu dropdown Liquid Glass melayang di kanan atas, 100% seragam
/// antara Ruang Obrolan Grup dan Komunitas.
class ChatRoomDropdownMenu extends StatelessWidget {
  const ChatRoomDropdownMenu({
    super.key,
    required this.menuKey,
    required this.entries,
  });

  static const double width = 236.0;
  static const double borderRadius = 20.0;

  final Key menuKey;
  final List<ChatRoomMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: HiqeoLiquidGlassSurface(
        key: menuKey,
        borderRadius: borderRadius,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final entry in entries)
              if (entry.isDivider)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: SizedBox(
                    height: 1,
                    child: ColoredBox(color: ChatRoomPalette.menuDivider),
                  ),
                )
              else
                _ChatRoomDropdownRow(entry: entry),
          ],
        ),
      ),
    );
  }
}

class _ChatRoomDropdownRow extends StatelessWidget {
  const _ChatRoomDropdownRow({required this.entry});

  final ChatRoomMenuEntry entry;

  @override
  Widget build(BuildContext context) {
    final baseFg = entry.destructive
        ? ChatRoomPalette.destructiveRed
        : ChatRoomPalette.textPrimary;
    final fg = entry.enabled ? baseFg : ChatRoomPalette.textSecondary;
    return InkWell(
      key: entry.key,
      onTap: entry.enabled ? entry.onTap : entry.onDisabledTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(entry.icon, size: 18, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    if (entry.subtitle != null &&
                        entry.subtitle!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 1.5),
                      Text(
                        entry.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: ChatRoomPalette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (entry.trailingIcon != null) ...<Widget>[
                const SizedBox(width: 6),
                Icon(entry.trailingIcon, size: 15, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Metadata pengelompokan pintar untuk pesan berurutan dari pengirim yang sama.
@immutable
class ChatBubbleCluster {
  const ChatBubbleCluster({
    required this.isFirstInGroup,
    required this.isLastInGroup,
  });

  final bool isFirstInGroup;
  final bool isLastInGroup;

  /// Jarak rapat (3,5 px) dalam satu klaster pengirim vs 11 px antar klaster.
  double get bottomGap => isLastInGroup ? 11.0 : 3.5;

  static ChatBubbleCluster compute({
    required bool sameSenderAsPrev,
    required bool sameSenderAsNext,
  }) {
    return ChatBubbleCluster(
      isFirstInGroup: !sameSenderAsPrev,
      isLastInGroup: !sameSenderAsNext,
    );
  }
}

/// Radius sudut modern: 18 px keliling + ekor 5 px pada pesan terbawah klaster,
/// dan sudut dalam 8 px agar klaster berurutan terasa menyatu.
BorderRadius chatBubbleBorderRadius({
  required bool outgoing,
  required ChatBubbleCluster cluster,
}) {
  if (outgoing) {
    return BorderRadius.only(
      topLeft: const Radius.circular(18),
      bottomLeft: const Radius.circular(18),
      topRight: Radius.circular(cluster.isFirstInGroup ? 18 : 8),
      bottomRight: Radius.circular(cluster.isLastInGroup ? 5 : 8),
    );
  }
  return BorderRadius.only(
    topRight: const Radius.circular(18),
    bottomRight: const Radius.circular(18),
    topLeft: Radius.circular(cluster.isFirstInGroup ? 18 : 8),
    bottomLeft: Radius.circular(cluster.isLastInGroup ? 5 : 8),
  );
}

BoxDecoration chatBubbleDecoration({
  required bool outgoing,
  required ChatBubbleCluster cluster,
}) {
  return BoxDecoration(
    color: outgoing ? ChatRoomPalette.outgoingFill : ChatRoomPalette.incomingFill,
    border: outgoing
        ? null
        : Border.all(color: ChatRoomPalette.incomingBorder, width: 1),
    borderRadius: chatBubbleBorderRadius(outgoing: outgoing, cluster: cluster),
  );
}

/// Avatar pengirim di kiri bawah klaster; menyisakan celah selebar 38 px pada
/// pesan sebelumnya di klaster yang sama agar sisi kiri gelembung tetap lurus.
class ChatSenderAvatarSlot extends StatelessWidget {
  const ChatSenderAvatarSlot({
    super.key,
    required this.visible,
    required this.senderId,
    required this.senderName,
    this.avatarUrl,
    this.avatarKey,
    this.onTap,
  });

  static const double radius = 15.0;
  static const double gutterWidth = radius * 2 + 8.0;

  final bool visible;
  final String senderId;
  final String senderName;
  final String? avatarUrl;
  final Key? avatarKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox(width: gutterWidth);
    }
    return ListenableBuilder(
      listenable: PublicProfileCacheService.instance,
      builder: (context, _) {
        final cache = PublicProfileCacheService.instance;
        final resolvedName = cache.resolveDisplayName(
          senderId,
          fallback: senderName,
        );
        final resolvedAvatar = cache.resolveAvatarUrl(
          senderId,
          fallback: avatarUrl,
        );
        final accent = ChatRoomPalette.senderPastel(senderId);
        final initial = resolvedName.trim().isNotEmpty
            ? resolvedName.trim()[0].toUpperCase()
            : '?';
        final fallbackChild = Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        );
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            key: avatarKey,
            onTap: onTap,
            child: PersistentAvatarImage(
              cacheKey: senderId,
              avatarUrl: resolvedAvatar,
              size: radius * 2,
              backgroundColor: accent.withValues(alpha: 0.22),
              fallback: fallbackChild,
            ),
          ),
        );
      },
    );
  }
}

/// Pil pemisah tanggal seragam di atas latar gelap topografi.
class ChatDateDividerPill extends StatelessWidget {
  const ChatDateDividerPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: ChatRoomPalette.textSecondary,
        ),
      ),
    );
  }
}

/// Pil pemisah pesan belum dibaca saat membuka ruang obrolan (`X pesan belum dibaca`).
class ChatUnreadDividerPill extends StatelessWidget {
  const ChatUnreadDividerPill({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count <= 1 ? '1 pesan belum dibaca' : '$count pesan belum dibaca';
    return Container(
      key: const ValueKey<String>('chat-unread-divider-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: ChatRoomPalette.badgeE2eeText.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ChatRoomPalette.badgeE2eeText.withValues(alpha: 0.45),
          width: 0.9,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: ChatRoomPalette.badgeE2eeText,
        ),
      ),
    );
  }
}

/// Label tanggal Indonesia seragam (`Hari ini`, `Kemarin`, atau `25 Okt 2026`).
String formatChatDayDividerLabel(DateTime utc, DateTime nowUtc) {
  final local = utc.toLocal();
  final nowLocal = nowUtc.toLocal();
  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final msgDay = DateTime(local.year, local.month, local.day);
  final diffDays = today.difference(msgDay).inDays;
  if (diffDays == 0) return 'Hari ini';
  if (diffDays == 1) return 'Kemarin';
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
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
