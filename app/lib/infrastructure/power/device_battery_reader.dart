import 'package:battery_plus/battery_plus.dart';

import '../../features/tracking/application/tracking_runtime.dart';

class DeviceBatteryReader implements BatteryReader {
  DeviceBatteryReader([Battery? battery]) : _battery = battery ?? Battery();

  final Battery _battery;

  @override
  Future<int> levelPercent() => _battery.batteryLevel;

  @override
  Future<bool> isCharging() async {
    final state = await _battery.batteryState;
    return state == BatteryState.charging || state == BatteryState.full;
  }
}
