/// 全局常量：代理端口与 BLE GATT UUID 定义。
class AppConstants {
  AppConstants._();

  /// App 内置代理服务器监听端口。
  static const int proxyPort = 8080;

  /// WebView 加载 UI 的基地址 (代理即本地服务器)。
  static String get proxyBaseUrl => 'http://localhost:$proxyPort';

  // BLE GATT UUID — TODO: 与设备端协议对齐，当前为占位值。

  /// 设备透传服务 UUID。
  static const String serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';

  /// 指令写入特征 UUID (手机 → 设备)。
  static const String writeCharUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';

  /// 通知特征 UUID (设备 → 手机)。
  static const String notifyCharUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';

  /// UI 包特征 UUID (读取 ui.html.gz)。
  static const String uiBundleCharUuid = '0000ffe2-0000-1000-8000-00805f9b34fb';
}
