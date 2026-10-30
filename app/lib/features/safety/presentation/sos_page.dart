import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/emergency_numbers.dart';
import '../../../core/platform/phone_dialer.dart';
import '../../../core/utils/clock.dart';
import '../../../design/app_theme.dart';
import '../../../design/motion/visual_effect_policy.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/header_icon_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_safety_repository.dart';
import '../../../infrastructure/power/power_profile_manager.dart';
import '../application/sos_location.dart';
import '../domain/safety_repository.dart';
import '../domain/sos_category.dart';
import '../domain/sos_event.dart';
import '../domain/sos_status_tracker.dart';
import '../domain/sos_trigger_controller.dart';
import 'slide_to_call.dart';

const double _ringSize = 188;

/// Layar SOS selalu memakai palet terbalik (biru gelap), tidak mengikuti tema
/// aplikasi. Hanya penyimpanan lokal yang diklaim; jalur kirim ke anggota,
/// server, dan kontak darurat belum ada sehingga barisnya tetap kosong.
class SosPage extends StatefulWidget {
  const SosPage({
    super.key,
    this.repository,
    this.locationProvider = const DeviceSosLocationProvider(),
    this.dialer = const MethodChannelPhoneDialer(),
    this.clock = const SystemClock(),
  });

  /// Disuntikkan untuk uji; produksi membuka basis data perangkat.
  final SafetyRepository? repository;
  final SosLocationProvider locationProvider;
  final PhoneDialer dialer;
  final Clock clock;

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  static final DeviceTier _deviceTier = VisualEffectPolicy.probeDeviceTier();

  late final SosTriggerController _trigger = SosTriggerController(
    countdownDuration: const Duration(seconds: 3),
  );
  late final Future<SafetyRepository?> _repositoryFuture;

  AppDatabase? _database;
  String? _repositoryError;

  SosStatusTracker _tracker = SosStatusTracker();
  SosCategory _category = SosCategory.other;
  SosEvent? _savedEvent;
  bool _cancelRequested = false;
  bool _cancelling = false;
  bool _saving = false;
  String? _saveNotice;
  String? _notice;
  Object? _token;
  DateTime? _holdStarted;
  Future<SosFix?>? _fixFuture;
  Timer? _ticker;

  /// Kunci trek geser yang sedang dipakai, supaya hanya satu yang aktif.
  String? _activeSlider;

  @override
  void initState() {
    super.initState();
    final injected = widget.repository;
    if (injected != null) {
      _repositoryFuture = Future<SafetyRepository?>.value(injected);
    } else {
      _repositoryFuture = _openRepository();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    final database = _database;
    if (database != null) unawaited(database.close());
    super.dispose();
  }

  Future<SafetyRepository?> _openRepository() async {
    try {
      final file = await defaultAppDatabaseFile();
      final database = openAppDatabase(file);
      if (!mounted) {
        await database.close();
        return null;
      }
      _database = database;
      return DriftSafetyRepository(database);
    } catch (_) {
      if (mounted) {
        setState(() {
          _repositoryError =
              'Penyimpanan lokal belum dapat dibuka; SOS tidak dapat disimpan di HP.';
        });
      }
      return null;
    }
  }

  SosTriggerState get _state => _trigger.state;

  bool get _active =>
      _state == SosTriggerState.countdown ||
      _state == SosTriggerState.triggered;

  void _ensureTicker() {
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _onTick(),
    );
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _onTick() {
    final now = widget.clock.nowUtc();
    final before = _trigger.state;
    final after = _trigger.tick(now);
    if (before == SosTriggerState.holding &&
        after == SosTriggerState.countdown) {
      _beginCountdown(now);
    }
    if (after == SosTriggerState.holding ||
        after == SosTriggerState.countdown) {
      _ensureTicker();
    } else {
      _stopTicker();
    }
    if (mounted) setState(() {});
  }

  void _beginHold() {
    final state = _trigger.state;
    if (state != SosTriggerState.idle && state != SosTriggerState.cancelled) {
      return;
    }
    final now = widget.clock.nowUtc();
    _token = Object();
    _cancelRequested = false;
    _cancelling = false;
    _saving = false;
    _saveNotice = null;
    _notice = null;
    _savedEvent = null;
    _tracker = SosStatusTracker();
    _category = SosCategory.other;
    _holdStarted = now;
    _fixFuture = widget.locationProvider.locate();
    _trigger.holdStarted(now);
    _ensureTicker();
    setState(() {});
  }

  void _endHold() {
    if (_trigger.state != SosTriggerState.holding) return;
    _trigger.holdReleased();
    _stopTicker();
    if (mounted) setState(() {});
  }

  void _beginCountdown(DateTime now) {
    _saving = true;
    _saveNotice = null;
    unawaited(
      _saveEvent(
        token: _token,
        fix: _fixFuture,
        category: _category,
        startedAt: now,
      ),
    );
  }

  Future<void> _saveEvent({
    required Object? token,
    required Future<SosFix?>? fix,
    required SosCategory category,
    required DateTime startedAt,
  }) async {
    final repository = await _repositoryFuture;
    SosFix? located;
    try {
      located = await (fix ?? widget.locationProvider.locate());
    } catch (_) {
      located = null;
    }
    if (!mounted || token != _token) return;

    if (located == null) {
      setState(() {
        _saving = false;
        _saveNotice =
            'Lokasi GPS belum tersedia. SOS tidak tersimpan di HP. Coba lagi saat sinyal GPS didapat.';
      });
      return;
    }
    if (repository == null) {
      setState(() {
        _saving = false;
        _saveNotice = 'Penyimpanan lokal belum siap. SOS tidak tersimpan di HP.';
      });
      return;
    }
    if (_cancelRequested) {
      setState(() => _saving = false);
      return;
    }

    final event = SosEvent(
      id: 'sos-${startedAt.microsecondsSinceEpoch}',
      authorId: 'perangkat-lokal',
      category: category,
      lat: located.lat,
      lon: located.lon,
      accuracyM: located.accuracyM,
      createdAtUtc: startedAt,
      receivedAtUtc: widget.clock.nowUtc(),
    );
    try {
      await repository.saveSosEvent(event);
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _saving = false;
        _saveNotice = 'SOS gagal disimpan di HP. Coba lagi.';
      });
      return;
    }
    if (!mounted || token != _token) return;

    _tracker.mark(SosDeliveryStage.savedLocally);
    setState(() {
      _savedEvent = event;
      _saving = false;
      _saveNotice = null;
    });

    if (_cancelRequested) {
      await _cancelPersisted(event);
    } else if (_category != event.category) {
      await _persistCategory(event, _category);
    }
  }

  Future<void> _cancel() async {
    if (!_active) return;
    _trigger.cancel();
    _stopTicker();
    _cancelRequested = true;
    setState(() => _cancelling = true);
    final event = _savedEvent;
    if (event != null) await _cancelPersisted(event);
    if (mounted) setState(() => _cancelling = false);
  }

  Future<void> _cancelPersisted(SosEvent event) async {
    final repository = await _repositoryFuture;
    var cancelled = false;
    if (repository != null) {
      try {
        cancelled = await repository.cancelSosEvent(
          event.id,
          widget.clock.nowUtc(),
        );
      } catch (_) {
        cancelled = false;
      }
    }
    if (!mounted) return;
    setState(() {
      if (cancelled) {
        _savedEvent = SosEvent(
          id: event.id,
          authorId: event.authorId,
          groupId: event.groupId,
          category: event.category,
          lat: event.lat,
          lon: event.lon,
          accuracyM: event.accuracyM,
          batteryPercent: event.batteryPercent,
          createdAtUtc: event.createdAtUtc,
          receivedAtUtc: event.receivedAtUtc,
          status: SosEventStatus.cancelled,
          cancelledAtUtc: widget.clock.nowUtc(),
        );
        _notice = null;
      } else {
        _notice =
            'SOS tersimpan di HP tetapi status batal gagal disimpan. Periksa kembali di perangkat ini.';
      }
    });
  }

  Future<void> _selectCategory(SosCategory category) async {
    if (!_active || _category == category) return;
    final previous = _category;
    setState(() => _category = category);
    final event = _savedEvent;
    if (event == null || event.status != SosEventStatus.active) return;
    final updated = await _persistCategory(event, category);
    if (!mounted || updated) return;
    setState(() => _category = previous);
    _showSnackBar('Kategori gagal disimpan di HP. Coba lagi.');
  }

  Future<bool> _persistCategory(SosEvent event, SosCategory category) async {
    if (event.status != SosEventStatus.active || _cancelRequested) return false;
    final repository = await _repositoryFuture;
    if (repository == null) return false;
    final updated = SosEvent(
      id: event.id,
      authorId: event.authorId,
      groupId: event.groupId,
      category: category,
      lat: event.lat,
      lon: event.lon,
      accuracyM: event.accuracyM,
      batteryPercent: event.batteryPercent,
      createdAtUtc: event.createdAtUtc,
      receivedAtUtc: event.receivedAtUtc,
      status: event.status,
      cancelledAtUtc: event.cancelledAtUtc,
    );
    try {
      await repository.saveSosEvent(updated);
    } catch (_) {
      return false;
    }
    if (!mounted || _cancelRequested) return false;
    setState(() => _savedEvent = updated);
    return true;
  }

  void _reset() {
    _trigger.reset();
    _stopTicker();
    _token = null;
    _cancelRequested = false;
    _cancelling = false;
    _saving = false;
    _saveNotice = null;
    _notice = null;
    _savedEvent = null;
    _tracker = SosStatusTracker();
    _category = SosCategory.other;
    _holdStarted = null;
    _fixFuture = null;
    setState(() {});
  }

  void _accessibilityTrigger() {
    final state = _trigger.state;
    if (state != SosTriggerState.idle && state != SosTriggerState.cancelled) {
      return;
    }
    _beginHold();
    final startedAt = widget.clock.nowUtc().add(_trigger.holdDuration);
    _trigger.tick(startedAt);
    _beginCountdown(startedAt);
    if (mounted) setState(() {});
  }

  Future<void> _dial(String number) async {
    var opened = false;
    try {
      opened = await widget.dialer.dial(number);
    } catch (_) {
      opened = false;
    }
    if (!mounted || opened) return;
    _showSnackBar(
      'Aplikasi telepon tidak dapat dibuka. Nomor $number dapat diketik manual.',
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Menutup layar. Bila SOS sedang berjalan, pengguna diminta konfirmasi dulu
  /// dan pembatalan memakai jalur [_cancel] yang sudah ada supaya status lokal
  /// tidak menggantung.
  Future<void> _requestClose() async {
    if (_cancelling) return;
    if (!_active) {
      Navigator.of(context).maybePop();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batalkan SOS?'),
        content: const Text(
          'SOS yang sedang berjalan akan ditandai batal di HP ini. '
          'Tidak ada pesan yang terkirim ke siapa pun.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Biarkan aktif'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Batalkan SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _cancel();
    // Layar tetap terbuka bila status batal gagal disimpan supaya catatannya
    // terlihat; selain itu tombol tutup melanjutkan maksud pengguna.
    if (!mounted || _notice != null) return;
    Navigator.of(context).pop();
  }

  /// Jalur tanpa geser untuk pembaca layar: konfirmasi dulu, baru buka nomor.
  Future<void> _confirmDial(String number, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Telepon $label?'),
        content: const Text(
          'Altracq membuka aplikasi telepon dengan nomor terisi. '
          'Panggilan tidak dilakukan otomatis.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Buka telepon'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _dial(number);
  }

  double _ringProgress() {
    final now = widget.clock.nowUtc();
    switch (_state) {
      case SosTriggerState.idle:
        return 0;
      case SosTriggerState.holding:
        final start = _holdStarted;
        if (start == null) return 0;
        final total = _trigger.holdDuration.inMilliseconds;
        if (total <= 0) return 1;
        return (now.difference(start).inMilliseconds / total)
            .clamp(0.0, 1.0)
            .toDouble();
      case SosTriggerState.countdown:
        final remaining = _trigger.countdownRemaining(now) ?? Duration.zero;
        final total = _trigger.countdownDuration.inMilliseconds;
        if (total <= 0) return 0;
        return (remaining.inMilliseconds / total)
            .clamp(0.0, 1.0)
            .toDouble();
      case SosTriggerState.triggered:
      case SosTriggerState.cancelled:
        return 1;
    }
  }

  int? _countdownSeconds() {
    if (_state != SosTriggerState.countdown) return null;
    final remaining =
        _trigger.countdownRemaining(widget.clock.nowUtc()) ?? Duration.zero;
    return math.max(0, (remaining.inMilliseconds + 999) ~/ 1000);
  }

  String _headerHint() => switch (_state) {
        SosTriggerState.idle => 'Tekan-tahan 3 detik untuk memulai',
        SosTriggerState.holding => 'Tetap tahan hingga lingkaran penuh',
        SosTriggerState.countdown ||
        SosTriggerState.triggered =>
          'Tekan-tahan 3 detik telah terpenuhi',
        SosTriggerState.cancelled => 'SOS dibatalkan',
      };

  String _copyText() => switch (_state) {
        SosTriggerState.idle =>
          'SOS hanya tersimpan di HP ini. Tidak ada pengiriman otomatis.',
        SosTriggerState.holding => 'Lepas untuk membatalkan.',
        SosTriggerState.countdown => _saving
            ? 'Mencari lokasi GPS sebelum menyimpan…'
            : (_saveNotice ?? 'SOS disimpan otomatis, kecuali dibatalkan.'),
        SosTriggerState.triggered => _saving
            ? 'SOS aktif. Menunggu lokasi GPS untuk disimpan.'
            : (_saveNotice ??
                'SOS tersimpan di HP. Tidak ada pengiriman otomatis ke anggota atau kontak darurat.'),
        SosTriggerState.cancelled => _cancelling
            ? 'Menandai SOS batal di HP…'
            : (_notice ??
                (_savedEvent != null
                    ? 'SOS dibatalkan. Data lokal ditandai batal; tidak ada pesan terkirim.'
                    : 'SOS dibatalkan sebelum tersimpan. Tidak ada data yang dikirim.')),
      };

  String _ringSemantics() => switch (_state) {
        SosTriggerState.idle =>
          'Tombol SOS. Tekan-tahan 3 detik untuk memulai.',
        SosTriggerState.holding => 'Tetap tahan. Lepas untuk membatalkan.',
        SosTriggerState.countdown =>
          'Hitung mundur SOS ${_countdownSeconds() ?? 0} detik. Tombol batal tersedia.',
        SosTriggerState.triggered => 'SOS aktif di perangkat ini.',
        SosTriggerState.cancelled => 'SOS dibatalkan.',
      };

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: altracqDarkTheme,
      child: Builder(
        builder: (context) {
          final colors = AltracqColors.of(context);
          final theme = Theme.of(context);
          // SOS tidak membaca baterai; kebijakan efek di layar ini hanya
          // mengikuti permintaan kurangi animasi dan golongan perangkat.
          return VisualEffectPolicyScope(
            policy: VisualEffectPolicy(
              powerProfile: PowerProfile.normal,
              reduceMotion: MediaQuery.disableAnimationsOf(context),
              deviceTier: _deviceTier,
            ),
            child: PopScope<void>(
              canPop: !_active,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                unawaited(_requestClose());
              },
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light,
                child: Scaffold(
                  backgroundColor: colors.background,
                  body: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                              AltracqSpacing.lg,
                              20,
                              AltracqSpacing.lg,
                              AltracqSpacing.sm,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _header(theme, colors),
                                const SizedBox(height: 20),
                                Center(child: _ring(theme, colors)),
                                const SizedBox(height: AltracqSpacing.lg),
                                Text(
                                  _copyText(),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: _saveNotice != null && !_saving
                                        ? colors.warningText
                                        : colors.textPrimary,
                                    height: 1.4,
                                  ),
                                ),
                                if (_repositoryError != null && !_active) ...<Widget>[
                                  const SizedBox(height: AltracqSpacing.sm),
                                  Text(
                                    _repositoryError!,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.warningText,
                                    ),
                                  ),
                                ],
                                if (_active) ...<Widget>[
                                  const SizedBox(height: AltracqSpacing.lg),
                                  _SosPillButton(
                                    key: const ValueKey('sos-cancel'),
                                    label: 'Batal, saya aman',
                                    onTap: () => unawaited(_cancel()),
                                  ),
                                  const SizedBox(height: AltracqSpacing.lg),
                                  _categoryChips(theme),
                                  const SizedBox(height: 20),
                                  _ladder(theme, colors),
                                ],
                                if (_state == SosTriggerState.cancelled) ...<Widget>[
                                  const SizedBox(height: AltracqSpacing.lg),
                                  _SosPillButton(
                                    key: const ValueKey('sos-reset'),
                                    label: 'Mulai SOS lagi',
                                    onTap: _reset,
                                  ),
                                  const SizedBox(height: 20),
                                  _ladder(theme, colors),
                                ],
                              ],
                            ),
                          ),
                        ),
                        _bottomBar(theme, colors),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(ThemeData theme, AltracqColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        HeaderIconButton(
          key: const ValueKey('sos-close'),
          icon: AltracqIcons.close,
          label: 'Tutup',
          onTap: _cancelling ? null : () => unawaited(_requestClose()),
        ),
        const SizedBox(width: AltracqSpacing.lg),
        Expanded(
          child: Text(
            _headerHint(),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _ring(ThemeData theme, AltracqColors colors) {
    final enabled =
        _state == SosTriggerState.idle || _state == SosTriggerState.cancelled;
    return Listener(
      onPointerDown: enabled ? (_) => _beginHold() : null,
      onPointerUp: _state == SosTriggerState.holding ? (_) => _endHold() : null,
      onPointerCancel:
          _state == SosTriggerState.holding ? (_) => _endHold() : null,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: _ringSemantics(),
        onLongPress: enabled ? _accessibilityTrigger : null,
        child: ExcludeSemantics(
          child: SizedBox(
            key: const ValueKey('sos-ring'),
            width: _ringSize,
            height: _ringSize,
            child: CustomPaint(
              painter: _SosRingPainter(
                progress: _ringProgress(),
                trackColor: colors.textSecondary.withValues(alpha: 0.45),
                arcColor: colors.textPrimary,
              ),
              child: Center(child: _ringCenter(theme, colors)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ringCenter(ThemeData theme, AltracqColors colors) {
    final base = theme.textTheme.displayLarge?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w800,
      height: 1,
    );
    return switch (_state) {
      SosTriggerState.idle ||
      SosTriggerState.holding =>
        Text(
          'SOS',
          style: base?.copyWith(fontSize: 44, letterSpacing: -1),
        ),
      SosTriggerState.countdown => Text(
          '${_countdownSeconds() ?? 0}',
          style: base?.copyWith(fontSize: 56, letterSpacing: -1),
        ),
      SosTriggerState.triggered => AltracqIcon(
          AltracqIcons.warning,
          size: 56,
          color: colors.textPrimary,
          strokeWidth: 1.6,
        ),
      SosTriggerState.cancelled => AltracqIcon(
          AltracqIcons.check,
          size: 60,
          color: colors.textPrimary,
        ),
    };
  }

  Widget _categoryChips(ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        for (final option in _categoryOptions)
          _CategoryChip(
            key: ValueKey('sos-category-${option.category.name}'),
            label: option.label,
            selected: _category == option.category,
            onTap: () => unawaited(_selectCategory(option.category)),
          ),
      ],
    );
  }

  Widget _ladder(ThemeData theme, AltracqColors colors) {
    final saved = _tracker.reached(SosDeliveryStage.savedLocally);
    final delivered = _tracker.reached(SosDeliveryStage.sentToPeers) ||
        _tracker.reached(SosDeliveryStage.acknowledgedByMember) ||
        _tracker.reached(SosDeliveryStage.forwardedToServer) ||
        _tracker.reached(SosDeliveryStage.deliveredToEmergencyContact);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Status pengiriman, ditampilkan apa adanya',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        _LadderRow(
          key: const ValueKey('sos-stage-savedLocally'),
          label: 'Tersimpan di HP',
          reached: saved,
        ),
        _LadderRow(
          key: const ValueKey('sos-stage-sentToPeers'),
          label: 'Diterima ${_tracker.peerCount} anggota',
          reached: _tracker.reached(SosDeliveryStage.sentToPeers),
        ),
        _LadderRow(
          key: const ValueKey('sos-stage-forwardedToServer'),
          label: 'Diteruskan ke server',
          reached: _tracker.reached(SosDeliveryStage.forwardedToServer),
        ),
        _LadderRow(
          key: const ValueKey('sos-stage-deliveredToContact'),
          label: 'Pesan sampai ke kontak darurat',
          reached: _tracker.reached(
            SosDeliveryStage.deliveredToEmergencyContact,
          ),
        ),
        if (saved && !delivered) ...<Widget>[
          const SizedBox(height: AltracqSpacing.sm),
          Text(
            'Hanya penyimpanan lokal yang terjadi. Pengiriman ke anggota, '
            'server, dan kontak darurat belum aktif.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _bottomBar(ThemeData theme, AltracqColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AltracqSpacing.lg,
        AltracqSpacing.sm,
        AltracqSpacing.lg,
        10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _callTrack(
            sliderKey: 'sos-call-115',
            otherKey: 'sos-call-112',
            label: 'Basarnas ${EmergencyNumbers.basarnas}',
            number: EmergencyNumbers.basarnas,
          ),
          const SizedBox(height: AltracqSpacing.md),
          _callTrack(
            sliderKey: 'sos-call-112',
            otherKey: 'sos-call-115',
            label: 'Darurat ${EmergencyNumbers.unified}',
            number: EmergencyNumbers.unified,
          ),
          const SizedBox(height: AltracqSpacing.md),
          Row(
            children: <Widget>[
              AltracqIcon(
                AltracqIcons.phone,
                size: 14,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Geser untuk menelepon',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'SOS tidak menjamin pertolongan datang. Altracq tidak mengklaim '
            'telah menghubungi Basarnas.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _callTrack({
    required String sliderKey,
    required String otherKey,
    required String label,
    required String number,
  }) =>
      SlideToCall(
        key: ValueKey<String>(sliderKey),
        label: label,
        semanticLabel: 'Telepon $label',
        interactive: _activeSlider != otherKey,
        onInteractionChanged: (active) =>
            setState(() => _activeSlider = active ? sliderKey : null),
        onTrigger: () => unawaited(_dial(number)),
        onConfirmRequest: () => unawaited(_confirmDial(number, label)),
      );
}

class _CategoryOption {
  const _CategoryOption(this.category, this.label);

  final SosCategory category;
  final String label;
}

const List<_CategoryOption> _categoryOptions = <_CategoryOption>[
  _CategoryOption(SosCategory.injury, 'CEDERA'),
  _CategoryOption(SosCategory.lost, 'TERSESAT'),
  _CategoryOption(SosCategory.weather, 'CUACA'),
];

class _SosRingPainter extends CustomPainter {
  const _SosRingPainter({
    required this.progress,
    required this.trackColor,
    required this.arcColor,
  });

  final double progress;
  final Color trackColor;
  final Color arcColor;

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = 12;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - stroke / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    if (clamped <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = arcColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * clamped,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_SosRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.arcColor != arcColor;
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Kategori $label',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: selected ? AltracqColors.light.warning : Colors.transparent,
            borderRadius: BorderRadius.circular(AltracqRadius.pill),
            border: selected
                ? null
                : Border.all(
                    color: colors.textPrimary.withValues(alpha: 0.55),
                  ),
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: ExcludeSemantics(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? AltracqColors.light.surface
                      : colors.textPrimary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SosPillButton extends StatelessWidget {
  const _SosPillButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AltracqColors.light.surface,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: Center(
              child: ExcludeSemantics(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AltracqColors.light.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LadderRow extends StatelessWidget {
  const _LadderRow({
    super.key,
    required this.label,
    required this.reached,
  });

  final String label;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label: ${reached ? 'sudah' : 'belum'}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                decoration: reached
                    ? BoxDecoration(
                        color: AltracqColors.light.secondary,
                        shape: BoxShape.circle,
                      )
                    : BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.textSecondary.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                      ),
                child: reached
                    ? Center(
                        child: AltracqIcon(
                          AltracqIcons.check,
                          size: 14,
                          strokeWidth: 2.2,
                          color: AltracqColors.light.textPrimary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: AltracqSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color:
                        reached ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
