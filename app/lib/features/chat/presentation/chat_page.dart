import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

import '../../../core/utils/clock.dart';
import '../../../design/glass/glass_surface.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_chat_repository.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../auth/application/account_controller.dart';
import '../../groups/application/group_selection.dart';
import '../../groups/domain/group_remote_service.dart';
import '../../safety/domain/payloads.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';

/// Layar Grup: percakapan grup terbaru. Pesan disimpan di database perangkat;
/// pengiriman ke anggota lain belum punya transport, sehingga status pesan
/// keluar jujur berhenti di "Tersimpan di HP · belum terkirim".
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    this.accountController,
    this.chatRepository,
    this.clock = const SystemClock(),
  });

  /// Disuntikkan untuk uji; produksi memakai layanan yang tersedia.
  final AccountController? accountController;
  final ChatRepository? chatRepository;
  final Clock clock;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final AccountController _account;
  late final bool _ownsAccount;

  AppDatabase? _database;
  ChatRepository? _chat;
  bool _ownsChat = false;
  bool _chatOpening = false;
  String? _chatOpenError;

  String? _groupId;
  String? _groupName;
  String? _userId;

  List<MemberDirectoryEntry> _members = const <MemberDirectoryEntry>[];
  bool _membersLoading = false;
  String? _membersError;
  int _rosterGeneration = 0;

  List<ChatMessage> _messages = const <ChatMessage>[];
  bool _messagesLoading = true;
  String? _messagesError;
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  int _messageGeneration = 0;

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _ownsAccount = widget.accountController == null;
    _account =
        widget.accountController ?? SupabaseServices.createAccountController();
    _account.initialize();
    _account.addListener(_onAccountChanged);
    _input.addListener(_onInputChanged);

    final injected = widget.chatRepository;
    if (injected != null) {
      _chat = injected;
      _syncAccount();
    } else {
      unawaited(_openRepository());
    }
  }

  @override
  void dispose() {
    _account.removeListener(_onAccountChanged);
    if (_ownsAccount) _account.dispose();
    unawaited(_messageSubscription?.cancel());
    _input
      ..removeListener(_onInputChanged)
      ..dispose();
    _scroll.dispose();
    if (_ownsChat) unawaited(_database?.close());
    super.dispose();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openRepository() async {
    setState(() {
      _chatOpening = true;
      _chatOpenError = null;
    });
    try {
      final file = await defaultAppDatabaseFile();
      final database = openAppDatabase(file);
      if (!mounted) {
        await database.close();
        return;
      }
      setState(() {
        _database = database;
        _chat = DriftChatRepository(database);
        _ownsChat = true;
        _chatOpening = false;
      });
      _syncAccount();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chatOpening = false;
        _chatOpenError = 'Pesan lokal belum dapat dibuka.';
        _messagesLoading = false;
      });
    }
  }

  void _onAccountChanged() {
    _syncAccount();
    if (mounted) setState(() {});
  }

  void _syncAccount() {
    final next = nextHikeOf(_account.groups);
    _userId = _account.user?.id;
    final groupId = next?.group.id;
    if (groupId == _groupId) return;

    _groupId = groupId;
    _groupName = next?.group.name;
    _members = const <MemberDirectoryEntry>[];
    _membersError = null;
    _membersLoading = false;
    _rosterGeneration++;
    _messages = const <ChatMessage>[];
    _messagesError = null;
    _messagesLoading = _chat != null && groupId != null;
    _messageGeneration++;

    if (groupId != null) {
      unawaited(_loadMembers(groupId));
    }
    _subscribeMessages();
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

  void _subscribeMessages() {
    unawaited(_messageSubscription?.cancel());
    _messageSubscription = null;
    final repo = _chat;
    final groupId = _groupId;
    if (repo == null || groupId == null) {
      _messagesLoading = false;
      _messagesError = null;
      return;
    }
    final generation = ++_messageGeneration;
    setState(() {
      _messagesLoading = true;
      _messagesError = null;
    });
    _messageSubscription = repo.watchMessages(groupId).listen(
      (messages) {
        if (!mounted || generation != _messageGeneration) return;
        setState(() {
          _messages = messages;
          _messagesLoading = false;
        });
        _scrollToBottom();
      },
      onError: (Object _) {
        if (!mounted || generation != _messageGeneration) return;
        setState(() {
          _messagesLoading = false;
          _messagesError = 'Pesan lokal belum dapat dibaca.';
        });
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final repo = _chat;
    final groupId = _groupId;
    final userId = _userId;
    if (text.isEmpty || _sending || repo == null || groupId == null) return;
    if (userId == null) {
      _showNotice('Masuk ke akun untuk menulis pesan.');
      return;
    }
    setState(() => _sending = true);
    try {
      final seq = await repo.nextSeq(groupId: groupId, authorId: userId);
      final now = widget.clock.nowUtc();
      await repo.saveMessage(ChatMessage(
        authorId: userId,
        seq: seq,
        groupId: groupId,
        type: PacketType.text,
        sentAtUtc: now,
        receivedAtUtc: now,
        payload: Uint8List.fromList(utf8.encode(text)),
        isOutgoing: true,
      ));
      if (!mounted) return;
      _input.clear();
    } catch (_) {
      if (mounted) {
        _showNotice('Pesan gagal disimpan di perangkat. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showNotice(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final hasGroup = _groupId != null;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HiqeoSpacing.lg,
              HiqeoSpacing.xl,
              HiqeoSpacing.lg,
              HiqeoSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _groupName ?? 'Grup Chat',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: colors.hairline),
          if (hasGroup) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.md),
            _memberStrip(theme, colors),
          ],
          Expanded(child: _messageArea(theme, colors)),
          if (hasGroup) ...<Widget>[
            Container(height: 1, color: colors.hairline),
            _composer(theme, colors),
          ],
        ],
      ),
    );
  }

  String _subtitle() {
    if (_groupId == null) {
      return 'Percakapan grup pendakianmu.';
    }
    if (_membersLoading) return 'Memuat anggota…';
    if (_membersError != null) return 'Anggota belum dimuat';
    final count = _members.length;
    if (count == 0) return 'Belum ada anggota · pesan lokal di perangkat ini';
    return '$count anggota · pesan lokal di perangkat ini';
  }

  Widget _memberStrip(ThemeData theme, HiqeoColors colors) {
    if (_membersLoading) {
      return Padding(
        padding: HiqeoSpacing.page,
        child: Text(
          'Memuat anggota…',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      );
    }
    if (_membersError != null) {
      return Padding(
        padding: HiqeoSpacing.page,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _membersError!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: _groupId == null
                  ? null
                  : () => unawaited(_loadMembers(_groupId!)),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    }
    if (_members.isEmpty) {
      return Padding(
        padding: HiqeoSpacing.page,
        child: Text(
          'Belum ada anggota di grup ini.',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      );
    }

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: HiqeoSpacing.page,
        itemCount: _members.length,
        separatorBuilder: (_, __) => const SizedBox(width: HiqeoSpacing.sm),
        itemBuilder: (context, index) {
          final member = _members[index];
          final isSelf = member.userId == _userId;
          return SizedBox(
            width: 148,
            child: GlassSurface(
              borderRadius: HiqeoRadius.card,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    member.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSelf ? 'Perangkat ini' : 'Lokasi belum dibagikan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _messageArea(ThemeData theme, HiqeoColors colors) {
    if (_groupId == null) {
      final String title;
      final String body;
      if (_account.isLoading) {
        title = 'Memuat grup…';
        body = 'Data grup diambil dari server.';
      } else if (!_account.isConfigured) {
        title = 'Aplikasi berjalan offline';
        body = 'Akun dan grup belum tersambung. Pesan lokal tetap tersimpan '
            'di perangkat ini.';
      } else if (_account.user == null) {
        title = 'Belum masuk';
        body = 'Masuk lewat Profil untuk memakai grup dan pesan.';
      } else {
        title = 'Belum ada grup';
        body = 'Grup yang kamu ikuti akan muncul di sini.';
      }
      return _EmptyChat(title: title, body: body);
    }
    if (_chatOpening) {
      return const _EmptyChat(
        title: 'Menyiapkan pesan…',
        body: 'Membuka penyimpanan lokal.',
      );
    }
    if (_chatOpenError != null) {
      return _EmptyChat(title: 'Pesan lokal belum siap', body: _chatOpenError!);
    }
    if (_messagesLoading) {
      return const _EmptyChat(
        title: 'Memuat pesan…',
        body: 'Membaca pesan yang tersimpan di perangkat.',
      );
    }
    if (_messagesError != null) {
      return _EmptyChat(title: 'Pesan lokal belum terbaca', body: _messagesError!);
    }
    if (_messages.isEmpty) {
      return const _EmptyChat(
        title: 'Belum ada pesan',
        body: 'Pesan yang kamu tulis hanya tersimpan di perangkat ini. '
            'Pengiriman ke anggota grup belum aktif.',
      );
    }

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        HiqeoSpacing.lg,
        HiqeoSpacing.lg,
        HiqeoSpacing.lg,
        HiqeoSpacing.lg,
      ),
      itemCount: _messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: HiqeoSpacing.md),
      itemBuilder: (context, index) =>
          _messageBubble(_messages[index], theme, colors),
    );
  }

  Widget _messageBubble(
    ChatMessage message,
    ThemeData theme,
    HiqeoColors colors,
  ) {
    final outgoing = message.isOutgoing;
    final body = switch (message.type) {
      PacketType.text => _textBubble(message, outgoing, theme, colors),
      PacketType.location => _locationBubble(message, outgoing, theme, colors),
      PacketType.voiceFragment => _noticeBubble(
          outgoing ? 'Pesan suara tersimpan, belum bisa diputar.' : 'Pesan suara',
          outgoing,
          theme,
          colors,
        ),
      _ => _noticeBubble(
          'Jenis pesan ini belum didukung di tampilan ini.',
          outgoing,
          theme,
          colors,
        ),
    };

    return Column(
      crossAxisAlignment:
          outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: <Widget>[
        body,
        if (outgoing) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            'Tersimpan di HP · belum terkirim',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _textBubble(
    ChatMessage message,
    bool outgoing,
    ThemeData theme,
    HiqeoColors colors,
  ) {
    final text = utf8.decode(message.payload, allowMalformed: true);
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.74,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: _bubbleDecoration(outgoing, colors),
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: outgoing ? colors.onPrimary : colors.textPrimary,
        ),
      ),
    );
  }

  Widget _locationBubble(
    ChatMessage message,
    bool outgoing,
    ThemeData theme,
    HiqeoColors colors,
  ) {
    LocationPayload? payload;
    try {
      payload = LocationPayload.fromBytes(message.payload);
    } catch (_) {
      payload = null;
    }
    String? sender;
    for (final member in _members) {
      if (member.userId == message.authorId) {
        sender = member.username;
        break;
      }
    }
    final title = outgoing
        ? 'Kamu membagikan lokasi'
        : sender == null
            ? 'Lokasi dibagikan'
            : '$sender membagikan lokasi';
    final textColor = outgoing ? colors.onPrimary : colors.textPrimary;
    final secondary =
        outgoing ? colors.onPrimary.withValues(alpha: 0.75) : colors.textSecondary;
    return Container(
      width: MediaQuery.sizeOf(context).width * 0.72,
      decoration: _bubbleDecoration(outgoing, colors),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 88,
            width: double.infinity,
            decoration: BoxDecoration(
              color: outgoing
                  ? colors.onPrimary.withValues(alpha: 0.12)
                  : colors.secondary.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(HiqeoRadius.floating),
            ),
            child: Center(
              child: HiqeoIcon(
                HiqeoIcons.pin,
                size: 28,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            payload == null
                ? 'Isi lokasi tidak dapat dibaca.'
                : '±${payload.accuracyM} m · '
                    '${formatDecimal(LatLng(payload.lat, payload.lon))}',
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ],
      ),
    );
  }

  Widget _noticeBubble(
    String text,
    bool outgoing,
    ThemeData theme,
    HiqeoColors colors,
  ) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.74,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: _bubbleDecoration(outgoing, colors),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: outgoing ? colors.onPrimary : colors.textPrimary,
        ),
      ),
    );
  }

  BoxDecoration _bubbleDecoration(bool outgoing, HiqeoColors colors) {
    return BoxDecoration(
      color: outgoing ? colors.primary : colors.surface,
      border: outgoing ? null : Border.all(color: colors.hairline),
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(HiqeoRadius.card),
        topRight: const Radius.circular(HiqeoRadius.card),
        bottomLeft: Radius.circular(outgoing ? HiqeoRadius.card : 4),
        bottomRight: Radius.circular(outgoing ? 4 : HiqeoRadius.card),
      ),
    );
  }

  Widget _composer(ThemeData theme, HiqeoColors colors) {
    final canSend = _input.text.trim().isNotEmpty && !_sending && _userId != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HiqeoSpacing.lg,
        HiqeoSpacing.sm,
        HiqeoSpacing.lg,
        HiqeoSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          GlassSurface(
            borderRadius: HiqeoRadius.pill,
            child: IconButton(
              tooltip: 'Pesan suara belum tersedia',
              onPressed: null,
              icon: HiqeoIcon(HiqeoIcons.mic, size: 22),
            ),
          ),
          const SizedBox(width: HiqeoSpacing.sm),
          Expanded(
            child: GlassSurface(
              borderRadius: HiqeoRadius.pill,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: TextField(
                key: const ValueKey('chat-input'),
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => unawaited(_send()),
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Tulis pesan',
                  hintStyle: theme.textTheme.bodyLarge
                      ?.copyWith(color: colors.textSecondary),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: HiqeoSpacing.sm),
          Semantics(
            label: 'Kirim pesan',
            button: true,
            enabled: canSend,
            child: SizedBox(
              key: const ValueKey('chat-send'),
              width: 48,
              height: 48,
              child: Material(
                color: canSend
                    ? colors.primary
                    : colors.secondary.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: canSend ? () => unawaited(_send()) : null,
                  child: Center(
                    child: HiqeoIcon(
                      HiqeoIcons.send,
                      size: 22,
                      color: canSend ? colors.onPrimary : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(HiqeoSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: HiqeoSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
