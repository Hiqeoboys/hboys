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
    this.linkedUserId,
    this.linkedUsername,
  }) {
    if (!isHiqeoAccount && !_e164Pattern.hasMatch(phoneE164)) {
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
  final String? linkedUserId;
  final String? linkedUsername;

  bool get isHiqeoAccount =>
      linkedUserId != null && linkedUserId!.trim().isNotEmpty;

  bool get isActive => consentStatus == EmergencyContactConsentStatus.granted;

  EmergencyContact copyWith({
    String? name,
    EmergencyContactConsentStatus? consentStatus,
    DateTime? consentAtUtc,
  }) =>
      EmergencyContact(
        id: id,
        userId: userId,
        name: name ?? this.name,
        phoneE164: phoneE164,
        createdAtUtc: createdAtUtc,
        channel: channel,
        consentStatus: consentStatus ?? this.consentStatus,
        consentAtUtc: consentAtUtc ?? this.consentAtUtc,
        linkedUserId: linkedUserId,
        linkedUsername: linkedUsername,
      );
}
