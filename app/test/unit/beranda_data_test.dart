import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/groups/application/group_key_manager.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/application/group_selection.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/home/beranda_page.dart';

RemoteGroup _remote(String id, DateTime created, {String? mountain}) =>
    RemoteGroup(
      group: Group(
        id: id,
        name: 'Grup $id',
        ownerId: 'user-1',
        createdAtUtc: created,
        mountain: mountain,
      ),
      role: GroupRole.owner,
    );

void main() {
  test('sapaan mengikuti jam lokal', () {
    expect(greetingForHour(0), 'Selamat pagi');
    expect(greetingForHour(10), 'Selamat pagi');
    expect(greetingForHour(11), 'Selamat siang');
    expect(greetingForHour(14), 'Selamat siang');
    expect(greetingForHour(15), 'Selamat sore');
    expect(greetingForHour(17), 'Selamat sore');
    expect(greetingForHour(18), 'Selamat malam');
    expect(greetingForHour(23), 'Selamat malam');
  });

  test('pendakian berikutnya memakai grup terbaru yang nyata', () {
    final older = _remote('lama', DateTime.utc(2026, 8, 1), mountain: 'Gede');
    final newer = _remote('baru', DateTime.utc(2026, 10, 1));
    final picked = nextHikeOf(<RemoteGroup>[older, newer]);
    expect(picked?.group.id, 'baru');
    expect(nextHikeOf(const <RemoteGroup>[]), isNull);
  });

  test('ringkasan pendakian hanya menyebut keadaan yang diketahui', () {
    const ready = GroupKeyStatus(
      availability: GroupKeyAvailability.ready,
      keyVersion: 2,
      memberCount: 4,
    );
    expect(nextHikeMeta(ready), '4 anggota · kunci v2 siap');

    const waiting = GroupKeyStatus(
      availability: GroupKeyAvailability.waitingForOwner,
      keyVersion: 3,
      memberCount: 2,
    );
    expect(nextHikeMeta(waiting), '2 anggota · menunggu kunci v3');

    expect(nextHikeMeta(null), 'Kunci grup belum dimuat');
  });
}
