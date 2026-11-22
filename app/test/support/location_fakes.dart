import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart'
    show TrackingAccess;
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/infrastructure/location/shared_location_service.dart';

/// Backend lokasi latar depan palsu: menghitung aliran yang dibuka/aktif dan
/// panggilan ke pengaturan, tanpa menyentuh platform.
class FakeForegroundBackend implements ForegroundLocationBackend {
  FakeForegroundBackend({this.access = TrackingAccess.whileInUse});

  TrackingAccess access;
  TrackingAccess accessAfterRequest = TrackingAccess.whileInUse;
  int checkCalls = 0;
  int requestCalls = 0;
  int openLocationCalls = 0;
  int openAppCalls = 0;
  int streamsOpened = 0;
  int activeStreams = 0;
  final List<StreamController<TrackPoint>> controllers =
      <StreamController<TrackPoint>>[];

  @override
  Future<TrackingAccess> checkAccess() async {
    checkCalls++;
    return access;
  }

  @override
  Future<TrackingAccess> requestAccess() async {
    requestCalls++;
    access = accessAfterRequest;
    return access;
  }

  @override
  Stream<TrackPoint> positions() {
    late StreamController<TrackPoint> controller;
    controller = StreamController<TrackPoint>(
      onListen: () {
        streamsOpened++;
        activeStreams++;
      },
      onCancel: () {
        activeStreams--;
      },
    );
    controllers.add(controller);
    return controller.stream;
  }

  void emit(TrackPoint p) => controllers.last.add(p);

  @override
  Future<bool> openLocationSettings() async {
    openLocationCalls++;
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppCalls++;
    return true;
  }
}

/// Sumber titik rekaman palsu untuk menguji peralihan rekaman <-> aliran
/// sendiri.
class FakeRecordingFeed extends ChangeNotifier
    implements RecordingLocationFeed {
  bool recording = false;
  TrackPoint? latest;
  int pulls = 0;

  @override
  bool get isRecording => recording;

  @override
  Listenable get changes => this;

  @override
  Future<TrackPoint?> latestPoint() async {
    pulls++;
    return latest;
  }

  void update({bool? recording, TrackPoint? latest}) {
    if (recording != null) this.recording = recording;
    if (latest != null) this.latest = latest;
    notifyListeners();
  }
}

