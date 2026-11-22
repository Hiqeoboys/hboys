import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/config/supabase_config.dart';
import 'package:nama_app/core/utils/safe_url_launcher.dart';
import 'package:nama_app/features/safety/application/sos_action_service.dart';

void main() {
  group('SafeUrlLauncher', () {
    test('allows https, valid sms, and valid tel URIs', () {
      expect(isAllowedLaunchUri(Uri.parse('https://hiqeo.com/privacy')), isTrue);
      expect(
        isAllowedLaunchUri(
          Uri(scheme: 'sms', path: '+6281234567890,+6281987654321'),
        ),
        isTrue,
      );
      expect(isAllowedLaunchUri(Uri(scheme: 'tel', path: '112')), isTrue);
      expect(isAllowedLaunchUri(Uri(scheme: 'tel', path: '+6281234567890')), isTrue);
    });

    test('rejects insecure or injectable URI schemes and payloads', () {
      expect(isAllowedLaunchUri(Uri.parse('http://hiqeo.com/privacy')), isFalse);
      expect(isAllowedLaunchUri(Uri.parse('javascript:alert(1)')), isFalse);
      expect(isAllowedLaunchUri(Uri.parse('file:///etc/passwd')), isFalse);
      expect(isAllowedLaunchUri(Uri.parse('intent://scan/#Intent;end')), isFalse);
      expect(isAllowedLaunchUri(Uri.parse('https://user:pass@hiqeo.com')), isFalse);
      expect(isAllowedLaunchUri(Uri(scheme: 'sms', path: 'not-a-phone')), isFalse);
      expect(isAllowedLaunchUri(Uri(scheme: 'tel', path: '112;reboot')), isFalse);
    });

    test('buildSafeGoogleMapsUri validates numeric range and rejects injection', () {
      final valid = buildSafeGoogleMapsUri(rawLat: '-8.1077', rawLon: '112.9224');
      expect(valid, isNotNull);
      expect(valid!.scheme, 'https');
      expect(valid.host, 'maps.google.com');
      expect(valid.queryParameters['q'], '-8.107700,112.922400');

      expect(buildSafeGoogleMapsUri(rawLat: '95', rawLon: '112'), isNull);
      expect(buildSafeGoogleMapsUri(rawLat: '-8', rawLon: '200'), isNull);
      expect(
        buildSafeGoogleMapsUri(rawLat: '-8.1&evil=1', rawLon: '112.9'),
        isNull,
      );
      expect(buildSafeGoogleMapsUri(rawLat: 'NaN', rawLon: '112.9'), isNull);
    });
  });

  group('buildEmergencySmsUri', () {
    test('filters out invalid or injected recipient numbers', () {
      final uri = buildEmergencySmsUri(
        <String>['+6281234567890', 'bad-entry', '08123456789', '1234;drop'],
        'SOS',
      );
      expect(uri.scheme, 'sms');
      expect(uri.path, '+6281234567890,08123456789');
      expect(isAllowedLaunchUri(uri), isTrue);
    });
  });

  group('SupabaseConfig.parseEnvString', () {
    test('ignores secret keys and private Mapbox/Supabase tokens', () {
      SupabaseConfig.parseEnvString('''
R2_SECRET_ACCESS_KEY=supersecret
R2_ACCESS_KEY_ID=access123
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiJ9.secret
WEBHOOK_SECRET=whsec_123
FIREBASE_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----
MAPBOX_ACCESS_TOKEN=sk.eyJ1Ijoic2VjcmV0In0.abc
SUPABASE_ANON_KEY=sb_secret_not_allowed
''');
      expect(SupabaseConfig.mapboxAccessToken, isNot(startsWith('sk.')));
      expect(SupabaseConfig.legacyAnonKey, isNot(startsWith('sb_secret_')));

      SupabaseConfig.parseEnvString('''
MAPBOX_ACCESS_TOKEN=pk.eyJ1IjoicHVibGljIn0.xyz
SUPABASE_ANON_KEY=sb_publishable_public_123
''');
      expect(SupabaseConfig.mapboxAccessToken, 'pk.eyJ1IjoicHVibGljIn0.xyz');
      expect(SupabaseConfig.legacyAnonKey, 'sb_publishable_public_123');
    });
  });
}
