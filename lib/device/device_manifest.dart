/// 设备 UI Manifest (WORK_V2 §15.1 / FRAMEWORK_V3 §9)。
///
/// 双格式兼容 (V3_GAP_ANALYSIS §4.2)：
/// - V3 格式：package / version / device{type,model} / protocol{version} /
///   entry / api_version / hash{algorithm,value}
/// - V2 格式：protocol / ui_version / device{type,model} / entry /
///   capabilities / package{size,sha256}
///
/// toJson 输出 V3 格式 (FRAMEWORK_V3 §9)；fromJson 两种格式均可解析。
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
    this.apiVersion = 1,
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

  /// Device API 版本 (FRAMEWORK_V3 §9)。
  final int apiVersion;

  factory DeviceManifest.fromJson(Map<String, dynamic> json) {
    // protocol：V2 顶层 int；V3 protocol.version
    final protocolValue = json['protocol'];
    final protocol = protocolValue is int
        ? protocolValue
        : (protocolValue is Map && protocolValue['version'] is int
            ? protocolValue['version'] as int
            : null);
    if (protocol == null) {
      throw const FormatException('manifest 缺少 protocol');
    }
    // ui 版本：V2 ui_version；V3 version
    final uiVersion =
        json['ui_version'] is String ? json['ui_version'] as String : json['version'] is String ? json['version'] as String : null;
    if (uiVersion == null || uiVersion.isEmpty) {
      throw const FormatException('manifest 缺少 ui_version/version');
    }
    final device = json['device'];
    // 完整性：V2 package{size,sha256}；V3 hash{value}
    final pkg = json['package'];
    final hash = json['hash'];
    final sha256 = pkg is Map && pkg['sha256'] is String
        ? pkg['sha256'] as String
        : (hash is Map && hash['value'] is String ? hash['value'] as String : null);
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
      packageSha256: sha256,
      apiVersion: json['api_version'] is int ? json['api_version'] as int : 1,
    );
  }

  /// 输出 V3 格式 (FRAMEWORK_V3 §9)。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'package': '${deviceType}_ui',
        'version': uiVersion,
        'device': <String, dynamic>{'type': deviceType, 'model': deviceModel},
        'protocol': <String, dynamic>{'version': protocol},
        'entry': entry,
        'api_version': apiVersion,
        if (capabilities.isNotEmpty) 'capabilities': capabilities,
        if (packageSize != null || packageSha256 != null)
          'hash': <String, dynamic>{
            'algorithm': 'sha256',
            if (packageSha256 != null) 'value': packageSha256,
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
