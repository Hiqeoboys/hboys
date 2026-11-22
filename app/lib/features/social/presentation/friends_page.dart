import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../design/background/app_background.dart';
import '../../../design/background/page_background.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../../../design/widgets/hiqeo_state_view.dart';
import '../../../design/widgets/persistent_avatar_image.dart';
import '../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../profile/presentation/other_user_profile_page.dart';
import '../data/friends_service.dart';

/// Halaman Daftar Teman & Permintaan Pertemanan di menu Profil.
class FriendsPage extends StatefulWidget {
  const FriendsPage({
    super.key,
    this.searchUsers,
    this.sendFriendRequest,
  });

  /// Disuntikkan untuk uji widget pencarian @username.
  final Future<List<UserSearchResult>> Function(String query)? searchUsers;
  final Future<void> Function(String userId)? sendFriendRequest;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final FriendsService _service = FriendsService.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  int _searchGen = 0;
  bool _searching = false;
  String? _searchError;
  List<UserSearchResult> _searchResults = const <UserSearchResult>[];

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    unawaited(_service.loadCached());
    _service.ensureRealtimeSubscribed();
    unawaited(_service.refresh());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    final normalized = raw.trim().replaceFirst(RegExp(r'^@+'), '');
    if (normalized.isEmpty) {
      _searchGen++;
      setState(() {
        _searching = false;
        _searchError = null;
        _searchResults = const <UserSearchResult>[];
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_runSearch(normalized));
    });
  }

  Future<void> _runSearch(String query) async {
    final gen = ++_searchGen;
    try {
      final results = widget.searchUsers != null
          ? await widget.searchUsers!(query)
          : await _service.searchUsersByUsername(query, limit: 15);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _searchResults = results;
        _searching = false;
        _searchError = null;
      });
    } catch (e) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _searching = false;
        _searchResults = const <UserSearchResult>[];
        _searchError = e is StateError ? e.message : 'Gagal mencari akun.';
      });
    }
  }

  Future<void> _sendRequest(UserSearchResult target) async {
    try {
      if (widget.sendFriendRequest != null) {
        await widget.sendFriendRequest!(target.userId);
      } else {
        await _service.sendFriendRequest(target.userId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Permintaan teman dikirim ke @${target.username}.'),
          ),
        );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FriendsPage._sendRequest failed: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'Permintaan teman belum terkirim. Periksa sinyal lalu coba lagi.',
            ),
          ),
        );
    }
  }

  Future<void> _confirmRemove(FriendRecord friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus teman?'),
        content: Text('Hapus ${friend.label} dari daftar temanmu?'),
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
    await _service.removeFriend(friend.friendshipId);
  }

  void _openUserProfile(FriendRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OtherUserProfilePage(
          userId: record.userId,
          initialName: record.displayName,
          initialUsername: record.username,
          initialAvatarUrl: record.avatarUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final incoming = _service.incomingRequests;
    final friends = _service.friends;

    return PageBackground(
      page: AppBackgroundPage.profil,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const HiqeoBackButton(inAppBar: true),
          leadingWidth: HiqeoBackButton.appBarWidth,
          title: const Text('Daftar teman'),
        ),
        body: RefreshIndicator(
          onRefresh: _service.refresh,
          child: _service.isLoading && friends.isEmpty && incoming.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: <Widget>[
                    TextField(
                      key: const ValueKey<String>('friends-username-search'),
                      controller: _searchCtrl,
                      maxLength: 21,
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Cari @username pendaki…',
                        counterText: '',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _onSearchChanged('');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                        filled: true,
                        fillColor: colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: colors.hairline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: colors.hairline),
                        ),
                      ),
                    ),
                    if (_searchCtrl.text
                        .trim()
                        .replaceFirst(RegExp(r'^@+'), '')
                        .isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      if (_searching)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_searchError != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colors.warning.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  _searchError!,
                                  style: TextStyle(color: colors.warningText),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  final q = _searchCtrl.text
                                      .trim()
                                      .replaceFirst(RegExp(r'^@+'), '');
                                  if (q.isNotEmpty) {
                                    unawaited(_runSearch(q));
                                  }
                                },
                                child: const Text('Coba lagi'),
                              ),
                            ],
                          ),
                        )
                      else if (_searchResults.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: colors.hairline),
                          ),
                          child: Text(
                            'Tidak ada akun dengan awalan "@${_searchCtrl.text.trim().replaceFirst(RegExp(r'^@+'), '')}".',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        )
                      else
                        for (final found in _searchResults)
                          _buildSearchResultTile(found, colors),
                    ],
                    const SizedBox(height: 14),
                    if (_service.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: HiqeoStateView(
                          icon: Icons.wifi_off_rounded,
                          title: 'Daftar teman belum bisa dimuat',
                          message: _service.error!,
                          isError: true,
                          actionLabel: 'Coba lagi',
                          onAction: () => unawaited(_service.refresh()),
                        ),
                      ),
                    if (incoming.isNotEmpty) ...<Widget>[
                      Text(
                        'Permintaan pertemanan (${incoming.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final req in incoming)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: colors.hairline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                                Row(
                                children: <Widget>[
                                  GestureDetector(
                                    onTap: () => _openUserProfile(req),
                                    child: PersistentAvatarImage(
                                      cacheKey: req.userId,
                                      avatarUrl: req.avatarUrl,
                                      size: 44,
                                      backgroundColor: colors.hairline,
                                      fallback: Center(
                                        child: Text(
                                          req.label[0].toUpperCase(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: colors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => _openUserProfile(req),
                                      child: ListenableBuilder(
                                        listenable:
                                            PublicProfileCacheService.instance,
                                        builder: (context, _) {
                                          final cache = PublicProfileCacheService
                                              .instance;
                                          final resolvedName =
                                              cache.resolveDisplayName(
                                            req.userId,
                                            fallback: req.label,
                                          );
                                          final resolvedUname =
                                              cache.resolveUsername(
                                            req.userId,
                                            fallback: req.username,
                                          );
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(
                                                resolvedName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: colors.textPrimary,
                                                ),
                                              ),
                                              if (resolvedUname != null &&
                                                  resolvedUname
                                                      .trim()
                                                      .isNotEmpty)
                                                Text(
                                                  '@${resolvedUname.trim()}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    color: colors.textSecondary,
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: <Widget>[
                                  TextButton(
                                    onPressed: () => unawaited(
                                      _service.respondToRequest(
                                        req.friendshipId,
                                        accept: false,
                                      ),
                                    ),
                                    child: const Text('Tolak'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () => unawaited(
                                      _service.respondToRequest(
                                        req.friendshipId,
                                        accept: true,
                                      ),
                                    ),
                                    child: const Text('Terima'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      'Teman (${friends.length})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (friends.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: colors.hairline),
                        ),
                        child: Text(
                          'Belum ada teman. Tambahkan pendaki dari ruang chat Komunitas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      )
                    else
                      for (final friend in friends)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: colors.hairline),
                          ),
                          child: ListenableBuilder(
                            listenable: PublicProfileCacheService.instance,
                            builder: (context, _) {
                              final cache = PublicProfileCacheService.instance;
                              final resolvedName = cache.resolveDisplayName(
                                friend.userId,
                                fallback: friend.label,
                              );
                              final resolvedUname = cache.resolveUsername(
                                friend.userId,
                                fallback: friend.username,
                              );
                              final resolvedAvatar = cache.resolveAvatarUrl(
                                friend.userId,
                                fallback: friend.avatarUrl,
                              );
                              final initial = resolvedName.isNotEmpty
                                  ? resolvedName[0].toUpperCase()
                                  : '?';
                              return ListTile(
                                onTap: () => _openUserProfile(friend),
                                leading: PersistentAvatarImage(
                                  cacheKey: friend.userId,
                                  avatarUrl: resolvedAvatar,
                                  size: 40,
                                  backgroundColor: colors.hairline,
                                  fallback: Center(
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  resolvedName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                subtitle: (resolvedUname != null &&
                                        resolvedUname.trim().isNotEmpty)
                                    ? Text(
                                        '@${resolvedUname.trim()}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.textSecondary,
                                        ),
                                      )
                                    : null,
                                trailing: IconButton(
                                  onPressed: () => _confirmRemove(friend),
                                  icon: Icon(
                                    Icons.person_remove_outlined,
                                    color: colors.warning,
                                  ),
                                  tooltip: 'Hapus teman',
                                ),
                              );
                            },
                          ),
                        ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSearchResultTile(UserSearchResult found, HiqeoColors colors) {
    final relation = _service.relationshipStatusFor(found.userId);
    final incomingReq = _service.incomingRequestFrom(found.userId);
    final Widget action;
    if (relation == 'friend') {
      action = Chip(
        label: const Text('Teman'),
        backgroundColor: colors.hairline,
        side: BorderSide.none,
      );
    } else if (relation == 'outgoing') {
      action = Chip(
        label: const Text('Menunggu'),
        backgroundColor: colors.hairline,
        side: BorderSide.none,
      );
    } else if (relation == 'incoming' && incomingReq != null) {
      action = FilledButton(
        onPressed: () => unawaited(
          _service.respondToRequest(incomingReq.friendshipId, accept: true),
        ),
        child: const Text('Terima'),
      );
    } else {
      action = FilledButton(
        key: ValueKey<String>('friends-add-${found.userId}'),
        onPressed: () => unawaited(_sendRequest(found)),
        child: const Text('Tambah'),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OtherUserProfilePage(
                userId: found.userId,
                initialName: found.displayName,
                initialUsername: found.username,
                initialAvatarUrl: found.avatarUrl,
              ),
            ),
          ),
          leading: PersistentAvatarImage(
            cacheKey: found.userId,
            avatarUrl: found.avatarUrl,
            size: 40,
            backgroundColor: colors.hairline,
            fallback: Center(
              child: Text(
                found.label[0].toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          title: Text(
            found.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          subtitle: Text(
            '@${found.username}',
            style: TextStyle(color: colors.textSecondary),
          ),
          trailing: action,
        ),
      ),
    );
  }
}
