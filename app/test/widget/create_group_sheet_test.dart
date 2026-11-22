import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/chat/domain/chat_message.dart';
import 'package:nama_app/features/chat/domain/chat_repository.dart';
import 'package:nama_app/features/chat/domain/media_attachment.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/groups/application/group_selection.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/group_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

class _EmptyChatRepo implements ChatRepository {
  @override
  Future<void> saveMessage(ChatMessage message) async {}

  @override
  Future<ChatMessage?> findMessage(String messageId) async => null;

  @override
  Future<List<ChatMessage>> recentMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeUtc,
  }) async =>
      const <ChatMessage>[];

  @override
  Stream<List<ChatMessage>> watchMessages(String groupId, {int limit = 50}) =>
      Stream<List<ChatMessage>>.value(const <ChatMessage>[]);

  @override
  Future<int> nextSeq({
    required String groupId,
    required String authorId,
  }) async =>
      1;

  @override
  Future<void> saveMedia(MediaAttachment media) async {}

  @override
  Future<List<MediaAttachment>> mediaForMessage(String messageId) async =>
      const <MediaAttachment>[];
}

class _RecordingGroupRepo implements GroupRepository {
  final List<Group> groups = <Group>[];
  final StreamController<List<Group>> _groupsCtrl =
      StreamController<List<Group>>.broadcast();
  final StreamController<List<GroupMember>> _membersCtrl =
      StreamController<List<GroupMember>>.broadcast();

  @override
  Future<void> saveGroup(Group group) async {
    groups.removeWhere((g) => g.id == group.id);
    groups.add(group);
    _groupsCtrl.add(List<Group>.unmodifiable(groups));
  }

  @override
  Future<Group?> findGroup(String id) async {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  @override
  Stream<List<Group>> watchGroups() async* {
    yield List<Group>.unmodifiable(groups);
    yield* _groupsCtrl.stream;
  }

  @override
  Future<void> deleteGroup(String id) async {
    groups.removeWhere((g) => g.id == id);
    _groupsCtrl.add(List<Group>.unmodifiable(groups));
  }

  @override
  Future<void> saveMember(GroupMember member) async {}

  @override
  Future<List<GroupMember>> membersOf(String groupId) async =>
      const <GroupMember>[];

  @override
  Stream<List<GroupMember>> watchMembers(String groupId) async* {
    yield const <GroupMember>[];
    yield* _membersCtrl.stream;
  }

  @override
  Future<void> removeMember(String groupId, String userId) async {}
}

class _TestAccount extends AccountController {
  _TestAccount()
      : super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'me'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  @override
  UserProfile? get profile => const UserProfile(
        userId: 'me',
        username: 'pendaki',
        publicKeyBase64: 'kunci',
      );

  @override
  List<RemoteGroup> get groups => const <RemoteGroup>[];

  @override
  void initialize() {}
}

/// Membungkus [ChatPage] di dalam struktur bertingkat persis seperti `HiqeoShell`:
/// Root Navigator (`MaterialApp`) -> `Scaffold(resizeToAvoidBottomInset: true)` ->
/// `Stack` berisi `MediaQuery` yang menyuntikkan padding navbar bawah + `Navigator`
/// cabang + Floating Bottom Navbar tiruan.
Widget _buildNestedShellHarness({
  required AccountController account,
  required GroupRepository groupRepo,
}) {
  return MaterialApp(
    theme: hiqeoLightTheme,
    home: Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Builder(
            builder: (context) {
              final mq = MediaQuery.of(context);
              final bottomPad = mq.viewInsets.bottom > 0 ? 0.0 : 90.0;
              return MediaQuery(
                data: mq.copyWith(
                  padding: mq.padding.copyWith(bottom: bottomPad),
                ),
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => ChatPage(
                      accountController: account,
                      chatRepository: _EmptyChatRepo(),
                      groupRepository: groupRepo,
                      initialOnline: false,
                    ),
                  ),
                ),
              );
            },
          ),
          const Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            height: 64,
            child: SizedBox(
              key: ValueKey<String>('mock-floating-navbar'),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NavBarVisibilityController.instance.reset();
    SocialGroupsStore.setInstanceForTesting(SocialGroupsStore());
  });

  tearDown(() {
    NavBarVisibilityController.instance.reset();
    SocialGroupsStore.setInstanceForTesting(null);
  });

  testWidgets(
      'modal Buat grup baru tampil di atas navbar (useRootNavigator) & tidak terbang saat keyboard muncul (single inset)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);

    final account = _TestAccount();
    final groupRepo = _RecordingGroupRepo();
    addTearDown(account.dispose);

    await tester.pumpWidget(
      _buildNestedShellHarness(account: account, groupRepo: groupRepo),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey<String>('grup-create-empty-btn')));
    await tester.pumpAndSettle();

    final cardFinder =
        find.byKey(const ValueKey<String>('create-group-sheet-card'));
    expect(cardFinder, findsOneWidget);

    // Saat keyboard tertutup: card berada di bawah (tepat di area aman bawah,
    // tidak didorong naik 90dp ke atas navbar).
    final closedRect = tester.getRect(cardFinder);
    expect(closedRect.bottom, greaterThan(800.0));

    // Simulasikan keyboard setinggi 300dp terbuka.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final keyboardRect = tester.getRect(cardFinder);
    // Hanya 1x offset keyboard (tepi bawah card tepat di 844 - 300 = 544),
    // tidak terbang ke atas layar (yang akan bernilai ~244 atau terpotong < 0).
    expect(keyboardRect.bottom, moreOrLessEquals(544.0, epsilon: 1.5));
    expect(keyboardRect.top, greaterThan(0.0));
  });

  testWidgets(
      'modal menampilkan pemilih foto & nama grup tanpa pilihan gunung/tanggal lalu memvalidasi nama',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final account = _TestAccount();
    final groupRepo = _RecordingGroupRepo();
    addTearDown(account.dispose);

    await tester.pumpWidget(
      _buildNestedShellHarness(account: account, groupRepo: groupRepo),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey<String>('grup-create-empty-btn')));
    await tester.pumpAndSettle();

    // Pemilih foto profil bulat + field nama grup tampil; field gunung/tanggal dihapus.
    expect(
      find.byKey(const ValueKey<String>('create-group-avatar-picker')),
      findsOneWidget,
    );
    expect(find.text('Pilih foto profil grup (opsional)'), findsOneWidget);
    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('create-group-name-input')),
    );
    expect(nameField.controller?.text, isEmpty);
    expect(nameField.decoration?.hintText, 'Masukkan nama grup');
    expect(
      find.byKey(const ValueKey<String>('create-group-mountain-picker')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('create-group-date-picker')),
      findsNothing,
    );
    expect(find.text('Pilih gunung tujuan'), findsNothing);
    expect(find.text('Pilih tanggal pendakian'), findsNothing);

    // Kirim saat nama grup kosong -> modal tetap terbuka + error validasi tampil.
    final cardFinder =
        find.byKey(const ValueKey<String>('create-group-sheet-card'));
    await tester
        .tap(find.byKey(const ValueKey<String>('create-group-submit-btn')));
    await tester.pumpAndSettle();

    final errorFinder =
        find.byKey(const ValueKey<String>('create-group-validation-error'));
    expect(cardFinder, findsOneWidget);
    expect(errorFinder, findsOneWidget);
    expect(find.text('Nama grup wajib diisi.'), findsOneWidget);

    // Ketik nama grup -> error hilang -> kirim -> modal tertutup & grup tersimpan.
    await tester.enterText(
      find.byKey(const ValueKey<String>('create-group-name-input')),
      'Tim Rinjani',
    );
    await tester.pumpAndSettle();
    expect(errorFinder, findsNothing);

    await tester
        .tap(find.byKey(const ValueKey<String>('create-group-submit-btn')));
    await tester.pumpAndSettle();

    expect(cardFinder, findsNothing);
    expect(groupRepo.groups.length, 1);
    expect(groupRepo.groups.single.name, 'Tim Rinjani');
  });
}
