import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/safety/application/sos_action_service.dart';
import 'package:nama_app/features/safety/application/sos_location.dart';
import 'package:nama_app/features/safety/application/sos_offline_queue_service.dart';
import 'package:nama_app/features/safety/application/sos_sms_service.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_category.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
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
      sentPhones: phones,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  final contacts = <EmergencyContact>[
    EmergencyContact(
      id: 'ec-1',
      userId: 'perangkat-lokal',
      name: 'Ibu',
      phoneE164: '+6281234567890',
      createdAtUtc: DateTime.utc(2026, 11, 20),
      consentStatus: EmergencyContactConsentStatus.granted,
    ),
    EmergencyContact(
      id: 'ec-2',
      userId: 'perangkat-lokal',
      name: 'Ayah',
      phoneE164: '+6281987654321',
      createdAtUtc: DateTime.utc(2026, 11, 20),
      consentStatus: EmergencyContactConsentStatus.granted,
    ),
    // Kontak akun Hiqeo saja (tanpa nomor telepon) tidak boleh masuk daftar SMS.
    EmergencyContact(
      id: 'ec-3',
      userId: 'perangkat-lokal',
      name: 'Rani',
      phoneE164: '',
      linkedUserId: 'user-rani',
      linkedUsername: 'rani',
      createdAtUtc: DateTime.utc(2026, 11, 20),
      consentStatus: EmergencyContactConsentStatus.granted,
    ),
  ];

  const fix = SosFix(
    lat: -7.54072,
    lon: 110.44572,
    accuracyM: 6,
    altitudeM: 2910,
  );

  test(
      'OFFLINE Android: mengirim zero-click SMS berisi koordinat+elevasi+baterai+Maps, siar Mesh, & masuk antrean sinkronisasi lalu flush saat online',
      () async {
    final smsSender = _FakeSmsSender(supported: true, granted: true);
    final queue = SosOfflineQueueService.forTesting();
    final launchedUris = <Uri>[];
    String? meshGroup;

    final runner = DeviceSosActionRunner(
      smsSender: smsSender,
      offlineQueue: queue,
      onlineChecker: () async => false,
      urlLauncher: (uri) async {
        launchedUris.add(uri);
        return true;
      },
      meshBroadcaster: ({required groupId, required payload}) async {
        meshGroup = groupId;
        return payload.altitudeMdpl == 2910;
      },
      batteryLevelReader: () async => 38,
      senderNameResolver: () => 'Andi',
      mountainNameResolver: () => 'Gunung Merapi',
      enableDeviceHardware: false,
    );

    final outcome = await runner.activate(
      sosUuid: 'sos-offline-1',
      fix: fix,
      category: SosCategory.injury,
      triggeredAtUtc: DateTime.utc(2026, 11, 21, 10, 0),
      safetyRepository: _MemSafetyRepo(contacts),
    );

    expect(outcome.isOnline, isFalse);
    expect(outcome.sentDirectSms, isTrue);
    expect(outcome.directSmsSentCount, 2);
    expect(outcome.sentMeshBroadcast, isTrue);
    expect(outcome.queuedForServerSync, isTrue);
    expect(outcome.savedRemoteUpsert, isFalse);
    // Tidak membuka dialog/sheet `sms:` karena SmsManager zero-click sudah berhasil.
    expect(launchedUris, isEmpty);
    expect(meshGroup, 'hiqeo-sos-public');

    expect(smsSender.sentCalls, hasLength(1));
    final sms = smsSender.sentCalls.single;
    expect(sms.phones, <String>['+6281234567890', '+6281987654321']);
    expect(sms.message, contains('-7.54072, 110.44572'));
    expect(sms.message, contains('2910 mdpl'));
    expect(sms.message, contains('38%'));
    expect(sms.message, contains('https://maps.google.com/?q=-7.54072,110.44572'));

    // Saat sinyal kembali (flushPending), item antrean langsung terkirim ke server.
    expect(queue.isPending('sos-offline-1'), isTrue);
    final uploadedIds = <String>[];
    final syncedCount = await queue.flushPending(
      connectivityCheckOverride: () async => true,
      uploaderOverride: (item) async {
        uploadedIds.add(item.sosUuid);
        return true;
      },
    );
    expect(syncedCount, 1);
    expect(uploadedIds, <String>['sos-offline-1']);
    expect(queue.isPending('sos-offline-1'), isFalse);
    expect(queue.wasSynced('sos-offline-1'), isTrue);
  });

  test(
      'ONLINE Android: mengirim serentak sos_events server + zero-click SMS redundan + grup + hook WhatsApp tanpa saling memblokir',
      () async {
    final smsSender = _FakeSmsSender(supported: true, granted: true);
    final queue = SosOfflineQueueService.forTesting();
    Map<String, dynamic>? serverPayload;
    GroupMessageRecord? sentGroupMsg;
    var whatsappCalled = false;

    final runner = DeviceSosActionRunner(
      smsSender: smsSender,
      offlineQueue: queue,
      onlineChecker: () async => true,
      remoteSosUpserter: (payload) async {
        serverPayload = payload;
        return true;
      },
      groupMessageSender: (msg) async {
        sentGroupMsg = msg;
        return true;
      },
      whatsappInvoker: (sosUuid, message, phones) async {
        whatsappCalled = true;
        return (configured: false, sent: false);
      },
      batteryLevelReader: () async => 82,
      senderNameResolver: () => 'Andi',
      activeGroupIdResolver: () => '11111111-1111-4111-8111-111111111111',
      mountainNameResolver: () => 'Gunung Semeru',
      enableDeviceHardware: false,
    );

    final outcome = await runner.activate(
      sosUuid: 'sos-online-1',
      fix: fix,
      category: SosCategory.lost,
      triggeredAtUtc: DateTime.utc(2026, 11, 21, 10, 5),
      safetyRepository: _MemSafetyRepo(contacts),
    );

    expect(outcome.isOnline, isTrue);
    expect(outcome.savedRemoteUpsert, isTrue);
    expect(outcome.queuedForServerSync, isFalse);
    expect(outcome.sentGroupMessage, isTrue);
    expect(outcome.sentDirectSms, isTrue);
    expect(outcome.directSmsSentCount, 2);
    expect(whatsappCalled, isTrue);
    expect(outcome.whatsappConfigured, isFalse);
    expect(serverPayload?['status'], 'active');
    expect(sentGroupMsg?.clientMsgId, normalizeToUuid('sos-sos-online-1'));
    expect(isValidUuid(sentGroupMsg?.clientMsgId), isTrue);
    expect(smsSender.sentCalls, hasLength(1));
  });

  test('OFFLINE iOS fallback tetap membuka sheet sms: otomatis', () async {
    final smsSender = _FakeSmsSender(supported: false, granted: false);
    final queue = SosOfflineQueueService.forTesting();
    Uri? openedUri;

    final runner = DeviceSosActionRunner(
      smsSender: smsSender,
      offlineQueue: queue,
      onlineChecker: () async => false,
      urlLauncher: (uri) async {
        openedUri = uri;
        return true;
      },
      meshBroadcaster: ({required groupId, required payload}) async => false,
      enableDeviceHardware: false,
    );

    final outcome = await runner.activate(
      sosUuid: 'sos-ios-1',
      fix: fix,
      category: SosCategory.weather,
      triggeredAtUtc: DateTime.utc(2026, 11, 21, 10, 10),
      safetyRepository: _MemSafetyRepo(contacts),
    );

    expect(outcome.sentDirectSms, isFalse);
    expect(outcome.openedOfflineSms, isTrue);
    expect(openedUri?.scheme, 'sms');
    expect(openedUri?.path, contains('+6281234567890'));
  });
}
