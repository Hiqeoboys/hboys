import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/core/utils/safe_url_launcher.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/notifications/data/user_notifications_service.dart';
import 'package:nama_app/features/notifications/presentation/notifications_page.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/safety/application/sos_action_service.dart';
import 'package:nama_app/features/safety/application/sos_location.dart';
import 'package:nama_app/features/safety/application/sos_offline_queue_service.dart';
import 'package:nama_app/features/safety/application/sos_sms_service.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_category.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
import 'package:nama_app/features/safety/presentation/widgets/nearby_sos_modal_overlay.dart';
import 'package:nama_app/features/tracking/application/tracking_controller.dart';
import 'package:nama_app/features/tracking/presentation/tracking_page.dart';
import 'package:nama_app/infrastructure/notifications/push_notification_overlay.dart';
import 'package:nama_app/infrastructure/notifications/push_notification_service.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemSafetyRepo implements SafetyRepository {
  _MemSafetyRepo(this.contacts);

  final List<EmergencyContact> contacts;

  @override
  Future<List<SosEvent>> activeSosEvents() async => const <SosEvent>[];

  @override
  Future<bool> cancelSosEvent(String id, DateTime nowUtc) async => true;

  @override
  Future<List<EmergencyContact>> contactsOf(String userId) async => contacts;

  @override
  Future<void> deleteContact(String id) async {}

  @override
  Future<SosEvent?> findSosEvent(String id) async => null;

  @override
  Future<void> saveContact(EmergencyContact contact) async {}

  @override
  Future<void> saveSosEvent(SosEvent event) async {}

  @override
  Stream<List<EmergencyContact>> watchContacts(String userId) =>
      const Stream<List<EmergencyContact>>.empty();

  @override
  Stream<List<SosEvent>> watchSosEvents() =>
      const Stream<List<SosEvent>>.empty();
}

class _FakeSmsSender implements SosSmsSender {
  _FakeSmsSender({required this.supported, required this.granted});

  final bool supported;
  final bool granted;
  final List<({List<String> phones, String message})> sentCalls =
      <({List<String> phones, String message})>[];

  @override
  bool get isSupported => supported;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<SosSmsBatchResult> sendSmsBatch({
    required List<String> phones,
    required String message,
  }) async {
    sentCalls.add((phones: phones, message: message));
    if (!granted) {
      return SosSmsBatchResult(
        supported: supported,
        permissionDenied: true,
        failedCount: phones.length,
        failedPhones: phones,
      );
    }
    return SosSmsBatchResult(
      supported: supported,
      sentCount: phones.length,
    );
  }
}

void main() {
  const fix = SosFix(
    lat: -6.89234,
    lon: 108.40567,
    accuracyM: 8,
    altitudeM: 2850.0,
  );
  final contacts = <EmergencyContact>[
    EmergencyContact(
      id: 'ec-1',
      userId: 'u1',
      name: 'Ibu',
      phoneE164: '+6281234567890',
      consentStatus: EmergencyContactConsentStatus.granted,
      createdAtUtc: DateTime.utc(2026, 11, 1),
    ),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackingListStore.setInstanceForTesting(PackingListStore());
    GroupHikePlanStore.setInstanceForTesting(GroupHikePlanStore());
    TrackingController.instance.clearActiveRoute();
    TrackingController.instance.setErrorForTesting(null);
  });

  group('Wave C #1: Tracking banner & route recovery', () {
    testWidgets(
        'TrackingView hides Rekaman tidak tersedia when recording and offers Muat ulang when permissionReady with error',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: Scaffold(
            body: TrackingView(
              phase: TrackingPhase.error,
              profile: PowerProfile.normal,
              permissionReady: true,
              error: 'Pelacakan di perangkat belum siap.',
              onRetryInitialize: () => retried = true,
            ),
          ),
        ),
      );
      expect(find.text('Rekaman tidak tersedia'), findsOneWidget);
      expect(find.text('Muat ulang'), findsOneWidget);
      await tester.tap(find.text('Muat ulang'));
      expect(retried, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: const Scaffold(
            body: TrackingView(
              phase: TrackingPhase.recording,
              profile: PowerProfile.normal,
              permissionReady: true,
              error: 'Stale error should stay hidden',
            ),
          ),
        ),
      );
      expect(find.text('Rekaman tidak tersedia'), findsNothing);
    });

    test('TrackingController clears stale error and active group route cleanly',
        () {
      final ctrl = TrackingController.instance;
      ctrl.setErrorForTesting(
        'Pelacakan di perangkat belum siap.',
        phase: TrackingPhase.error,
      );
      expect(ctrl.error, isNotNull);
      ctrl.setErrorForTesting(null, phase: TrackingPhase.idle);
      expect(ctrl.error, isNull);

      ctrl.setActiveRoute(
        mountainName: 'Gunung Ciremai',
        trailName: 'Apuy',
        trailId: 'apuy',
        groupId: '11111111-1111-4111-8111-111111111111',
      );
      expect(ctrl.activeGroupId, '11111111-1111-4111-8111-111111111111');
      ctrl.clearActiveRoute();
      expect(ctrl.activeGroupId, isNull);
      expect(ctrl.activeMountainName, isNull);
    });
  });

  group('Wave C #2: 3-Mode SOS, Cross-Platform URIs, & Liquid Glass Modal', () {
    test(
        'Solo Hike SOS sends ONLY via WhatsApp & SMS to emergency contacts, NEVER to groups or BLE mesh',
        () async {
      final sms = _FakeSmsSender(supported: true, granted: true);
      final queue = SosOfflineQueueService.forTesting();
      Map<String, dynamic>? serverPayload;
      var groupMessageCalled = false;
      var meshCalled = false;
      Uri? launchedWhatsappUri;

      final runner = DeviceSosActionRunner(
        smsSender: sms,
        offlineQueue: queue,
        onlineChecker: () async => true,
        urlLauncher: (uri) async {
          launchedWhatsappUri = uri;
          return true;
        },
        remoteSosUpserter: (payload) async {
          serverPayload = payload;
          return true;
        },
        groupMessageSender: (_) async {
          groupMessageCalled = true;
          return true;
        },
        meshBroadcaster: ({required groupId, required payload}) async {
          meshCalled = true;
          return true;
        },
        whatsappInvoker: (_, __, ___) async =>
            (configured: false, sent: false),
        batteryLevelReader: () async => 27,
        senderNameResolver: () => 'Bima',
        mountainNameResolver: () => 'Gunung Ciremai',
        modeResolver: () => SosDispatchMode.soloHike,
        enableDeviceHardware: false,
      );

      final outcome = await runner.activate(
        sosUuid: 'sos-solo-1',
        fix: fix,
        category: SosCategory.injury,
        triggeredAtUtc: DateTime.utc(2026, 11, 22, 14, 15),
        safetyRepository: _MemSafetyRepo(contacts),
      );

      expect(outcome.sosMode, SosDispatchMode.soloHike);
      expect(outcome.sentDirectSms, isTrue);
      expect(outcome.openedWhatsappFallback, isTrue);
      expect(launchedWhatsappUri?.scheme, 'whatsapp');
      expect(groupMessageCalled, isFalse);
      expect(meshCalled, isFalse);
      expect(serverPayload?['sos_mode'], 'solo_hike');
      expect(serverPayload?.containsKey('group_id'), isFalse);
    });

    test(
        'Active Group Hike SOS sends strictly to the active hike groupId + emergency contacts',
        () async {
      const activeGroupUuid = '22222222-2222-4222-8222-222222222222';
      final sms = _FakeSmsSender(supported: true, granted: true);
      final queue = SosOfflineQueueService.forTesting();
      Map<String, dynamic>? serverPayload;
      String? sentGroupId;

      final runner = DeviceSosActionRunner(
        smsSender: sms,
        offlineQueue: queue,
        onlineChecker: () async => true,
        remoteSosUpserter: (payload) async {
          serverPayload = payload;
          return true;
        },
        groupMessageSender: (msg) async {
          sentGroupId = msg.groupId;
          return true;
        },
        whatsappInvoker: (_, __, ___) async => (configured: true, sent: true),
        batteryLevelReader: () async => 64,
        senderNameResolver: () => 'Sinta',
        activeGroupIdResolver: () => activeGroupUuid,
        enableDeviceHardware: false,
      );

      final outcome = await runner.activate(
        sosUuid: 'sos-group-1',
        fix: fix,
        category: SosCategory.lost,
        triggeredAtUtc: DateTime.utc(2026, 11, 22, 10, 5),
        safetyRepository: _MemSafetyRepo(contacts),
      );

      expect(outcome.sosMode, SosDispatchMode.groupHike);
      expect(outcome.sentGroupMessage, isTrue);
      expect(sentGroupId, activeGroupUuid);
      expect(serverPayload?['sos_mode'], 'group_hike');
      expect(serverPayload?['group_id'], activeGroupUuid);
      expect(outcome.whatsappAutoSent, isTrue);
    });

    test(
        'Home / No Active Hike SOS dispatches nearby 5 km broadcast (sos_mode=nearby) without hijacking any group',
        () async {
      final sms = _FakeSmsSender(supported: false, granted: false);
      final queue = SosOfflineQueueService.forTesting();
      Map<String, dynamic>? serverPayload;
      var groupMsgCalled = false;

      final runner = DeviceSosActionRunner(
        smsSender: sms,
        offlineQueue: queue,
        onlineChecker: () async => true,
        remoteSosUpserter: (payload) async {
          serverPayload = payload;
          return true;
        },
        groupMessageSender: (_) async {
          groupMsgCalled = true;
          return true;
        },
        batteryLevelReader: () async => 41,
        senderNameResolver: () => 'Raka',
        enableDeviceHardware: false,
      );

      final outcome = await runner.activate(
        sosUuid: 'sos-nearby-1',
        fix: fix,
        category: SosCategory.medical,
        triggeredAtUtc: DateTime.utc(2026, 11, 22, 12, 30),
        safetyRepository: _MemSafetyRepo(const <EmergencyContact>[]),
      );

      expect(outcome.sosMode, SosDispatchMode.nearbyHome);
      expect(groupMsgCalled, isFalse);
      expect(serverPayload?['sos_mode'], 'nearby');
      expect(serverPayload?.containsKey('group_id'), isFalse);
      expect(serverPayload?['local_time_hhmm'], isNotEmpty);
    });

    test('Cross-platform URI builders format SMS, WhatsApp, and Android/iOS Maps safely',
        () {
      final smsUri = buildEmergencySmsUri(
        const <String>['+6281234567890'],
        'Butuh bantuan segera di jalur',
      );
      expect(smsUri.scheme, 'sms');
      expect(smsUri.toString(), contains('%20'));
      expect(smsUri.toString(), isNot(contains('+Butuh')));
      expect(smsUri.queryParameters['body'], 'Butuh bantuan segera di jalur');

      final waUri = buildSafeWhatsappUri(
        phoneE164: '+6281234567890',
        message: 'SOS Darurat',
      );
      expect(waUri, isNotNull);
      expect(waUri!.scheme, 'whatsapp');
      expect(isAllowedLaunchUri(waUri), isTrue);

      final iosMaps = buildSafeMapsUri(
        rawLat: '-6.89234',
        rawLon: '108.40567',
        platformOverride: TargetPlatform.iOS,
      );
      final androidMaps = buildSafeMapsUri(
        rawLat: '-6.89234',
        rawLon: '108.40567',
        platformOverride: TargetPlatform.android,
      );
      expect(iosMaps?.host, 'maps.apple.com');
      expect(androidMaps?.host, 'maps.google.com');
    });

    test(
        'Nearby SOS distance formatting and push notification channel normalization',
        () {
      expect(formatNearbySosDistance(450), '450 m');
      expect(formatNearbySosDistance(2340), '2,3 km');

      final notif = InAppPushNotification.fromRemoteData(
        id: 'n-nearby-1',
        title: 'DARURAT SOS TERDEKAT',
        body:
            'Seseorang dalam jarak 450 m mengirimkan SOS pada titik lokasi -6.89234, 108.40567 pukul 19:22 dengan sisa baterai 18%. Ayo kita periksa keadaannya.',
        data: <String, String>{
          'type': 'sos_nearby',
          'sos_mode': 'nearby',
          'distance_m': '450',
          'lat': '-6.89234',
          'lon': '108.40567',
          'battery_pct': '18',
          'sos_time_hhmm': '19:22',
        },
      );
      expect(notif.isUrgent, isTrue);
      expect(
        PushNotificationService.resolveChannelId(notif),
        kHiqeoSosChannelId,
      );
    });

    testWidgets(
        'Tapping sos_nearby opens Liquid Glass Card Modal directly on active screen without navigating away',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/beranda',
        routes: <GoRoute>[
          GoRoute(
            path: '/beranda',
            builder: (_, __) => const Scaffold(
              body: Center(child: Text('Halaman Aktif Beranda')),
            ),
          ),
          GoRoute(
            path: '/grup',
            builder: (_, __) => const Scaffold(
              body: Center(child: Text('Grup Pendakian')),
            ),
          ),
          GoRoute(
            path: '/sos',
            builder: (_, __) => const Scaffold(
              body: Center(child: Text('Layar SOS')),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          theme: hiqeoLightTheme,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final notif = InAppPushNotification.fromRemoteData(
        id: 'n-nearby-2',
        title: 'DARURAT SOS TERDEKAT',
        body:
            'Seseorang dalam jarak 2,3 km mengirimkan SOS pada titik lokasi -6.89234, 108.40567 pukul 20:05 dengan sisa baterai 12%. Ayo kita periksa keadaannya.',
        data: <String, String>{
          'type': 'sos_nearby',
          'sos_mode': 'nearby',
          'distance_m': '2300',
          'lat': '-6.89234',
          'lon': '108.40567',
          'battery_pct': '12',
          'sos_time_hhmm': '20:05',
          'area_label': 'Pos 3 Ciremai',
        },
      );

      final ctx = router.routerDelegate.navigatorKey.currentContext!;
      dispatchPushNavigation(router, notif, dialogContext: ctx);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('nearby-sos-modal-card')),
          findsOneWidget);
      expect(find.text('Sinyal SOS Terdekat'), findsOneWidget);
      expect(find.text('20:05'), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);
      expect(find.text('-6.89234, 108.40567'), findsOneWidget);
      expect(find.text('Halaman Aktif Beranda'), findsOneWidget);
      expect(find.text('Grup Pendakian'), findsNothing);
      expect(find.text('Layar SOS'), findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('nearby-sos-close-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('nearby-sos-modal-card')),
          findsNothing);
    });

    testWidgets(
        'Notifications inbox item sos_nearby opens Liquid Glass Modal directly on inbox screen',
        (tester) async {
      final item = UserNotificationItem(
        id: 'inbox-nearby-1',
        userId: 'u1',
        type: 'sos_nearby',
        title: 'DARURAT SOS TERDEKAT',
        body:
            'Seseorang dalam jarak 450 m mengirimkan SOS pada titik lokasi -6.89234, 108.40567 pukul 21:10 dengan sisa baterai 9%. Ayo kita periksa keadaannya.',
        isRead: false,
        createdAtUtc: DateTime.utc(2026, 11, 22, 14, 10),
        data: const <String, String>{
          'sos_mode': 'nearby',
          'distance_m': '450',
          'lat': '-6.89234',
          'lon': '108.40567',
          'battery_pct': '9',
          'sos_time_hhmm': '21:10',
        },
      );

      final service = UserNotificationsService.createForTesting(
        initialItems: <UserNotificationItem>[item],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: NotificationsPage(service: service),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SOS Terdekat'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('nearby-sos-modal-card')),
          findsOneWidget);
      expect(find.text('21:10'), findsOneWidget);
      expect(find.text('9%'), findsOneWidget);
    });
  });

  group('Wave C #3: Auto-Reset Siapkan Pendakian after stop', () {
    test(
        'completeAndResetAfterHike clears Group & Solo plans, PackingList, and prevents completed invite re-hydration',
        () async {
      final packing = PackingListStore.instance;
      await packing.clearAll();
      await packing.toggleSelectItem('tenda');
      await packing.finishStage1();
      await packing.togglePackedItem('tenda');
      expect(packing.selectedIds, isNotEmpty);
      expect(packing.packedIds, isNotEmpty);
      expect(packing.stage1Done, isTrue);

      final planStore = GroupHikePlanStore.instance;
      const completedPlan = GroupHikePlan(
        inviteId: 'inv-wavec-1',
        groupId: 'local-group-1',
        groupName: 'Tim Puncak',
        mountainId: 'ciremai',
        mountainName: 'Gunung Ciremai',
        trailId: 'apuy',
        trailName: 'Apuy',
        organizerUserId: 'u1',
        organizerName: 'Ketua',
        readyUserIds: <String>{'u1', 'u2'},
        memberCount: 2,
        status: 'started',
      );
      await planStore.setPlan(completedPlan);
      await planStore.setSoloPlan(
        const SoloHikePlan(
          mountainId: 'ciremai',
          mountainName: 'Gunung Ciremai',
          trailId: 'apuy',
          trailName: 'Apuy',
          isStarted: true,
        ),
      );
      expect(planStore.activePlan, isNotNull);
      expect(planStore.soloPlan?.isStarted, isTrue);

      await packing.clearAll();
      await planStore.completeAndResetAfterHike();
      TrackingController.instance.clearActiveRoute();

      expect(packing.selectedIds, isEmpty);
      expect(packing.packedIds, isEmpty);
      expect(packing.stage1Done, isFalse);
      expect(planStore.activePlan, isNull);
      expect(planStore.soloPlan, isNull);
      expect(planStore.activePlanForGroup('local-group-1'), isNull);

      // Re-processing stale completed prep row / reloading does NOT revive completed invite.
      await planStore.handlePrepRowForTesting(<String, dynamic>{
        'group_id': 'local-group-1',
        'invite_id': 'inv-wavec-1',
        'mountain_id': 'ciremai',
        'mountain_name': 'Gunung Ciremai',
        'status': 'started',
        'ready_user_ids': <String>['u1', 'u2'],
        'member_count': 2,
      });
      expect(planStore.activePlan, isNull);

      final reloadedStore = GroupHikePlanStore();
      await reloadedStore.load(force: true);
      expect(reloadedStore.activePlan, isNull);
      expect(reloadedStore.soloPlan, isNull);
    });
  });
}
