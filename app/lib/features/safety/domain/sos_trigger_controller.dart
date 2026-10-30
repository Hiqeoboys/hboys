enum SosTriggerState { idle, holding, countdown, triggered, cancelled }

/// Mesin status pemicu SOS: tekan-tahan lalu hitung mundur dengan opsi batal.
/// Setelah hitung mundur dimulai, melepas jari TIDAK membatalkan; pengguna harus
/// menekan batal. Waktu disuntikkan lewat parameter agar mudah diuji.
class SosTriggerController {
  SosTriggerController({
    this.holdDuration = const Duration(seconds: 3),
    this.countdownDuration = const Duration(seconds: 5),
  });

  final Duration holdDuration;
  final Duration countdownDuration;

  SosTriggerState _state = SosTriggerState.idle;
  DateTime? _holdStart;
  DateTime? _countdownStart;

  SosTriggerState get state => _state;

  void holdStarted(DateTime now) {
    if (_state == SosTriggerState.idle || _state == SosTriggerState.cancelled) {
      _state = SosTriggerState.holding;
      _holdStart = now;
    }
  }

  void holdReleased() {
    if (_state == SosTriggerState.holding) {
      _state = SosTriggerState.idle;
      _holdStart = null;
    }
  }

  /// Panggil berkala (mis. tiap 100 ms) untuk memajukan state.
  SosTriggerState tick(DateTime now) {
    if (_state == SosTriggerState.holding &&
        now.difference(_holdStart!) >= holdDuration) {
      _state = SosTriggerState.countdown;
      _countdownStart = now;
    } else if (_state == SosTriggerState.countdown &&
        now.difference(_countdownStart!) >= countdownDuration) {
      _state = SosTriggerState.triggered;
    }
    return _state;
  }

  Duration? countdownRemaining(DateTime now) {
    if (_state != SosTriggerState.countdown) return null;
    final left = countdownDuration - now.difference(_countdownStart!);
    return left.isNegative ? Duration.zero : left;
  }

  void cancel() {
    if (_state == SosTriggerState.holding || _state == SosTriggerState.countdown) {
      _state = SosTriggerState.cancelled;
      _holdStart = null;
      _countdownStart = null;
    }
  }

  void reset() {
    _state = SosTriggerState.idle;
    _holdStart = null;
    _countdownStart = null;
  }
}
