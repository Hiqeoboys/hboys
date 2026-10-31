import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/kartu/application/kartu_exporter.dart';
import 'package:nama_app/features/plus/application/plus_controller.dart';
import 'package:nama_app/features/plus/domain/cloud_backup.dart';
import 'package:nama_app/features/plus/domain/gpx_export.dart';
import 'package:nama_app/features/plus/domain/plus_entitlement.dart';
import 'package:nama_app/features/plus/domain/plus_plan.dart';
import 'package:nama_app/features/plus/domain/plus_remote_config.dart';
import 'package:nama_app/features/plus/domain/plus_repositories.dart';
import 'package:nama_app/features/plus/domain/route_weather.dart';
import 'package:nama_app/features/plus/infrastructure/device_sharing.dart';
import 'package:nama_app/features/plus/infrastructure/local_plus_stores.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';

const PlusPlan annualPlan = PlusPlan(
  id: 'annual',
  title: 'Hiqeo Plus Tahunan',
  priceLabel: 'Rp 249.000',
  periodLabel: 'per tahun',
  durationDays: 365,
);

const PlusPlan foundingPlan = PlusPlan(
  id: 'founding',
  title: 'Founding Member',
  priceLabel: 'Rp 349.000',
  periodLabel: 'sekali bayar',
  quotaRemaining: 87,
  quotaTotal: 500,
);

PlusRemoteConfig plusConfig({
  required DateTime fetchedAtUtc,
  int graceDays = 10,
  bool leaderboard = false,
  bool peakBadges = false,
  List<PlusPlan> plans = const <PlusPlan>[annualPlan, foundingPlan],
}) =>
    PlusRemoteConfig(
      plans: plans,
      graceDays: graceDays,
      flags: PlusFeatureFlags(
        leaderboard: leaderboard,
        peakBadges: peakBadges,
      ),
      fetchedAtUtc: fetchedAtUtc,
    );

EntitlementPayload plusPayload({
  String planId = 'annual',
  DateTime? issuedAtUtc,
  DateTime? expiresAtUtc,
}) =>
    EntitlementPayload(
      version: EntitlementPayload.currentVersion,
      subject: 'local-device',
      planId: planId,
      issuedAtUtc: issuedAtUtc ?? DateTime.utc(2026, 1, 1),
      expiresAtUtc: expiresAtUtc ?? DateTime.utc(2027, 6, 1),
    );

CloudBackupState cloudBackupState({
  bool autoBackup = false,
  String recoveryCode = 'ABCD-EFGH-JKLM-NPQR',
  List<BackupDevice>? devices,
  bool connected = false,
  DateTime? lastBackupAtUtc,
}) =>
    CloudBackupState(
      autoBackup: autoBackup,
      recoveryCode: recoveryCode,
      devices: devices ??
          <BackupDevice>[
            BackupDevice(
              name: 'Perangkat ini',
              lastActiveUtc: DateTime.utc(2026, 10, 31, 8),
              current: true,
            ),
          ],
      connected: connected,
      lastBackupAtUtc: lastBackupAtUtc,
    );

TrackingSession completedSession({
  required String id,
  required DateTime startedAtUtc,
  double distanceM = 0,
  int movingSeconds = 0,
  double elevationGainM = 0,
}) =>
    TrackingSession(
      id: id,
      startedAtUtc: startedAtUtc,
      endedAtUtc: startedAtUtc.add(const Duration(hours: 3)),
      distanceM: distanceM,
      movingSeconds: movingSeconds,
      elevationGainM: elevationGainM,
      elevationLossM: elevationGainM,
      status: TrackingSessionStatus.completed,
    );

RouteWeatherForecast weatherForecast({
  required String routeName,
  required DateTime fetchedAtUtc,
  String source = 'Demo lokal',
  int dayCount = 2,
}) {
  final firstDay = DateTime(
    fetchedAtUtc.year,
    fetchedAtUtc.month,
    fetchedAtUtc.day,
  );
  return RouteWeatherForecast(
    routeName: routeName,
    source: source,
    fetchedAtUtc: fetchedAtUtc,
    days: <RouteWeatherDay>[
      for (var dayIndex = 0; dayIndex < dayCount; dayIndex++)
        RouteWeatherDay(
          dateLocal: firstDay.add(Duration(days: dayIndex)),
          peakTemperatureC: 18.0 + dayIndex,
          peakRainPercent: 40 + dayIndex,
          condition: WeatherCondition.partlyCloudy,
          hours: <RouteWeatherHour>[
            for (var hour = 6; hour <= 18; hour += 3)
              RouteWeatherHour(
                timeLocal: firstDay.add(Duration(days: dayIndex, hours: hour)),
                temperatureC: 12.0 + hour / 3,
                rainPercent: 20 + hour,
                condition: WeatherCondition.partlyCloudy,
              ),
          ],
          posts: const <RouteWeatherPost>[
            RouteWeatherPost(
              name: 'Pos 1',
              altitudeM: 1500,
              temperatureC: 17,
              rainPercent: 30,
              condition: WeatherCondition.clear,
            ),
            RouteWeatherPost(
              name: 'Puncak',
              altitudeM: 2200,
              temperatureC: 12,
              rainPercent: 55,
              condition: WeatherCondition.rain,
            ),
          ],
        ),
    ],
  );
}

class FakeRouteWeatherRepository implements RouteWeatherRepository {
  FakeRouteWeatherRepository({this.forecast, this.error});

  RouteWeatherForecast? forecast;
  String? error;
  int fetches = 0;

  @override
  Future<RouteWeatherForecast> fetch({
    required String routeName,
    required DateTime nowLocal,
  }) async {
    fetches++;
    final message = error;
    if (message != null) throw RouteWeatherUnavailable(message);
    final current = forecast;
    if (current == null) {
      throw const RouteWeatherUnavailable('Prakiraan belum tersedia.');
    }
    return current;
  }
}

class FakeCloudBackupRepository implements CloudBackupRepository {
  FakeCloudBackupRepository(
    this.state, {
    this.failLoad = false,
    this.failSet = false,
  });

  CloudBackupState state;
  bool failLoad;
  bool failSet;
  int writes = 0;

  @override
  Future<CloudBackupState> load() async {
    if (failLoad) throw StateError('gagal');
    return state;
  }

  @override
  Future<CloudBackupState> setAutoBackup(bool enabled) async {
    if (failSet) throw StateError('gagal');
    state = state.copyWith(autoBackup: enabled);
    writes++;
    return state;
  }
}

class FakePlusConfigRepository implements PlusRemoteConfigRepository {
  FakePlusConfigRepository(this.config);

  PlusRemoteConfig? config;
  bool fail = false;
  int fetches = 0;

  @override
  Future<PlusRemoteConfig> fetch({required DateTime fetchedAtUtc}) async {
    fetches++;
    final current = config;
    if (fail || current == null) {
      throw const PlusConfigUnavailable('offline');
    }
    return PlusRemoteConfig(
      plans: current.plans,
      graceDays: current.graceDays,
      flags: current.flags,
      fetchedAtUtc: fetchedAtUtc,
    );
  }
}

class FakePlusVerifier implements EntitlementVerifier {
  FakePlusVerifier([Map<String, EntitlementPayload>? tokens])
      : tokens = tokens ?? <String, EntitlementPayload>{};

  final Map<String, EntitlementPayload> tokens;
  int verifications = 0;

  @override
  Future<EntitlementPayload?> verify(String token) async {
    verifications++;
    return tokens[token];
  }
}

class FakePlusBilling implements PlusBillingRepository {
  PlusBillingResult purchaseResult =
      const PlusBillingResult.unavailable('belum diatur');
  PlusBillingResult restoreResult = const PlusBillingResult.nothingToRestore();
  final List<String> purchases = <String>[];
  int restoreCalls = 0;

  @override
  Future<PlusBillingResult> purchase(String planId) async {
    purchases.add(planId);
    return purchaseResult;
  }

  @override
  Future<PlusBillingResult> restore() async {
    restoreCalls++;
    return restoreResult;
  }
}

Future<PlusController> buildPlusController({
  DateTime? nowUtc,
  bool withConfig = true,
  PlusRemoteConfig? config,
  String? token,
  EntitlementPayload? payload,
  Map<String, EntitlementPayload> verificationTokens =
      const <String, EntitlementPayload>{},
  FakePlusBilling? billing,
  bool leaderboard = false,
  bool peakBadges = false,
}) async {
  final now = nowUtc ?? DateTime.utc(2026, 10, 31, 8);
  final PlusRemoteConfig? resolvedConfig = withConfig
      ? (config ??
          plusConfig(
            fetchedAtUtc: now,
            leaderboard: leaderboard,
            peakBadges: peakBadges,
          ))
      : null;
  final verifierTokens = <String, EntitlementPayload>{...verificationTokens};
  if (token != null && payload != null) verifierTokens[token] = payload;
  final controller = PlusController(
    configRepository: FakePlusConfigRepository(resolvedConfig),
    configStore: InMemoryPlusConfigStore(resolvedConfig),
    entitlementStore: InMemoryEntitlementLocalStore(token: token),
    verifier: FakePlusVerifier(verifierTokens),
    billing: billing ?? FakePlusBilling(),
    clock: FakeClock(now),
  );
  await controller.loadCached();
  return controller;
}

class FakeTrackingRepository implements TrackingRepository {
  FakeTrackingRepository({
    this.sessions = const <TrackingSession>[],
    this.pointsBySession = const <String, List<TrackPoint>>{},
    this.failSessions = false,
    this.failPoints = false,
  });

  List<TrackingSession> sessions;
  Map<String, List<TrackPoint>> pointsBySession;
  bool failSessions;
  bool failPoints;
  int watchCalls = 0;

  @override
  Stream<List<TrackingSession>> watchSessions() {
    watchCalls++;
    if (failSessions) {
      return Stream<List<TrackingSession>>.error(StateError('gagal'));
    }
    return Stream<List<TrackingSession>>.value(sessions);
  }

  @override
  Future<void> saveSession(TrackingSession session) async {
    sessions = <TrackingSession>[...sessions, session];
  }

  @override
  Future<TrackingSession?> findSession(String id) async {
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  @override
  Future<TrackingSession?> findActiveSession() async {
    for (final session in sessions) {
      if (session.status == TrackingSessionStatus.active) return session;
    }
    return null;
  }

  @override
  Future<void> deleteSession(String id) async {
    sessions = <TrackingSession>[
      for (final session in sessions)
        if (session.id != id) session,
    ];
  }

  @override
  Future<void> addPoint(String sessionId, TrackPoint point) async {}

  @override
  Future<List<TrackPoint>> points(String sessionId) async {
    if (failPoints) throw StateError('gagal');
    return pointsBySession[sessionId] ?? const <TrackPoint>[];
  }

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async {
    final points = pointsBySession[sessionId];
    return points == null || points.isEmpty ? null : points.last;
  }
}

class RecordingGpxExporter implements GpxExporter {
  RecordingGpxExporter({this.result = true});

  bool result;
  bool fail = false;
  final List<({String fileName, String contents, String? subject})> calls =
      <({String fileName, String contents, String? subject})>[];

  @override
  Future<bool> share({
    required String fileName,
    required String contents,
    String? subject,
  }) async {
    if (fail) throw StateError('gagal');
    calls.add((fileName: fileName, contents: contents, subject: subject));
    return result;
  }
}

class RecordingKartuExporter implements KartuExporter {
  RecordingKartuExporter({this.captureResult = true, this.shareResult = true});

  bool captureResult;
  bool shareResult;
  int captures = 0;
  String? sharedFileName;
  Uint8List? sharedBytes;

  @override
  Future<Uint8List?> capturePng(GlobalKey boundaryKey) async {
    captures++;
    if (!captureResult) return null;
    return Uint8List.fromList(<int>[1, 2, 3]);
  }

  @override
  Future<bool> savePng(Uint8List bytes, String fileName) async => true;

  @override
  Future<bool> sharePng(Uint8List bytes, String fileName) async {
    sharedFileName = fileName;
    sharedBytes = bytes;
    return shareResult;
  }
}

class RecordingTextSharer implements PlusTextSharer {
  RecordingTextSharer({this.result = true});

  bool result;
  String? lastText;
  String? lastSubject;
  int calls = 0;

  @override
  Future<bool> share(String text, {String? subject}) async {
    calls++;
    lastText = text;
    lastSubject = subject;
    return result;
  }
}

/// Titik contoh dengan posisi berurutan; dipakai grafik dan rute.
List<TrackPoint> samplePoints({
  int count = 2,
  DateTime? startUtc,
  double startLat = -6.8,
  double stepLat = 0.001,
  double lon = 106.8,
  double? startAltitudeM = 1500,
  double stepAltitudeM = 10,
  int secondsPerStep = 60,
}) {
  final start = startUtc ?? DateTime.utc(2026, 3, 1, 0);
  return <TrackPoint>[
    for (var index = 0; index < count; index++)
      TrackPoint(
        lat: startLat + index * stepLat,
        lon: lon,
        altitudeM:
            startAltitudeM == null ? null : startAltitudeM + index * stepAltitudeM,
        timestampUtc: start.add(Duration(seconds: index * secondsPerStep)),
        accuracyM: 5,
      ),
  ];
}

/// `Offset` normalisasi tidak boleh kosong agar rute tergambar di kartu rekap.
bool hasRoute(List<Offset>? route) => route != null && route.length >= 2;
