import 'dart:typed_data';

/// 与设备交互的抽象通道：上层 (UI Runtime) 只依赖此接口，
/// 不关心底层是 BLE 实现还是 Mock 实现。
///
/// 对应 FRAMEWORK_V2 §9 DeviceClient 的职责。Phase 1 暂由
/// [BleTransport] 直接实现；后续引入 DeviceClient / Protocol 分层。
abstract class DeviceSession {
  /// 建立通道 (BLE: 连接 + 发现服务 + 订阅 Notify)。
  Future<void> init();

  /// 发送一条 JSON 指令。
  /// [sync] 为 true 时等待设备响应 (带超时)；false 时发送后立即返回。
  Future<Map<String, dynamic>> sendCommand(
    Map<String, dynamic> command, {
    bool sync = true,
  });

  /// 设备主动推送 (type: push / event / patch)。
  Stream<Map<String, dynamic>> get pushes;

  /// 读取设备端 UI 压缩包 (ui.html.gz) 的原始字节。
  Future<Uint8List> readUiBundle();

  /// 是否已连接。
  bool get isConnected;

  /// 会话展示名称 (设备名)。
  String get name;

  /// 释放底层资源。
  Future<void> dispose();
}
