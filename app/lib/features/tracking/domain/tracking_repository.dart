import 'track_point.dart';
import 'tracking_session.dart';

abstract interface class TrackingRepository {
  Future<void> saveSession(TrackingSession session);
  Future<TrackingSession?> findSession(String id);

  /// Sesi berstatus aktif terbaru, dipakai untuk pemulihan setelah aplikasi mati.
  Future<TrackingSession?> findActiveSession();
  Stream<List<TrackingSession>> watchSessions();
  Future<void> deleteSession(String id);

  Future<void> addPoint(String sessionId, TrackPoint point);

  /// Titik sesi diurutkan menurut waktu rekam, lalu urutan masuk.
  Future<List<TrackPoint>> points(String sessionId);

  /// Titik terbaru sesi, dipakai peta untuk posisi terkini tanpa memuat semua.
  Future<TrackPoint?> latestPoint(String sessionId);
}
