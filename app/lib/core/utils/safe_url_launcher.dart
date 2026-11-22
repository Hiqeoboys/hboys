import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _smsPhonePattern = RegExp(r'^\+?[0-9]{6,16}$');
final RegExp _telPhonePattern = RegExp(r'^\+?[0-9]{2,16}$');
final RegExp _waPhoneDigitsPattern = RegExp(r'^[0-9]{8,15}$');
final RegExp _geoCoordsPattern = RegExp(r'^-?[0-9]+(\.[0-9]+)?,-?[0-9]+(\.[0-9]+)?$');
final RegExp _controlChars = RegExp(r'[\u0000-\u001F\u007F]');

/// Validates external launch URIs against an explicit scheme allowlist
/// (`https`, `sms`, `tel`, `whatsapp`, `geo`).
bool isAllowedLaunchUri(Uri uri) {
  final raw = uri.toString();
  if (_controlChars.hasMatch(raw)) return false;

  switch (uri.scheme.toLowerCase()) {
    case 'https':
      return uri.host.isNotEmpty && uri.userInfo.isEmpty;
    case 'sms':
      final recipients = uri.path
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList(growable: false);
      return recipients.isNotEmpty &&
          recipients.every(_smsPhonePattern.hasMatch);
    case 'tel':
      final target = uri.path.trim();
      return target.isNotEmpty && _telPhonePattern.hasMatch(target);
    case 'whatsapp':
      return uri.host.toLowerCase() == 'send' && uri.userInfo.isEmpty;
    case 'geo':
      return _geoCoordsPattern.hasMatch(uri.path.trim());
    default:
      return false;
  }
}

/// Parses coordinates defensively so untrusted push payloads cannot inject arbitrary query/host parts.
Uri? buildSafeGoogleMapsUri({
  required String rawLat,
  required String rawLon,
}) {
  final lat = double.tryParse(rawLat.trim());
  final lon = double.tryParse(rawLon.trim());
  if (lat == null ||
      lon == null ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat < -90 ||
      lat > 90 ||
      lon < -180 ||
      lon > 180) {
    return null;
  }
  return Uri.https(
    'maps.google.com',
    '/',
    <String, String>{
      'q': '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}',
    },
  );
}

/// Builds a platform-native Maps URL (Apple Maps on iOS, Google Maps on Android).
Uri? buildSafeMapsUri({
  required String rawLat,
  required String rawLon,
  TargetPlatform? platformOverride,
}) {
  final lat = double.tryParse(rawLat.trim());
  final lon = double.tryParse(rawLon.trim());
  if (lat == null ||
      lon == null ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat < -90 ||
      lat > 90 ||
      lon < -180 ||
      lon > 180) {
    return null;
  }
  final coord = '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}';
  final platform = platformOverride ?? defaultTargetPlatform;
  if (platform == TargetPlatform.iOS) {
    return Uri.https(
      'maps.apple.com',
      '/',
      <String, String>{'q': coord, 'll': coord},
    );
  }
  return Uri.https('maps.google.com', '/', <String, String>{'q': coord});
}

/// Builds a WhatsApp share URL (`whatsapp://send` or `https://wa.me/...` fallback).
Uri? buildSafeWhatsappUri({
  required String phoneE164,
  required String message,
  bool webFallback = false,
}) {
  final digits = phoneE164.replaceAll(RegExp(r'[^0-9]'), '');
  if (!_waPhoneDigitsPattern.hasMatch(digits)) return null;
  final encodedText = Uri.encodeComponent(message);
  if (webFallback) {
    return Uri.parse('https://wa.me/$digits?text=$encodedText');
  }
  return Uri.parse('whatsapp://send?phone=$digits&text=$encodedText');
}

Future<bool> launchSafeExternalUrl(Uri uri) async {
  if (!isAllowedLaunchUri(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
