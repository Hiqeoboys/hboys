import 'tracking_status.dart';

class TrackingTaskProtocol {
  static const databasePathKey = 'tracking.databasePath';
  static const commandKey = 'command';
  static const stopCommand = 'stop';
  static const statusCommand = 'status';
  static const pauseCommand = 'pause';
  static const resumeCommand = 'resume';

  static const startedType = 'started';
  static const updateType = 'update';
  static const stoppedType = 'stopped';
  static const errorType = 'error';
}

sealed class TrackingEvent {
  const TrackingEvent();
}

final class TrackingProgressEvent extends TrackingEvent {
  const TrackingProgressEvent(this.status, {this.started = false});

  final TrackingStatus status;
  final bool started;
}

final class TrackingStoppedEvent extends TrackingEvent {
  const TrackingStoppedEvent({this.status, this.warning});

  final TrackingStatus? status;
  final String? warning;
}

final class TrackingFailureEvent extends TrackingEvent {
  const TrackingFailureEvent(this.message, {this.fatal = false});

  final String message;
  final bool fatal;
}

class TrackingStopResult {
  const TrackingStopResult({required this.clean, this.warning});

  final bool clean;
  final String? warning;
}

abstract interface class TrackingBackend {
  Stream<TrackingEvent> get events;

  Future<bool> isRunning();

  Future<void> start();

  Future<TrackingStopResult> stop();

  Future<void> pause();

  Future<void> resume();

  Future<void> requestStatus();

  Future<void> dispose();
}
