import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/auth/presentation/account_page.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/home/beranda_page.dart';
import 'package:nama_app/features/profile/presentation/profil_page.dart';
import 'package:nama_app/infrastructure/cache/offline_account_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';
import '../support/plus_fixtures.dart';

final DateTime now = DateTime.utc(2027, 5, 1);
const AuthUser testUser = AuthUser(
  id: 'user-1',
  email: 'budi@example.com',
  provider: AuthProviderKind.google,
);
final Uint8List identityKey =
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

class _MemoryAccountCache implements OfflineAccountCache {
  UserProfile? storedProfile;

  @override
  Future<UserProfile?> readProfile(String userId) async => storedProfile;

  @override
  Future<void> writeProfile(UserProfile profile) async {
    storedProfile = profile;
  }

  @override
  Future<void> deleteProfile(String userId) async => storedProfile = null;

  @override
  Future<List<CachedGroupEntry>> readGroups(String userId) async =>
      const <CachedGroupEntry>[];

  @override
  Future<void> writeGroups(
      String userId, List<CachedGroupEntry> groups) async {}

  @override
  Future<List<IncomingInvitation>> readInvitations(String userId) async =>
      const <IncomingInvitation>[];

  @override
  Future<void> writeInvitations(
    String userId,
    List<IncomingInvitation> invitations,
  ) async {}

  @override
  Future<List<MemberDirectoryEntry>> readMembers(String groupId) async =>
      const <MemberDirectoryEntry>[];

  @override
  Future<void> writeMembers(
    String groupId,
    List<MemberDirectoryEntry> members,
  ) async {}

  @override
  Future<String?> cacheAvatarFile({
    required String userId,
    required String avatarUrl,
  }) async =>
      null;

  @override
  Future<String?> saveAvatarBytes({
    required String userId,
    required String avatarUrl,
    required Uint8List bytes,
  }) async =>
      null;

  @override
  Future<void> clearUser(String userId) async => storedProfile = null;
}

AccountController buildController({
  required FakeAuthService auth,
  UserProfile? profile,
  FakeProfileRepository? profiles,
  OfflineAccountCache? cache,
}) {
  return AccountController(
    authService: auth,
    profileRepository: profiles ?? (FakeProfileRepository()..current = profile),
    keyDirectory: FakeKeyDirectory(),
    identity: FakeIdentity(identityKey),
    cache: cache,
    clock: FakeClock(now),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('menampilkan petunjuk setup bila Supabase belum dikonfigurasi',
      (tester) async {
    final auth = FakeAuthService(isConfigured: false);
    final controller = buildController(auth: auth);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: AccountPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Akun'), findsOneWidget);
    expect(find.text('Layanan akun sedang tidak tersedia'), findsOneWidget);
    expect(find.text('Masuk dengan Google'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await auth.close();
  });

  testWidgets('menampilkan tombol OAuth saat belum masuk', (tester) async {
    final auth = FakeAuthService();
    final controller = buildController(auth: auth);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: AccountPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Masuk dengan Google'), findsOneWidget);

    await tester.tap(find.text('Masuk dengan Google'));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, [AuthProviderKind.google]);
    expect(find.textContaining('Selesaikan login di browser'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await auth.close();
  });

  testWidgets(
      'halaman Akun menampilkan Foto profil (tanpa teks teknis), Nama akun di atas Username, & aksi akun',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthService(currentUser: testUser);
    final controller = buildController(
      auth: auth,
      profile: UserProfile(
        userId: testUser.id,
        username: 'budi_99',
        fullName: 'Budi Santoso',
        publicKeyBase64: base64Encode(identityKey),
      ),
    );
    var localCleared = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: AccountPage(
          controller: controller,
          onClearAllLocalData: () async => localCleared++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Akun'), findsOneWidget);
    expect(find.text('Foto profil'), findsOneWidget);
    expect(find.text('Ketuk Ubah untuk mengganti foto'), findsOneWidget);
    // Point 12: teks teknis WebP / 512x512 dihapus
    expect(find.textContaining('Potong 1:1 WebP'), findsNothing);
    expect(find.textContaining('512×512'), findsNothing);

    // Point 11: kartu Nama akun di bawah Foto profil dan di atas Username
    expect(find.text('Nama akun'), findsOneWidget);
    expect(find.text('Budi Santoso'), findsOneWidget);
    expect(find.text('@budi_99'), findsOneWidget);
    expect(find.text('Ganti'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('account-change-name-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('account-change-username-button')),
      findsOneWidget,
    );

    final avatarRect = tester.getRect(
      find.byKey(const ValueKey<String>('account-avatar-card')),
    );
    final nameRect = tester.getRect(
      find.byKey(const ValueKey<String>('account-name-card')),
    );
    final usernameRect = tester.getRect(
      find.byKey(const ValueKey<String>('account-username-card')),
    );
    expect(nameRect.top, greaterThan(avatarRect.bottom));
    expect(usernameRect.top, greaterThan(nameRect.bottom));

    expect(find.text('budi@example.com'), findsOneWidget);
    final scrollable = find.byType(Scrollable).first;
    final switchBtn =
        find.byKey(const ValueKey<String>('account-switch-button'));
    await tester.scrollUntilVisible(switchBtn, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(find.text('Ganti akun'), findsOneWidget);
    final signOutBtn =
        find.byKey(const ValueKey<String>('account-signout-button'));
    await tester.scrollUntilVisible(signOutBtn, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(find.text('Keluar'), findsOneWidget);
    final deleteBtnCheck =
        find.byKey(const ValueKey<String>('account-delete-button'));
    await tester.scrollUntilVisible(deleteBtnCheck, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(find.text('Hapus akun'), findsOneWidget);

    // Zero group/invitation UI on AccountPage
    expect(find.text('Undangan masuk'), findsNothing);
    expect(find.text('Buat grup'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Masuk dengan Google'),
      -200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Masuk dengan Google'), findsOneWidget);

    // Uji dialog hapus akun dengan ketik HAPUS
    final deleteBtn =
        find.byKey(const ValueKey<String>('account-delete-button'));
    await tester.ensureVisible(deleteBtn);
    await tester.pumpAndSettle();
    await tester.tap(deleteBtn);
    await tester.pump();
    expect(find.text('Hapus akun permanen?'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('account-delete-confirm-input')),
      'HAPUS',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('account-confirm-delete-button')),
    );
    await tester.pumpAndSettle();
    expect(auth.deleteAccountCalls, 1);
    expect(localCleared, 1);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await auth.close();
  });

  testWidgets(
      'mengganti Nama akun memvalidasi batas 40 karakter, memperbarui cache & Beranda + Profil seketika',
      (tester) async {
    final auth = FakeAuthService(currentUser: testUser);
    final profiles = FakeProfileRepository()
      ..current = UserProfile(
        userId: testUser.id,
        username: 'budi_99',
        fullName: 'Budi Lama',
        publicKeyBase64: base64Encode(identityKey),
      );
    final cache = _MemoryAccountCache();
    final controller = buildController(
      auth: auth,
      profiles: profiles,
      cache: cache,
    )..initialize();

    expect(
      await controller.updateFullName('   '),
      'Nama akun tidak boleh kosong.',
    );
    expect(
      await controller.updateFullName('a' * 41),
      'Nama akun maksimal 40 karakter.',
    );

    final tracking = FakeTrackingRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: DefaultTabController(
          length: 3,
          child: Scaffold(
            body: TabBarView(
              children: <Widget>[
                AccountPage(controller: controller),
                BerandaPage(
                  accountController: controller,
                  repository: tracking,
                ),
                ProfilPage(
                  accountController: controller,
                  trackingRepository: tracking,
                  downloadedMountainCount: () async => 0,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('account-change-name-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ganti nama akun'), findsOneWidget);

    // Kosongkan input -> error wajib isi muncul & tombol simpan nonaktif
    await tester.enterText(
      find.byKey(const ValueKey<String>('change-name-input')),
      '   ',
    );
    await tester.pump();
    expect(find.text('Nama akun tidak boleh kosong.'), findsOneWidget);

    // Isi nama baru -> simpan -> terupdate ke repo, cache, Beranda, & Profil
    await tester.enterText(
      find.byKey(const ValueKey<String>('change-name-input')),
      'Raka Pratama',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('change-name-save-button')),
    );
    await tester.pumpAndSettle();

    expect(profiles.updateFullNameCalls, <String>['Raka Pratama']);
    expect(controller.profile?.fullName, 'Raka Pratama');
    expect(cache.storedProfile?.fullName, 'Raka Pratama');
    expect(find.text('Raka Pratama'), findsOneWidget);

    // Pindah tab ke Beranda -> langsung menampilkan "Halo, Raka Pratama"
    final tabCtrl = DefaultTabController.of(
      tester.element(find.byType(TabBarView)),
    );
    tabCtrl.animateTo(1);
    await tester.pumpAndSettle();
    expect(find.text('Halo, Raka Pratama'), findsOneWidget);

    // Pindah tab ke Profil -> langsung menampilkan "Raka Pratama"
    tabCtrl.animateTo(2);
    await tester.pumpAndSettle();
    expect(find.text('Raka Pratama'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await auth.close();
  });
}
