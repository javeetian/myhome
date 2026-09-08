import '../protocol/protocol_messages.dart';
import 'virtual_hardware.dart';

/// Smart Light 设备逻辑 (WORK_V3 §9/§27)：业务规则层。
///
/// 只操作 [LightHardware] 抽象，不接触协议 / BLE / UI。
/// 真实设备固件中由开发者实现相同逻辑 (操作真实硬件驱动, §45)，
/// 模拟与真实共享同一套命令语义与状态模型 (§4)。
class LightDeviceLogic {
  LightDeviceLogic(this.hardware);

  final LightHardware hardware;

  /// 当前状态快照 (含传感器读数)。
  Map<String, dynamic> get state => <String, dynamic>{
        'power': hardware.power.on,
        'brightness': hardware.pwm.value,
        'color_temperature': hardware.colorTemperature.value,
        'temperature': double.parse(hardware.temperature.value.toStringAsFixed(1)),
      };

  void setPower(bool value) => hardware.power.set(value);

  void setBrightness(int value) => hardware.pwm.set(value);

  void setColorTemperature(int value) => hardware.colorTemperature.set(value);

  /// 命令分发 (§39 命令模型)：返回业务错误 (null = 成功)。
  /// 参数校验严格：类型不符 / 越界均报错 (错误码 §10.5)。
  DeviceError? dispatch(String cmd, Map<String, dynamic> params) {
    switch (cmd) {
      case 'light.set_power':
        final power = params['power'];
        if (power is! bool) {
          return const DeviceError(code: 3001, message: 'invalid power');
        }
        setPower(power);
        return null;
      case 'light.set_brightness':
        final value = params['value'];
        if (value is! num || value.toInt() < hardware.pwm.min || value.toInt() > hardware.pwm.max) {
          return const DeviceError(code: 3001, message: 'invalid brightness');
        }
        setBrightness(value.toInt());
        return null;
      case 'light.set_color_temperature':
        final value = params['value'];
        if (value is! num ||
            value.toInt() < hardware.colorTemperature.min ||
            value.toInt() > hardware.colorTemperature.max) {
          return const DeviceError(
              code: 3001, message: 'invalid color_temperature');
        }
        setColorTemperature(value.toInt());
        return null;
      default:
        return DeviceError(code: 3002, message: 'unknown command "$cmd"');
    }
  }
}
