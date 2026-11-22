import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/social/data/friends_service.dart';
import 'package:nama_app/features/social/presentation/friends_page.dart';

void main() {
  testWidgets(
      'pencarian @username memakai debounce 500ms dan dapat mengirim permintaan teman',
      (tester) async {
    final queries = <String>[];
    final sentTo = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: FriendsPage(
          searchUsers: (q) async {
            queries.add(q);
            return const <UserSearchResult>[
              UserSearchResult(
                userId: 'u-budi',
                username: 'budi_pendaki',
                displayName: 'Budi Santoso',
              ),
            ];
          },
          sendFriendRequest: (userId) async {
            sentTo.add(userId);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('friends-username-search')),
      '@budi',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(queries, isEmpty);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(queries, <String>['budi']);
    expect(find.text('Budi Santoso'), findsOneWidget);
    expect(find.text('@budi_pendaki'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('friends-add-u-budi')));
    await tester.pumpAndSettle();

    expect(sentTo, <String>['u-budi']);
    expect(
      find.text('Permintaan teman dikirim ke @budi_pendaki.'),
      findsOneWidget,
    );
  });
}
