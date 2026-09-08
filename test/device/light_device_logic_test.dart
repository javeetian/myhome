import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/light_device_logic.dart';
import 'package:myhome/device/virtual_hardware.dart';

/// Smart Light 设备逻辑 (WORK_V3 §9/§27) 测试：
/// 纯业务层，不依赖协议 / BLE。
void main() {
  late LightHardware hardware;
  late LightDeviceLogic logic;

  setUp(() {
    hardware = LightHardware();
    logic = LightDeviceLogic(hardware);
  });

  test('状态快照包含硬件读数', () {
    expect(logic.state, <String, dynamic>{
      'power': false,
      'brightness': 80,
      'color_temperature': 4000,
      'temperature': 25.0,
    });
  });

  test('light.set_power 命令', () {
    expect(logic.dispatch('light.set_power', <String, dynamic>{'power': true}),
        isNull);
    expect(hardware.power.on, isTrue);
  });

  test('light.set_brightness 命令 (边界钳位)', () {
    expect(
        logic.dispatch(
            'light.set_brightness', <String, dynamic>{'value': 60}),
        isNull);
    expect(hardware.pwm.value, 60);
  });

  test('参数校验：类型错误 → 3001', () {
    final error = logic.dispatch('light.set_power', <String, dynamic>{'power': 'yes'});
    expect(error?.code, 3001);
    expect(error?.message, contains('invalid power'));
  });

  test('参数校验：越界 → 3001', () {
    final error = logic.dispatch('light.set_brightness', <String, dynamic>{'value': 999});
    expect(error?.code, 3001);
    expect(hardware.pwm.value, 80, reason: '越界参数不得修改硬件');
  });

  test('未知命令 → 3002', () {
    final error = logic.dispatch('light.fly', const <String, dynamic>{});
    expect(error?.code, 3002);
    expect(error?.message, contains('light.fly'));
  });

  test('色温命令 (uint16 边界)', () {
    expect(
        logic.dispatch(
            'light.set_color_temperature', <String, dynamic>{'value': 5000}),
        isNull);
    expect(hardware.colorTemperature.value, 5000);
  });
}
