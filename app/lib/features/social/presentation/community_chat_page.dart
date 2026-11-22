import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../design/glass/glass_surface.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/hiqeo_state_view.dart';
import '../../../design/widgets/nav_bar_visibility.dart';
import '../../../design/widgets/persistent_avatar_image.dart';
import '../../../design/widgets/persistent_media_image.dart';
import '../../../infrastructure/cache/hiqeo_media_cache_service.dart';
import '../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../../infrastructure/network/hiqeo_http_overrides.dart';
import '../../../infrastructure/notifications/fcm_notification_service.dart';
import '../../../infrastructure/storage/media_url_normalizer.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../chat/presentation/chat_mute_sheet.dart';
import '../../chat/presentation/chat_room_chrome.dart';
import '../../plus/application/plus_navigation.dart';
import '../../plus/application/plus_scope.dart';
import '../data/chat_mute_service.dart';
import '../data/community_media_tools.dart';
import '../data/community_service.dart';
import '../data/friends_service.dart';
import '../data/moderation_service.dart';
import '../data/social_unread_store.dart';
import 'community_camera_page.dart';
import 'community_media_viewer_page.dart';
import 'widgets/community_chat_interactions.dart';

/// Ruang obrolan Komunitas (Online-Only) dengan tata letak Stack penuh layar,
/// Header & Bilah Input Liquid Glass, latar kontur topografi `#242B40`,
/// dropdown kanan-atas selaras Grup, toast galat di atas, dan tanpa double inset.
class CommunityChatPage extends StatefulWidget {
  const CommunityChatPage({
    super.key,
    required this.community,
    this.initialMessages,
    this.hasFullSocialOverride,
    this.currentUserIdOverride,
    this.onSendText,
    this.onSendTextWithMeta,
    this.onDeleteMessage,
    this.initialTargetMessageId,
    this.initialMembers,
    this.muteService,
    this.thumbnailCache,
    this.onJoinCommunity,
    this.onOpenPlusPaywall,
    this.firstEnteredAtOverride,
  });

  final CommunitySummary community;

  /// Opsional untuk uji widget tanpa jaringan Supabase.
  final List<CommunityMessage>? initialMessages;
  final bool? hasFullSocialOverride;
  final String? currentUserIdOverride;
  final Future<void> Function(String text)? onSendText;
  final Future<void> Function({
    required String text,
    String? replyToMessageId,
    List<String> mentionedUserIds,
  })? onSendTextWithMeta;
  final Future<void> Function(String messageId)? onDeleteMessage;
  final String? initialTargetMessageId;
  final List<CommunityMemberEntry>? initialMembers;
  final ChatMuteService? muteService;
  final CommunityVideoThumbnailCache? thumbnailCache;
  final Future<CommunitySummary?> Function()? onJoinCommunity;
  final VoidCallback? onOpenPlusPaywall;
  final DateTime? firstEnteredAtOverride;

  @override
  State<CommunityChatPage> createState() => _CommunityChatPageState();
}

class _CommunityChatPageState extends State<CommunityChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _composerFocusNode = FocusNode();

  late CommunitySummary _community;
  late final ChatMuteService _muteService =
      widget.muteService ?? ChatMuteService.instance;
  List<CommunityMessage> _messages = const <CommunityMessage>[];
  List<CommunityMemberEntry> _communityMembers = const <CommunityMemberEntry>[];
  bool _loading = true;
  bool _sending = false;
  bool _joining = false;
  bool _menuOpen = false;
  bool _hasMoreOlderMessages = false;
  bool _loadingOlderMessages = false;
  DateTime? _firstEnteredAtUtc;
  String? _error;
  RealtimeChannel? _channel;

  String? _topToastText;
  bool _topToastIsError = false;
  Timer? _topToastTimer;
  bool _hasText = false;

  CommunityMessage? _replyingTo;
  MentionQueryMatch? _activeMentionMatch;
  List<CommunityMemberEntry> _mentionSuggestions =
      const <CommunityMemberEntry>[];
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _messageItemKeys = <String, GlobalKey>{};
  final GlobalKey _unreadDividerKey = GlobalKey();
  RoomReadCursor? _initialReadCursor;
  int? _firstUnreadIndex;
  int _unreadDividerCount = 0;
  bool _initialScrollDone = false;
  double _lastKeyboardInset = 0.0;
  double _lastViewportHeight = 0.0;

  String? get _currentUserId =>
      widget.currentUserIdOverride ??
      SupabaseServices.clientOrNull?.auth.currentUser?.id;

  bool get _isOwner => _community.isOwner(_currentUserId);

  void _onTextChanged() {
    final nextHasText = _textController.text.trim().isNotEmpty;
    final match = extractActiveMentionQuery(_textController.value);
    final nextSuggestions = match == null
        ? const <CommunityMemberEntry>[]
        : filterCommunityMentions(
            _communityMembers,
            match.query,
            excludeUserId: _currentUserId,
          );
    final prevIds =
        _mentionSuggestions.map((e) => e.userId).toList(growable: false);
    final nextIds =
        nextSuggestions.map((e) => e.userId).toList(growable: false);
    final suggestionsChanged = !listEquals(prevIds, nextIds) ||
        _activeMentionMatch?.startOffset != match?.startOffset ||
        _activeMentionMatch?.endOffset != match?.endOffset ||
        _activeMentionMatch?.query != match?.query;
    if ((nextHasText != _hasText || suggestionsChanged) && mounted) {
      setState(() {
        _hasText = nextHasText;
        _activeMentionMatch = match;
        _mentionSuggestions = nextSuggestions;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _community = widget.community;
    _firstEnteredAtUtc = widget.firstEnteredAtOverride?.toUtc();
    NavBarVisibilityController.instance.setRoomChatOpen(true);
    FcmNotificationService.instance.setActiveRoom(
      type: 'community',
      id: _community.id,
    );
    unawaited(_muteService.loadAll());
    if (widget.initialMembers != null) {
      _communityMembers = List<CommunityMemberEntry>.of(widget.initialMembers!);
    } else {
      unawaited(_loadCommunityMembers());
    }
    if (widget.initialMessages != null) {
      final since = _firstEnteredAtUtc;
      final initial = since == null
          ? widget.initialMessages!
          : widget.initialMessages!
              .where((m) => !m.createdAt.isBefore(since))
              .toList(growable: false);
      _messages = List<CommunityMessage>.of(initial);
      _hasMoreOlderMessages = false;
      _loading = false;
      unawaited(_resolveInitialCursorAndScroll());
    } else {
      unawaited(_initLoadWithCursor());
      _channel = CommunityService.instance.subscribeMessages(
        communityId: _community.id,
        onChange: () => unawaited(_loadMessages(silent: true)),
      );
    }
  }

  @override
  void dispose() {
    _topToastTimer?.cancel();
    _highlightTimer?.cancel();
    NavBarVisibilityController.instance.setRoomChatOpen(false);
    FcmNotificationService.instance.clearActiveRoom(
      type: 'community',
      id: _community.id,
    );
    final latestMsg = _messages.isNotEmpty ? _messages.last : null;
    final nowUtc = DateTime.now().toUtc();
    final readAt = latestMsg != null && latestMsg.createdAt.isAfter(nowUtc)
        ? latestMsg.createdAt
        : nowUtc;
    unawaited(
      SocialUnreadStore.instance.markCommunityRead(
        _community.id,
        at: readAt,
        lastMessageId: latestMsg?.id,
      ),
    );
    final channel = _channel;
    if (channel != null) {
      unawaited(SupabaseServices.clientOrNull?.removeChannel(channel));
    }
    _textController
      ..removeListener(_onTextChanged)
      ..dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCommunityMembers() async {
    try {
      final members =
          await CommunityService.instance.fetchCommunityMembers(_community.id);
      if (!mounted) return;
      if (members.isNotEmpty) {
        setState(() => _communityMembers = members);
      }
    } catch (_) {}
  }

  Future<void> _initLoadWithCursor() async {
    _firstEnteredAtUtc ??=
        await CommunityService.instance.recordFirstEntry(_community.id);
    _initialReadCursor =
        await SocialUnreadStore.instance.getCommunityReadCursor(_community.id);
    if (!mounted) return;
    await _loadMessages();
  }

  Future<void> _resolveInitialCursorAndScroll() async {
    _initialReadCursor ??=
        await SocialUnreadStore.instance.getCommunityReadCursor(_community.id);
    if (!mounted || _messages.isEmpty) return;
    _applyCursorAndScrollOnMessages();
  }

  void _applyCursorAndScrollOnMessages() {
    if (!mounted || _messages.isEmpty) return;
    if (!_initialScrollDone) {
      _initialScrollDone = true;
      final targetId = widget.initialTargetMessageId;
      if (targetId != null && targetId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpToAndHighlightMessage(targetId);
        });
      } else {
        final marker = computeUnreadMarker<CommunityMessage>(
          messages: _messages,
          cursor: _initialReadCursor ?? const RoomReadCursor(),
          currentUserId: _currentUserId ?? '',
          idOf: (m) => m.id,
          senderIdOf: (m) => m.senderId,
          createdAtOf: (m) => m.createdAt,
        );
        if (marker.unreadCount > 0 && marker.firstUnreadIndex != null) {
          setState(() {
            _firstUnreadIndex = marker.firstUnreadIndex;
            _unreadDividerCount = marker.unreadCount;
          });
          _scrollToUnreadDivider(marker.firstUnreadIndex!);
        } else {
          _scrollToBottom(immediate: true);
        }
      }
    } else {
      final nearBottom = !_scrollController.hasClients ||
          (_scrollController.position.maxScrollExtent -
                  _scrollController.position.pixels) <
              180;
      if (_messages.last.senderId == _currentUserId || nearBottom) {
        _scrollToBottom();
      }
    }

    final latest = _messages.last;
    final nowUtc = DateTime.now().toUtc();
    final readAt =
        latest.createdAt.isAfter(nowUtc) ? latest.createdAt : nowUtc;
    unawaited(
      SocialUnreadStore.instance.markCommunityRead(
        _community.id,
        at: readAt,
        lastMessageId: latest.id,
      ),
    );
  }

  void _scrollToUnreadDivider(int targetIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final ctx = _unreadDividerKey.currentContext;
      if (ctx != null) {
        unawaited(
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: 0.15,
          ),
        );
        return;
      }
      final maxExt = _scrollController.position.maxScrollExtent;
      if (maxExt > 0 && _messages.isNotEmpty) {
        final ratio = (targetIndex / _messages.length).clamp(0.0, 1.0);
        _scrollController.jumpTo(maxExt * ratio);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final resolvedCtx = _unreadDividerKey.currentContext;
          if (mounted && resolvedCtx != null) {
            unawaited(
              Scrollable.ensureVisible(
                resolvedCtx,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: 0.15,
              ),
            );
          }
        });
      }
    });
  }

  void _jumpToAndHighlightMessage(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) {
      _showTopToast('Pesan asli tidak ditemukan di riwayat saat ini.');
      return;
    }
    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final keyCtx = _messageItemKeys[messageId]?.currentContext;
      if (keyCtx != null) {
        unawaited(
          Scrollable.ensureVisible(
            keyCtx,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: 0.35,
          ),
        );
        return;
      }
      if (!_scrollController.hasClients || _messages.isEmpty) return;
      final maxExt = _scrollController.position.maxScrollExtent;
      final ratio = (idx / _messages.length).clamp(0.0, 1.0);
      _scrollController.jumpTo(maxExt * ratio);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final resolvedCtx = _messageItemKeys[messageId]?.currentContext;
        if (mounted && resolvedCtx != null) {
          unawaited(
            Scrollable.ensureVisible(
              resolvedCtx,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: 0.35,
            ),
          );
        }
      });
    });
  }

  void _showTopToast(String message, {bool isError = false}) {
    if (!mounted) return;
    _topToastTimer?.cancel();
    setState(() {
      _topToastText = message;
      _topToastIsError = isError;
    });
    _topToastTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _topToastText = null);
    });
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      _firstEnteredAtUtc ??=
          await CommunityService.instance.recordFirstEntry(_community.id);
      final page = await CommunityService.instance.fetchMessagesPage(
        _community.id,
        limit: 40,
        sinceUtc: _firstEnteredAtUtc,
      );
      if (!mounted) return;
      final List<CommunityMessage> nextList;
      final bool hasMore;
      if (silent && _messages.isNotEmpty) {
        final byId = <String, CommunityMessage>{
          for (final m in _messages) m.id: m,
          for (final m in page.messages) m.id: m,
        };
        nextList = byId.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        hasMore = _hasMoreOlderMessages || page.hasMore;
      } else {
        nextList = page.messages;
        hasMore = page.hasMore;
      }
      final bound = _firstEnteredAtUtc;
      final reachedBound = nextList.isEmpty ||
          (bound != null && !nextList.first.createdAt.isAfter(bound));
      setState(() {
        _messages = nextList;
        _hasMoreOlderMessages = hasMore && !reachedBound;
        _loading = false;
      });
      _applyCursorAndScrollOnMessages();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityChatPage._loadMessages failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Pesan komunitas belum bisa dimuat. Periksa sinyal lalu coba lagi.';
      });
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlderMessages ||
        !_hasMoreOlderMessages ||
        _messages.isEmpty) {
      return;
    }
    final oldest = _messages.first.createdAt;
    final bound = _firstEnteredAtUtc;
    if (bound != null && !oldest.isAfter(bound)) {
      setState(() => _hasMoreOlderMessages = false);
      return;
    }
    setState(() => _loadingOlderMessages = true);
    try {
      final page = await CommunityService.instance.fetchMessagesPage(
        _community.id,
        limit: 40,
        beforeUtc: oldest,
        sinceUtc: bound,
      );
      if (!mounted) return;
      if (page.messages.isEmpty) {
        setState(() {
          _hasMoreOlderMessages = false;
          _loadingOlderMessages = false;
        });
        return;
      }
      final existingIds = _messages.map((m) => m.id).toSet();
      final olderUnique = page.messages
          .where((m) => !existingIds.contains(m.id))
          .toList(growable: false);
      final combined = <CommunityMessage>[...olderUnique, ..._messages];
      final reachedBound = combined.isEmpty ||
          (bound != null && !combined.first.createdAt.isAfter(bound));
      setState(() {
        _messages = combined;
        _hasMoreOlderMessages = page.hasMore && !reachedBound;
        _loadingOlderMessages = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

  Future<void> _handleJoinCommunity({required bool hasFullSocial}) async {
    if (_joining || _community.isJoined) return;
    setState(() => _joining = true);
    try {
      if (widget.onJoinCommunity != null) {
        final updated = await widget.onJoinCommunity!();
        if (!mounted) return;
        setState(() {
          _community = updated ??
              _community.copyWith(
                isJoined: true,
                memberCount: _community.memberCount + 1,
              );
          _joining = false;
        });
      } else {
        await CommunityService.instance.joinCommunity(
          _community.id,
          isOwner: _isOwner,
        );
        if (!mounted) return;
        setState(() {
          _community = _community.copyWith(
            isJoined: true,
            memberCount: _community.memberCount + 1,
          );
          _joining = false;
        });
        unawaited(_loadCommunityMembers());
      }
      if (!hasFullSocial && mounted) {
        _openPlusUpgradeFromCommunity();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityChatPage join failed: $e');
      }
      if (mounted) {
        setState(() => _joining = false);
        _showTopToast(
          'Belum bisa bergabung ke komunitas. Periksa sinyal lalu coba lagi.',
          isError: true,
        );
      }
    }
  }

  void _openPlusUpgradeFromCommunity() {
    if (widget.onOpenPlusPaywall != null) {
      widget.onOpenPlusPaywall!();
      return;
    }
    openPlusPaywall(
      context,
      notice:
          'Untuk mengirim pesan di komunitas, dibutuhkan paket Hiqeo Plus Mahasiswa atau Tahunan.',
      requireFullSocialPlan: true,
    );
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final maxExt = _scrollController.position.maxScrollExtent;
      if (immediate) {
        _scrollController.jumpTo(maxExt);
      } else {
        unawaited(
          _scrollController.animateTo(
            maxExt,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  void _selectMention(CommunityMemberEntry member) {
    final match = _activeMentionMatch;
    final text = _textController.text;
    final username = member.username.trim().replaceFirst(RegExp(r'^@+'), '');
    if (username.isEmpty) return;
    final insertion = '@$username ';
    final start = (match != null && match.startOffset <= text.length)
        ? match.startOffset
        : text.length;
    final end = (match != null && match.endOffset <= text.length)
        ? match.endOffset
        : text.length;
    final nextText = text.replaceRange(start, end, insertion);
    final nextCursor = start + insertion.length;
    _textController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextCursor),
    );
    setState(() {
      _activeMentionMatch = null;
      _mentionSuggestions = const <CommunityMemberEntry>[];
    });
    _composerFocusNode.requestFocus();
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;
    final replyId = _replyingTo?.id;
    final mentionedIds = resolveMentionedUserIds(text, _communityMembers);
    setState(() => _sending = true);
    try {
      if (widget.onSendTextWithMeta != null) {
        await widget.onSendTextWithMeta!(
          text: text,
          replyToMessageId: replyId,
          mentionedUserIds: mentionedIds,
        );
      } else if (widget.onSendText != null) {
        await widget.onSendText!(text);
      } else {
        await CommunityService.instance.sendTextMessage(
          communityId: _community.id,
          text: text,
          replyToMessageId: replyId,
          mentionedUserIds: mentionedIds,
        );
      }
      _textController.clear();
      if (mounted) {
        setState(() {
          _replyingTo = null;
          _activeMentionMatch = null;
          _mentionSuggestions = const <CommunityMemberEntry>[];
        });
      }
      if (widget.onSendTextWithMeta == null && widget.onSendText == null) {
        await _loadMessages(silent: true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityChatPage._sendText failed: $e');
      }
      _showTopToast(
        'Pesan belum terkirim. Periksa sinyal lalu coba lagi.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openFullScreenCamera() async {
    if (_sending) return;
    final result = await Navigator.of(context).push<CapturedMediaResult>(
      MaterialPageRoute<CapturedMediaResult>(
        builder: (_) => const CommunityCameraPage(),
      ),
    );
    if (result == null || !mounted) return;

    final replyId = _replyingTo?.id;
    setState(() => _sending = true);
    try {
      if (result.isVideo) {
        await CommunityService.instance.sendVideoMessage(
          communityId: _community.id,
          videoFile: result.file,
          durationSec: result.durationSec ?? 1,
          replyToMessageId: replyId,
        );
      } else {
        await CommunityService.instance.sendImageMessage(
          communityId: _community.id,
          imageFile: result.file,
          replyToMessageId: replyId,
        );
      }
      if (mounted && _replyingTo != null) {
        setState(() => _replyingTo = null);
      }
      await _loadMessages(silent: true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityChatPage._openFullScreenCamera failed: $e');
      }
      _showTopToast(
        e is StateError
            ? e.message
            : 'Media belum bisa diunggah. Periksa koneksi lalu coba lagi.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showOwnMessageDeleteSheet(CommunityMessage msg) async {
    if (msg.isDeleted) return;
    unawaited(HapticFeedback.mediumImpact());
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) {
        final safeBottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + safeBottom),
          child: HiqeoLiquidGlassSurface(
            key: const ValueKey<String>('community-own-msg-sheet'),
            borderRadius: 24,
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ChatRoomPalette.textSecondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  key: const ValueKey<String>('community-msg-action-delete'),
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: ChatRoomPalette.destructiveRed,
                  ),
                  title: const Text(
                    'Hapus pesan',
                    style: TextStyle(
                      color: ChatRoomPalette.destructiveRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop('delete'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action != 'delete' || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey<String>('community-msg-delete-dialog'),
        title: const Text('Hapus pesan?'),
        content: const Text(
          'Pesan ini akan dihapus untuk semua anggota komunitas.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const ValueKey<String>('community-msg-delete-confirm-btn'),
            style: FilledButton.styleFrom(
              backgroundColor: ChatRoomPalette.destructiveRed,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (widget.onDeleteMessage != null) {
        await widget.onDeleteMessage!(msg.id);
      } else {
        await CommunityService.instance.deleteMessage(msg.id);
      }
      if (!mounted) return;
      final nowUtc = DateTime.now().toUtc();
      setState(() {
        _messages = _messages
            .map(
              (m) => m.id == msg.id
                  ? CommunityMessage(
                      id: m.id,
                      communityId: m.communityId,
                      senderId: m.senderId,
                      senderName: m.senderName,
                      senderUsername: m.senderUsername,
                      senderAvatarUrl: m.senderAvatarUrl,
                      messageType: CommunityMessageType.text,
                      content: null,
                      mediaUrl: null,
                      mediaThumbnailUrl: null,
                      mediaDurationSec: null,
                      isDeleted: true,
                      deletedAt: nowUtc,
                      replyToMessageId: m.replyToMessageId,
                      mentionedUserIds: const <String>[],
                      createdAt: m.createdAt,
                    )
                  : m,
            )
            .toList(growable: false);
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityChatPage deleteMessage failed: $e');
      }
      _showTopToast(
        'Pesan belum bisa dihapus. Periksa sinyal lalu coba lagi.',
        isError: true,
      );
    }
  }

  CommunityMessage? _replyTargetFor(
    CommunityMessage msg, [
    Map<String, CommunityMessage>? messagesById,
  ]) {
    final targetId = msg.replyToMessageId;
    if (targetId == null || targetId.isEmpty) return null;
    if (messagesById != null) return messagesById[targetId];
    for (final m in _messages) {
      if (m.id == targetId) return m;
    }
    return null;
  }

  void _toggleHamburgerMenu() {
    setState(() => _menuOpen = !_menuOpen);
  }

  void _runMenuAction(Future<void> Function() action) {
    setState(() => _menuOpen = false);
    unawaited(action());
  }

  Future<void> _showCommunityInfoSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) {
        final colors = HiqeoColors.of(ctx);
        final safeBottom = MediaQuery.paddingOf(ctx).bottom;
        final avatarUrl = _community.avatarUrl;
        final description = _community.description.trim();
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + safeBottom),
          child: GlassSurface(
            key: const ValueKey<String>('community-info-sheet'),
            tier: GlassTier.panel,
            borderRadius: 28,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    PersistentAvatarImage(
                      cacheKey: 'community_${_community.id}',
                      avatarUrl: avatarUrl,
                      size: 48,
                      resolveFromProfileCache: false,
                      backgroundColor: colors.hairline,
                      fallback: Icon(
                        Icons.groups_rounded,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _community.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_community.memberCount} anggota · Komunitas',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          () {
                            final creatorUid =
                                _community.createdBy ?? _community.ownerId;
                            final cache = PublicProfileCacheService.instance;
                            final cachedCreator = cache.getCached(creatorUid);
                            final rawName =
                                _community.creatorName?.trim().isNotEmpty ==
                                        true
                                    ? _community.creatorName!.trim()
                                    : cachedCreator?.fullName?.trim();
                            final rawUname =
                                _community.creatorUsername?.trim().isNotEmpty ==
                                        true
                                    ? _community.creatorUsername!.trim()
                                    : cachedCreator?.username?.trim();
                            final creatorName =
                                (rawName != null && rawName.isNotEmpty)
                                    ? rawName
                                    : null;
                            final cleanUname = rawUname
                                ?.replaceFirst(RegExp(r'^@+'), '')
                                .trim();
                            final creatorUname =
                                (cleanUname != null && cleanUname.isNotEmpty)
                                    ? '@$cleanUname'
                                    : null;
                            final creatorLabel =
                                creatorName != null && creatorUname != null
                                    ? '$creatorName ($creatorUname)'
                                    : (creatorName ?? creatorUname);
                            final createdStr =
                                formatIndonesianFullDate(_community.createdAt);
                            return Text(
                              creatorLabel != null
                                  ? 'Dibuat oleh $creatorLabel · $createdStr'
                                  : 'Dibuat $createdStr',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.textSecondary,
                              ),
                            );
                          }(),
                        ],
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_isOwner) ...<Widget>[
                  HiqeoButton(
                    label: 'Edit komunitas',
                    variant: HiqeoButtonVariant.secondary,
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      unawaited(_showEditCommunityDialog());
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                HiqeoButton(
                  label: 'Laporkan komunitas',
                  variant: HiqeoButtonVariant.secondary,
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    unawaited(_showReportCommunityDialog());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditCommunityDialog() async {
    final nameCtrl = TextEditingController(text: _community.name);
    final descCtrl = TextEditingController(text: _community.description);
    File? pickedPhoto;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final colors = HiqeoColors.of(dialogCtx);
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Text(
              'Edit komunitas',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  GestureDetector(
                    onTap: saving
                        ? null
                        : () async {
                            final xfile = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                            );
                            if (xfile != null) {
                              setDialogState(() {
                                pickedPhoto = File(xfile.path);
                              });
                            }
                          },
                    child: Column(
                      children: <Widget>[
                        if (pickedPhoto != null)
                          ClipOval(
                            child: Image.file(
                              pickedPhoto!,
                              width: 76,
                              height: 76,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          PersistentAvatarImage(
                            cacheKey: 'community_${_community.id}',
                            avatarUrl: _community.avatarUrl,
                            size: 76,
                            resolveFromProfileCache: false,
                            backgroundColor: colors.hairline,
                            fallback: Center(
                              child: Icon(
                                Icons.groups_rounded,
                                size: 32,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          'Ubah foto profil komunitas',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Nama komunitas',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Deskripsi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (nameCtrl.text.trim().isEmpty) return;
                        setDialogState(() => saving = true);
                        try {
                          final updated =
                              await CommunityService.instance.updateCommunity(
                            community: _community,
                            name: nameCtrl.text,
                            description: descCtrl.text,
                            newAvatarFile: pickedPhoto,
                          );
                          if (mounted) {
                            setState(() => _community = updated);
                          }
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        } catch (e) {
                          if (kDebugMode) {
                            debugPrint('CommunityChatPage._edit failed: $e');
                          }
                          setDialogState(() => saving = false);
                          _showTopToast(
                            'Perubahan belum bisa disimpan. Coba lagi.',
                            isError: true,
                          );
                        }
                      },
                child: Text(saving ? 'Menyimpan…' : 'Simpan'),
              ),
            ],
          ),
        );
      },
    );
    nameCtrl.dispose();
    descCtrl.dispose();
  }

  /// Dialog Laporkan Komunitas (TIDAK menampilkan nama pemilik komunitas).
  Future<void> _showReportCommunityDialog() async {
    await _showReportDialog(
      title: 'Laporkan komunitas',
      subtitle: 'Pilih alasan pelaporan untuk komunitas "${_community.name}".',
      onSubmit: (reason, details) => ModerationService.instance.submitReport(
        targetType: ModerationTargetType.community,
        targetId: _community.id,
        communityId: _community.id,
        reason: reason,
        details: details,
      ),
    );
  }

  Future<void> _confirmDeleteCommunity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus komunitas?'),
        content: Text(
          'Komunitas "${_community.name}" dan seluruh pesannya akan dihapus secara permanen.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: HiqeoColors.of(ctx).warning,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await CommunityService.instance.deleteCommunity(_community.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityChatPage deleteCommunity failed: $e');
      }
      _showTopToast(
        'Komunitas belum bisa dihapus. Periksa sinyal lalu coba lagi.',
        isError: true,
      );
    }
  }

  Future<void> _confirmLeaveCommunity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar komunitas?'),
        content: Text(
          'Kamu akan keluar dari "${_community.name}", namun komunitas ini tetap aktif untuk anggota lain.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Keluar komunitas'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await CommunityService.instance.leaveCommunity(_community.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _onTapSender(
    CommunityMessage msg, {
    required bool hasFullSocialAccess,
  }) async {
    if (msg.senderId == _currentUserId) return;
    final colors = HiqeoColors.of(context);
    final relation =
        FriendsService.instance.relationshipStatusFor(msg.senderId);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) {
        final safeBottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + safeBottom),
          child: HiqeoLiquidGlassSurface(
            key: const ValueKey<String>('community-sender-action-sheet'),
            borderRadius: 28,
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: () {
                    final cache = PublicProfileCacheService.instance;
                    final resolvedName = cache.resolveDisplayName(
                      msg.senderId,
                      fallback: msg.senderName,
                    );
                    final resolvedUsername = cache.resolveUsername(
                      msg.senderId,
                      fallback: msg.senderUsername,
                    );
                    final resolvedAvatar = cache.resolveAvatarUrl(
                      msg.senderId,
                      fallback: msg.senderAvatarUrl,
                    );
                    final initial = resolvedName.isNotEmpty
                        ? resolvedName[0].toUpperCase()
                        : '?';
                    final fallbackAvatar = Center(
                      child: Text(
                        initial,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    );
                    return Row(
                      children: <Widget>[
                        PersistentAvatarImage(
                          cacheKey: msg.senderId,
                          avatarUrl: resolvedAvatar,
                          size: 40,
                          backgroundColor: colors.hairline,
                          fallback: fallbackAvatar,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                resolvedName,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              if (resolvedUsername != null &&
                                  resolvedUsername.isNotEmpty)
                                Text(
                                  '@$resolvedUsername',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: colors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }(),
                ),
                Divider(color: colors.hairline, height: 1),
                if (hasFullSocialAccess)
                  ListTile(
                    key: const ValueKey('sender-action-add-friend'),
                    leading: Icon(
                      relation == 'friend'
                          ? Icons.check_circle_outline_rounded
                          : Icons.person_add_alt_1_rounded,
                      color: relation == 'friend'
                          ? colors.textSecondary
                          : colors.primary,
                    ),
                    title: Text(
                      relation == 'friend'
                          ? 'Sudah berteman'
                          : (relation == 'outgoing'
                              ? 'Permintaan terkirim'
                              : 'Tambahkan teman'),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    enabled: relation == null,
                    onTap: relation == null
                        ? () => Navigator.of(ctx).pop('add_friend')
                        : null,
                  ),
                ListTile(
                  key: const ValueKey('sender-action-report-message'),
                  leading: Icon(Icons.flag_outlined, color: colors.warningText),
                  title: Text(
                    'Laporkan pesan',
                    style: TextStyle(
                      color: colors.warningText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop('report_message'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'add_friend') {
      try {
        await FriendsService.instance.sendFriendRequest(msg.senderId);
        _showTopToast('Permintaan pertemanan dikirim ke ${msg.senderName}.');
      } catch (e) {
        if (kDebugMode) {
          debugPrint('CommunityChatPage addFriend failed: $e');
        }
        _showTopToast(
          e is StateError
              ? e.message
              : 'Permintaan teman belum terkirim. Periksa sinyal lalu coba lagi.',
          isError: true,
        );
      }
    } else if (action == 'report_message') {
      await _showReportDialog(
        title: 'Laporkan pesan',
        subtitle: 'Laporkan pesan dari ${msg.senderName} ke tim moderasi.',
        onSubmit: (reason, details) => ModerationService.instance.submitReport(
          targetType: ModerationTargetType.communityMessage,
          targetId: msg.id,
          communityId: _community.id,
          reportedUserId: msg.senderId,
          reason: reason,
          details: details,
          messageExcerpt: msg.content ?? '[${msg.messageType.name}]',
        ),
      );
    }
  }

  Future<void> _showReportDialog({
    required String title,
    required String subtitle,
    required Future<void> Function(String reason, String? details) onSubmit,
  }) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (_) => CommunityReportDialog(
        title: title,
        subtitle: subtitle,
        onSubmit: onSubmit,
      ),
    );
    if (submitted == true) {
      _showTopToast('Laporan dikirim ke tim moderasi.');
    }
  }

  Future<void> _openMediaViewer(
    CommunityMessage msg, {
    Uint8List? initialThumbnailBytes,
  }) async {
    await openCommunityMediaViewer(
      context,
      message: msg,
      currentUserId: _currentUserId,
      initialThumbnailBytes: initialThumbnailBytes,
      thumbnailCache: widget.thumbnailCache,
      onReportMedia: (target) => _showReportDialog(
        title: 'Laporkan media',
        subtitle: 'Laporkan media dari ${target.senderName} ke tim moderasi.',
        onSubmit: (reason, details) => ModerationService.instance.submitReport(
          targetType: ModerationTargetType.communityMessage,
          targetId: target.id,
          communityId: _community.id,
          reportedUserId: target.senderId,
          reason: reason,
          details: details,
          messageExcerpt: target.content ?? '[${target.messageType.name}]',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    // Terapkan inset keyboard TEPAT SATU KALI (`resizeToAvoidBottomInset: false`)
    // agar pil teks duduk tepat di atas keyboard tanpa melayang kejauhan.
    final composerBottom =
        (keyboardInset > 0 ? keyboardInset : safeBottom) + 10;
    final plus = PlusScope.maybeOf(context);
    final hasFullSocial =
        widget.hasFullSocialOverride ?? (plus?.hasFullSocialAccess ?? false);
    final canCompose = _community.isJoined && hasFullSocial;
    final nowUtc = DateTime.now().toUtc();

    const composerHeight = 52.0;
    final extraBottom = (canCompose && _replyingTo != null ? 64.0 : 0.0) +
        (canCompose && _mentionSuggestions.isNotEmpty ? 120.0 : 0.0);

    return ChatRoomCanvas(
      child: PopScope(
        canPop: !_menuOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _menuOpen) {
            setState(() => _menuOpen = false);
          }
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          extendBody: true,
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          body: ListenableBuilder(
            listenable: _muteService,
            builder: (context, _) {
              final isMuted = _muteService.isMuted('community', _community.id);
              final muteSub = chatMuteStatusShortLabel(
                _muteService,
                'community',
                _community.id,
              );
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // 1. Daftar pesan mengalir penuh di belakang header & pil input kaca
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    Center(
                      child: HiqeoStateView(
                        icon: Icons.wifi_off_rounded,
                        title: 'Pesan belum bisa dimuat',
                        message: _error!,
                        isError: true,
                        darkRoom: true,
                        actionLabel: 'Coba lagi',
                        onAction: () => unawaited(_loadMessages()),
                      ),
                    )
                  else if (_messages.isEmpty)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          ChatRoomHeaderBar.listTopPadding(topPad),
                          24,
                          composerBottom + composerHeight + 24,
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ChatDateDividerPill(label: 'Hari ini'),
                            SizedBox(height: 16),
                            Text(
                              'Belum ada pesan di komunitas ini.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ChatRoomPalette.textSecondary,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final deltaInset = keyboardInset - _lastKeyboardInset;
                        final deltaHeight = _lastViewportHeight > 0
                            ? _lastViewportHeight - constraints.maxHeight
                            : 0.0;
                        final delta =
                            deltaInset > deltaHeight ? deltaInset : deltaHeight;
                        _lastKeyboardInset = keyboardInset;
                        _lastViewportHeight = constraints.maxHeight;

                        if (delta > 24 &&
                            _scrollController.hasClients &&
                            _messages.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted || !_scrollController.hasClients) {
                              return;
                            }
                            final maxExt =
                                _scrollController.position.maxScrollExtent;
                            if ((maxExt - _scrollController.position.pixels) <=
                                180 + delta) {
                              _scrollController.jumpTo(maxExt);
                            } else {
                              _scrollController.jumpTo(
                                (_scrollController.position.pixels + delta)
                                    .clamp(0.0, maxExt),
                              );
                            }
                          });
                        }

                        final showLoadOlder = _hasMoreOlderMessages &&
                            _messages.isNotEmpty &&
                            (_firstEnteredAtUtc == null ||
                                _messages.first.createdAt
                                    .isAfter(_firstEnteredAtUtc!));
                        final Map<String, CommunityMessage> messagesById =
                            <String, CommunityMessage>{
                          for (final m in _messages) m.id: m,
                        };

                        return NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.metrics.pixels <= 40 &&
                                showLoadOlder) {
                              unawaited(_loadOlderMessages());
                            }
                            return false;
                          },
                          child: RepaintBoundary(
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: EdgeInsets.fromLTRB(
                              14,
                              ChatRoomHeaderBar.listTopPadding(topPad),
                              14,
                              composerBottom + composerHeight + 26 + extraBottom,
                            ),
                            itemCount:
                                _messages.length + (showLoadOlder ? 1 : 0),
                            itemBuilder: (context, rawIndex) {
                              if (showLoadOlder && rawIndex == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Center(
                                    child: _loadingOlderMessages
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: ChatRoomPalette
                                                  .textPrimary,
                                            ),
                                          )
                                        : TextButton(
                                            key: const ValueKey<String>(
                                              'community-load-older-btn',
                                            ),
                                            onPressed: () =>
                                                unawaited(_loadOlderMessages()),
                                            child: const Text(
                                              'Muat pesan sebelumnya',
                                            ),
                                          ),
                                  ),
                                );
                              }
                              final index =
                                  showLoadOlder ? rawIndex - 1 : rawIndex;
                              final msg = _messages[index];
                              final isMe = msg.senderId == _currentUserId;
                              final dayLabel = formatChatDayDividerLabel(
                                  msg.createdAt, nowUtc);
                              final showDayHeader = index == 0 ||
                                  formatChatDayDividerLabel(
                                        _messages[index - 1].createdAt,
                                        nowUtc,
                                      ) !=
                                      dayLabel;
                              final showUnreadDivider =
                                  _firstUnreadIndex != null &&
                                      _unreadDividerCount > 0 &&
                                      index == _firstUnreadIndex;
                              final nextHasUnreadDivider =
                                  _firstUnreadIndex != null &&
                                      _unreadDividerCount > 0 &&
                                      (index + 1) == _firstUnreadIndex;
                              final sameSenderAsPrev = !showDayHeader &&
                                  !showUnreadDivider &&
                                  index > 0 &&
                                  _messages[index - 1].senderId == msg.senderId;
                              final sameSenderAsNext = !nextHasUnreadDivider &&
                                  index + 1 < _messages.length &&
                                  formatChatDayDividerLabel(
                                        _messages[index + 1].createdAt,
                                        nowUtc,
                                      ) ==
                                      dayLabel &&
                                  _messages[index + 1].senderId == msg.senderId;
                              final cluster = ChatBubbleCluster.compute(
                                sameSenderAsPrev: sameSenderAsPrev,
                                sameSenderAsNext: sameSenderAsNext,
                              );
                              final replyTarget =
                                  _replyTargetFor(msg, messagesById);
                              final itemKey = _messageItemKeys.putIfAbsent(
                                msg.id,
                                GlobalKey.new,
                              );

                              return Column(
                                key: itemKey,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  if (showDayHeader)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: index == 0 ? 0 : 8,
                                        bottom: 10,
                                      ),
                                      child: Center(
                                        child: ChatDateDividerPill(
                                          label: dayLabel,
                                        ),
                                      ),
                                    ),
                                  if (showUnreadDivider)
                                    Padding(
                                      key: _unreadDividerKey,
                                      padding: const EdgeInsets.only(
                                        top: 4,
                                        bottom: 10,
                                      ),
                                      child: Center(
                                        child: ChatUnreadDividerPill(
                                          count: _unreadDividerCount,
                                        ),
                                      ),
                                    ),
                                  _CommunityBubble(
                                    message: msg,
                                    isMe: isMe,
                                    cluster: cluster,
                                    replyTarget: replyTarget,
                                    isHighlighted:
                                        _highlightedMessageId == msg.id,
                                    thumbnailCache: widget.thumbnailCache,
                                    onReply: (!hasFullSocial || msg.isDeleted)
                                        ? null
                                        : () {
                                            setState(() => _replyingTo = msg);
                                            _composerFocusNode.requestFocus();
                                          },
                                    onTapReplyQuote: msg.replyToMessageId != null
                                        ? () => _jumpToAndHighlightMessage(
                                              msg.replyToMessageId!,
                                            )
                                        : null,
                                    onLongPress: (isMe && !msg.isDeleted)
                                        ? () => unawaited(
                                              _showOwnMessageDeleteSheet(msg),
                                            )
                                        : null,
                                    onTapSender: () => _onTapSender(
                                      msg,
                                      hasFullSocialAccess: hasFullSocial,
                                    ),
                                    onTapMedia: (thumbBytes) => unawaited(
                                      _openMediaViewer(
                                        msg,
                                        initialThumbnailBytes: thumbBytes,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                            ),
                          ),
                        );
                      },
                    ),

                  // 2. Header Atas Liquid Glass melayang seragam dengan Ruang Obrolan Grup
                  Positioned(
                    top: topPad + ChatRoomHeaderBar.topMargin,
                    left: 14,
                    right: 14,
                    child: ChatRoomHeaderBar(
                      headerPillKey: const ValueKey('community-glass-header'),
                      headerTapKey:
                          const ValueKey<String>('community-header-info-btn'),
                      headerSemanticsLabel: 'Info komunitas',
                      onHeaderTap: () => unawaited(_showCommunityInfoSheet()),
                      avatarUrl: _community.avatarUrl,
                      avatarCacheKey: 'community_${_community.id}',
                      fallbackIcon: Icons.groups_rounded,
                      title: _community.name,
                      subtitle: '${_community.memberCount} anggota',
                      isOnline: true,
                      showPresenceDot: false,
                      isMuted: isMuted,
                      badgeLabel: 'Komunitas',
                      badgeIcon: Icons.public_rounded,
                      badgeColor: ChatRoomPalette.badgeCommunityText,
                      menuButtonKey:
                          const ValueKey('community-hamburger-button'),
                      menuSemanticsLabel: 'Menu komunitas',
                      onMenuTap: _toggleHamburgerMenu,
                    ),
                  ),

                  // 3. Toast galat/info melayang di bagian atas (tidak terhalang keyboard)
                  if (_topToastText != null)
                    Positioned(
                      top: ChatRoomHeaderBar.dropdownTop(topPad),
                      left: 16,
                      right: 16,
                      child: GestureDetector(
                        key: const ValueKey<String>('community-top-toast'),
                        onTap: () => setState(() => _topToastText = null),
                        child: HiqeoLiquidGlassSurface(
                          borderRadius: 18,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                _topToastIsError
                                    ? Icons.error_outline_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 18,
                                color: _topToastIsError
                                    ? ChatRoomPalette.destructiveRed
                                    : ChatRoomPalette.statusOnline,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _topToastText!,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: ChatRoomPalette.textPrimary,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: ChatRoomPalette.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 4. Bilah Input Bawah Liquid Glass melayang (tanpa wadah solid di belakang)
                  Positioned(
                    key: const ValueKey<String>('community-composer-position'),
                    left: 14,
                    right: 14,
                    bottom: composerBottom,
                    child: !_community.isJoined
                        ? Semantics(
                            button: true,
                            label: 'Gabung / Ikuti komunitas',
                            child: GestureDetector(
                              key: const ValueKey<String>(
                                'community-join-button',
                              ),
                              behavior: HitTestBehavior.opaque,
                              onTap: _joining
                                  ? null
                                  : () => unawaited(
                                        _handleJoinCommunity(
                                          hasFullSocial: hasFullSocial,
                                        ),
                                      ),
                              child: HiqeoLiquidGlassSurface(
                                borderRadius: 26,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                child: Center(
                                  child: _joining
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: ChatRoomPalette.textPrimary,
                                          ),
                                        )
                                      : const Text(
                                          'Gabung / Ikuti komunitas',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: ChatRoomPalette.textPrimary,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          )
                        : hasFullSocial
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  if (_mentionSuggestions.isNotEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: CommunityMentionSuggestionsOverlay(
                                        suggestions: _mentionSuggestions,
                                        onSelect: _selectMention,
                                      ),
                                    ),
                                  if (_replyingTo != null)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: CommunityReplyPreviewBar(
                                        replyingTo: _replyingTo!,
                                        resolvedSenderName:
                                            PublicProfileCacheService.instance
                                                .resolveDisplayName(
                                          _replyingTo!.senderId,
                                          fallback: _replyingTo!.senderName,
                                        ),
                                        onCancel: () =>
                                            setState(() => _replyingTo = null),
                                      ),
                                    ),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: <Widget>[
                                      Expanded(
                                        child: HiqeoLiquidGlassSurface(
                                          key: const ValueKey(
                                            'community-glass-composer',
                                          ),
                                          borderRadius: 26,
                                          padding: const EdgeInsets.only(
                                            left: 16,
                                            right: 6,
                                          ),
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              minHeight: 50,
                                            ),
                                            child: Row(
                                              children: <Widget>[
                                                Expanded(
                                                  child: TextField(
                                                    key: const ValueKey(
                                                      'community-input',
                                                    ),
                                                    controller: _textController,
                                                    focusNode:
                                                        _composerFocusNode,
                                                    minLines: 1,
                                                    maxLines: 4,
                                                    maxLength: 2000,
                                                    style: const TextStyle(
                                                      fontSize: 14.5,
                                                      color: ChatRoomPalette
                                                          .textPrimary,
                                                    ),
                                                    decoration:
                                                        const InputDecoration(
                                                      hintText:
                                                          'Tulis pesan komunitas…',
                                                      hintStyle: TextStyle(
                                                        color: ChatRoomPalette
                                                            .textSecondary,
                                                        fontSize: 14,
                                                      ),
                                                      counterText: '',
                                                      border: InputBorder.none,
                                                      isDense: true,
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Semantics(
                                                  button: true,
                                                  label:
                                                      'Buka kamera komunitas',
                                                  child: GestureDetector(
                                                    key: const ValueKey(
                                                      'community-camera-button',
                                                    ),
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onTap: _sending
                                                        ? null
                                                        : _openFullScreenCamera,
                                                    child: const SizedBox(
                                                      width: 44,
                                                      height: 44,
                                                      child: Center(
                                                        child: Icon(
                                                          Icons
                                                              .camera_alt_outlined,
                                                          size: 22,
                                                          color: ChatRoomPalette
                                                              .textPrimary,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      HiqeoGlassCircleButton(
                                        key: const ValueKey(
                                          'community-send-button',
                                        ),
                                        semanticsLabel: 'Kirim pesan komunitas',
                                        size: 50,
                                        emphasized: _hasText,
                                        onTap: _sending ? null : _sendText,
                                        child: _sending
                                            ? const Padding(
                                                padding: EdgeInsets.all(13),
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: ChatRoomPalette
                                                      .textPrimary,
                                                ),
                                              )
                                            : Icon(
                                                Icons.send_rounded,
                                                size: 20,
                                                color: _hasText
                                                    ? ChatRoomPalette
                                                        .textPrimary
                                                    : ChatRoomPalette
                                                        .textSecondary,
                                              ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : HiqeoLiquidGlassSurface(
                                key: const ValueKey('community-glass-composer'),
                                borderRadius: 24,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    const Expanded(
                                      child: Text(
                                        'Kirim pesan komunitas khusus Hiqeo Plus Mahasiswa atau Tahunan.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: ChatRoomPalette.textSecondary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      key: const ValueKey<String>(
                                        'community-upgrade-plus-button',
                                      ),
                                      onPressed:
                                          _openPlusUpgradeFromCommunity,
                                      child: const Text(
                                        'Hiqeo Plus',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: ChatRoomPalette.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                  ),

                  // 5. Overlay Menu Dropdown Melayang (Kanan Atas, tepat 12 px di bawah header)
                  if (_menuOpen) ...<Widget>[
                    Positioned.fill(
                      child: GestureDetector(
                        key: const ValueKey<String>('community-dropdown-scrim'),
                        behavior: HitTestBehavior.translucent,
                        onTap: () => setState(() => _menuOpen = false),
                      ),
                    ),
                    Positioned(
                      top: ChatRoomHeaderBar.dropdownTop(topPad),
                      right: 14,
                      child: ChatRoomDropdownMenu(
                        menuKey: const ValueKey<String>(
                          'community-dropdown-menu',
                        ),
                        entries: <ChatRoomMenuEntry>[
                          if (_isOwner)
                            ChatRoomMenuEntry.item(
                              key: const ValueKey('community-menu-edit'),
                              icon: Icons.edit_outlined,
                              label: 'Edit komunitas',
                              onTap: () =>
                                  _runMenuAction(_showEditCommunityDialog),
                            ),
                          ChatRoomMenuEntry.item(
                            key: const ValueKey('community-menu-mute'),
                            icon: isMuted
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_outlined,
                            label: 'Bisukan notifikasi',
                            subtitle: muteSub.isNotEmpty ? muteSub : null,
                            onTap: () => _runMenuAction(
                              () => showChatMuteSheet(
                                context,
                                roomType: 'community',
                                roomId: _community.id,
                                roomName: _community.name,
                                muteService: _muteService,
                              ),
                            ),
                          ),
                          ChatRoomMenuEntry.item(
                            key: const ValueKey('community-menu-report'),
                            icon: Icons.flag_outlined,
                            label: 'Laporkan komunitas',
                            onTap: () =>
                                _runMenuAction(_showReportCommunityDialog),
                          ),
                          if (_community.isJoined || _isOwner)
                            const ChatRoomMenuEntry.divider(),
                          if (_community.isJoined)
                            ChatRoomMenuEntry.item(
                              key: const ValueKey('community-menu-leave'),
                              icon: Icons.logout_rounded,
                              label: 'Keluar komunitas',
                              destructive: true,
                              onTap: () =>
                                  _runMenuAction(_confirmLeaveCommunity),
                            ),
                          if (_isOwner)
                            ChatRoomMenuEntry.item(
                              key: const ValueKey('community-menu-delete'),
                              icon: Icons.delete_outline_rounded,
                              label: 'Hapus komunitas',
                              destructive: true,
                              onTap: () =>
                                  _runMenuAction(_confirmDeleteCommunity),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class CommunityReportDialog extends StatefulWidget {
  const CommunityReportDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onSubmit,
  });

  final String title;
  final String subtitle;
  final Future<void> Function(String reason, String? details) onSubmit;

  @override
  State<CommunityReportDialog> createState() => _CommunityReportDialogState();
}

class _CommunityReportDialogState extends State<CommunityReportDialog> {
  final TextEditingController _detailsCtrl = TextEditingController();
  String _selectedReason = ModerationService.defaultReasons.first;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_selectedReason, _detailsCtrl.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityReportDialog failed: $e');
      }
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Laporan belum terkirim. Periksa sinyal lalu coba lagi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.subtitle, style: const TextStyle(fontSize: 13.5)),
            const SizedBox(height: 12),
            for (final reason in ModerationService.defaultReasons)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _submitting
                    ? null
                    : () => setState(() => _selectedReason = reason),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        _selectedReason == reason
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 20,
                        color: _selectedReason == reason
                            ? colors.primary
                            : colors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          reason,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailsCtrl,
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Detail tambahan (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(fontSize: 12, color: colors.warningText),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Mengirim…' : 'Kirim laporan'),
        ),
      ],
    );
  }
}

class _CommunityBubble extends StatelessWidget {
  const _CommunityBubble({
    required this.message,
    required this.isMe,
    required this.cluster,
    required this.onTapSender,
    required this.onTapMedia,
    this.replyTarget,
    this.isHighlighted = false,
    this.onReply,
    this.onTapReplyQuote,
    this.onLongPress,
    this.thumbnailCache,
  });

  final CommunityMessage message;
  final bool isMe;
  final ChatBubbleCluster cluster;
  final VoidCallback onTapSender;
  final void Function(Uint8List? thumbnailBytes) onTapMedia;
  final CommunityMessage? replyTarget;
  final bool isHighlighted;
  final VoidCallback? onReply;
  final VoidCallback? onTapReplyQuote;
  final VoidCallback? onLongPress;
  final CommunityVideoThumbnailCache? thumbnailCache;

  Widget? _buildQuoteBox(PublicProfileCacheService cache) {
    if (message.replyToMessageId == null || message.replyToMessageId!.isEmpty) {
      return null;
    }
    final target = replyTarget;
    final replySender = target != null
        ? cache.resolveDisplayName(target.senderId, fallback: target.senderName)
        : (message.replyToSenderName?.trim().isNotEmpty == true
            ? message.replyToSenderName!.trim()
            : 'Pendaki');
    final replyDeleted =
        (target?.isDeleted ?? false) || message.replyToIsDeleted;
    final replyType = target?.messageType ??
        message.replyToMessageType ??
        CommunityMessageType.text;
    final rawContent = target?.content ?? message.replyToContent;
    final IconData? mediaIcon = switch (replyType) {
      CommunityMessageType.image => Icons.photo_camera_outlined,
      CommunityMessageType.video => Icons.videocam_outlined,
      CommunityMessageType.text => null,
    };
    final snippet = switch (replyType) {
      CommunityMessageType.image =>
        rawContent?.trim().isNotEmpty == true ? rawContent!.trim() : 'Foto',
      CommunityMessageType.video =>
        rawContent?.trim().isNotEmpty == true ? rawContent!.trim() : 'Video',
      CommunityMessageType.text =>
        rawContent?.trim().isNotEmpty == true ? rawContent!.trim() : 'Pesan',
    };
    final thumbUrl = target == null
        ? null
        : (target.messageType == CommunityMessageType.video
            ? target.mediaThumbnailUrl
            : target.mediaUrl);
    return CommunityReplyQuoteBox(
      senderName: replySender,
      snippet: snippet,
      outgoing: isMe,
      mediaIcon: mediaIcon,
      thumbnailUrl: thumbUrl,
      isDeleted: replyDeleted,
      onTap: onTapReplyQuote ?? () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PublicProfileCacheService.instance,
      builder: (context, _) {
        final cache = PublicProfileCacheService.instance;
        final senderName = cache.resolveDisplayName(
          message.senderId,
          fallback: message.senderName,
        );
        final senderAvatarUrl = cache.resolveAvatarUrl(
          message.senderId,
          fallback: message.senderAvatarUrl,
        );
        final screenWidth = MediaQuery.sizeOf(context).width;
        final textColor =
            isMe ? ChatRoomPalette.outgoingText : ChatRoomPalette.incomingText;
        final metaColor =
            isMe ? ChatRoomPalette.outgoingMeta : ChatRoomPalette.incomingMeta;
        final mentionColor =
            isMe ? const Color(0xFF1D4ED8) : const Color(0xFF7DD3FC);
        final senderColor = ChatRoomPalette.senderPastel(message.senderId);
        final showSenderName = !isMe && cluster.isFirstInGroup;
        final localTime = message.createdAt.toLocal();
        final hh = localTime.hour.toString().padLeft(2, '0');
        final mm = localTime.minute.toString().padLeft(2, '0');
        final timeStr = '$hh:$mm';
        final isDeleted = message.isDeleted;
        final isPhoto = !isDeleted &&
            message.messageType == CommunityMessageType.image &&
            message.mediaUrl != null;
        final isVideo = !isDeleted &&
            message.messageType == CommunityMessageType.video &&
            message.mediaUrl != null;
        final hasCaption =
            message.content != null && message.content!.isNotEmpty;
        final maxMediaWidth = screenWidth * 0.74;
        final quoteBox = isDeleted ? null : _buildQuoteBox(cache);

        final Widget bubble;
        if (isDeleted) {
          bubble = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: screenWidth * 0.76),
            child: DecoratedBox(
              key: ValueKey<String>('community-bubble-${message.id}'),
              decoration:
                  chatBubbleDecoration(outgoing: isMe, cluster: cluster),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 9, 13, 8),
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (showSenderName)
                        GestureDetector(
                          key: ValueKey<String>(
                            'community-msg-sender-${message.id}',
                          ),
                          onTap: onTapSender,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              senderName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: senderColor,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        'Pesan telah dihapus',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontStyle: FontStyle.italic,
                          color: metaColor,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _CommunityMetaRow(
                          timeStr: timeStr,
                          isMe: isMe,
                          metaColor: metaColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        } else if (isPhoto) {
          bubble = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxMediaWidth + 10),
            child: DecoratedBox(
              key: ValueKey<String>('community-bubble-${message.id}'),
              decoration:
                  chatBubbleDecoration(outgoing: isMe, cluster: cluster),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (showSenderName)
                      GestureDetector(
                        onTap: onTapSender,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(7, 3, 7, 5),
                          child: Text(
                            senderName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: senderColor,
                            ),
                          ),
                        ),
                      ),
                    if (quoteBox != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(7, 2, 7, 2),
                        child: quoteBox,
                      ),
                    _AdaptiveCommunityPhoto(
                      message: message,
                      maxWidth: maxMediaWidth,
                      timeStr: timeStr,
                      isMe: isMe,
                      onTap: () => onTapMedia(null),
                    ),
                    if (hasCaption)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(7, 7, 7, 4),
                        child: Text.rich(
                          TextSpan(
                            children: buildHighlightedMentionSpans(
                              message.content!,
                              baseStyle: TextStyle(
                                fontSize: 13.8,
                                height: 1.35,
                                color: textColor,
                              ),
                              mentionStyle: TextStyle(
                                fontSize: 13.8,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                                color: mentionColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        } else if (isVideo) {
          bubble = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxMediaWidth + 10),
            child: DecoratedBox(
              key: ValueKey<String>('community-bubble-${message.id}'),
              decoration:
                  chatBubbleDecoration(outgoing: isMe, cluster: cluster),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (showSenderName)
                      GestureDetector(
                        onTap: onTapSender,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(7, 3, 7, 5),
                          child: Text(
                            senderName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: senderColor,
                            ),
                          ),
                        ),
                      ),
                    if (quoteBox != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(7, 2, 7, 2),
                        child: quoteBox,
                      ),
                    _InlineVideoCard(
                      messageId: message.id,
                      url: MediaUrlNormalizer.normalize(message.mediaUrl!) ??
                          message.mediaUrl!,
                      thumbnailUrl: MediaUrlNormalizer.normalize(
                        message.mediaThumbnailUrl,
                      ),
                      maxWidth: maxMediaWidth,
                      durationSec: message.mediaDurationSec,
                      thumbnailCache: thumbnailCache,
                      onOpenFullscreen: onTapMedia,
                    ),
                    if (hasCaption)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(7, 7, 7, 2),
                        child: Text.rich(
                          TextSpan(
                            children: buildHighlightedMentionSpans(
                              message.content!,
                              baseStyle: TextStyle(
                                fontSize: 13.8,
                                height: 1.35,
                                color: textColor,
                              ),
                              mentionStyle: TextStyle(
                                fontSize: 13.8,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                                color: mentionColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(7, 4, 7, 3),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _CommunityMetaRow(
                          timeStr: timeStr,
                          isMe: isMe,
                          metaColor: metaColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          bubble = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: screenWidth * 0.76),
            child: DecoratedBox(
              key: ValueKey<String>('community-bubble-${message.id}'),
              decoration:
                  chatBubbleDecoration(outgoing: isMe, cluster: cluster),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 9, 13, 8),
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (showSenderName)
                        GestureDetector(
                          key: ValueKey<String>(
                            'community-msg-sender-${message.id}',
                          ),
                          onTap: onTapSender,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              senderName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: senderColor,
                              ),
                            ),
                          ),
                        ),
                      if (quoteBox != null) quoteBox,
                      if (hasCaption)
                        Text.rich(
                          TextSpan(
                            children: buildHighlightedMentionSpans(
                              message.content!,
                              baseStyle: TextStyle(
                                fontSize: 14.2,
                                height: 1.38,
                                color: textColor,
                              ),
                              mentionStyle: TextStyle(
                                fontSize: 14.2,
                                height: 1.38,
                                fontWeight: FontWeight.w700,
                                color: mentionColor,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 3),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _CommunityMetaRow(
                          timeStr: timeStr,
                          isMe: isMe,
                          metaColor: metaColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final interactiveBubble = (onLongPress != null && !isDeleted)
            ? GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPress: onLongPress,
                child: bubble,
              )
            : bubble;

        final rowContent = Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (!isMe)
              ChatSenderAvatarSlot(
                visible: cluster.isLastInGroup,
                senderId: message.senderId,
                senderName: senderName,
                avatarUrl: senderAvatarUrl,
                avatarKey: cluster.isLastInGroup
                    ? ValueKey<String>('community-msg-avatar-${message.id}')
                    : null,
                onTap: cluster.isLastInGroup ? onTapSender : null,
              ),
            Flexible(child: interactiveBubble),
          ],
        );

        return Padding(
          padding: EdgeInsets.only(bottom: cluster.bottomGap),
          child: SwipeToReplyWrapper(
            enabled: !isDeleted && onReply != null,
            onReply: onReply ?? () {},
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: isHighlighted
                  ? const EdgeInsets.symmetric(horizontal: 4, vertical: 3)
                  : EdgeInsets.zero,
              decoration: isHighlighted
                  ? BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.45),
                      ),
                    )
                  : null,
              child: rowContent,
            ),
          ),
        );
      },
    );
  }
}

class _CommunityMetaRow extends StatelessWidget {
  const _CommunityMetaRow({
    required this.timeStr,
    required this.isMe,
    required this.metaColor,
  });

  final String timeStr;
  final bool isMe;
  final Color metaColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          timeStr,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: metaColor,
          ),
        ),
        if (isMe) ...<Widget>[
          const SizedBox(width: 4),
          Icon(
            Icons.check_rounded,
            size: 14,
            color: metaColor,
          ),
        ],
      ],
    );
  }
}

class _AdaptiveCommunityPhoto extends StatefulWidget {
  const _AdaptiveCommunityPhoto({
    required this.message,
    required this.maxWidth,
    required this.timeStr,
    required this.isMe,
    required this.onTap,
  });

  final CommunityMessage message;
  final double maxWidth;
  final String timeStr;
  final bool isMe;
  final VoidCallback onTap;

  @override
  State<_AdaptiveCommunityPhoto> createState() =>
      _AdaptiveCommunityPhotoState();
}

class _AdaptiveCommunityPhotoState extends State<_AdaptiveCommunityPhoto> {
  static final Map<String, double> _aspectCache = <String, double>{};

  double? _aspectRatio;
  int _probeGen = 0;
  ImageStream? _imageStream;
  ImageStreamListener? _streamListener;

  @override
  void initState() {
    super.initState();
    _aspectRatio = _aspectCache[widget.message.mediaUrl ?? ''];
    _resolveNaturalRatio();
  }

  @override
  void didUpdateWidget(covariant _AdaptiveCommunityPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.mediaUrl != widget.message.mediaUrl) {
      _detachStream();
      _aspectRatio = _aspectCache[widget.message.mediaUrl ?? ''];
      _resolveNaturalRatio();
    }
  }

  @override
  void dispose() {
    _detachStream();
    super.dispose();
  }

  void _detachStream() {
    if (_imageStream != null && _streamListener != null) {
      _imageStream!.removeListener(_streamListener!);
    }
    _imageStream = null;
    _streamListener = null;
  }

  void _resolveNaturalRatio() {
    final rawUrl = widget.message.mediaUrl;
    final url = MediaUrlNormalizer.normalize(rawUrl) ?? rawUrl;
    if (url == null || url.isEmpty || _aspectRatio != null) return;

    if (!MediaUrlNormalizer.isNetworkUrl(url)) {
      _attachAspectListener(ResizeImage(FileImage(File(url)), width: 256), url);
      return;
    }

    final syncCached = HiqeoMediaCacheService.instance.cachedFileSync(url);
    if (syncCached != null) {
      _attachAspectListener(
        ResizeImage(FileImage(syncCached), width: 256),
        url,
      );
      return;
    }
    final gen = ++_probeGen;
    unawaited(() async {
      final resolved =
          await HiqeoMediaCacheService.instance.resolveMediaFile(url);
      if (!mounted ||
          gen != _probeGen ||
          resolved == null ||
          _aspectRatio != null) {
        return;
      }
      _attachAspectListener(ResizeImage(FileImage(resolved), width: 256), url);
    }());
  }

  void _attachAspectListener(ImageProvider provider, String cacheKey) {
    _detachStream();
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w > 0 && h > 0) {
          final ratio = w / h;
          _aspectCache[cacheKey] = ratio;
          if (mounted) setState(() => _aspectRatio = ratio);
        }
        _detachStream();
      },
      onError: (_, __) => _detachStream(),
    );
    _imageStream = stream;
    _streamListener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final rawUrl = widget.message.mediaUrl!;
    final url = MediaUrlNormalizer.normalize(rawUrl) ?? rawUrl;
    final isLocalFile = !MediaUrlNormalizer.isNetworkUrl(url);
    final box = computeAdaptiveMediaBoxSize(
      maxWidth: widget.maxWidth,
      minHeight: 140,
      maxHeight: 340,
      aspectRatio: _aspectRatio,
    );
    final int decodeWidth = (box.width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(240, 900);
    final Widget brokenFallback = SizedBox(
      width: box.width,
      height: box.height,
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
        ),
      ),
    );
    final Widget imageWidget = isLocalFile
        ? Image.file(
            File(url),
            fit: BoxFit.contain,
            width: box.width,
            height: box.height,
            cacheWidth: decodeWidth,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => brokenFallback,
          )
        : PersistentMediaImage(
            url: url,
            fit: BoxFit.contain,
            width: box.width,
            height: box.height,
            cacheWidth: decodeWidth,
            errorBuilder: (_) => brokenFallback,
          );

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.maxWidth,
            minHeight: 140,
            maxHeight: 340,
          ),
          child: ClipRRect(
            key: ValueKey<String>('community-photo-frame-${widget.message.id}'),
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
              color: const Color(0xFF141926),
              child: SizedBox(
                width: box.width,
                height: box.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Hero(
                      tag: communityMediaHeroTag(widget.message.id),
                      child: imageWidget,
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        key: ValueKey<String>(
                          'community-photo-time-${widget.message.id}',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.56),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              widget.timeStr,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            if (widget.isMe) ...<Widget>[
                              const SizedBox(width: 3),
                              const Icon(
                                Icons.check_rounded,
                                size: 13,
                                color: Color(0xFFB3BCD2),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineVideoCard extends StatefulWidget {
  const _InlineVideoCard({
    required this.messageId,
    required this.url,
    required this.maxWidth,
    required this.onOpenFullscreen,
    this.thumbnailUrl,
    this.durationSec,
    this.thumbnailCache,
  });

  final String messageId;
  final String url;
  final String? thumbnailUrl;
  final double maxWidth;
  final int? durationSec;
  final CommunityVideoThumbnailCache? thumbnailCache;
  final void Function(Uint8List? thumbnailBytes) onOpenFullscreen;

  @override
  State<_InlineVideoCard> createState() => _InlineVideoCardState();
}

class _InlineVideoCardState extends State<_InlineVideoCard> {
  VideoPlayerController? _controller;
  Uint8List? _thumbBytes;
  double? _aspectRatio;
  bool _initialized = false;
  bool _isPlaying = false;
  bool _playedInline = false;
  late String _badgeText;

  CommunityVideoThumbnailCache get _cache =>
      widget.thumbnailCache ?? CommunityVideoThumbnailCache.instance;

  @override
  void initState() {
    super.initState();
    _badgeText = formatVideoDurationSeconds(widget.durationSec ?? 0);
    _thumbBytes = _cache.getMemoryBytes(
      widget.url,
      messageId: widget.messageId,
    );
    _aspectRatio = _cache.getAspectRatio(widget.url);
    if (_thumbBytes != null && _aspectRatio == null) {
      unawaited(_decodeThumbAspect(_thumbBytes!));
    }
    unawaited(_loadCover());
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      c.removeListener(_onControllerTick);
      unawaited(c.dispose().catchError((Object _) {}));
    }
    super.dispose();
  }

  Future<void> _decodeThumbAspect(Uint8List bytes) async {
    try {
      final decoded = await decodeImageFromList(bytes);
      final w = decoded.width.toDouble();
      final h = decoded.height.toDouble();
      if (w > 0 && h > 0) {
        final ratio = w / h;
        _cache.setAspectRatio(widget.url, ratio);
        if (mounted) setState(() => _aspectRatio = ratio);
      }
    } catch (_) {}
  }

  Future<void> _loadCover() async {
    final cached = await _cache.resolveThumbnail(
      videoUrl: widget.url,
      thumbnailUrl: widget.thumbnailUrl,
      messageId: widget.messageId,
    );
    if (!mounted) return;
    if (cached != null && cached.isNotEmpty) {
      setState(() => _thumbBytes = cached);
      if (_aspectRatio == null) {
        await _decodeThumbAspect(cached);
      }
      return;
    }

    // Fallback bila platform tidak mendukung MediaMetadataRetriever & URL valid:
    // inisialisasi frame pertama (Duration.zero) tanpa langsung memutar.
    final normalizedUrl =
        MediaUrlNormalizer.normalize(widget.url) ?? widget.url;
    final resolvedSource =
        await HiqeoMediaCacheService.instance.resolvePlayableVideoSource(
      normalizedUrl,
    );
    if (!mounted) return;
    VideoPlayerController? c;
    try {
      if (resolvedSource.file != null) {
        c = VideoPlayerController.file(resolvedSource.file!);
      } else {
        final streamUri =
            Uri.tryParse(resolvedSource.streamUrl ?? normalizedUrl);
        if (streamUri == null ||
            (streamUri.scheme != 'http' && streamUri.scheme != 'https')) {
          return;
        }
        c = VideoPlayerController.networkUrl(
          streamUri,
          httpHeaders: const <String, String>{
            'User-Agent': HiqeoHttpOverrides.userAgent,
          },
        );
      }
      await c.initialize().timeout(const Duration(seconds: 15));
      if (!mounted) {
        unawaited(c.dispose().catchError((Object _) {}));
        return;
      }
      _controller = c;
      c.addListener(_onControllerTick);
      await c.seekTo(Duration.zero);
      await c.pause();
      if (!mounted) return;
      final ar = c.value.aspectRatio;
      if (ar.isFinite && ar > 0) {
        _cache.setAspectRatio(widget.url, ar);
      }
      setState(() {
        _initialized = true;
        if (ar.isFinite && ar > 0) _aspectRatio = ar;
        _badgeText = formatVideoRemainingBadge(
          total: c!.value.duration,
          position: c.value.position,
          isPlaying: c.value.isPlaying,
          fallbackTotalSec: widget.durationSec,
        );
      });
    } catch (_) {
      _controller = null;
      if (c != null) {
        c.removeListener(_onControllerTick);
        unawaited(c.dispose().catchError((Object _) {}));
      }
    }
  }

  void _onControllerTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final val = c.value;
    if (val.isPlaying) _playedInline = true;

    if (_playedInline &&
        val.isInitialized &&
        !val.isPlaying &&
        val.duration > Duration.zero &&
        val.position >= val.duration - const Duration(milliseconds: 120)) {
      _playedInline = false;
      unawaited(
        c.seekTo(Duration.zero).then((_) async {
          await c.pause();
          if (mounted) _syncBadgeFromController(c);
        }),
      );
      return;
    }
    _syncBadgeFromController(c);
  }

  void _syncBadgeFromController(VideoPlayerController c) {
    final v = c.value;
    final nextBadge = formatVideoRemainingBadge(
      total: v.duration,
      position: v.position,
      isPlaying: v.isPlaying,
      fallbackTotalSec: widget.durationSec,
    );
    if (_isPlaying == v.isPlaying && _badgeText == nextBadge) return;
    setState(() {
      _isPlaying = v.isPlaying;
      _badgeText = nextBadge;
    });
  }

  Future<void> _toggleInlinePlay() async {
    try {
      var c = _controller;
      if (c == null) {
        final normalizedUrl =
            MediaUrlNormalizer.normalize(widget.url) ?? widget.url;
        final resolvedSource =
            await HiqeoMediaCacheService.instance.resolvePlayableVideoSource(
          normalizedUrl,
        );
        if (!mounted) return;
        if (resolvedSource.file != null) {
          c = VideoPlayerController.file(resolvedSource.file!);
        } else {
          final streamUrl = resolvedSource.streamUrl ?? normalizedUrl;
          c = VideoPlayerController.networkUrl(
            Uri.parse(streamUrl),
            httpHeaders: const <String, String>{
              'User-Agent': HiqeoHttpOverrides.userAgent,
            },
          );
        }
        _controller = c;
        c.addListener(_onControllerTick);
        await c.initialize();
        if (!mounted) return;
        _initialized = true;
        final ar = c.value.aspectRatio;
        if (ar.isFinite && ar > 0) _aspectRatio = ar;
      }
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        if (c.value.duration > Duration.zero &&
            c.value.position >=
                c.value.duration - const Duration(milliseconds: 120)) {
          await c.seekTo(Duration.zero);
        }
        _playedInline = true;
        await c.play();
      }
      if (mounted) _syncBadgeFromController(c);
    } catch (_) {}
  }

  void _handleOpenFullscreen() {
    if (_controller?.value.isPlaying ?? false) {
      unawaited(_controller?.pause());
    }
    widget.onOpenFullscreen(_thumbBytes);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final box = computeAdaptiveMediaBoxSize(
      maxWidth: widget.maxWidth,
      minHeight: 140,
      maxHeight: 340,
      aspectRatio: _aspectRatio,
    );
    final showBadge = widget.durationSec != null || _initialized;
    final int decodeWidth = (box.width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(240, 900);

    return RepaintBoundary(
      child: GestureDetector(
        key: ValueKey<String>('community-video-card-${widget.messageId}'),
        onTap: _handleOpenFullscreen,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.maxWidth,
            minHeight: 140,
            maxHeight: 340,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
              color: const Color(0xFF141926),
              child: SizedBox(
                width: box.width,
                height: box.height,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Hero(
                      tag: communityMediaHeroTag(widget.messageId),
                      child: (_initialized && c != null)
                          ? Center(
                              child: AspectRatio(
                                aspectRatio: c.value.aspectRatio > 0
                                    ? c.value.aspectRatio
                                    : 16 / 9,
                                child: VideoPlayer(c),
                              ),
                            )
                          : (_thumbBytes != null
                              ? AnimatedOpacity(
                                  opacity: 1.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Image.memory(
                                    _thumbBytes!,
                                    fit: BoxFit.contain,
                                    width: box.width,
                                    height: box.height,
                                    cacheWidth: decodeWidth,
                                  ),
                                )
                              : const SizedBox.shrink()),
                    ),
                    if (!_initialized || !_isPlaying)
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white70),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    Positioned(
                      left: 8,
                      bottom: 6,
                      child: GestureDetector(
                        key: ValueKey<String>(
                          'community-video-inline-play-${widget.messageId}',
                        ),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => unawaited(_toggleInlinePlay()),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.56),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    if (showBadge)
                      Positioned(
                        right: 8,
                        bottom: 6,
                        child: Container(
                          key: ValueKey<String>(
                            'community-video-duration-${widget.messageId}',
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.56),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _badgeText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
