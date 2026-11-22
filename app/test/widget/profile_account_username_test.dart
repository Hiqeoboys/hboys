import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/platform/contact_picker.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/auth/presentation/change_username_sheet.dart';
import 'package:nama_app/features/safety/domain/emergency_contact.dart';
import 'package:nama_app/features/safety/domain/phone_validator.dart';
import 'package:nama_app/features/safety/domain/safety_repository.dart';
import 'package:nama_app/features/safety/domain/sos_event.dart';
import 'package:nama_app/features/safety/presentation/emergency_contacts_sheet.dart';

import '../support/account_fakes.dart';

final Uint8List _key = Uint8List.fromList(List<int>.generate(32, (i) => i + 3));
final DateTime _now = DateTime.utc(2026, 6, 15, 10, 0);

class _MemorySafetyRepo implements SafetyRepository {
  _MemorySafetyRepo([List<EmergencyContact>? initial])
      : items = List<EmergencyContact>.of(initial ?? const <EmergencyContact>[]);

  final List<EmergencyContact> items;

  @override
  Future<List<EmergencyContact>> contactsOf(String userId) async =>
      List<EmergencyContact>.of(items);

  @override
  Future<void> saveContact(EmergencyContact contact) async {
    items.removeWhere((c) => c.id == contact.id);
    items.add(contact);
  }

  @override
  Stream<List<EmergencyContact>> watchContacts(String userId) =>
      Stream<List<EmergencyContact>>.value(List<EmergencyContact>.of(items));

  @override
  Future<void> deleteContact(String id) async {
    items.removeWhere((c) => c.id == id);
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

class _StubPicker implements ContactPicker {
  _StubPicker(this.result);
  final ContactPickResult result;

  @override
  Future<ContactPickResult> pickContact() async => result;
}

AccountController _makeAccount({
  required FakeProfileRepository profiles,
  required FakeAuthService auth,
}) {
  return AccountController(
    authService: auth,
    profileRepository: profiles,
    keyDirectory: FakeKeyDirectory(),
    identity: FakeIdentity(_key),
    clock: FakeClock(_now),
  );
}

void main() {
  testWidgets(
      'ChangeUsernameSheet memvalidasi format, menolak kata terlarang/terpakai, dan menyimpan username valid',
      (tester) async {
    final auth = FakeAuthService(
      currentUser: const AuthUser(
        id: 'u1',
        email: 'raka@example.com',
        provider: AuthProviderKind.google,
      ),
    );
    final profiles = FakeProfileRepository()
      ..current = UserProfile(
        userId: 'u1',
        username: 'raka_lama',
        publicKeyBase64: base64Encode(_key),
      );
    final account = _makeAccount(profiles: profiles, auth: auth)..initialize();
    addTearDown(() async {
      account.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showChangeUsernameSheet(context, controller: account),
              child: const Text('Buka'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    expect(find.text('Ganti username'), findsOneWidget);
    expect(find.text('Bisa diganti sekali tiap 7 hari.'), findsOneWidget);

    // Format salah -> tombol simpan nonaktif & pesan aturan muncul
    await tester.enterText(
      find.byKey(const ValueKey<String>('change-username-input')),
      'ra..ka',
    );
    await tester.pump();
    expect(
      find.text('Tidak boleh mengandung dua titik berurutan (..).'),
      findsOneWidget,
    );

    // Server mengembalikan error "taken"
    profiles.setUsernameError = const AccountException('taken', 'taken');
    await tester.enterText(
      find.byKey(const ValueKey<String>('change-username-input')),
      'raka_terpakai',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('change-username-save-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Username sudah dipakai. Pilih yang lain.'), findsOneWidget);

    // Server mengembalikan error "blocked" (moderasi sisi server)
    profiles.setUsernameError = const AccountException('blocked', 'blocked');
    await tester.enterText(
      find.byKey(const ValueKey<String>('change-username-input')),
      'raka_diblokir',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('change-username-save-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Username ini tidak diperbolehkan. Pilih yang lain.'),
      findsOneWidget,
    );

    // Username valid berhasil disimpan -> sheet menutup
    profiles.setUsernameError = null;
    await tester.enterText(
      find.byKey(const ValueKey<String>('change-username-input')),
      'raka_baru',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('change-username-save-button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('change-username-sheet')), findsNothing);
    expect(account.profile?.username, 'raka_baru');
  });

  testWidgets('ChangeUsernameSheet menampilkan jeda 7 hari saat baru diganti',
      (tester) async {
    final auth = FakeAuthService(
      currentUser: const AuthUser(id: 'u1', provider: AuthProviderKind.google),
    );
    final profiles = FakeProfileRepository()
      ..current = UserProfile(
        userId: 'u1',
        username: 'raka_sehat',
        usernameChangedAtUtc: _now.subtract(const Duration(days: 4)),
        publicKeyBase64: base64Encode(_key),
      );
    final account = _makeAccount(profiles: profiles, auth: auth)..initialize();
    addTearDown(() async {
      account.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showChangeUsernameSheet(context, controller: account),
              child: const Text('Buka'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('username-cooldown-banner')),
      findsOneWidget,
    );
    expect(
      find.text('Username baru bisa diganti lagi dalam 3 hari'),
      findsOneWidget,
    );
  });

  testWidgets(
      'sheet kontak darurat mendukung pilih kontak perangkat & membatasi maksimal 3 kontak',
      (tester) async {
    final repo = _MemorySafetyRepo(<EmergencyContact>[
      EmergencyContact(
        id: 'c1',
        userId: 'u1',
        name: 'Ayah',
        phoneE164: '+628111111111',
        createdAtUtc: _now,
      ),
      EmergencyContact(
        id: 'c2',
        userId: 'u1',
        name: 'Ibu',
        phoneE164: '+628222222222',
        createdAtUtc: _now,
      ),
    ]);
    final picker = _StubPicker(
      const ContactPickResult(
        status: ContactPickStatus.picked,
        contact: PickedContact(name: 'Kakak', phone: '0813-5555-6666'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showEmergencyContactsSheet(
                context,
                ownerUserId: 'u1',
                safetyRepository: repo,
                contactPicker: picker,
              ),
              child: const Text('Kontak'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kontak'));
    await tester.pumpAndSettle();

    // Tambah kontak ke-3 lewat picker perangkat
    await tester.tap(
      find.byKey(const ValueKey<String>('emergency-sheet-add-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('emergency-pick-device-contact')),
    );
    await tester.pumpAndSettle();
    final saveBtn = find.byKey(
      const ValueKey<String>('emergency-contact-save-button'),
    );
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(repo.items, hasLength(kMaxEmergencyContacts));
    expect(repo.items.last.name, 'Kakak');
    expect(repo.items.last.phoneE164, '+6281355556666');
    expect(find.text('Maksimal 3 kontak darurat'), findsOneWidget);
  });
}
