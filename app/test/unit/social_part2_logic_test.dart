import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/social/data/community_service.dart';
import 'package:nama_app/infrastructure/notifications/fcm_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FcmNotificationService.instance.activeRoomKey = null;
  });

  test('resolveCommunitySenderName mengikuti urutan displayName -> username -> email -> Pendaki',
      () {
    expect(
      resolveCommunitySenderName(
        displayName: '  Rani Puspita ',
        username: 'rani',
        email: 'rani@mail.com',
      ),
      'Rani Puspita',
    );
    expect(
      resolveCommunitySenderName(
        displayName: '   ',
        username: '@rani_hike',
        email: 'rani@mail.com',
      ),
      'rani_hike',
    );
    expect(
      resolveCommunitySenderName(
        displayName: null,
        username: '',
        email: 'pendaki.jawa@example.com',
      ),
      'pendaki.jawa',
    );
    expect(
      resolveCommunitySenderName(
        displayName: '',
        username: null,
        email: '',
      ),
      'Pendaki',
    );
  });

  test('shouldUploadMemberLocation hanya meng-UPSERT saat sesi aktif tiap >=12dtk atau pindah >=10m',
      () {
    final t0 = DateTime.utc(2026, 11, 20, 8, 0, 0);
    const p0 = LatLng(-6.89000, 108.40800);
    const pNear = LatLng(-6.89002, 108.40800); // ~2.2 m
    const pFar = LatLng(-6.89015, 108.40800); // ~16.7 m

    // Tidak aktif -> tidak mengunggah kecuali dipaksa (buka Lokasi Terakhir).
    expect(
      shouldUploadMemberLocation(
        lastUploadedAt: null,
        lastPosition: null,
        nowUtc: t0,
        currentPosition: p0,
        isActiveSession: false,
      ),
      isFalse,
    );
    expect(
      shouldUploadMemberLocation(
        lastUploadedAt: t0,
        lastPosition: p0,
        nowUtc: t0,
        currentPosition: p0,
        isActiveSession: false,
        force: true,
      ),
      isTrue,
    );

    // Sesi aktif: titik pertama selalu diunggah.
    expect(
      shouldUploadMemberLocation(
        lastUploadedAt: null,
        lastPosition: null,
        nowUtc: t0,
        currentPosition: p0,
        isActiveSession: true,
      ),
      isTrue,
    );
    // Diam (<10 m) dan baru 5 detik -> lewati untuk hemat database.
    expect(
      shouldUploadMemberLocation(
        lastUploadedAt: t0,
        lastPosition: p0,
        nowUtc: t0.add(const Duration(seconds: 5)),
        currentPosition: pNear,
        isActiveSession: true,
      ),
      isFalse,
    );
    // Pindah >= 10 m dalam 4 detik -> langsung UPSERT.
    expect(
      shouldUploadMemberLocation(
        lastUploadedAt: t0,
        lastPosition: p0,
        nowUtc: t0.add(const Duration(seconds: 4)),
        currentPosition: pFar,
        isActiveSession: true,
      ),
      isTrue,
    );
    // Sudah 12 detik meski hampir diam -> UPSERT.
    expect(
      shouldUploadMemberLocation(
        lastUploadedAt: t0,
        lastPosition: p0,
        nowUtc: t0.add(const Duration(seconds: 12)),
        currentPosition: pNear,
        isActiveSession: true,
      ),
      isTrue,
    );
  });

  test('GroupHikePlan.fromPrepRow dan markReadyRemote menjaga 1 baris unik tanpa duplikasi',
      () async {
    final plan = GroupHikePlan.fromPrepRow(
      <String, dynamic>{
        'group_id': 'g-1',
        'invite_id': 'inv-1',
        'mountain_id': 'ciremai',
        'mountain_name': 'Gunung Ciremai',
        'trail_id': 'apuy',
        'trail_name': 'Via Apuy',
        'organizer_user_id': 'user-a',
        'organizer_name': 'Andi',
        'ready_user_ids': <String>['user-a'],
        'member_count': 2,
      },
      groupName: 'Tim Ciremai',
    );
    expect(plan, isNotNull);
    expect(plan!.allMembersReady, isFalse);

    final store = GroupHikePlanStore();
    await store.setPlan(plan);
    final updated = await store.markReadyRemote(plan, 'user-b');
    expect(updated.readyUserIds, containsAll(<String>['user-a', 'user-b']));
    expect(updated.allMembersReady, isTrue);
    expect(store.activePlan?.mountainId, 'ciremai');
    expect(store.activePlan?.groupId, 'g-1');
  });

  test('InAppPushNotification memetakan rute tiap jenis & menekan banner di ruang obrolan yang sedang dibuka',
      () {
    final fcm = FcmNotificationService.instance;
    final grp = InAppPushNotification.fromRemoteData(
      title: 'Tim Merbabu',
      body: 'Pesan baru',
      data: <String, dynamic>{'kind': 'group_message', 'group_id': 'g-1'},
    );
    expect(grp.route, '/grup');
    expect(fcm.shouldShowForegroundBanner(grp), isTrue);

    fcm.activeRoomKey = 'group:g-1';
    expect(fcm.shouldShowForegroundBanner(grp), isFalse);

    final sos = InAppPushNotification.fromRemoteData(
      data: <String, dynamic>{'kind': 'sos_alert', 'group_id': 'g-1'},
    );
    // Sinyal SOS darurat tidak pernah ditekan.
    expect(sos.isUrgent, isTrue);
    expect(fcm.shouldShowForegroundBanner(sos), isTrue);

    final friend = InAppPushNotification.fromRemoteData(
      data: <String, dynamic>{'kind': 'friend_request'},
    );
    expect(friend.route, '/teman');
  });
}
