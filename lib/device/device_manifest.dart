/// 设备 UI Manifest (WORK_V2 §15.1/§26)。
///
/// JSON 结构：
/// ```json
/// {
///   "protocol": 1,
///   "ui_version": "1.2.3",
///   "device": {"type": "light", "model": "AC7014"},
///   "entry": "index.html",
///   "capabilities": ["power", "brightness"],
///   "package": {"size": 183421, "sha256": "..."}   // 可选 (§15.5)
/// }
/// ```
class DeviceManifest {
  const DeviceManifest({
    required this.protocol,
    required this.uiVersion,
    this.deviceType = '',
    this.deviceModel = '',
    this.entry = 'index.html',
    this.capabilities = const <String>[],
    this.packageSize,
    this.packageSha256,
  });

  /// App 支持的协议版本 (§24)。
  static const int supportedProtocol = 1;

  /// 设备协议版本 (§24 版本控制)。
  final int protocol;

  /// UI 版本 (缓存键, §15.4)。
  final String uiVersion;

  final String deviceType;
  final String deviceModel;

  /// 入口页面 (默认 index.html)。
  final String entry;

  /// 设备能力 (§25/§26)：UI 据此决定展示哪些功能。
  final List<String> capabilities;

  /// ui.pkg 大小 (字节, §15.5 完整性)。
  final int? packageSize;

  /// ui.pkg SHA256 (hex, §15.5 完整性)。
  final String? packageSha256;

  factory DeviceManifest.fromJson(Map<String, dynamic> json) {
    final protocol = json['protocol'];
    final uiVersion = json['ui_version'];
    if (protocol is! int) {
      throw const FormatException('manifest 缺少 protocol');
    }
    if (uiVersion is! String || uiVersion.isEmpty) {
      throw const FormatException('manifest 缺少 ui_version');
    }
    final device = json['device'];
    final pkg = json['package'];
    return DeviceManifest(
      protocol: protocol,
      uiVersion: uiVersion,
      deviceType: device is Map<String, dynamic> ? '${device['type'] ?? ''}' : '',
      deviceModel: device is Map<String, dynamic> ? '${device['model'] ?? ''}' : '',
      entry: json['entry'] is String ? json['entry'] as String : 'index.html',
      capabilities: json['capabilities'] is List
          ? (json['capabilities'] as List).whereType<String>().toList()
          : const <String>[],
      packageSize: pkg is Map<String, dynamic> && pkg['size'] is int
          ? pkg['size'] as int
          : null,
      packageSha256: pkg is Map<String, dynamic> && pkg['sha256'] is String
          ? pkg['sha256'] as String
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'protocol': protocol,
        'ui_version': uiVersion,
        'device': <String, dynamic>{'type': deviceType, 'model': deviceModel},
        'entry': entry,
        'capabilities': capabilities,
        if (packageSize != null || packageSha256 != null)
          'package': <String, dynamic>{
            if (packageSize != null) 'size': packageSize,
            if (packageSha256 != null) 'sha256': packageSha256,
          },
      };

  /// 协议版本检查 (§24)：不兼容抛 [UnsupportedProtocolError]。
  void checkProtocolSupported() {
    if (protocol != supportedProtocol) {
      throw UnsupportedProtocolError(protocol, supportedProtocol);
    }
  }
}

/// 设备协议版本不兼容 (§24)。
class UnsupportedProtocolError implements Exception {
  const UnsupportedProtocolError(this.deviceProtocol, this.supportedProtocol);

  final int deviceProtocol;
  final int supportedProtocol;

  @override
  String toString() =>
      '设备协议版本 $deviceProtocol 不受支持 (App 支持 $supportedProtocol)';
}
