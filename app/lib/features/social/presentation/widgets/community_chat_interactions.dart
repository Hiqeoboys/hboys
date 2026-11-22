import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../../design/tokens.dart';
import '../../../../design/widgets/account_badges.dart';
import '../../../../design/widgets/persistent_avatar_image.dart';
import '../../../../design/widgets/persistent_media_image.dart';
import '../../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../../../infrastructure/storage/media_url_normalizer.dart';
import '../../../chat/presentation/chat_room_chrome.dart';
import '../../data/community_service.dart';

/// Format tanggal penuh berbahasa Indonesia (contoh: `14 November 2026`).
String formatIndonesianFullDate(DateTime date) {
  const months = <String>[
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  final local = date.toLocal();
  final idx = (local.month - 1).clamp(0, 11);
  return '${local.day} ${months[idx]} ${local.year}';
}

@immutable
class MentionQueryMatch {
  const MentionQueryMatch({
    required this.startOffset,
    required this.endOffset,
    required this.query,
  });

  final int startOffset;
  final int endOffset;
  final String query;
}

/// Mendeteksi token `@username` aktif pada posisi kursor [value].
MentionQueryMatch? extractActiveMentionQuery(TextEditingValue value) {
  final text = value.text;
  final sel = value.selection;
  final cursor = sel.isValid ? sel.baseOffset : text.length;
  if (cursor <= 0 || cursor > text.length) return null;

  var i = cursor - 1;
  while (i >= 0) {
    final ch = text[i];
    if (ch == '@') {
      if (i > 0 && !RegExp(r'\s').hasMatch(text[i - 1])) {
        return null;
      }
      final query = text.substring(i + 1, cursor);
      if (query.contains(RegExp(r'\s'))) return null;
      return MentionQueryMatch(
        startOffset: i,
        endOffset: cursor,
        query: query.toLowerCase(),
      );
    }
    if (RegExp(r'\s').hasMatch(ch)) {
      return null;
    }
    i--;
  }
  return null;
}

/// Menyaring hanya anggota yang SUDAH bergabung di komunitas ([members]).
List<CommunityMemberEntry> filterCommunityMentions(
  List<CommunityMemberEntry> members,
  String query, {
  String? excludeUserId,
  int limit = 6,
}) {
  final q = query.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
  final seen = <String>{};
  final result = <CommunityMemberEntry>[];

  for (final m in members) {
    if (m.userId.isEmpty || m.userId == excludeUserId) continue;
    final cleanUsername = m.username.trim().replaceFirst(RegExp(r'^@+'), '');
    if (cleanUsername.isEmpty) continue;
    if (!seen.add(m.userId)) continue;

    final matches = q.isEmpty ||
        cleanUsername.toLowerCase().contains(q) ||
        m.fullName.toLowerCase().contains(q);
    if (matches) {
      result.add(m);
      if (result.length >= limit) break;
    }
  }
  return result;
}

/// Mengambil daftar unik `userId` anggota komunitas yang disebut (`@username`) di [text].
List<String> resolveMentionedUserIds(
  String text,
  List<CommunityMemberEntry> members,
) {
  if (text.trim().isEmpty || members.isEmpty) return const <String>[];
  final byUsername = <String, String>{};
  for (final m in members) {
    final u = m.username.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
    if (u.isNotEmpty && m.userId.isNotEmpty) {
      byUsername[u] = m.userId;
    }
  }
  if (byUsername.isEmpty) return const <String>[];

  final regex = RegExp(r'(?:^|\s)@([A-Za-z0-9_.]{2,32})');
  final foundIds = <String>[];
  final seen = <String>{};
  for (final match in regex.allMatches(text)) {
    final token = match.group(1)?.toLowerCase();
    if (token == null) continue;
    final uid = byUsername[token];
    if (uid != null && seen.add(uid)) {
      foundIds.add(uid);
    }
  }
  return foundIds;
}

/// Memecah teks pesan menjadi `InlineSpan` dengan sorotan warna pada `@username`.
List<InlineSpan> buildHighlightedMentionSpans(
  String text, {
  required TextStyle baseStyle,
  required TextStyle mentionStyle,
}) {
  final regex = RegExp(r'(^|\s)(@[A-Za-z0-9_.]{2,32})');
  final spans = <InlineSpan>[];
  var lastEnd = 0;

  for (final match in regex.allMatches(text)) {
    final prefixStart = match.start;
    final mentionStart = match.start + (match.group(1)?.length ?? 0);
    if (prefixStart > lastEnd) {
      spans.add(
        TextSpan(text: text.substring(lastEnd, prefixStart), style: baseStyle),
      );
    }
    final prefix = match.group(1) ?? '';
    if (prefix.isNotEmpty) {
      spans.add(TextSpan(text: prefix, style: baseStyle));
    }
    final mention = match.group(2) ?? '';
    spans.add(TextSpan(text: mention, style: mentionStyle));
    lastEnd = match.end;
    if (mentionStart == lastEnd) continue;
  }

  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
  }
  if (spans.isEmpty) {
    spans.add(TextSpan(text: text, style: baseStyle));
  }
  return spans;
}

/// Pembungkus geser ke kanan (*swipe-to-reply*) dengan umpan balik haptik lembut
/// dan animasi kembali mulus untuk pesan teks, foto, maupun video.
class SwipeToReplyWrapper extends StatefulWidget {
  const SwipeToReplyWrapper({
    super.key,
    required this.enabled,
    required this.onReply,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<SwipeToReplyWrapper>
    with SingleTickerProviderStateMixin {
  static const double _maxOffset = 64.0;
  static const double _triggerOffset = 44.0;

  late final AnimationController _resetController;
  Animation<double>? _resetAnimation;
  double _dragOffset = 0.0;
  bool _triggeredHaptic = false;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        if (_resetAnimation != null && mounted) {
          setState(() => _dragOffset = _resetAnimation!.value);
        }
      });
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    final next = (_dragOffset + details.delta.dx).clamp(0.0, _maxOffset);
    if (next == _dragOffset) return;
    if (!_triggeredHaptic && next >= _triggerOffset) {
      _triggeredHaptic = true;
      unawaited(HapticFeedback.lightImpact());
    }
    setState(() => _dragOffset = next);
  }

  void _onDragEnd([DragEndDetails? _]) {
    if (!widget.enabled) return;
    final shouldReply = _dragOffset >= _triggerOffset;
    final start = _dragOffset;
    _triggeredHaptic = false;
    if (start > 0) {
      _resetAnimation = Tween<double>(begin: start, end: 0.0).animate(
        CurvedAnimation(parent: _resetController, curve: Curves.easeOutCubic),
      );
      unawaited(_resetController.forward(from: 0.0));
    }
    if (shouldReply) {
      widget.onReply();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final progress = (_dragOffset / _triggerOffset).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragEnd,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[
          if (_dragOffset > 2)
            Positioned(
              left: 4,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.14 * progress),
                ),
                child: Icon(
                  Icons.reply_rounded,
                  size: 17,
                  color: ChatRoomPalette.textPrimary
                      .withValues(alpha: progress.clamp(0.25, 1.0)),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Pratinjau balasan di atas bilah mengetik.
class CommunityReplyPreviewBar extends StatelessWidget {
  const CommunityReplyPreviewBar({
    super.key,
    required this.replyingTo,
    required this.resolvedSenderName,
    required this.onCancel,
  });

  final CommunityMessage replyingTo;
  final String resolvedSenderName;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final thumbUrl = MediaUrlNormalizer.normalize(
      replyingTo.messageType == CommunityMessageType.video
          ? replyingTo.mediaThumbnailUrl
          : replyingTo.mediaUrl,
    );
    final isMedia = replyingTo.messageType != CommunityMessageType.text;
    final IconData? mediaIcon = switch (replyingTo.messageType) {
      CommunityMessageType.image => Icons.photo_camera_outlined,
      CommunityMessageType.video => Icons.videocam_outlined,
      CommunityMessageType.text => null,
    };
    final snippet = switch (replyingTo.messageType) {
      CommunityMessageType.image =>
        replyingTo.content?.trim().isNotEmpty == true
            ? replyingTo.content!.trim()
            : 'Foto',
      CommunityMessageType.video =>
        replyingTo.content?.trim().isNotEmpty == true
            ? replyingTo.content!.trim()
            : 'Video',
      CommunityMessageType.text => replyingTo.content?.trim() ?? 'Pesan',
    };

    return HiqeoLiquidGlassSurface(
      key: const ValueKey<String>('community-reply-preview-bar'),
      borderRadius: 18,
      enableBlur: false,
      fillColor: ChatRoomPalette.incomingFill,
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Membalas $resolvedSenderName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: <Widget>[
                    if (mediaIcon != null) ...<Widget>[
                      Icon(
                        mediaIcon,
                        size: 14,
                        color: ChatRoomPalette.textSecondary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: ChatRoomPalette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isMedia && thumbUrl != null && thumbUrl.isNotEmpty) ...<Widget>[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: PersistentMediaImage(
                url: thumbUrl,
                width: 36,
                height: 36,
                cacheWidth: 96,
                fit: BoxFit.cover,
                enableRetryOnTap: false,
                placeholder: const SizedBox(width: 36, height: 36),
                errorBuilder: (_) => const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(width: 4),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              key: const ValueKey<String>('community-reply-cancel-btn'),
              onPressed: onCancel,
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: ChatRoomPalette.textSecondary,
              ),
              tooltip: 'Batalkan balasan',
            ),
          ),
        ],
      ),
    );
  }
}

/// Kotak kutipan pesan asli di dalam gelembung komunitas yang membalas.
class CommunityReplyQuoteBox extends StatelessWidget {
  const CommunityReplyQuoteBox({
    super.key,
    required this.senderName,
    required this.snippet,
    required this.outgoing,
    this.mediaIcon,
    this.thumbnailUrl,
    this.isDeleted = false,
    required this.onTap,
  });

  final String senderName;
  final String snippet;
  final bool outgoing;
  final IconData? mediaIcon;
  final String? thumbnailUrl;
  final bool isDeleted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent =
        outgoing ? const Color(0xFF2563EB) : ChatRoomPalette.badgeCommunityText;
    final boxBg = outgoing
        ? ChatRoomPalette.outgoingText.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.09);
    final titleColor = outgoing ? accent : accent;
    final bodyColor =
        outgoing ? ChatRoomPalette.outgoingMeta : ChatRoomPalette.incomingMeta;
    final normalizedThumb = MediaUrlNormalizer.normalize(thumbnailUrl);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: boxBg,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: accent, width: 3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (!isDeleted && mediaIcon != null) ...<Widget>[
                        Icon(
                          mediaIcon,
                          size: 13.5,
                          color: bodyColor,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          isDeleted ? 'Pesan telah dihapus' : snippet,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle:
                                isDeleted ? FontStyle.italic : FontStyle.normal,
                            color: bodyColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!isDeleted &&
                normalizedThumb != null &&
                normalizedThumb.isNotEmpty) ...<Widget>[
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: PersistentMediaImage(
                  url: normalizedThumb,
                  width: 34,
                  height: 34,
                  cacheWidth: 96,
                  fit: BoxFit.cover,
                  enableRetryOnTap: false,
                  placeholder: const SizedBox(width: 34, height: 34),
                  errorBuilder: (_) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Daftar saran anggota komunitas saat pengguna mengetik `@`.
class CommunityMentionSuggestionsOverlay extends StatelessWidget {
  const CommunityMentionSuggestionsOverlay({
    super.key,
    required this.suggestions,
    required this.onSelect,
  });

  final List<CommunityMemberEntry> suggestions;
  final ValueChanged<CommunityMemberEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return HiqeoLiquidGlassSurface(
      key: const ValueKey<String>('community-mention-suggestions'),
      borderRadius: 18,
      enableBlur: false,
      fillColor: ChatRoomPalette.incomingFill,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            final member = suggestions[index];
            final name = member.fullName.trim().isNotEmpty
                ? member.fullName.trim()
                : member.username;
            final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
            return InkWell(
              key: ValueKey<String>(
                'community-mention-item-${member.username}',
              ),
              onTap: () => onSelect(member),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: <Widget>[
                    PersistentAvatarImage(
                      cacheKey: member.userId,
                      avatarUrl: member.avatarUrl,
                      size: 32,
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      fallback: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: ChatRoomPalette.textPrimary,
                          ),
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
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: ChatRoomPalette.textPrimary,
                                  ),
                                ),
                              ),
                              if (PublicProfileCacheService.instance
                                  .resolveIsOfficial(
                                member.userId,
                                fallback: member.isOfficial,
                                usernameFallback: member.username,
                              )) ...<Widget>[
                                const SizedBox(width: 4),
                                const OfficialVerifiedBadge(size: 14),
                              ],
                            ],
                          ),
                          Text(
                            '@${member.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: ChatRoomPalette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
