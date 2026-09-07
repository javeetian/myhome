/// 全局常量：代理端口。
/// BLE GATT UUID 统一由 [BleConstants] 管理 (WORK_V2 §6.3)。
class AppConstants {
  AppConstants._();

  /// App 内置代理服务器监听端口。
  static const int proxyPort = 8080;

  /// WebView 加载 UI 的基地址 (代理即本地服务器)。
  static String get proxyBaseUrl => 'http://localhost:$proxyPort';
}
