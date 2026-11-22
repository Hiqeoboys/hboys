import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/platform/contact_picker.dart';
import '../../../design/glass/glass_surface.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_safety_repository.dart';
import '../../social/data/friends_service.dart';
import '../application/emergency_contact_sync_service.dart';
import '../application/sos_sms_service.dart';
import '../domain/emergency_contact.dart';
import '../domain/phone_validator.dart';
import '../domain/safety_repository.dart';

/// Kartu Kontak Darurat di halaman Profil.
///
/// Menampilkan hingga 3 kontak darurat (avatar 38 dp, nama, nomor tersamar)
/// serta dua tombol di bawah: "Tambah kontak darurat" (primary, flex, 48 dp)
/// dan "Hapus" (secondary, 48 dp, nonaktif saat kosong). Keduanya membuka
/// sheet bersama [showEmergencyContactsSheet].
class EmergencyContactsCard extends StatelessWidget {
  const EmergencyContactsCard({
    super.key,
    required this.contacts,
    required this.loading,
    required this.failed,
    required this.onOpenSheet,
    this.onOpenAddMode,
  });

  final List<EmergencyContact> contacts;
  final bool loading;
  final bool failed;
  final VoidCallback onOpenSheet;
  final VoidCallback? onOpenAddMode;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final visibleContacts = contacts.take(kMaxEmergencyContacts).toList();
    final hasContacts = visibleContacts.isNotEmpty;

    return GlassSurface(
      key: const ValueKey<String>('profil-emergency-contacts-card'),
      tier: GlassTier.card,
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.12),
                ),
                child: Center(
                  child: HiqeoIcon(
                    HiqeoIcons.phone,
                    size: 22,
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
                      'Kontak darurat',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nomor HP langsung aktif · Akun Hiqeo via persetujuan',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Memuat kontak darurat…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            )
          else if (failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Kontak darurat belum dapat dibaca dari HP ini.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            )
          else if (!hasContacts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Belum ada kontak darurat.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            )
          else
            Column(
              children: <Widget>[
                for (int i = 0; i < visibleContacts.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 8),
                  _ContactRowItem(contact: visibleContacts[i]),
                ],
              ],
            ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    key: const ValueKey<String>('emergency-card-add-button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: onOpenAddMode ?? onOpenSheet,
                    child: const Text(
                      'Tambah kontak darurat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: FilledButton.tonal(
                  key: const ValueKey<String>('emergency-card-delete-button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.secondary,
                    foregroundColor: colors.textPrimary,
                    disabledBackgroundColor:
                        colors.secondary.withValues(alpha: 0.5),
                    disabledForegroundColor:
                        colors.textSecondary.withValues(alpha: 0.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: hasContacts ? onOpenSheet : null,
                  child: const Text(
                    'Hapus',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Membuka sheet Kontak Darurat dari mana saja (Beranda maupun Profil) dengan
/// membuka koneksi database lokal otomatis bila [safetyRepository] tidak
/// disuntikkan.
Future<void> openDeviceEmergencyContactsSheet(
  BuildContext context, {
  String? userId,
  SafetyRepository? safetyRepository,
  ContactPicker? contactPicker,
  SosSmsSender? smsSender,
  bool startInAddMode = false,
  VoidCallback? onChanged,
}) async {
  AppDatabase? ownedDb;
  SafetyRepository? repo = safetyRepository;
  if (repo == null) {
    try {
      ownedDb = openAppDatabase(await defaultAppDatabaseFile());
      repo = DriftSafetyRepository(ownedDb);
    } catch (_) {
      repo = null;
    }
  }
  if (!context.mounted) {
    await ownedDb?.close();
    return;
  }
  try {
    await showEmergencyContactsSheet(
      context,
      ownerUserId: userId ?? kLocalEmergencyContactOwnerId,
      safetyRepository: repo,
      contactPicker: contactPicker ?? const MethodChannelContactPicker(),
      smsSender: smsSender ?? const MethodChannelSosSmsSender(),
      startInAddMode: startInAddMode,
      onChanged: onChanged,
    );
  } finally {
    await ownedDb?.close();
  }
}

/// Menampilkan bottom sheet kaca (tier [GlassTier.panel]) untuk melihat,
/// menambah (dari kontak HP/manual langsung aktif, atau akun Hiqeo via
/// persetujuan), dan menghapus kontak darurat.
Future<void> showEmergencyContactsSheet(
  BuildContext context, {
  required String ownerUserId,
  required SafetyRepository? safetyRepository,
  ContactPicker contactPicker = const MethodChannelContactPicker(),
  SosSmsSender smsSender = const MethodChannelSosSmsSender(),
  bool startInAddMode = false,
  VoidCallback? onChanged,
  Future<List<UserSearchResult>> Function(String query)? searchHiqeoUsers,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (sheetContext) => _EmergencyContactsSheetContent(
      ownerUserId: ownerUserId,
      safetyRepository: safetyRepository,
      contactPicker: contactPicker,
      smsSender: smsSender,
      startInAddMode: startInAddMode,
      onChanged: onChanged,
      searchHiqeoUsers: searchHiqeoUsers,
    ),
  );
}

enum _EmergencyAddMode { phone, hiqeoAccount }

class _EmergencyContactsSheetContent extends StatefulWidget {
  const _EmergencyContactsSheetContent({
    required this.ownerUserId,
    required this.safetyRepository,
    required this.contactPicker,
    required this.smsSender,
    required this.startInAddMode,
    this.onChanged,
    this.searchHiqeoUsers,
  });

  final String ownerUserId;
  final SafetyRepository? safetyRepository;
  final ContactPicker contactPicker;
  final SosSmsSender smsSender;
  final bool startInAddMode;
  final VoidCallback? onChanged;
  final Future<List<UserSearchResult>> Function(String query)? searchHiqeoUsers;

  @override
  State<_EmergencyContactsSheetContent> createState() =>
      _EmergencyContactsSheetContentState();
}

class _EmergencyContactsSheetContentState
    extends State<_EmergencyContactsSheetContent> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _usernameSearchController =
      TextEditingController();
  final EmergencyContactSyncService _sync = EmergencyContactSyncService.instance;

  List<EmergencyContact> _contacts = const <EmergencyContact>[];
  bool _loading = true;
  bool _failed = false;
  bool _adding = false;
  bool _saving = false;
  _EmergencyAddMode _addMode = _EmergencyAddMode.phone;
  Timer? _searchDebounce;
  int _searchGen = 0;
  bool _searchingUsers = false;
  String? _searchError;
  List<UserSearchResult> _searchResults = const <UserSearchResult>[];
  String? _formError;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _adding = widget.startInAddMode;
    _sync.addListener(_onSyncChanged);
    _sync.ensureRealtimeSubscribed();
    unawaited(_load());
    unawaited(_refreshRemote());
  }

  @override
  void dispose() {
    _sync.removeListener(_onSyncChanged);
    _searchDebounce?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _usernameSearchController.dispose();
    super.dispose();
  }

  void _onSyncChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshRemote() async {
    final repo = widget.safetyRepository;
    await _sync.refreshIncomingRequests();
    if (repo != null) {
      await _sync.syncOutgoingContacts(repo, widget.ownerUserId);
      if (mounted) await _load();
    }
  }

  Future<void> _load() async {
    final repo = widget.safetyRepository;
    if (repo == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    try {
      final list = await repo.contactsOf(widget.ownerUserId);
      if (!mounted) return;
      setState(() {
        _contacts = list;
        _loading = false;
        _failed = false;
        if (_contacts.length >= kMaxEmergencyContacts) {
          _adding = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _pickFromDeviceContacts() async {
    setState(() {
      _formError = null;
      _notice = null;
    });
    final result = await widget.contactPicker.pickContact();
    if (!mounted) return;
    switch (result.status) {
      case ContactPickStatus.picked:
        final picked = result.contact!;
        _nameController.text = picked.name;
        _phoneController.text = picked.phone;
        setState(() {
          _adding = true;
          _notice = 'Kontak dipilih. Periksa lalu simpan.';
        });
      case ContactPickStatus.permissionDenied:
        setState(() {
          _formError =
              'Izin kontak belum diberikan. Kamu tetap bisa mengisi nomor secara manual.';
        });
      case ContactPickStatus.unsupported:
        setState(() {
          _notice =
              'Pemilih kontak tidak tersedia di perangkat ini. Masukkan nomor secara manual.';
        });
      case ContactPickStatus.cancelled:
        break;
    }
  }

  Future<void> _saveNewContact() async {
    final repo = widget.safetyRepository;
    if (repo == null) {
      setState(() => _formError = 'Penyimpanan lokal belum siap.');
      return;
    }
    if (_contacts.length >= kMaxEmergencyContacts) {
      setState(() => _formError = 'Maksimal $kMaxEmergencyContacts kontak darurat.');
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _formError = 'Masukkan nama kontak darurat.');
      return;
    }
    final phoneErr = IndonesianPhoneValidator.validateError(
      _phoneController.text,
    );
    if (phoneErr != null) {
      setState(() => _formError = phoneErr);
      return;
    }
    final phoneE164 = IndonesianPhoneValidator.toE164(_phoneController.text)!;
    final duplicate = _contacts.any((c) => c.phoneE164 == phoneE164);
    if (duplicate) {
      setState(() => _formError = 'Nomor ini sudah ada di daftar kontak darurat.');
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _notice = null;
    });
    try {
      final now = DateTime.now().toUtc();
      final rand = math.Random().nextInt(999999).toString().padLeft(6, '0');
      final contact = EmergencyContact(
        id: 'ec-${now.microsecondsSinceEpoch}-$rand',
        userId: widget.ownerUserId,
        name: name,
        phoneE164: phoneE164,
        createdAtUtc: now,
        consentStatus: EmergencyContactConsentStatus.granted,
        consentAtUtc: now,
      );
      await repo.saveContact(contact);
      unawaited(_sync.mirrorPhoneContactToRemote(contact));
      _nameController.clear();
      _phoneController.clear();
      await _load();
      widget.onChanged?.call();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _adding = false;
        _notice = 'Kontak darurat langsung aktif untuk SMS/WhatsApp SOS.';
      });
      unawaited(
        promptEmergencySmsPermission(context, sender: widget.smsSender),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = 'Gagal menyimpan kontak darurat.';
      });
    }
  }

  void _onUsernameQueryChanged(String raw) {
    _searchDebounce?.cancel();
    final clean = raw.trim().replaceFirst(RegExp(r'^@+'), '');
    if (clean.isEmpty) {
      _searchGen++;
      setState(() {
        _searchingUsers = false;
        _searchError = null;
        _searchResults = const <UserSearchResult>[];
      });
      return;
    }
    setState(() {
      _searchingUsers = true;
      _searchError = null;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_searchUsers(clean));
    });
  }

  Future<void> _searchUsers(String clean) async {
    final gen = ++_searchGen;
    try {
      final results = widget.searchHiqeoUsers != null
          ? await widget.searchHiqeoUsers!(clean)
          : await FriendsService.instance.searchUsersByUsername(
              clean,
              limit: 15,
            );
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _searchResults = results;
        _searchingUsers = false;
        _searchError = null;
      });
    } catch (e) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _searchingUsers = false;
        _searchResults = const <UserSearchResult>[];
        _searchError = e is StateError ? e.message : 'Gagal mencari akun Hiqeo.';
      });
    }
  }

  Future<void> _inviteHiqeoAccount(UserSearchResult target) async {
    final repo = widget.safetyRepository;
    if (repo == null) {
      setState(() => _formError = 'Penyimpanan lokal belum siap.');
      return;
    }
    if (_contacts.length >= kMaxEmergencyContacts) {
      setState(() => _formError = 'Maksimal $kMaxEmergencyContacts kontak darurat.');
      return;
    }
    if (_contacts.any((c) => c.linkedUserId == target.userId)) {
      setState(
        () => _formError = '@${target.username} sudah ada di kontak darurat.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
      _notice = null;
    });
    try {
      await _sync.sendHiqeoAccountRequest(target: target, localRepo: repo);
      _usernameSearchController.clear();
      _searchResults = const <UserSearchResult>[];
      await _load();
      widget.onChanged?.call();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _adding = false;
        _notice =
            'Permintaan persetujuan dikirim ke @${target.username} (menunggu).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = e is StateError
            ? e.message
            : 'Gagal mengirim permintaan ke @${target.username}.';
      });
    }
  }

  Future<void> _confirmDeleteContact(EmergencyContact contact) async {
    final repo = widget.safetyRepository;
    if (repo == null) return;

    final detailLabel = contact.isHiqeoAccount
        ? '@${contact.linkedUsername ?? 'pendaki'}'
        : IndonesianPhoneValidator.mask(contact.phoneE164);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = HiqeoColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: colors.surface,
          title: const Text('Hapus kontak darurat?'),
          content: Text(
            'Hapus ${contact.name} ($detailLabel) dari daftar kontak darurat di HP ini?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              key: const ValueKey<String>('emergency-delete-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'Hapus',
                style: TextStyle(
                  color: colors.warningText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    try {
      await repo.deleteContact(contact.id);
      unawaited(_sync.syncDeleteRemote(contact.id));
      await _load();
      widget.onChanged?.call();
      if (mounted) {
        setState(() => _notice = 'Kontak darurat dihapus.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _formError = 'Gagal menghapus kontak darurat.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    final canAddMore = _contacts.length < kMaxEmergencyContacts;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardBottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: GlassSurface(
          key: const ValueKey<String>('emergency-contacts-sheet'),
          tier: GlassTier.panel,
          borderRadius: 28,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 32 + safeBottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Handle 36 x 4
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
                const SizedBox(height: 16),
                Text(
                  'Kontak darurat',
                  style: TextStyle(
                    fontFamily: HiqeoTypography.family,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nomor HP langsung aktif. Akun Hiqeo aktif setelah disetujui.',
                  style: TextStyle(
                    fontFamily: HiqeoTypography.family,
                    fontSize: 13.5,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),

                if (_sync.incomingRequests.isNotEmpty) ...<Widget>[
                  Text(
                    'Permintaan kontak darurat (${_sync.incomingRequests.length})',
                    style: TextStyle(
                      fontFamily: HiqeoTypography.family,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final req in _sync.incomingRequests)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            req.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '@${req.requesterUsername} ingin jadi kontak daruratmu',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              TextButton(
                                onPressed: () => unawaited(
                                  _sync.respondToRequest(req.id, accept: false),
                                ),
                                child: const Text('Tolak'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => unawaited(
                                  _sync.respondToRequest(req.id, accept: true),
                                ),
                                child: const Text('Terima'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                ],

                if (_notice != null) ...<Widget>[
                  Text(
                    _notice!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_formError != null) ...<Widget>[
                  Text(
                    _formError!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.warningText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_failed)
                  Text(
                    'Kontak darurat belum dapat dibaca dari HP ini.',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: colors.textSecondary,
                    ),
                  )
                else if (_contacts.isEmpty && !_adding)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Belum ada kontak darurat.',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textSecondary,
                      ),
                    ),
                  )
                else if (_contacts.isNotEmpty) ...<Widget>[
                  for (int i = 0; i < _contacts.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: 10),
                    _ContactRowItem(
                      contact: _contacts[i],
                      onDelete: () => _confirmDeleteContact(_contacts[i]),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],

                if (_adding && canAddMore) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: ChoiceChip(
                                key: const ValueKey<String>(
                                  'emergency-mode-phone',
                                ),
                                visualDensity: VisualDensity.compact,
                                label: const Center(child: Text('Nomor HP')),
                                selected: _addMode == _EmergencyAddMode.phone,
                                onSelected: (_) => setState(
                                  () => _addMode = _EmergencyAddMode.phone,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                key: const ValueKey<String>(
                                  'emergency-mode-hiqeo',
                                ),
                                visualDensity: VisualDensity.compact,
                                label: const Center(child: Text('Akun Hiqeo')),
                                selected:
                                    _addMode == _EmergencyAddMode.hiqeoAccount,
                                onSelected: (_) => setState(
                                  () => _addMode = _EmergencyAddMode.hiqeoAccount,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_addMode == _EmergencyAddMode.phone) ...<Widget>[
                          OutlinedButton.icon(
                            key: const ValueKey<String>(
                              'emergency-pick-device-contact',
                            ),
                            onPressed: _saving ? null : _pickFromDeviceContacts,
                            icon: HiqeoIcon(
                              HiqeoIcons.user,
                              size: 18,
                              color: colors.primary,
                            ),
                            label: Text(
                              'Pilih dari kontak HP',
                              style: TextStyle(
                                color: colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const ValueKey<String>(
                              'emergency-contact-name-input',
                            ),
                            controller: _nameController,
                            maxLength: 60,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Nama kontak',
                              hintText: 'Contoh: Ibu atau Pendamping',
                              counterText: '',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            key: const ValueKey<String>(
                              'emergency-contact-phone-input',
                            ),
                            controller: _phoneController,
                            maxLength: 20,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Nomor telepon Indonesia',
                              hintText: '081234567890 atau +6281234567890',
                              counterText: '',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() {
                                            _adding = false;
                                            _formError = null;
                                          }),
                                  child: const Text('Batal'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  key: const ValueKey<String>(
                                    'emergency-contact-save-button',
                                  ),
                                  onPressed: _saving ? null : _saveNewContact,
                                  child: Text(
                                    _saving ? 'Menyimpan…' : 'Simpan kontak',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...<Widget>[
                          TextField(
                            key: const ValueKey<String>(
                              'emergency-hiqeo-search-input',
                            ),
                            controller: _usernameSearchController,
                            maxLength: 21,
                            onChanged: _onUsernameQueryChanged,
                            decoration: const InputDecoration(
                              labelText: 'Cari @username akun Hiqeo',
                              hintText: 'Contoh: @rani',
                              counterText: '',
                              prefixIcon: Icon(Icons.search_rounded),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_searchingUsers)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_searchError != null)
                            Text(
                              _searchError!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.warningText,
                              ),
                            )
                          else if (_searchResults.isNotEmpty)
                            for (final u in _searchResults)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(u.label),
                                subtitle: Text('@${u.username}'),
                                trailing: FilledButton(
                                  key: ValueKey<String>(
                                    'emergency-invite-${u.userId}',
                                  ),
                                  onPressed: _saving
                                      ? null
                                      : () => unawaited(_inviteHiqeoAccount(u)),
                                  child: const Text('Minta'),
                                ),
                              )
                          else if (_usernameSearchController.text
                              .trim()
                              .isNotEmpty)
                            Text(
                              'Tidak ada akun Hiqeo yang cocok.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.textSecondary,
                              ),
                            ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                      _adding = false;
                                      _formError = null;
                                    }),
                            child: const Text('Batal'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Catatan informasi 12,5 sp
                Text(
                  'Kontak nomor HP langsung aktif untuk WhatsApp/SMS darurat saat SOS. '
                  'Akun Hiqeo menerima permintaan persetujuan lewat notifikasi.',
                  style: TextStyle(
                    fontFamily: HiqeoTypography.family,
                    fontSize: 12.5,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                if (!_adding)
                  SizedBox(
                    height: 52,
                    child: HiqeoButton(
                      key: const ValueKey<String>(
                        'emergency-sheet-add-button',
                      ),
                      label: canAddMore
                          ? 'Tambah kontak darurat'
                          : 'Maksimal $kMaxEmergencyContacts kontak darurat',
                      onPressed: canAddMore
                          ? () => setState(() {
                                _adding = true;
                                _formError = null;
                                _notice = null;
                              })
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactRowItem extends StatelessWidget {
  const _ContactRowItem({
    required this.contact,
    this.onDelete,
  });

  final EmergencyContact contact;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final initial = contact.name.trim().isEmpty
        ? '?'
        : String.fromCharCode(contact.name.trim().runes.first).toUpperCase();

    return Row(
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.secondary,
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                fontFamily: HiqeoTypography.family,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                contact.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: HiqeoTypography.family,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                contact.isHiqeoAccount
                    ? '@${contact.linkedUsername ?? 'pendaki'}'
                    : IndonesianPhoneValidator.mask(contact.phoneE164),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: HiqeoTypography.family,
                  fontSize: 12.5,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _ConsentStatusPill(status: contact.consentStatus),
        if (onDelete != null) ...<Widget>[
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Hapus ${contact.name}',
            child: GestureDetector(
              key: ValueKey<String>('emergency-contact-delete-${contact.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onDelete,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.warning.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: colors.warningText,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ConsentStatusPill extends StatelessWidget {
  const _ConsentStatusPill({required this.status});

  final EmergencyContactConsentStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final (String label, Color bg, Color fg) = switch (status) {
      EmergencyContactConsentStatus.granted => (
          'Aktif',
          colors.success.withValues(alpha: 0.14),
          colors.successText,
        ),
      EmergencyContactConsentStatus.pending => (
          'Menunggu',
          colors.warning.withValues(alpha: 0.14),
          colors.warningText,
        ),
      EmergencyContactConsentStatus.revoked => (
          'Ditolak',
          colors.hairline,
          colors.textSecondary,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
