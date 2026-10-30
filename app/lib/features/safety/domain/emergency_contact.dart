enum EmergencyContactChannel { sms, whatsapp }

enum EmergencyContactConsentStatus { pending, granted, revoked }

final RegExp _e164Pattern = RegExp(r'^\+[0-9]{8,15}$');

class EmergencyContact {
  EmergencyContact({
    required this.id,
    required this.userId,
    required this.name,
    required this.phoneE164,
    required this.createdAtUtc,
    this.channel = EmergencyContactChannel.sms,
    this.consentStatus = EmergencyContactConsentStatus.pending,
    this.consentAtUtc,
  }) {
    if (!_e164Pattern.hasMatch(phoneE164)) {
      throw ArgumentError.value(
        phoneE164,
        'phoneE164',
        'harus format E.164, contoh +628123456789',
      );
    }
  }

  final String id;
  final String userId;
  final String name;
  final String phoneE164;
  final EmergencyContactChannel channel;
  final EmergencyContactConsentStatus consentStatus;
  final DateTime? consentAtUtc;
  final DateTime createdAtUtc;
}
