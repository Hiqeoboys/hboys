enum PowerProfile { normal, saver, critical }

/// Memilih profil daya dari level baterai dengan histeresis, supaya profil tidak
/// bolak-balik saat baterai di sekitar ambang.
/// Turun: < 40% -> hemat, < 20% -> kritis. Naik: >= 43% -> normal, >= 23% -> hemat.
class PowerProfileManager {
  PowerProfileManager({PowerProfile initial = PowerProfile.normal}) : _profile = initial;

  PowerProfile _profile;
  PowerProfile get profile => _profile;

  PowerProfile update(int batteryPercent, {bool charging = false}) {
    if (charging) {
      _profile = PowerProfile.normal;
      return _profile;
    }
    switch (_profile) {
      case PowerProfile.normal:
        if (batteryPercent < 20) {
          _profile = PowerProfile.critical;
        } else if (batteryPercent < 40) {
          _profile = PowerProfile.saver;
        }
      case PowerProfile.saver:
        if (batteryPercent < 20) {
          _profile = PowerProfile.critical;
        } else if (batteryPercent >= 43) {
          _profile = PowerProfile.normal;
        }
      case PowerProfile.critical:
        if (batteryPercent >= 43) {
          _profile = PowerProfile.normal;
        } else if (batteryPercent >= 23) {
          _profile = PowerProfile.saver;
        }
    }
    return _profile;
  }
}

/// Parameter perilaku per profil. Angka awal; kalibrasi dengan data uji baterai.
class PowerProfileConfig {
  const PowerProfileConfig({
    required this.gpsInterval,
    required this.locationShareInterval,
    required this.allowVoice,
    required this.allowImages,
  });

  final Duration gpsInterval;
  final Duration locationShareInterval;
  final bool allowVoice;
  final bool allowImages;

  static const normal = PowerProfileConfig(
    gpsInterval: Duration(seconds: 5),
    locationShareInterval: Duration(seconds: 60),
    allowVoice: true,
    allowImages: true,
  );
  static const saver = PowerProfileConfig(
    gpsInterval: Duration(seconds: 15),
    locationShareInterval: Duration(minutes: 3),
    allowVoice: false,
    allowImages: false,
  );
  static const critical = PowerProfileConfig(
    gpsInterval: Duration(seconds: 60),
    locationShareInterval: Duration(minutes: 10),
    allowVoice: false,
    allowImages: false,
  );

  static PowerProfileConfig of(PowerProfile profile) => switch (profile) {
        PowerProfile.normal => normal,
        PowerProfile.saver => saver,
        PowerProfile.critical => critical,
      };
}
