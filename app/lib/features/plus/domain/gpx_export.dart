import '../../tracking/domain/track_point.dart';
import '../../tracking/domain/tracking_session.dart';
import '../../../core/brand/app_brand.dart';

/// Dokumen GPX 1.1 dari satu sesi dan titiknya.
///
/// Ekspor GPX tetap tersedia untuk semua pengguna, termasuk setelah
/// berhenti berlangganan. [creator] selalu nama merek agar berkas yang
/// diimpor aplikasi lain menyebut Hiqeo.
abstract final class GpxDocument {
  static String build({
    required TrackingSession session,
    required List<TrackPoint> points,
    String? name,
  }) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="${_escape(AppBrand.name)}" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 '
        'http://www.topografix.com/GPX/1/1/gpx.xsd">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>${_escape(name ?? _defaultName(session))}</name>')
      ..writeln('    <time>${session.startedAtUtc.toIso8601String()}</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_escape(name ?? _defaultName(session))}</name>')
      ..writeln('    <trkseg>');
    for (final point in points) {
      buffer.writeln(
        '      <trkpt lat="${point.lat.toStringAsFixed(6)}" '
        'lon="${point.lon.toStringAsFixed(6)}">',
      );
      final altitude = point.altitudeM;
      if (altitude != null) {
        buffer.writeln('        <ele>${altitude.toStringAsFixed(1)}</ele>');
      }
      buffer
        ..writeln(
            '        <time>${point.timestampUtc.toIso8601String()}</time>')
        ..writeln('      </trkpt>');
    }
    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buffer.toString();
  }

  static String _defaultName(TrackingSession session) {
    final local = session.startedAtUtc.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return 'Pendakian $day/$month/${local.year}';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// Menulis berkas GPX dan membuka lembar berbagi.
abstract interface class GpxExporter {
  Future<bool> share({
    required String fileName,
    required String contents,
    String? subject,
  });
}
