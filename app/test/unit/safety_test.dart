import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/safety/domain/payloads.dart';
import 'package:nama_app/features/safety/domain/sos_category.dart';
import 'package:nama_app/features/safety/domain/sos_status_tracker.dart';
import 'package:nama_app/features/safety/domain/sos_trigger_controller.dart';

final t0 = DateTime.utc(2027, 6, 1, 8);

void main() {
  group('SosTriggerController', () {
    test('tahan 3 detik lalu hitung mundur 5 detik lalu terpicu', () {
      final c = SosTriggerController()..holdStarted(t0);
      expect(c.tick(t0.add(const Duration(seconds: 2))), SosTriggerState.holding);
      expect(c.tick(t0.add(const Duration(seconds: 3))), SosTriggerState.countdown);
      expect(c.tick(t0.add(const Duration(seconds: 7))), SosTriggerState.countdown);
      expect(c.tick(t0.add(const Duration(seconds: 8))), SosTriggerState.triggered);
    });

    test('melepas sebelum 3 detik membatalkan tahan', () {
      final c = SosTriggerController()..holdStarted(t0);
      c.tick(t0.add(const Duration(seconds: 1)));
      c.holdReleased();
      expect(c.state, SosTriggerState.idle);
    });

    test('melepas jari saat hitung mundur TIDAK membatalkan', () {
      final c = SosTriggerController()..holdStarted(t0);
      c.tick(t0.add(const Duration(seconds: 3)));
      c.holdReleased();
      expect(c.state, SosTriggerState.countdown);
    });

    test('batal saat hitung mundur', () {
      final c = SosTriggerController()..holdStarted(t0);
      c.tick(t0.add(const Duration(seconds: 3)));
      c.cancel();
      expect(c.state, SosTriggerState.cancelled);
      expect(c.tick(t0.add(const Duration(seconds: 30))), SosTriggerState.cancelled);
    });

    test('sisa hitung mundur', () {
      final c = SosTriggerController()..holdStarted(t0);
      c.tick(t0.add(const Duration(seconds: 3)));
      expect(
        c.countdownRemaining(t0.add(const Duration(seconds: 5))),
        const Duration(seconds: 3),
      );
    });
  });

  group('SosStatusTracker', () {
    test('awalnya tidak boleh mengklaim sampai ke kontak darurat', () {
      final s = SosStatusTracker()..mark(SosDeliveryStage.savedLocally);
      expect(s.mayClaimDeliveredToContact, isFalse);
      expect(s.leftTheGroup, isFalse);
      expect(s.highest, SosDeliveryStage.savedLocally);
    });

    test('diteruskan ke server belum berarti sampai ke kontak', () {
      final s = SosStatusTracker()
        ..mark(SosDeliveryStage.savedLocally)
        ..mark(SosDeliveryStage.forwardedToServer);
      expect(s.leftTheGroup, isTrue);
      expect(s.mayClaimDeliveredToContact, isFalse);
    });

    test('klaim hanya setelah kontak benar-benar menerima', () {
      final s = SosStatusTracker()
        ..mark(SosDeliveryStage.sentToPeers, peers: 2)
        ..mark(SosDeliveryStage.deliveredToEmergencyContact);
      expect(s.mayClaimDeliveredToContact, isTrue);
      expect(s.peerCount, 2);
    });
  });

  group('Payload', () {
    test('SOS round trip 20 byte', () {
      const sos = SosPayload(
        sosId: '0102030405060708',
        lat: -7.1234567,
        lon: 107.9876543,
        accuracyM: 12,
        batteryPercent: 37,
        category: SosCategory.injury,
      );
      final bytes = sos.toBytes();
      expect(bytes.length, SosPayload.length);
      final back = SosPayload.fromBytes(bytes);
      expect(back.sosId, '0102030405060708');
      expect(back.lat, closeTo(-7.1234567, 1e-7));
      expect(back.lon, closeTo(107.9876543, 1e-7));
      expect(back.accuracyM, 12);
      expect(back.batteryPercent, 37);
      expect(back.category, SosCategory.injury);
    });

    test('lokasi round trip 11 byte', () {
      const loc = LocationPayload(lat: -6.9, lon: 107.6, accuracyM: 8, batteryPercent: 90);
      final back = LocationPayload.fromBytes(loc.toBytes());
      expect(loc.toBytes().length, LocationPayload.length);
      expect(back.lat, closeTo(-6.9, 1e-7));
      expect(back.batteryPercent, 90);
    });

    test('menolak panjang salah', () {
      expect(() => SosPayload.fromBytes(Uint8List(5)), throwsFormatException);
      expect(() => LocationPayload.fromBytes(Uint8List(5)), throwsFormatException);
    });

    test('kategori tak dikenal menjadi other', () {
      expect(SosCategory.fromCode(77), SosCategory.other);
    });
  });
}
