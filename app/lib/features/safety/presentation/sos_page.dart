import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/brand/app_brand.dart';
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
import '../../chat/domain/group_chat_models.dart';
import '../application/sos_action_service.dart';
import '../application/sos_location.dart';
import '../application/sos_offline_queue_service.dart';
import '../application/sos_sms_service.dart';
import '../domain/safety_repository.dart';
import '../domain/sos_category.dart';
import '../domain/sos_event.dart';
import '../domain/sos_status_tracker.dart';
import '../domain/sos_trigger_controller.dart';
import 'slide_to_call.dart';

const double _ringSize = 188;

/// Konstanta tunggal untuk menampilkan petunjuk sekali pakai
/// "Tahan cincin untuk mengaktifkan" di bawah cincin SOS pada pembukaan pertama.
const bool kShowSosHoldHint = false;

const String _kSosHoldHintSeenKey = 'hiqeo_sos_hold_hint_seen_v1';

/// Layar SOS selalu memakai palet terbalik (biru gelap), tidak mengikuti tema
/// aplikasi. Tahan 3 detik langsung memicu senter Morse, sirene volume penuh,
/// penyimpanan lokal, 1 UPSERT `sos_events`, pesan grup/Hiqeo Mesh, dan SMS.
class SosPage extends StatefulWidget {
  const SosPage({
    super.key,
    this.repository,
    this.locationProvider = const DeviceSosLocationProvider(),
    this.dialer = const MethodChannelPhoneDialer(),
    this.actionRunner,
    this.smsSender,
    this.offlineQueue,
    this.clock = const SystemClock(),
    this.showHoldHint = kShowSosHoldHint,
  });

  /// Disuntikkan untuk uji; produksi membuka basis data perangkat.
  final SafetyRepository? repository;
  final SosLocationProvider locationProvider;
  final PhoneDialer dialer;
  final SosActionRunner? actionRunner;
  final SosSmsSender? smsSender;
  final SosOfflineQueueService? offlineQueue;
  final Clock clock;
  final bool showHoldHint;

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  static final DeviceTier _deviceTier = VisualEffectPolicy.probeDeviceTier();

  late final SosTriggerController _trigger = SosTriggerController(
    holdDuration: const Duration(seconds: 3),
    countdownDuration: Duration.zero,
  );
  late final SosActionRunner _actionRunner =
      widget.actionRunner ?? DeviceSosActionRunner();
  late final SosSmsSender _smsSender =
      widget.smsSender ?? const MethodChannelSosSmsSender();
  late final SosOfflineQueueService _offlineQueue =
      widget.offlineQueue ?? SosOfflineQueueService.instance;
  late final Future<SafetyRepository?> _repositoryFuture;

  AppDatabase? _database;
  String? _repositoryError;

  SosStatusTracker _tracker = SosStatusTracker();
  SosCategory _category = SosCategory.other;
  SosEvent? _savedEvent;
  SosDispatchOutcome? _sosOutcome;
  String? _activeSosUuid;
  bool _cancelRequested = false;
  bool _cancelling = false;
  bool _saving = false;
  String? _saveNotice;
  String? _notice;
  Object? _token;
  DateTime? _holdStarted;
  Future<SosFix?>? _fixFuture;
  Timer? _ticker;
  bool _smsSupported = false;
  bool _smsGranted = true;

  /// Kunci trek geser yang sedang dipakai, supaya hanya satu yang aktif.
  String? _activeSlider;
  bool _showFirstTimeHint = false;

  @override
  void initState() {
    super.initState();
    _offlineQueue.addListener(_onQueueChanged);
    unawaited(_offlineQueue.load());
    final injected = widget.repository;
    if (injected != null) {
      _repositoryFuture = Future<SafetyRepository?>.value(injected);
    } else {
      _repositoryFuture = _openRepository();
    }
    if (widget.showHoldHint) {
      unawaited(_loadHoldHintSeen());
    }
    unawaited(_initSmsPermissionState());
  }

  void _onQueueChanged() {
    if (!mounted) return;
    final activeId = _activeSosUuid;
    if (activeId != null && _offlineQueue.wasSynced(activeId)) {
      _tracker.mark(SosDeliveryStage.forwardedToServer);
    }
    setState(() {});
  }

  Future<void> _initSmsPermissionState() async {
    if (!_smsSender.isSupported) return;
    final granted = await _smsSender.hasPermission();
    if (!mounted) return;
    setState(() {
      _smsSupported = true;
      _smsGranted = granted;
    });
    if (!granted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final approved = await promptEmergencySmsPermission(
          context,
          sender: _smsSender,
          onlyOncePerInstall: true,
        );
        if (mounted) {
          setState(() => _smsGranted = approved);
        }
      });
    }
  }

  Future<void> _requestSmsPermissionFromChip() async {
    final approved = await promptEmergencySmsPermission(
      context,
      sender: _smsSender,
    );
    if (!mounted) return;
    setState(() => _smsGranted = approved);
  }

  Future<void> _loadHoldHintSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_kSosHoldHintSeenKey) ?? false;
      if (!seen && mounted) {
        setState(() => _showFirstTimeHint = true);
        await prefs.setBool(_kSosHoldHintSeenKey, true);
      }
    } catch (_) {
      if (mounted) setState(() => _showFirstTimeHint = true);
    }
  }

  @override
  void dispose() {
    _offlineQueue.removeListener(_onQueueChanged);
    _ticker?.cancel();
    if (_active ||
        _sosOutcome?.flashlightActive == true ||
        _sosOutcome?.sirenActive == true) {
      unawaited(
        _actionRunner.deactivate(
          remoteSosId: _sosOutcome?.remoteSosId ?? _activeSosUuid,
        ),
      );
    }
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
      const Duration(milliseconds: 50),
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
        (after == SosTriggerState.countdown ||
            after == SosTriggerState.triggered)) {
      _activateSos(now);
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
    _sosOutcome = null;
    _activeSosUuid = null;
    _tracker = SosStatusTracker();
    _category = SosCategory.other;
    _holdStarted = now;
    _showFirstTimeHint = false;
    unawaited(HapticFeedback.mediumImpact());
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

  void _activateSos(DateTime now) {
    unawaited(HapticFeedback.heavyImpact());
    _saving = true;
    _saveNotice = null;
    final sosUuid = generateUuidV4();
    _activeSosUuid = sosUuid;
    unawaited(
      _dispatchAndPersistSos(
        token: _token,
        sosUuid: sosUuid,
        fix: _fixFuture,
        category: _category,
        startedAt: now,
      ),
    );
  }

  Future<void> _dispatchAndPersistSos({
    required Object? token,
    required String sosUuid,
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
    if (_cancelRequested) {
      setState(() => _saving = false);
      return;
    }

    // Jalankan aksi perangkat keras & jaringan (senter Morse, sirene volume
    // maksimal, 1 UPSERT sos_events, pesan grup/Mesh, SMS darurat) bersamaan
    // dengan penyimpanan lokal SQLite.
    final actionFuture = _actionRunner
        .activate(
          sosUuid: sosUuid,
          fix: located,
          category: category,
          triggeredAtUtc: startedAt,
          safetyRepository: repository,
        )
        .catchError((Object _) => const SosDispatchOutcome());

    SosEvent? savedEvent;
    String? localNotice;
    if (located == null) {
      localNotice =
          'Lokasi GPS belum tersedia. Senter & sirene SOS tetap aktif; koordinat belum tersimpan di HP.';
    } else if (repository == null) {
      localNotice =
          'Penyimpanan lokal belum siap. Senter & sirene SOS tetap aktif.';
    } else {
      final candidate = SosEvent(
        id: sosUuid,
        authorId: 'perangkat-lokal',
        category: category,
        lat: located.lat,
        lon: located.lon,
        accuracyM: located.accuracyM,
        createdAtUtc: startedAt,
        receivedAtUtc: widget.clock.nowUtc(),
      );
      try {
        await repository.saveSosEvent(candidate);
        savedEvent = candidate;
      } catch (_) {
        localNotice = 'SOS gagal disimpan di HP. Coba lagi.';
      }
    }

    final outcome = await actionFuture;

    if (!mounted || token != _token) {
      if (outcome.flashlightActive || outcome.sirenActive) {
        unawaited(
          _actionRunner.deactivate(
            remoteSosId: outcome.remoteSosId ?? sosUuid,
          ),
        );
      }
      return;
    }

    if (_cancelRequested) {
      unawaited(
        _actionRunner.deactivate(remoteSosId: outcome.remoteSosId ?? sosUuid),
      );
      if (savedEvent != null) {
        await _cancelPersisted(savedEvent);
      }
      if (mounted) setState(() => _saving = false);
      return;
    }

    if (savedEvent != null) {
      _tracker.mark(SosDeliveryStage.savedLocally);
    }
    if (outcome.sentGroupMessage || outcome.sentMeshBroadcast) {
      _tracker.mark(SosDeliveryStage.sentToPeers, peers: 1);
    }
    if (outcome.savedRemoteUpsert || _offlineQueue.wasSynced(sosUuid)) {
      _tracker.mark(SosDeliveryStage.forwardedToServer);
    }
    if (outcome.notifiedEmergencyContacts ||
        outcome.sentDirectSms ||
        outcome.openedOfflineSms ||
        outcome.whatsappAutoSent) {
      _tracker.mark(SosDeliveryStage.deliveredToEmergencyContact);
    }

    setState(() {
      _savedEvent = savedEvent;
      _sosOutcome = outcome;
      _saving = false;
      _saveNotice = localNotice;
    });

    if (savedEvent != null && _category != savedEvent.category) {
      await _persistCategory(savedEvent, _category);
    }
  }

  Future<void> _cancel() async {
    if (!_active) return;
    _trigger.cancel();
    _stopTicker();
    _cancelRequested = true;
    setState(() => _cancelling = true);
    final remoteId = _sosOutcome?.remoteSosId ?? _activeSosUuid;
    if (remoteId != null) {
      unawaited(_offlineQueue.markCancelled(remoteId, widget.clock.nowUtc()));
    }
    try {
      await _actionRunner.deactivate(remoteSosId: remoteId);
    } catch (_) {}
    _sosOutcome = null;
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
    _sosOutcome = null;
    _activeSosUuid = null;
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
    _activateSos(startedAt);
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
        title: const Text('Matikan SOS?'),
        content: const Text(
          'Senter Morse, sirene darurat, dan status SOS aktif akan dimatikan.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Biarkan aktif'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Matikan SOS'),
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
          '${AppBrand.name} membuka aplikasi telepon dengan nomor terisi. '
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
        return (remaining.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
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
        SosTriggerState.idle => '',
        SosTriggerState.holding => 'Tetap tahan hingga lingkaran penuh',
        SosTriggerState.countdown => 'Tekan-tahan 3 detik telah terpenuhi',
        SosTriggerState.triggered => 'SOS aktif',
        SosTriggerState.cancelled => 'SOS dimatikan',
      };

  String _copyText() => switch (_state) {
        SosTriggerState.idle => 'Tekan dan tahan 3 detik',
        SosTriggerState.holding =>
          'Tetap tahan hingga penuh. Lepas untuk membatalkan.',
        SosTriggerState.countdown => _saving
            ? 'Mengaktifkan SOS…'
            : (_saveNotice ?? 'SOS aktif.'),
        SosTriggerState.triggered => _saving
            ? 'Mengaktifkan SOS, senter Morse & sirene…'
            : (_saveNotice ??
                'SOS aktif. Senter Morse, sirene, dan peringatan darurat sedang berjalan.'),
        SosTriggerState.cancelled => _cancelling
            ? 'Mematikan SOS…'
            : (_notice ??
                (_savedEvent != null
                    ? 'SOS dimatikan. Senter, sirene, dan status darurat telah dihentikan.'
                    : 'SOS dimatikan.')),
      };

  String _ringSemantics() => switch (_state) {
        SosTriggerState.idle =>
          'Tombol SOS. Tekan dan tahan 3 detik untuk mengaktifkan.',
        SosTriggerState.holding => 'Tetap tahan. Lepas untuk membatalkan.',
        SosTriggerState.countdown =>
          'Hitung mundur SOS ${_countdownSeconds() ?? 0} detik. Tombol matikan tersedia.',
        SosTriggerState.triggered =>
          'SOS aktif. Senter Morse dan sirene darurat sedang menyala.',
        SosTriggerState.cancelled => 'SOS dimatikan.',
      };

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: hiqeoDarkTheme,
      child: Builder(
        builder: (context) {
          final colors = HiqeoColors.of(context);
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
                              HiqeoSpacing.lg,
                              20,
                              HiqeoSpacing.lg,
                              HiqeoSpacing.sm,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _header(theme, colors),
                                const SizedBox(height: 20),
                                Center(child: _ring(theme, colors)),
                                if (_showFirstTimeHint &&
                                    _state == SosTriggerState.idle) ...<Widget>[
                                  const SizedBox(height: 12),
                                  Text(
                                    'Tahan cincin untuk mengaktifkan',
                                    key: const ValueKey<String>(
                                      'sos-first-time-hint',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: HiqeoSpacing.lg),
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
                                if (_smsSupported &&
                                    !_smsGranted &&
                                    !_active) ...<Widget>[
                                  const SizedBox(height: HiqeoSpacing.md),
                                  Center(
                                    child: OutlinedButton.icon(
                                      key: const ValueKey<String>(
                                        'sos-enable-sms-pill',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: colors.textPrimary,
                                        side: BorderSide(
                                          color: colors.warning
                                              .withValues(alpha: 0.65),
                                        ),
                                        shape: const StadiumBorder(),
                                      ),
                                      onPressed: () => unawaited(
                                        _requestSmsPermissionFromChip(),
                                      ),
                                      icon: const Icon(
                                        Icons.sms_outlined,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'Aktifkan SMS darurat otomatis',
                                      ),
                                    ),
                                  ),
                                ],
                                if (_repositoryError != null &&
                                    !_active) ...<Widget>[
                                  const SizedBox(height: HiqeoSpacing.sm),
                                  Text(
                                    _repositoryError!,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.warningText,
                                    ),
                                  ),
                                ],
                                if (_active) ...<Widget>[
                                  if (_sosOutcome?.flashlightActive == true ||
                                      _sosOutcome?.sirenActive == true) ...<Widget>[
                                    const SizedBox(height: HiqeoSpacing.md),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: <Widget>[
                                        if (_sosOutcome?.flashlightActive ==
                                            true)
                                          const _HardwareBadge(
                                            key: ValueKey(
                                              'sos-hardware-flashlight',
                                            ),
                                            icon: Icons.flashlight_on_rounded,
                                            label: 'Senter Morse SOS',
                                          ),
                                        if (_sosOutcome?.sirenActive == true)
                                          const _HardwareBadge(
                                            key: ValueKey(
                                              'sos-hardware-siren',
                                            ),
                                            icon: Icons.volume_up_rounded,
                                            label: 'Sirene aktif',
                                          ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: HiqeoSpacing.lg),
                                  _SosPillButton(
                                    key: const ValueKey('sos-cancel'),
                                    label: 'Matikan SOS',
                                    onTap: () => unawaited(_cancel()),
                                  ),
                                  const SizedBox(height: HiqeoSpacing.lg),
                                  _categoryChips(theme),
                                  const SizedBox(height: 20),
                                  _ladder(theme, colors),
                                ],
                                if (_state ==
                                    SosTriggerState.cancelled) ...<Widget>[
                                  const SizedBox(height: HiqeoSpacing.lg),
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

  Widget _header(ThemeData theme, HiqeoColors colors) {
    final hint = _headerHint();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        HeaderIconButton(
          key: const ValueKey('sos-close'),
          icon: HiqeoIcons.close,
          label: 'Tutup',
          onTap: _cancelling ? null : () => unawaited(_requestClose()),
        ),
        if (hint.isNotEmpty) ...<Widget>[
          const SizedBox(width: HiqeoSpacing.lg),
          Expanded(
            child: Text(
              hint,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ring(ThemeData theme, HiqeoColors colors) {
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
                arcColor: _state == SosTriggerState.triggered
                    ? colors.warning
                    : colors.textPrimary,
                fillColor: _state == SosTriggerState.triggered
                    ? colors.warning.withValues(alpha: 0.34)
                    : colors.warning.withValues(alpha: 0.24),
              ),
              child: Center(child: _ringCenter(theme, colors)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ringCenter(ThemeData theme, HiqeoColors colors) {
    final base = theme.textTheme.displayLarge?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w800,
      height: 1,
    );
    return switch (_state) {
      SosTriggerState.idle || SosTriggerState.holding => Text(
          'SOS',
          style: base?.copyWith(fontSize: 44, letterSpacing: -1),
        ),
      SosTriggerState.countdown => Text(
          '${_countdownSeconds() ?? 0}',
          style: base?.copyWith(fontSize: 56, letterSpacing: -1),
        ),
      SosTriggerState.triggered => HiqeoIcon(
          HiqeoIcons.warning,
          size: 56,
          color: colors.textPrimary,
          strokeWidth: 1.6,
        ),
      SosTriggerState.cancelled => HiqeoIcon(
          HiqeoIcons.check,
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

  Widget _ladder(ThemeData theme, HiqeoColors colors) {
    final outcome = _sosOutcome;
    final activeId = _activeSosUuid;
    final saved = _tracker.reached(SosDeliveryStage.savedLocally);
    final syncedFromQueue =
        activeId != null && _offlineQueue.wasSynced(activeId);
    final waitingInternetSync = !syncedFromQueue &&
        (outcome?.queuedForServerSync == true ||
            (activeId != null && _offlineQueue.isPending(activeId)));

    final serverReached =
        _tracker.reached(SosDeliveryStage.forwardedToServer) || syncedFromQueue;
    final contactReached =
        _tracker.reached(SosDeliveryStage.deliveredToEmergencyContact);

    final peerLabel = outcome?.sentMeshBroadcast == true &&
            outcome?.sentGroupMessage != true
        ? 'Disiarkan via Hiqeo Mesh (offline)'
        : (outcome?.sentGroupMessage == true && outcome?.sentMeshBroadcast == true
            ? 'Terkirim ke chat grup & Hiqeo Mesh'
            : (outcome?.sentGroupMessage == true
                ? 'Terkirim ke ruang obrolan grup'
                : 'Pesan grup / Hiqeo Mesh'));

    final serverLabel = serverReached
        ? 'Terkirim ke server & kontak Hiqeo'
        : (waitingInternetSync
            ? 'Menunggu sinyal internet untuk sinkronisasi server'
            : 'Diteruskan ke server');

    final String contactLabel;
    if (outcome?.sentDirectSms == true && outcome?.whatsappAutoSent == true) {
      contactLabel = 'SMS Darurat & WhatsApp terkirim otomatis';
    } else if (outcome?.sentDirectSms == true) {
      contactLabel = 'SMS Darurat terkirim otomatis';
    } else if (outcome?.openedOfflineSms == true) {
      contactLabel = 'Draft SMS darurat dibuka otomatis';
    } else if (outcome?.whatsappAutoSent == true) {
      contactLabel = 'Pesan WhatsApp & kontak darurat terkirim otomatis';
    } else if (outcome?.smsPermissionDenied == true &&
        outcome?.hasPhoneEmergencyContacts == true) {
      contactLabel = 'Izin SMS darurat otomatis belum diaktifkan';
    } else {
      contactLabel = 'Pesan sampai ke kontak darurat';
    }

    final anyExternalDelivery =
        _tracker.reached(SosDeliveryStage.sentToPeers) ||
            serverReached ||
            contactReached;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Status pengiriman',
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
          label: peerLabel,
          reached: _tracker.reached(SosDeliveryStage.sentToPeers),
        ),
        _LadderRow(
          key: const ValueKey('sos-stage-forwardedToServer'),
          label: serverLabel,
          reached: serverReached,
          pending: waitingInternetSync && !serverReached,
        ),
        _LadderRow(
          key: const ValueKey('sos-stage-deliveredToContact'),
          label: contactLabel,
          reached: contactReached,
        ),
        if (saved && waitingInternetSync && !serverReached) ...<Widget>[
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            'SOS akan otomatis dikirim ke server begitu sinyal internet kembali tersedia.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ] else if (saved && !anyExternalDelivery) ...<Widget>[
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            'Mode offline / tanpa grup aktif: senter Morse & sirene tetap bekerja 100% di HP ini.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _bottomBar(ThemeData theme, HiqeoColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HiqeoSpacing.lg,
        HiqeoSpacing.sm,
        HiqeoSpacing.lg,
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
          const SizedBox(height: HiqeoSpacing.md),
          _callTrack(
            sliderKey: 'sos-call-112',
            otherKey: 'sos-call-115',
            label: 'Darurat ${EmergencyNumbers.unified}',
            number: EmergencyNumbers.unified,
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Row(
            children: <Widget>[
              HiqeoIcon(
                HiqeoIcons.phone,
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
            'SOS tidak menjamin pertolongan datang. ${AppBrand.name} tidak '
            'mengklaim telah menghubungi Basarnas.',
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

class _HardwareBadge extends StatelessWidget {
  const _HardwareBadge({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
        border: Border.all(color: colors.warning.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: colors.textPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SosRingPainter extends CustomPainter {
  const _SosRingPainter({
    required this.progress,
    required this.trackColor,
    required this.arcColor,
    required this.fillColor,
  });

  final double progress;
  final Color trackColor;
  final Color arcColor;
  final Color fillColor;

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
    final fillRadius = (radius - stroke / 2) * clamped;
    if (fillRadius > 0) {
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor;
      canvas.drawCircle(center, fillRadius, fill);
    }
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
      oldDelegate.arcColor != arcColor ||
      oldDelegate.fillColor != fillColor;
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
    final colors = HiqeoColors.of(context);
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
            color: selected ? HiqeoColors.light.warning : Colors.transparent,
            borderRadius: BorderRadius.circular(HiqeoRadius.pill),
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
                  color:
                      selected ? HiqeoColors.light.surface : colors.textPrimary,
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
        color: HiqeoColors.light.surface,
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
                    color: HiqeoColors.light.textPrimary,
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
    this.pending = false,
  });

  final String label;
  final bool reached;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final semanticSuffix = reached ? 'sudah' : (pending ? 'menunggu' : 'belum');
    return Semantics(
      container: true,
      label: '$label: $semanticSuffix',
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
                        color: HiqeoColors.light.secondary,
                        shape: BoxShape.circle,
                      )
                    : BoxDecoration(
                        color: pending
                            ? colors.warning.withValues(alpha: 0.22)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: pending
                              ? colors.warning
                              : colors.textSecondary.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                      ),
                child: reached
                    ? Center(
                        child: HiqeoIcon(
                          HiqeoIcons.check,
                          size: 14,
                          strokeWidth: 2.2,
                          color: HiqeoColors.light.textPrimary,
                        ),
                      )
                    : (pending
                        ? Center(
                            child: Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: colors.warning,
                            ),
                          )
                        : null),
              ),
              const SizedBox(width: HiqeoSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: (reached || pending)
                        ? colors.textPrimary
                        : colors.textSecondary,
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
