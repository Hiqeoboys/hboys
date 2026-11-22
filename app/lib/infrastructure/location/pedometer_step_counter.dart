import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StepSourceState {
  checking,
  sensorActive,
  permissionNeeded,
  sensorUnavailable,
}

/// Menghitung perkiraan langkah dari jarak tempuh:
///   langkah = jarak / (0,415 x tinggi_badan_m)
int estimateStepsFromDistance({
  required double distanceM,
  double heightCm = 170,
}) {
  if (!distanceM.isFinite || distanceM <= 0) return 0;
  final heightM = (heightCm > 50 ? heightCm : 170) / 100.0;
  final strideM = 0.415 * heightM;
  if (strideM <= 0) return 0;
  return (distanceM / strideM).round();
}

/// Pembaca sensor langkah perangkat (`Sensor.TYPE_STEP_COUNTER` di Android /
/// CoreMotion di iOS) yang menyimpan baseline awal sesi (`initialStepBaseline`),
/// memotong langkah saat sesi dijeda, dan menjaga hitungan jika sensor reset.
class PedometerStepCounter extends ChangeNotifier {
  PedometerStepCounter({
    Stream<int>? stepStreamOverride,
    bool persistBaseline = true,
    DateTime Function()? clockNowUtc,
    this.calibrationWindow = const Duration(seconds: 2),
  })  : _stepStreamOverride = stepStreamOverride,
        _persistBaseline = persistBaseline,
        _clockNowUtc = clockNowUtc ?? _defaultClockNowUtc;

  static DateTime _defaultClockNowUtc() => DateTime.now().toUtc();

  static const String _storageKey = 'hiqeo_step_baseline_v1';

  final Stream<int>? _stepStreamOverride;
  final bool _persistBaseline;
  final DateTime Function() _clockNowUtc;
  final Duration calibrationWindow;

  StreamSubscription<int>? _subscription;
  StepSourceState _state = StepSourceState.checking;
  int? _initialStepBaseline;
  int? _lastRawSensorSteps;
  int? _pauseStartedRawSteps;
  int _pausedStepsOffset = 0;
  int _sessionSteps = 0;
  bool _isPaused = false;
  bool _isGpsMoving = true;
  DateTime? _sessionStartedAtUtc;
  String? _activeSessionId;

  StepSourceState get state => _state;
  int? get sensorSteps =>
      _state == StepSourceState.sensorActive ? _sessionSteps : null;

  @visibleForTesting
  int? get initialStepBaseline => _initialStepBaseline;

  @visibleForTesting
  int get pausedStepsOffset => _pausedStepsOffset;

  void syncSession({
    required String? sessionId,
    required bool activityPermissionGranted,
    bool isPaused = false,
    bool isFinished = false,
    bool? isGpsMoving,
  }) {
    if (isGpsMoving != null) {
      _isGpsMoving = isGpsMoving;
    }
    if (sessionId == null) {
      stop();
      return;
    }

    if (isFinished) {
      if (_activeSessionId == sessionId) {
        _subscription?.cancel();
        _subscription = null;
        _isPaused = false;
        _pauseStartedRawSteps = null;
        if (_persistBaseline) {
          unawaited(_clearPersistedBaseline());
        }
      }
      return;
    }

    if (!activityPermissionGranted) {
      _subscription?.cancel();
      _subscription = null;
      _activeSessionId = sessionId;
      _isPaused = isPaused;
      if (_state != StepSourceState.permissionNeeded) {
        _state = StepSourceState.permissionNeeded;
        notifyListeners();
      }
      return;
    }

    if (_activeSessionId != sessionId) {
      _activeSessionId = sessionId;
      _sessionStartedAtUtc = _clockNowUtc();
      _initialStepBaseline = null;
      _lastRawSensorSteps = null;
      _pauseStartedRawSteps = null;
      _pausedStepsOffset = 0;
      _sessionSteps = 0;
      _isPaused = isPaused;
      if (_persistBaseline) {
        unawaited(_restorePersistedBaseline(sessionId));
      }
      _startListening();
      return;
    }

    _updatePauseState(isPaused);
    if (_subscription == null) {
      _startListening();
    }
  }

  void _updatePauseState(bool paused) {
    if (_isPaused == paused) return;
    if (paused) {
      _isPaused = true;
      _pauseStartedRawSteps = _lastRawSensorSteps;
    } else {
      if (_pauseStartedRawSteps != null && _lastRawSensorSteps != null) {
        _pausedStepsOffset += math.max(
          0,
          _lastRawSensorSteps! - _pauseStartedRawSteps!,
        );
      }
      _pauseStartedRawSteps = null;
      _isPaused = false;
      if (_persistBaseline) {
        unawaited(_savePersistedBaseline());
      }
      notifyListeners();
    }
  }

  void _handleSensorReading(int totalSteps) {
    if (_initialStepBaseline == null) {
      _initialStepBaseline = totalSteps;
      _lastRawSensorSteps = totalSteps;
      _pausedStepsOffset = 0;
      _pauseStartedRawSteps = _isPaused ? totalSteps : null;
      _sessionSteps = 0;
      _state = StepSourceState.sensorActive;
      if (_persistBaseline) unawaited(_savePersistedBaseline());
      notifyListeners();
      return;
    }

    final prevRaw = _lastRawSensorSteps;
    if (prevRaw != null && totalSteps < prevRaw) {
      // Sensor perangkat di-reset (misal perangkat baru menyala ulang).
      _initialStepBaseline = totalSteps - _sessionSteps;
      _pausedStepsOffset = 0;
      _pauseStartedRawSteps = _isPaused ? totalSteps : null;
      _lastRawSensorSteps = totalSteps;
    } else {
      _lastRawSensorSteps = totalSteps;
    }

    // Jendela kalibrasi awal (1–2 detik pertama): buang flush batch hardware
    // TYPE_STEP_COUNTER dengan menggeser baseline sehingga langkah mulai bersih di 0.
    final startedAt = _sessionStartedAtUtc;
    if (startedAt != null &&
        calibrationWindow > Duration.zero &&
        _clockNowUtc().difference(startedAt) < calibrationWindow) {
      _initialStepBaseline = totalSteps - _pausedStepsOffset;
      _pauseStartedRawSteps = _isPaused ? totalSteps : null;
      _sessionSteps = 0;
      _state = StepSourceState.sensorActive;
      if (_persistBaseline) unawaited(_savePersistedBaseline());
      notifyListeners();
      return;
    }

    if (_isPaused) {
      _pauseStartedRawSteps ??= totalSteps;
      if (_state != StepSourceState.sensorActive) {
        _state = StepSourceState.sensorActive;
        notifyListeners();
      }
      if (_persistBaseline) unawaited(_savePersistedBaseline());
      return;
    }

    // Penjaga lonjakan saat diam: jika GPS memastikan berhenti (speed == 0)
    // namun sensor memuntahkan > 4 langkah sekaligus, serap lonjakan itu ke offset.
    final delta = prevRaw != null ? (totalSteps - prevRaw) : 0;
    if (!_isGpsMoving && delta > 4) {
      _pausedStepsOffset += delta;
    }

    _sessionSteps = math.max(
      0,
      totalSteps - _initialStepBaseline! - _pausedStepsOffset,
    );
    _state = StepSourceState.sensorActive;
    if (_persistBaseline) unawaited(_savePersistedBaseline());
    notifyListeners();
  }

  void _startListening() {
    _subscription?.cancel();
    try {
      final stream = _stepStreamOverride ??
          Pedometer.stepCountStream.map((event) => event.steps);
      _subscription = stream.listen(
        _handleSensorReading,
        onError: (_) {
          _state = StepSourceState.sensorUnavailable;
          notifyListeners();
        },
      );
    } catch (_) {
      _state = StepSourceState.sensorUnavailable;
      notifyListeners();
    }
  }

  Future<void> _restorePersistedBaseline(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['sessionId'] != sessionId) return;
      if (_activeSessionId != sessionId) return;

      final baseline = (decoded['initialStepBaseline'] as num?)?.toInt();
      final lastRaw = (decoded['lastRawSensorSteps'] as num?)?.toInt();
      final pausedOffset = (decoded['pausedStepsOffset'] as num?)?.toInt() ?? 0;
      final savedSteps = (decoded['sessionSteps'] as num?)?.toInt() ?? 0;

      if (baseline != null && _initialStepBaseline == null) {
        _initialStepBaseline = baseline;
        _lastRawSensorSteps = lastRaw;
        _pausedStepsOffset = pausedOffset;
        _sessionSteps = savedSteps;
        if (_isPaused) {
          _pauseStartedRawSteps = lastRaw;
        }
        _state = StepSourceState.sensorActive;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _savePersistedBaseline() async {
    final sessionId = _activeSessionId;
    final baseline = _initialStepBaseline;
    if (sessionId == null || baseline == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(<String, Object?>{
          'sessionId': sessionId,
          'initialStepBaseline': baseline,
          'lastRawSensorSteps': _lastRawSensorSteps,
          'pausedStepsOffset': _pausedStepsOffset,
          'sessionSteps': _sessionSteps,
        }),
      );
    } catch (_) {}
  }

  Future<void> _clearPersistedBaseline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }

  void markSensorUnavailable() {
    _subscription?.cancel();
    _subscription = null;
    if (_state != StepSourceState.sensorUnavailable) {
      _state = StepSourceState.sensorUnavailable;
      notifyListeners();
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _activeSessionId = null;
    _initialStepBaseline = null;
    _lastRawSensorSteps = null;
    _pauseStartedRawSteps = null;
    _pausedStepsOffset = 0;
    _sessionSteps = 0;
    _isPaused = false;
    if (_persistBaseline) {
      unawaited(_clearPersistedBaseline());
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}

