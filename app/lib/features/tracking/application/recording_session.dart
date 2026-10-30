import '../../../core/utils/clock.dart';
import '../domain/track_point.dart';
import '../domain/tracking_engine.dart';
import '../domain/tracking_repository.dart';
import '../domain/tracking_session.dart';
import 'session_recovery.dart';

/// Sesi yang sedang direkam. Setiap titik diterima langsung ditulis ke DB
/// sebelum total sesi diperbarui, sehingga proses yang mati di tengah jalan
/// dapat dipulihkan dari titik-titik tersebut.
class RecordingSession {
  RecordingSession._({
    required TrackingRepository repository,
    required Clock clock,
    required TrackingSession session,
    required TrackingEngine engine,
    required int pointCount,
    TrackingSnapshot? snapshot,
  })  : _repository = repository,
        _clock = clock,
        _session = session,
        _engine = engine,
        _pointCount = pointCount,
        _snapshot = snapshot;

  final TrackingRepository _repository;
  final Clock _clock;
  final TrackingEngine _engine;

  TrackingSession _session;
  TrackingSnapshot? _snapshot;
  int _pointCount;

  TrackingSession get session => _session;
  TrackingSnapshot? get snapshot => _snapshot;
  int get pointCount => _pointCount;

  static Future<RecordingSession> startNew({
    required TrackingRepository repository,
    required Clock clock,
    String? groupId,
    String? trailId,
    String? id,
  }) async {
    final now = clock.nowUtc();
    final session = TrackingSession(
      id: id ?? 'sesi-${now.microsecondsSinceEpoch}',
      startedAtUtc: now,
      groupId: groupId,
      trailId: trailId,
    );
    await repository.saveSession(session);
    return RecordingSession._(
      repository: repository,
      clock: clock,
      session: session,
      engine: TrackingEngine(),
      pointCount: 0,
    );
  }

  static Future<RecordingSession> resume({
    required TrackingRepository repository,
    required Clock clock,
    required RecoveredTrackingSession recovered,
  }) async {
    var session = recovered.session;
    final snapshot = recovered.lastSnapshot;
    if (snapshot != null) {
      session = session.copyWith(
        distanceM: snapshot.distanceM,
        movingSeconds: snapshot.movingTime.inSeconds,
        elevationGainM: snapshot.gainM,
        elevationLossM: snapshot.lossM,
      );
      await repository.saveSession(session);
    }
    return RecordingSession._(
      repository: repository,
      clock: clock,
      session: session,
      engine: recovered.engine,
      pointCount: recovered.points.length,
      snapshot: snapshot,
    );
  }

  Future<TrackingSnapshot?> onFix(TrackPoint raw) async {
    final snapshot = _engine.onFix(raw);
    if (snapshot == null) return null;

    await _repository.addPoint(_session.id, snapshot.lastPoint);
    _pointCount++;
    _snapshot = snapshot;
    _session = _session.copyWith(
      distanceM: snapshot.distanceM,
      movingSeconds: snapshot.movingTime.inSeconds,
      elevationGainM: snapshot.gainM,
      elevationLossM: snapshot.lossM,
    );
    await _repository.saveSession(_session);
    return snapshot;
  }

  Future<TrackingSession> finish() async {
    if (_session.status == TrackingSessionStatus.completed) return _session;
    _session = _session.copyWith(
      endedAtUtc: _clock.nowUtc(),
      status: TrackingSessionStatus.completed,
    );
    await _repository.saveSession(_session);
    return _session;
  }
}

/// Melanjutkan sesi aktif bila ada, atau memulai sesi baru. Dipakai baik oleh
/// layanan latar Android maupun pengendali iOS sehingga semantiknya sama.
Future<RecordingSession> openOrStartRecordingSession({
  required TrackingRepository repository,
  required Clock clock,
  String? groupId,
  String? trailId,
}) async {
  final recovered = await SessionRecovery(repository).recoverActive();
  if (recovered != null) {
    return RecordingSession.resume(
      repository: repository,
      clock: clock,
      recovered: recovered,
    );
  }
  return RecordingSession.startNew(
    repository: repository,
    clock: clock,
    groupId: groupId,
    trailId: trailId,
  );
}
