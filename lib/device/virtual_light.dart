import 'dart:async';
import 'dart:typed_data';

import '../protocol/protocol_messages.dart';
import 'light_device_logic.dart';
import 'protocol_device.dart';
import 'virtual_hardware.dart';

/// Smart Light 虚拟设备 (WORK_V3 §2 第一参考设备)。
///
/// 状态：power / brightness / color_temperature + temperature 传感器。
/// 命令：light.set_power / light.set_brightness / light.set_color_temperature。
/// 行为：连接推初始状态；每 5 秒温度采样推送；命令成功后
/// 状态版本递增 + light.state_changed 事件。
///
/// 分层 (WORK_V3 §27)：
/// ```text
/// VirtualLight (协议设备)
///   ├── LightDeviceLogic (业务规则)
///   └── LightHardware (VirtualPwm / Gpio / Sensor)
/// ```
/// 真实设备固件实现相同 Device Logic（操作真实硬件驱动），
/// 模拟与真实共享同一命令语义与状态模型 (§4)。
class VirtualLight extends ProtocolDevice {
  VirtualLight._(this.hardware, this.logic);

  /// 创建 Smart Light 虚拟设备；[hardware] 可注入 (测试)。
  factory VirtualLight({LightHardware? hardware}) {
    final hw = hardware ?? LightHardware();
    return VirtualLight._(hw, LightDeviceLogic(hw));
  }

  final LightHardware hardware;
  final LightDeviceLogic logic;

  static const String _deviceId = 'smart_light';
  static const String _uiVersion = '0.0.0'; // Phase 13 UI 包建立后更新

  int _stateVersion = 0;
  Timer? _temperatureTimer;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => 'Smart Light';

  @override
  String get uiVersion => _uiVersion;

  @override
  DeviceHelloAck helloAckFor(DeviceHello hello) => DeviceHelloAck(
        requestId: hello.requestId,
        protocolVersion: 1,
        deviceType: 'light',
        deviceModel: 'L100',
        firmwareVersion: '1.0.0',
        uiVersion: _uiVersion,
        capabilities: const <String>[
          'power',
          'brightness',
          'color_temperature',
          'temperature',
        ],
      );

  @override
  Future<void> onDeviceConnect() async {
    _stateVersion = 1;
    pushState(currentState);
    // 温度传感器周期采样 (VirtualHardware → State)
    _temperatureTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      hardware.temperature.sample();
      pushState(_nextSnapshot());
    });
  }

  @override
  Future<void> onDeviceDisconnect() async {
    _temperatureTimer?.cancel();
    _temperatureTimer = null;
  }

  @override
  DeviceState get currentState =>
      DeviceState(version: _stateVersion, state: logic.state);

  DeviceState _nextSnapshot() =>
      DeviceState(version: ++_stateVersion, state: logic.state);

  @override
  Future<DeviceResponse?> handleCommand(DeviceCommand command) async {
    final error = logic.dispatch(command.cmd, command.params);
    if (error != null) {
      return DeviceResponse(
        requestId: command.requestId,
        status: 'error',
        error: error,
      );
    }
    final snapshot = _nextSnapshot();
    pushState(snapshot);
    sendEvent('light.state_changed', <String, dynamic>{
      'version': snapshot.version,
      'state': snapshot.state,
    });
    return DeviceResponse(
      requestId: command.requestId,
      data: <String, dynamic>{'version': snapshot.version},
    );
  }

  @override
  Uint8List? resourceBytes(String path) => null; // Phase 13 UI 包接入
}
