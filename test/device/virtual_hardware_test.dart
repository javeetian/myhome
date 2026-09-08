import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/virtual_hardware.dart';

/// 虚拟硬件 (WORK_V3 §8/§26) 测试。
void main() {
  group('VirtualPwm', () {
    test('设置值并自动钳位', () {
      final pwm = VirtualPwm(min: 0, max: 100);
      pwm.set(80);
      expect(pwm.value, 80);
      pwm.set(150);
      expect(pwm.value, 100);
      pwm.set(-5);
      expect(pwm.value, 0);
    });

    test('色温 PWM 边界', () {
      final ct = VirtualPwm(min: 2700, max: 6500, initial: 4000);
      expect(ct.value, 4000);
      ct.set(8000);
      expect(ct.value, 6500);
    });
  });

  group('VirtualGpio', () {
    test('开关量', () {
      final gpio = VirtualGpio();
      expect(gpio.on, isFalse);
      gpio.set(true);
      expect(gpio.on, isTrue);
    });
  });

  group('VirtualSensor', () {
    test('采样在漂移范围内变化', () {
      final sensor = VirtualSensor(initial: 25.0, drift: 0.3);
      for (var i = 0; i < 100; i++) {
        final sample = sensor.sample();
        expect(sample, inInclusiveRange(25.0 - 0.3 * 100, 25.0 + 0.3 * 100));
      }
    });
  });

  group('LightHardware (§2 第一参考设备)', () {
    test('组合硬件初始值', () {
      final hw = LightHardware();
      expect(hw.power.on, isFalse);
      expect(hw.pwm.value, 80);
      expect(hw.colorTemperature.value, 4000);
      expect(hw.temperature.value, 25.0);
    });
  });
}
