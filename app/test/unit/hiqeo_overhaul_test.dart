import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/config/plans.dart';
import 'package:nama_app/features/kartu/domain/kartu_data.dart';
import 'package:nama_app/features/map/domain/mountain_pack_data.dart';
import 'package:nama_app/features/plus/domain/plus_entitlement.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/safety/domain/first_aid_data.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Local GPX Mountain Catalog & Descent Mode', () {
    test('loads exactly 9 mountains and 11 local GPX trails without exposing .gpx names', () {
      final packs = MountainPackData.createDefaultPacks();
      expect(packs.length, 9);

      final allTrails = packs.expand((p) => p.package.trails).toList();
      expect(allTrails.length, 11);

      for (final pack in packs) {
        expect(pack.name.toLowerCase(), isNot(contains('.gpx')));
        expect(pack.name.toLowerCase(), isNot(contains('assets/')));
        for (final trail in pack.package.trails) {
          expect(trail.name.toLowerCase(), isNot(contains('.gpx')));
          expect(trail.name.toLowerCase(), isNot(contains('assets/')));
          expect(trail.gpxAssetPath, isNotNull);
          expect(trail.gpxAssetPath!.startsWith('assets/gpx/'), isTrue);
          expect(trail.gpxAssetPath!.endsWith('.gpx'), isTrue);
        }
      }
    });

    test('TrackRoute.reversed() flips start and summit coordinates cleanly', () {
      final route = TrackRoute.fromPoints(
        id: 'ciremai_apuy',
        name: 'Via Apuy',
        points: const <TrackRoutePoint>[
          TrackRoutePoint(lat: -6.9149, lon: 108.3709, ele: 1450),
          TrackRoutePoint(lat: -6.9060, lon: 108.3880, ele: 2250),
          TrackRoutePoint(lat: -6.8974, lon: 108.4050, ele: 3078),
        ],
      );
      final descent = route.reversed();
      expect(descent.points.length, route.points.length);
      expect(descent.startPoint!.lat, route.endPoint!.lat);
      expect(descent.endPoint!.lat, route.startPoint!.lat);
      expect(descent.totalDistanceM, closeTo(route.totalDistanceM, 1e-6));
    });
  });

  group('2-Stage Packing List & Group Hike Invite Protocol', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('supports no list, partial packed reminder, and all packed states', () async {
      final store = PackingListStore();
      await store.load(force: true);
      expect(store.hasPackingList, isFalse);

      // Pastikan perlengkapan gunung bersalju / ekstrem tersedia
      final ids = store.catalog.map((e) => e.id).toSet();
      expect(ids, containsAll(<String>['crampon', 'ice_axe', 'down_jacket', 'bivvy', 'snow_goggles']));

      await store.toggleSelectItem('headlamp');
      await store.toggleSelectItem('crampon');
      await store.addCustomItem('Kopi Sachet');
      expect(store.selectedIds.length, 3);
      expect(store.stage1Done, isFalse);

      await store.finishStage1();
      expect(store.stage1Done, isTrue);
      expect(store.missingItems.length, 3);
      expect(store.allPacked, isFalse);

      await store.togglePackedItem('headlamp');
      expect(store.missingItems.length, 2);
      expect(store.allPacked, isFalse);

      for (final item in List<PackingItem>.of(store.missingItems)) {
        await store.togglePackedItem(item.id);
      }
      expect(store.missingItems, isEmpty);
      expect(store.allPacked, isTrue);
    });

    test('GroupHikeInviteMessage encodes/decodes plan and gates readiness on other members', () {
      const plan = GroupHikePlan(
        inviteId: 'inv-1',
        groupId: 'grp-1',
        groupName: 'Tim Merbabu',
        mountainId: 'merbabu',
        mountainName: 'Gunung Merbabu',
        trailId: 'merbabu_selo',
        trailName: 'Via Selo',
        organizerUserId: 'u-owner',
        organizerName: 'Raka',
        readyUserIds: <String>{'u-owner'},
        memberCount: 3,
      );

      expect(plan.hasOtherMemberReady, isFalse);

      final encoded = GroupHikeInviteMessage.encodeInvite(plan);
      final decoded = GroupHikeInviteMessage.tryDecodeInvite(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.mountainName, 'Gunung Merbabu');
      expect(decoded.trailName, 'Via Selo');
      expect(decoded.groupName, 'Tim Merbabu');

      final readyMsg = GroupHikeInviteMessage.encodeReady(
        inviteId: 'inv-1',
        userId: 'u-friend',
        userName: 'Dina',
      );
      final decodedReady = GroupHikeInviteMessage.tryDecodeReady(readyMsg);
      expect(decodedReady, isNotNull);
      expect(decodedReady!.userId, 'u-friend');

      final updated = decoded.copyWith(
        readyUserIds: <String>{...decoded.readyUserIds, decodedReady.userId},
      );
      expect(updated.hasOtherMemberReady, isTrue);
    });
  });

  group('Hiqeo Plus 3-Plan Entitlements', () {
    test('defines exactly 3 plans with correct pricing and no forbidden copy', () {
      final plans = buildDefaultPlusPlans();
      expect(plans.length, 3);
      expect(
        plans.map((p) => p.id).toList(),
        <String>['trip_pass_3d', 'student_annual', 'annual'],
      );
      expect(plans[0].priceLabel, 'Rp7.900');
      expect(plans[1].priceLabel, 'Rp79.000');
      expect(plans[2].priceLabel, 'Rp149.000');

      for (final plan in plans) {
        expect(plan.title.toLowerCase(), isNot(contains('fitur terbatas')));
        expect(plan.periodLabel.toLowerCase(), isNot(contains('fitur terbatas')));
        expect((plan.note ?? '').toLowerCase(), isNot(contains('fitur terbatas')));
      }
    });

    test('grants full social/leaderboard/community access only to student & annual plans', () {
      final now = DateTime.utc(2026, 11, 20);
      final future = now.add(const Duration(days: 30));

      const freeAccess = PlusAccess.free;
      final tripPass = PlusAccess(
        state: PlusAccessState.active,
        planId: 'trip_pass_3d',
        expiresAtUtc: now.add(const Duration(days: 3)),
      );
      final student = PlusAccess(
        state: PlusAccessState.active,
        planId: 'student_annual',
        expiresAtUtc: future,
      );
      final annual = PlusAccess(
        state: PlusAccessState.active,
        planId: 'annual',
        expiresAtUtc: future,
      );

      expect(freeAccess.hasFullSocialAccess, isFalse);
      expect(tripPass.hasFullSocialAccess, isFalse);
      expect(student.hasFullSocialAccess, isTrue);
      expect(annual.hasFullSocialAccess, isTrue);
    });
  });

  group('Offline First Aid & Safety Guide', () {
    test('contains all 10 required clinical topics with all 3 mandatory subsections', () {
      expect(kFirstAidTopics.length, 10);
      for (final topic in kFirstAidTopics) {
        expect(topic.title.trim(), isNotEmpty);
        expect(topic.dangerSigns, isNotEmpty);
        expect(topic.firstAidSteps, isNotEmpty);
        expect(topic.prohibitionsAndMyths, isNotEmpty);
      }
    });
  });

  group('Kartu Fallback Profile & Route', () {
    test('guarantees elevation profile and route when ensureFallback is enabled', () {
      final session = TrackingSession(
        id: 'sess-1',
        startedAtUtc: DateTime.utc(2026, 11, 1, 6, 0),
        endedAtUtc: DateTime.utc(2026, 11, 1, 11, 0),
        status: TrackingSessionStatus.completed,
        distanceM: 6200,
        movingSeconds: 14400,
        elevationGainM: 1200,
        elevationLossM: 400,
      );
      final data = KartuData.fromSession(
        session,
        const <TrackPoint>[],
        ensureFallback: true,
      );
      expect(data, isNotNull);
      expect(data!.profile, isNotNull);
      expect(data.profile!.length, greaterThanOrEqualTo(2));
      expect(data.route, isNotNull);
      expect(data.route!.length, greaterThanOrEqualTo(2));
    });
  });
}
