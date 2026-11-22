import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/platform/contact_picker.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
import 'package:nama_app/features/safety/presentation/emergency_contacts_sheet.dart';
import 'package:nama_app/features/social/data/friends_service.dart';

class _InMemorySafetyRepo implements SafetyRepository {
  final List<EmergencyContact> contacts = <EmergencyContact>[];

  @override
  Future<List<EmergencyContact>> contactsOf(String userId) async =>
      List<EmergencyContact>.of(contacts);

  @override
  Future<void> saveContact(EmergencyContact contact) async {
    contacts.removeWhere((c) => c.id == contact.id);
    contacts.add(contact);
  }

  @override
  Stream<List<EmergencyContact>> watchContacts(String userId) =>
      Stream<List<EmergencyContact>>.value(List<EmergencyContact>.of(contacts));

  @override
  Future<void> deleteContact(String id) async {
    contacts.removeWhere((c) => c.id == id);
  }

  @override
  Future<void> saveSosEvent(SosEvent event) async {}

  @override
  Future<SosEvent?> findSosEvent(String id) async => null;

  @override
  Future<List<SosEvent>> activeSosEvents() async => const <SosEvent>[];

  @override
  Stream<List<SosEvent>> watchSosEvents() => const Stream<List<SosEvent>>.empty();

  @override
  Future<bool> cancelSosEvent(String id, DateTime nowUtc) async => false;
}

class _NoopContactPicker implements ContactPicker {
  const _NoopContactPicker();

  @override
  Future<ContactPickResult> pickContact() async =>
      const ContactPickResult(status: ContactPickStatus.cancelled);
}

void main() {
  testWidgets(
      'kontak non-Hiqeo langsung Aktif dan mode Akun Hiqeo mencari @username dengan debounce 500ms',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _InMemorySafetyRepo();
    final queries = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showEmergencyContactsSheet(
                  context,
                  ownerUserId: 'user-1',
                  safetyRepository: repo,
                  contactPicker: const _NoopContactPicker(),
                  startInAddMode: true,
                  searchHiqeoUsers: (q) async {
                    queries.add(q);
                    return const <UserSearchResult>[
                      UserSearchResult(
                        userId: 'u-rani',
                        username: 'rani_hike',
                        displayName: 'Rani',
                      ),
                    ];
                  },
                ),
                child: const Text('Buka'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    // 1. Tambah nomor HP non-Hiqeo -> langsung status Aktif (granted).
    await tester.enterText(
      find.byKey(const ValueKey<String>('emergency-contact-name-input')),
      'Ibu',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('emergency-contact-phone-input')),
      '081234567890',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('emergency-contact-save-button')),
    );
    await tester.pumpAndSettle();

    expect(repo.contacts, hasLength(1));
    expect(
      repo.contacts.single.consentStatus,
      EmergencyContactConsentStatus.granted,
    );
    expect(repo.contacts.single.isActive, isTrue);
    expect(find.text('Aktif'), findsOneWidget);
    expect(find.text('Menunggu'), findsNothing);

    // 2. Beralih ke tab Akun Hiqeo dan cari @username dengan debounce 500ms.
    await tester.tap(
      find.byKey(const ValueKey<String>('emergency-sheet-add-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('emergency-mode-hiqeo')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('emergency-hiqeo-search-input')),
      '@rani',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(queries, isEmpty);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(queries, <String>['rani']);
    expect(find.text('Rani'), findsOneWidget);
    expect(find.text('@rani_hike'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('emergency-invite-u-rani')),
      findsOneWidget,
    );
  });
}
