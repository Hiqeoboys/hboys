import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/auth/presentation/account_page.dart';

import '../support/account_fakes.dart';

final DateTime now = DateTime.utc(2027, 5, 1);
final AuthUser testUser =
    const AuthUser(id: 'user-1', email: 'budi@example.com');
final Uint8List identityKey =
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

AccountController buildController({
  required FakeAuthService auth,
  UserProfile? profile,
  FakeProfileRepository? profiles,
}) {
  return AccountController(
    authService: auth,
    profileRepository: profiles ?? (FakeProfileRepository()..current = profile),
    keyDirectory: FakeKeyDirectory(),
    identity: FakeIdentity(identityKey),
    clock: FakeClock(now),
  );
}

void main() {
  testWidgets('menampilkan petunjuk setup bila Supabase belum dikonfigurasi',
      (tester) async {
    final auth = FakeAuthService(isConfigured: false);
    final controller = buildController(auth: auth);

    await tester.pumpWidget(
      MaterialApp(home: AccountPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Supabase belum dikonfigurasi'), findsOneWidget);
    expect(find.text('Masuk dengan Google'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await auth.close();
  });

  testWidgets('menampilkan tombol OAuth saat belum masuk', (tester) async {
    final auth = FakeAuthService();
    final controller = buildController(auth: auth);

    await tester.pumpWidget(
      MaterialApp(home: AccountPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Masuk dengan Google'), findsOneWidget);
    expect(find.text('Masuk dengan Apple'), findsOneWidget);

    await tester.tap(find.text('Masuk dengan Google'));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, [AuthProviderKind.google]);
    expect(find.textContaining('Selesaikan login di browser'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await auth.close();
  });

  testWidgets('menampilkan akun dan bagian grup saat sudah masuk',
      (tester) async {
    final auth = FakeAuthService(currentUser: testUser);
    final controller = buildController(
      auth: auth,
      profile: UserProfile(
        userId: testUser.id,
        username: 'budi_99',
        publicKeyBase64: base64Encode(identityKey),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: AccountPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('@budi_99'), findsOneWidget);
    expect(find.text('Undangan masuk'), findsOneWidget);
    expect(find.text('Grup'), findsOneWidget);
    expect(find.text('Masuk dengan Google'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await auth.close();
  });
}
