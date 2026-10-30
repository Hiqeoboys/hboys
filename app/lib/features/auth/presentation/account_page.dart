import 'package:flutter/material.dart';

import '../../../infrastructure/supabase/supabase_services.dart';
import '../../groups/application/group_key_manager.dart';
import '../../groups/domain/group_remote_service.dart';
import '../application/account_controller.dart';
import '../domain/auth_service.dart';

class AccountPage extends StatefulWidget {
  AccountPage({super.key, AccountController? controller})
      : _controller =
            controller ?? SupabaseServices.createAccountController(),
        _ownsController = controller == null;

  final AccountController _controller;
  final bool _ownsController;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget._controller.initialize();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    if (widget._ownsController) widget._controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akun & Grup')),
      body: AnimatedBuilder(
        animation: widget._controller,
        builder: (context, _) {
          final controller = widget._controller;
          if (!controller.isConfigured) return _setupView(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (controller.isLoading || controller.isBusy)
                const LinearProgressIndicator(),
              if (controller.error != null)
                _messageCard(
                  context,
                  controller.error!,
                  isError: true,
                ),
              if (controller.notice != null)
                _messageCard(context, controller.notice!),
              const SizedBox(height: 8),
              if (controller.user == null)
                _signedOutView(context, controller)
              else ...[
                _accountCard(context, controller),
                const SizedBox(height: 12),
                if (controller.profile == null)
                  _usernameForm(context, controller)
                else ...[
                  if (controller.deviceKeyMismatch)
                    _keyMismatchCard(context, controller),
                  _invitationsSection(context, controller),
                  const SizedBox(height: 12),
                  _groupsSection(context, controller),
                ],
              ],
              const SizedBox(height: 24),
              Text(
                'Fitur grup memerlukan internet. Kunci grup disimpan di '
                'keystore/Keychain perangkat; bila perangkat hilang, kunci '
                'lama tidak dapat dipulihkan. Semua perilaku server dan login '
                'belum diuji di perangkat nyata.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _setupView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Supabase belum dikonfigurasi',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Login, username, direktori kunci, dan grup tidak aktif '
                  'sampai kredensial publik Supabase diberikan saat build.',
                ),
                const SizedBox(height: 12),
                const SelectableText(
                  'flutter run \\\n'
                  '  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \\\n'
                  '  --dart-define=SUPABASE_PUBLISHABLE_KEY=...',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Daftarkan redirect URL id.nama.namaapp://login-callback di '
                  'Supabase Auth > URL Configuration, aktifkan penyedia Google '
                  'dan Apple, lalu cocokkan intent filter Android/'
                  'CFBundleURLTypes iOS. Jangan memakai service role key.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Rekaman GPS, peta offline, dan SOS tidak diubah oleh layar ini. '
          'Tanpa akun, data grup memang tidak tersedia.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _signedOutView(
    BuildContext context,
    AccountController controller,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Masuk untuk grup',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Autentikasi memakai OAuth Google atau Apple. Aplikasi tidak '
              'melihat kata sandi. Email hanya dipakai untuk identitas akun, '
              'username tetap menjadi identitas publik.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: controller.isBusy
                  ? null
                  : () => controller.signIn(AuthProviderKind.google),
              icon: const Icon(Icons.login),
              label: const Text('Masuk dengan Google'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: controller.isBusy
                  ? null
                  : () => controller.signIn(AuthProviderKind.apple),
              icon: const Icon(Icons.apple),
              label: const Text('Masuk dengan Apple'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(
    BuildContext context,
    AccountController controller,
  ) {
    final user = controller.user!;
    final profile = controller.profile;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    profile == null ? 'Akun masuk' : '@${profile.username}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed:
                      controller.isBusy ? null : controller.signOut,
                  child: const Text('Keluar'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              user.email ?? 'Email tidak tersedia',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyMismatchCard(
    BuildContext context,
    AccountController controller,
  ) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kunci perangkat berbeda dari direktori',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Kunci grup yang dibungkus untuk kunci lama tidak dapat dibuka. '
              'Hanya lanjutkan bila perangkat lama memang hilang atau direset.',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: controller.isBusy
                  ? null
                  : () => _confirmKeyReplacement(context, controller),
              child: const Text('Daftarkan kunci perangkat ini'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmKeyReplacement(
    BuildContext context,
    AccountController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ganti kunci perangkat?'),
        content: const Text(
          'Anggota grup harus membagikan ulang kunci. Pesan dan kunci grup '
          'lama yang hanya dimiliki kunci sebelumnya tidak dapat dipulihkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ganti kunci'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.registerCurrentDeviceKey();
  }

  Widget _usernameForm(
    BuildContext context,
    AccountController controller,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pilih username',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Username bersifat publik dan dipakai untuk undangan dengan '
              'pencocokan persis. Huruf kecil, angka, titik, atau garis bawah; '
              '3-20 karakter. Kunci publik perangkat ikut didaftarkan.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: controller.isBusy
                  ? null
                  : () => controller.registerUsername(
                        _usernameController.text,
                      ),
              child: const Text('Daftarkan username'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _invitationsSection(
    BuildContext context,
    AccountController controller,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mail_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Undangan masuk',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Muat ulang',
                  onPressed: controller.isBusy ? null : controller.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (controller.invitations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Tidak ada undangan pending.'),
              )
            else
              for (final invitation in controller.invitations)
                _InvitationTile(
                  invitation: invitation,
                  busy: controller.isBusy,
                  onAccept: () => controller.respondToInvitation(
                    invitation,
                    accept: true,
                  ),
                  onReject: () => controller.respondToInvitation(
                    invitation,
                    accept: false,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _groupsSection(
    BuildContext context,
    AccountController controller,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Grup',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: controller.isBusy
                      ? null
                      : () => _showCreateGroupDialog(context, controller),
                  icon: const Icon(Icons.add),
                  label: const Text('Buat'),
                ),
              ],
            ),
            if (controller.groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Belum ada grup. Buat grup lalu undang anggota.'),
              )
            else
              for (final group in controller.groups)
                _GroupTile(
                  group: group,
                  status: controller.keyStatusFor(group.group.id),
                  keyError: controller.keyErrorFor(group.group.id),
                  busy: controller.isBusy,
                  onEnsureKey: () =>
                      controller.ensureGroupKey(group.group.id),
                  onInvite: group.isOwner && controller.profile != null
                      ? () => _showInviteDialog(context, controller, group)
                      : null,
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateGroupDialog(
    BuildContext context,
    AccountController controller,
  ) async {
    final nameController = TextEditingController();
    final mountainController = TextEditingController();
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buat grup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Nama grup',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: mountainController,
              decoration: const InputDecoration(
                labelText: 'Gunung (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              (nameController.text, mountainController.text),
            ),
            child: const Text('Buat'),
          ),
        ],
      ),
    );
    nameController.dispose();
    mountainController.dispose();
    if (result != null) {
      await controller.createGroup(result.$1, mountain: result.$2);
    }
  }

  Future<void> _showInviteDialog(
    BuildContext context,
    AccountController controller,
    RemoteGroup group,
  ) async {
    final usernameController = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Undang ke ${group.group.name}'),
        content: TextField(
          controller: usernameController,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Username (persis)',
            prefixText: '@',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(usernameController.text),
            child: const Text('Kirim undangan'),
          ),
        ],
      ),
    );
    usernameController.dispose();
    if (username != null && username.trim().isNotEmpty) {
      await controller.invite(
        groupId: group.group.id,
        username: username,
      );
    }
  }

  Widget _messageCard(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    return Card(
      color: isError
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message),
      ),
    );
  }
}

class _InvitationTile extends StatelessWidget {
  const _InvitationTile({
    required this.invitation,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  final IncomingInvitation invitation;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            invitation.groupName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            'Dari @${invitation.inviterUsername} · berlaku sampai '
            '${_formatDate(invitation.expiresAtUtc)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: busy ? null : onAccept,
                child: const Text('Terima'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: busy ? null : onReject,
                child: const Text('Tolak'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.status,
    required this.keyError,
    required this.busy,
    required this.onEnsureKey,
    required this.onInvite,
  });

  final RemoteGroup group;
  final GroupKeyStatus? status;
  final String? keyError;
  final bool busy;
  final VoidCallback onEnsureKey;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final version = group.group.keyVersion;
    final keyText = keyError ??
        switch (status?.availability) {
          null => 'Kunci belum dimuat.',
          GroupKeyAvailability.ready => group.isOwner
              ? 'Kunci v$version siap untuk ${status!.memberCount} anggota.'
              : 'Kunci v$version tersedia di perangkat.',
          GroupKeyAvailability.waitingForOwner =>
            'Menunggu kunci v$version dari pemilik.',
        };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.group.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Chip(
                label: Text(group.isOwner ? 'Pemilik' : 'Anggota'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (group.group.mountain != null)
            Text(
              group.group.mountain!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 4),
          Text(keyText, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy ? null : onEnsureKey,
                child: Text(
                  status?.availability == GroupKeyAvailability.ready
                      ? 'Periksa kunci'
                      : 'Muat kunci',
                ),
              ),
              if (onInvite != null)
                TextButton(
                  onPressed: busy ? null : onInvite,
                  child: const Text('Undang'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime utc) {
  final local = utc.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day-$month-${local.year}';
}
