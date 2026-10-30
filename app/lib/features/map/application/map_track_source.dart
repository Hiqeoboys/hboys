import '../../tracking/application/tracking_controller.dart';
import '../../tracking/domain/track_point.dart';

class MapTrackSnapshot {
  const MapTrackSnapshot({required this.points, required this.latestPoint});

  final List<TrackPoint> points;
  final TrackPoint? latestPoint;
}

abstract interface class MapTrackSource {
  Future<MapTrackSnapshot> load();
}

class TrackingControllerMapTrackSource implements MapTrackSource {
  const TrackingControllerMapTrackSource();

  @override
  Future<MapTrackSnapshot> load() async {
    final controller = TrackingController.instance;
    await controller.initialize();
    final points = await controller.currentTrackPoints();
    final latest = await controller.latestRecordedPoint();
    return MapTrackSnapshot(points: points, latestPoint: latest);
  }
}
