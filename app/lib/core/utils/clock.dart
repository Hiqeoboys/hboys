/// Jam yang bisa dipalsukan saat tes. Semua logika waktu memakai ini, bukan
/// DateTime.now() langsung. Waktu selalu UTC.
abstract interface class Clock {
  DateTime nowUtc();
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

class FakeClock implements Clock {
  FakeClock(this._now);
  DateTime _now;

  @override
  DateTime nowUtc() => _now;

  void advance(Duration d) => _now = _now.add(d);
}
