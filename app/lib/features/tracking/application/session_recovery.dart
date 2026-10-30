import '../domain/track_point.dart';
import '../domain/tracking_engine.dart';
import '../domain/tracking_repository.dart';
import '../domain/tracking_session.dart';

class RecoveredTrackingSession {
  const RecoveredTrackingSession({
    required this.session,
    required this.engine,
    required this.points,
    required this.lastSnapshot,
  });

  final TrackingSession session;
  final TrackingEngine engine;
  final List<TrackPoint> points;
  final TrackingSnapshot? lastSnapshot;
}

/// Memulihkan sesi aktif setelah proses aplikasi berhenti.
///
/// Titik yang tersimpan hanya titik yang sudah lolos filter, jadi memutarnya
/// ulang lewat [TrackingEngine] yang sama membangun kembali jarak, elevasi,
/// auto-pause, dan jendela pace/vertical speed.
class SessionRecovery {
  SessionRecovery(
    this._repository, {
    TrackingEngine Function()? engineFactory,
  }) : _engineFactory = engineFactory ?? TrackingEngine.new;

  final TrackingRepository _repository;
  final TrackingEngine Function() _engineFactory;

  Future<RecoveredTrackingSession?> recoverActive() async {
    final session = await _repository.findActiveSession();
    if (session == null) return null;

    final points = await _repository.points(session.id);
    final engine = _engineFactory();
    TrackingSnapshot? lastSnapshot;
    for (final point in points) {
      lastSnapshot = engine.onFix(point) ?? lastSnapshot;
    }

    return RecoveredTrackingSession(
      session: session,
      engine: engine,
      points: points,
      lastSnapshot: lastSnapshot,
    );
  }
}
