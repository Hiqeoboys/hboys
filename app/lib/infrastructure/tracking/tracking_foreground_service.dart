import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class TrackingForegroundService {
  static bool _initialized = false;

  /// Dipanggil sekali dari bootstrap pada Android.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tracking',
        channelName: 'Rekaman pendakian',
        channelDescription:
            'Notifikasi tetap saat aplikasi merekam perjalanan di latar belakang.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
  }
}
