import 'dart:convert';
import 'dart:typed_data';

import '../device/device_client.dart';
import '../device/device_manifest.dart';
import 'ui_cache.dart';

/// UI 加载结果。
class UiLoadResult {
  const UiLoadResult({required this.rootDir, required this.manifest});

  /// UI 静态文件根目录 (缓存命中或解包后的版本目录)。
  final String rootDir;

  final DeviceManifest manifest;
}

/// UI Runtime (WORK_V2 §15.3)：设备 UI 加载编排。
///
/// ```text
/// 读取 manifest.json → 协议版本检查 → 缓存命中检查
///   ├── 命中 → 直接加载
///   └── 未命中 → 下载 ui.pkg → SHA256 校验 → 解包缓存 → 加载
/// ```
class UiRuntime {
  UiRuntime({required DeviceClient client, required UiCache cache})
      : _client = client,
        _cache = cache;

  final DeviceClient _client;
  final UiCache _cache;

  /// 加载设备 UI，返回静态根目录与 manifest。
  Future<UiLoadResult> loadUi() async {
    // 1. 读取 manifest (§15.1/§26)
    final manifest = await _readManifest();
    manifest.checkProtocolSupported(); // §24
    // 2. 缓存命中 (§15.3/§35：Key = type + model + version)
    final cached = _cache.lookup(
      manifest.deviceType,
      manifest.deviceModel,
      manifest.uiVersion,
    );
    if (cached != null) {
      return UiLoadResult(rootDir: cached, manifest: manifest);
    }
    // 3. 下载 ui.pkg
    final pkg = await _download('ui.pkg');
    // 4. 完整性校验 + 解包 + 缓存 (§15.5)
    final root = await _cache.store(
      manifest.deviceType,
      manifest.deviceModel,
      manifest.uiVersion,
      pkg,
      expectedSize: manifest.packageSize,
      expectedSha256: manifest.packageSha256,
    );
    return UiLoadResult(rootDir: root, manifest: manifest);
  }

  Future<DeviceManifest> _readManifest() async {
    final bytes = await _download('manifest.json');
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw StateError('manifest.json 非法: ${e.message}');
    }
    if (json is! Map<String, dynamic>) {
      throw StateError('manifest.json 顶层必须是对象');
    }
    return DeviceManifest.fromJson(json);
  }

  /// 经 RESOURCE_REQUEST/RESPONSE 下载资源 (§27)。
  Future<Uint8List> _download(String path) async {
    final response = await _client.requestResource(path);
    if (!response.isOk) {
      throw StateError(
        '资源下载失败 ($path): ${response.error?.message ?? response.status}',
      );
    }
    return response.data ?? Uint8List(0);
  }
}
