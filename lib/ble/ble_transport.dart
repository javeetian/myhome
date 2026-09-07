import 'dart:async';

/// 字节级 BLE 传输抽象 (WORK_V2 §6.1)。
///
/// 上层 (Protocol / DeviceClient) 只依赖此接口，不关心底层是
/// flutter_reactive_ble 还是 universal_ble —— 具体 Plugin 由实现层屏蔽。
/// 任何上层代码都不得越过此接口直接调用 BLE Plugin (WORK_V2 §55)。
abstract class BleTransport {
  /// 连接设备并完成 GATT 准备：
  /// 连接 → MTU 协商 → 发现服务 → 校验 TX/RX 特征 → 订阅 Notify。
  Future<void> connect(String deviceId);

  /// 断开连接并取消订阅。
  Future<void> disconnect();

  /// 向设备写入原始字节 (写入 TX Characteristic)。
  Future<void> write(List<int> data);

  /// 设备发来的原始字节流 (来自 RX Characteristic 的 Notify)。
  Stream<List<int>> get notifications;

  /// 请求协商 MTU，返回实际协商结果。
  ///
  /// 不要假设 MTU = 247，必须以返回值 (实际协商结果) 为准。
  Future<int> requestMtu(int mtu);
}
