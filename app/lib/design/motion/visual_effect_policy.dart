import 'dart:io' show File, Platform;

import 'package:flutter/widgets.dart';

import '../../infrastructure/power/power_profile_manager.dart';

/// Golongan kemampuan perangkat untuk efek mahal (blur, metaball).
enum DeviceTier { capable, lowEnd }

/// Keputusan menyalakan efek visual.
///
/// Aturan rancangan: blur kaca mati saat profil daya Hemat/Kritis atau di
/// perangkat lemah; gooey mati pada kondisi itu ditambah saat sistem meminta
/// kurangi animasi. Fungsi aplikasi tidak pernah bergantung pada efek ini.
@immutable
class VisualEffectPolicy {
  const VisualEffectPolicy({
    required this.powerProfile,
    required this.reduceMotion,
    required this.deviceTier,
  });

  static const VisualEffectPolicy full = VisualEffectPolicy(
    powerProfile: PowerProfile.normal,
    reduceMotion: false,
    deviceTier: DeviceTier.capable,
  );

  final PowerProfile powerProfile;
  final bool reduceMotion;
  final DeviceTier deviceTier;

  bool get _powerRestricted => powerProfile != PowerProfile.normal;
  bool get _lowEnd => deviceTier == DeviceTier.lowEnd;

  bool get glassBlur => !_powerRestricted && !_lowEnd;
  bool get gooey => !_powerRestricted && !_lowEnd && !reduceMotion;

  /// Heuristika sederhana tanpa plugin: inti prosesor sangat sedikit atau RAM
  /// di bawah 3 GB menandakan perangkat kelas bawah. Dapat ditimpa lewat uji.
  /// Di platform tanpa `/proc/meminfo` (iOS, mesin pengembang) RAM dianggap
  /// tidak diketahui dan perangkat dianggap mampu.
  static DeviceTier probeDeviceTier({int? processorCount, int? totalMemoryKb}) {
    final cores = processorCount ?? Platform.numberOfProcessors;
    if (cores <= 2) return DeviceTier.lowEnd;
    final memoryKb = totalMemoryKb ?? _readTotalMemoryKb();
    if (memoryKb != null && memoryKb < 3 * 1024 * 1024) {
      return DeviceTier.lowEnd;
    }
    return DeviceTier.capable;
  }

  static int? _readTotalMemoryKb() {
    try {
      final first = File('/proc/meminfo').readAsLinesSync().first;
      final kb = first
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .skip(1)
          .first;
      return int.parse(kb);
    } on Exception {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is VisualEffectPolicy &&
      other.powerProfile == powerProfile &&
      other.reduceMotion == reduceMotion &&
      other.deviceTier == deviceTier;

  @override
  int get hashCode => Object.hash(powerProfile, reduceMotion, deviceTier);
}

/// Menyebarkan [VisualEffectPolicy] ke kaca dan gooey di bawahnya.
class VisualEffectPolicyScope extends InheritedWidget {
  const VisualEffectPolicyScope({
    super.key,
    required this.policy,
    required super.child,
  });

  final VisualEffectPolicy policy;

  static VisualEffectPolicy of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<VisualEffectPolicyScope>()
          ?.policy ??
      VisualEffectPolicy.full;

  @override
  bool updateShouldNotify(VisualEffectPolicyScope oldWidget) =>
      oldWidget.policy != policy;
}
