import 'dart:math';

/// 虚拟硬件 (WORK_V3 §8/§26)：真实硬件的 PC 替身。
///
/// 业务逻辑 (Device Logic) 只操作这些抽象 —— 与真实设备 SDK 的
/// Hardware Adapter (C 函数指针结构体, WORK_V3 §27/§31) 一一对应。

/// 虚拟 PWM（亮度 / 色温等模拟量输出）。
class VirtualPwm {
  VirtualPwm({this.min = 0, this.max = 100, int initial = 0})
      : value = initial;

  final int min;
  final int max;
  int value;

  /// 设置输出值 (自动钳位到 [min, max])。
  void set(int v) => value = v.clamp(min, max);
}

/// 虚拟 GPIO（开关量输出）。
class VirtualGpio {
  VirtualGpio({bool initial = false}) : on = initial;

  bool on;

  void set(bool v) => on = v;
}

/// 虚拟传感器（温度等模拟量输入，带随机漂移）。
class VirtualSensor {
  VirtualSensor({required this.initial, this.drift = 0.3})
      : value = initial;

  final double initial;

  /// 每次采样随机漂移幅度 (±)。
  final double drift;

  double value;

  final Random _random = Random();

  /// 采样一次：值按漂移幅度随机变化。
  double sample() {
    value += _random.nextDouble() * 2 * drift - drift;
    return value;
  }
}

/// Smart Light 硬件组合 (WORK_V3 §2 第一参考设备)。
/// 对应真实设备的：电源 GPIO + 亮度 PWM + 色温 PWM + 温度传感器。
class LightHardware {
  final VirtualGpio power = VirtualGpio();
  final VirtualPwm pwm = VirtualPwm(min: 0, max: 100, initial: 80);
  final VirtualPwm colorTemperature =
      VirtualPwm(min: 2700, max: 6500, initial: 4000);
  final VirtualSensor temperature =
      VirtualSensor(initial: 25.0, drift: 0.3);
}
