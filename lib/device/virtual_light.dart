import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../protocol/protocol_messages.dart';
import '../ui_runtime/ui_package.dart';
import 'device_manifest.dart';
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
  VirtualLight._(this.hardware, this.logic, this.uiPkgBytes);

  /// 创建 Smart Light 虚拟设备；[hardware] 可注入 (测试)；
  /// [uiPkgBytes] 为外部 UI 包 (Device Studio 加载 devices/smart_light/build/ui.pkg)。
  factory VirtualLight({LightHardware? hardware, Uint8List? uiPkgBytes}) {
    final hw = hardware ?? LightHardware();
    return VirtualLight._(hw, LightDeviceLogic(hw), uiPkgBytes);
  }

  final LightHardware hardware;
  final LightDeviceLogic logic;

  /// 外部 UI 包 (null = 无 UI，仅协议调试)。
  final Uint8List? uiPkgBytes;

  Map<String, Uint8List>? _uiFiles;

  static const String _deviceId = 'smart_light';
  static const String _defaultUiVersion = '0.0.0';

  int _stateVersion = 0;
  Timer? _temperatureTimer;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => 'Smart Light';

  @override
  String get uiVersion {
    final manifestBytes = resourceBytes('manifest.json');
    if (manifestBytes != null) {
      try {
        return DeviceManifest.fromJson(
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>,
        ).uiVersion;
      } catch (_) {
        // 坏 manifest：回退默认版本
      }
    }
    return _defaultUiVersion;
  }

  @override
  DeviceHelloAck helloAckFor(DeviceHello hello) => DeviceHelloAck(
        requestId: hello.requestId,
        protocolVersion: 1,
        deviceType: 'light',
        deviceModel: 'L100',
        firmwareVersion: '1.0.0',
        uiVersion: uiVersion,
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
  Uint8List? resourceBytes(String path) {
    if (uiPkgBytes == null) {
      return null;
    }
    if (path == 'ui.pkg') {
      return uiPkgBytes; // 整个包 (与 DemoDevice 语义一致, §27)
    }
    _uiFiles ??= UiPackage.unpack(uiPkgBytes!);
    return _uiFiles![path];
  }

  /// 重置设备状态 (WORK_V3 §7/§29)：硬件回初始值，状态版本归零。
  @override
  Future<void> reset() async {
    hardware.power.set(false);
    hardware.pwm.set(80);
    hardware.colorTemperature.set(4000);
    _stateVersion = 0;
  }
}
