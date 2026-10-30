import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';

import 'sos_category.dart';

const double _coordScale = 1e7;

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Isi paket SOS (20 byte, sebelum enkripsi):
/// sosId(8) lat(int32) lon(int32) akurasi(uint16, meter) baterai(uint8) kategori(uint8).
class SosPayload {
  const SosPayload({
    required this.sosId,
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.batteryPercent,
    required this.category,
  });

  static const int length = 20;

  /// ID unik SOS (16 hex). Dipakai untuk ACK dan pembatalan.
  final String sosId;
  final double lat;
  final double lon;
  final int accuracyM;
  final int batteryPercent;
  final SosCategory category;

  Uint8List toBytes() {
    final out = Uint8List(length);
    final bd = ByteData.sublistView(out);
    out.setRange(0, 8, hexToBytes(sosId));
    bd.setInt32(8, (lat * _coordScale).round());
    bd.setInt32(12, (lon * _coordScale).round());
    bd.setUint16(16, _clampInt(accuracyM, 0, 0xFFFF));
    bd.setUint8(18, _clampInt(batteryPercent, 0, 100));
    bd.setUint8(19, category.code);
    return out;
  }

  factory SosPayload.fromBytes(Uint8List bytes) {
    if (bytes.length != length) {
      throw FormatException('Payload SOS harus $length byte, dapat ${bytes.length}');
    }
    final bd = ByteData.sublistView(bytes);
    return SosPayload(
      sosId: bytesToHex(bytes.sublist(0, 8)),
      lat: bd.getInt32(8) / _coordScale,
      lon: bd.getInt32(12) / _coordScale,
      accuracyM: bd.getUint16(16),
      batteryPercent: bd.getUint8(18),
      category: SosCategory.fromCode(bd.getUint8(19)),
    );
  }
}

/// Isi paket lokasi (11 byte): lat(int32) lon(int32) akurasi(uint16) baterai(uint8).
class LocationPayload {
  const LocationPayload({
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.batteryPercent,
  });

  static const int length = 11;

  final double lat;
  final double lon;
  final int accuracyM;
  final int batteryPercent;

  Uint8List toBytes() {
    final out = Uint8List(length);
    final bd = ByteData.sublistView(out);
    bd.setInt32(0, (lat * _coordScale).round());
    bd.setInt32(4, (lon * _coordScale).round());
    bd.setUint16(8, _clampInt(accuracyM, 0, 0xFFFF));
    bd.setUint8(10, _clampInt(batteryPercent, 0, 100));
    return out;
  }

  factory LocationPayload.fromBytes(Uint8List bytes) {
    if (bytes.length != length) {
      throw FormatException('Payload lokasi harus $length byte, dapat ${bytes.length}');
    }
    final bd = ByteData.sublistView(bytes);
    return LocationPayload(
      lat: bd.getInt32(0) / _coordScale,
      lon: bd.getInt32(4) / _coordScale,
      accuracyM: bd.getUint16(8),
      batteryPercent: bd.getUint8(10),
    );
  }
}
