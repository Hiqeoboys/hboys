import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/clock.dart';
import 'supabase_services.dart';

typedef PresencePingFn = Future<void> Function();

/// Mengelola kehadiran "Terakhir aktif" (`profiles.last_seen_at`) berdasarkan
/// pembukaan aplikasi (lifecycle `resumed` & heartbeat berkala setiap 2,5 menit),
/// terpisah sepenuhnya dari fitur berbagi lokasi grup.
class AppPresenceService with WidgetsBindingObserver {
  AppPresenceService({
    PresencePingFn? pingFn,
    Clock clock = const SystemClock(),
    Duration interval = const Duration(minutes: 2, seconds: 30),
    Duration minGap = const Duration(seconds: 30),
  })  : _pingFn = pingFn ?? _defaultPing,
        _clock = clock,
        _interval = interval,
        _minGap = minGap;

  static final AppPresenceService instance = AppPresenceService();

  final PresencePingFn _pingFn;
  final Clock _clock;
  final Duration _interval;
  final Duration _minGap;

  Timer? _timer;
  bool _started = false;
  bool _observerAttached = false;
  bool _inFlight = false;
  DateTime? _lastPingAtUtc;

  bool get isStarted => _started;
  bool get isHeartbeatActive => _timer?.isActive ?? false;

  /// Mulai mengamati lifecycle aplikasi dan menjalankan ping kehadiran berkala.
  void start() {
    if (!_observerAttached) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observerAttached = true;
      } catch (_) {
        // Aman pada unit test tanpa WidgetsBinding.
      }
    }
    _started = true;
    _startTimer();
    unawaited(pingNow());
  }

  /// Menghentikan observer dan timer heartbeat (dipanggil saat logout / hapus akun).
  void stop() {
    _started = false;
    _stopTimer();
    if (_observerAttached) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observerAttached = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _startTimer();
        unawaited(pingNow());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _stopTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      unawaited(pingNow());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Mengirim pembaruan `profiles.last_seen_at = now()` dengan throttle agar
  /// event resume beruntun tidak membebani database.
  Future<bool> pingNow({bool force = false}) async {
    if (_inFlight) return false;
    final now = _clock.nowUtc();
    if (!force && _lastPingAtUtc != null) {
      final elapsed = now.difference(_lastPingAtUtc!);
      if (elapsed < _minGap) return false;
    }

    _inFlight = true;
    try {
      await _pingFn();
      _lastPingAtUtc = _clock.nowUtc();
      return true;
    } catch (_) {
      return false;
    } finally {
      _inFlight = false;
    }
  }

  static Future<void> _defaultPing() async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      await client.rpc('touch_last_seen');
    } on PostgrestException catch (error) {
      final msg = '${error.message} ${error.details ?? ''}';
      if (error.code == 'PGRST202' ||
          error.code == '42883' ||
          msg.contains('touch_last_seen')) {
        await client
            .from('profiles')
            .update(<String, dynamic>{
              'last_seen_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', user.id);
      }
    } catch (_) {}
  }

  @visibleForTesting
  void resetThrottleForTesting() {
    _lastPingAtUtc = null;
  }
}
