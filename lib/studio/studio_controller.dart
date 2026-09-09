import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/app_log.dart';
import '../device/device_client.dart';
import '../device/device_definition.dart';
import '../device/device_manifest.dart';
import '../device/protocol_device.dart';
import '../protocol/protocol_messages.dart';
import '../simulator/fault_injector.dart';
import '../tools/code_generator.dart';
import 'opened_files_controller.dart';
import '../ui_runtime/ui_cache.dart';
import '../ui_runtime/ui_package.dart';
import '../ui_runtime/ui_server.dart';

/// Device Studio 会话状态 (WORK_V3 §22/§28)。
class StudioState {
  const StudioState({
    this.device,
    this.client,
    this.uiServer,
    this.entryUrl,
    this.currentState,
    this.helloAck,
    this.error,
    this.faultInjector,
    this.deviceDir,
    this.reloadCount = 0,
    this.protocolLog = const <String>[],
  });

  final ProtocolDevice? device;
  final DeviceClient? client;
  final UiServer? uiServer;

  /// 故障注入器 (Phase 21 面板操控)。
  final FaultInjector? faultInjector;

  /// 当前设备目录 (devices/ 或外部导入目录)，左栏文件树根。
  /// null = 设备无目录 (内置 Demo 等)。
  final String? deviceDir;

  /// UI Hot Reload 计数 (Phase 37)：变化时 WebView 重载。
  final int reloadCount;

  /// UI 预览入口 (随机端口 + token)。
  final String? entryUrl;

  /// 设备当前状态。
  final DeviceState? currentState;

  /// 握手结果 (设备信息)。
  final DeviceHelloAck? helloAck;

  final String? error;

  /// Protocol Console 日志 (§24)。
  final List<String> protocolLog;

  bool get isRunning => client != null;

  StudioState copyWith({
    DeviceState? currentState,
    List<String>? protocolLog,
    int? reloadCount,
  }) =>
      StudioState(
        device: device,
        client: client,
        uiServer: uiServer,
        entryUrl: entryUrl,
        currentState: currentState ?? this.currentState,
        helloAck: helloAck,
        error: error,
        faultInjector: faultInjector,
        deviceDir: deviceDir,
        reloadCount: reloadCount ?? this.reloadCount,
        protocolLog: protocolLog ?? this.protocolLog,
      );
}

/// Device Studio 控制器 (WORK_V3 §28/§29)：
/// 选择模拟设备 → 会话(连接/握手/同步) → UI 包解压 → UI Runtime → 日志收集。
class StudioController extends Notifier<StudioState> {
  StudioController({UiCache? cache}) : _cache = cache;

  /// 测试注入缓存目录 (生产用应用私有目录)。
  final UiCache? _cache;

  static const int _maxLogLines = 200;

  final List<String> _logLines = <String>[];

  StreamSubscription<DeviceState>? _stateSub;
  StreamSubscription<DeviceEvent>? _eventSub;

  // 资源引用私有缓存：onDispose 期间不能访问 state/ref
  DeviceClient? _client;
  UiServer? _uiServer;

  // UI Hot Reload (Phase 37)
  StreamSubscription<FileSystemEvent>? _uiWatchSub;
  Timer? _uiDebounce;
  String? _uiWatchDir;
  String? _uiWatchOut;

  /// 当前会话日志实例 (菜单栏日志等级设置即时生效)。
  AppLog? _log;

  @override
  StudioState build() {
    ref.onDispose(_disposeResources);
    return const StudioState();
  }

  /// 启动模拟设备会话。[deviceDir] 为设备源目录 (左栏文件树根)。
  Future<bool> start(ProtocolDevice device, {String? deviceDir}) async {
    await stop();
    final log = AppLog(level: LogLevel.trace, output: _appendLog);
    _log = log;
    // 故障注入包装 (Phase 21)：Studio 面板操控
    final injector = FaultInjector(device);
    injector.onDisconnectRequested = () {
      _appendLog('WARN 故障注入：写入时断开');
    };
    try {
      final client = DeviceClient(
        transport: injector,
        deviceId: device.deviceId,
        log: log,
      );
      await client.connect();
      final ack = await client.hello();
      await client.syncState();
      client.startHeartbeat();

      // UI 包 (设备提供) → 解压缓存 → 静态根 (§15.3/§35)
      String? staticRoot;
      final pkgBytes = device.resourceBytes('ui.pkg');
      if (pkgBytes != null) {
        final cache = _cache ?? await UiCache.open();
        staticRoot = await _storeUiPackage(cache, device, pkgBytes);
      }
      final uiServer = UiServer(client: client, staticRoot: staticRoot);
      await uiServer.start();

      _stateSub = client.states.listen((s) {
        state = state.copyWith(currentState: s);
      });
      _eventSub = client.events.listen((e) {
        _appendLog('EVENT ${e.event} ${e.data}');
      });

      _client = client;
      _uiServer = uiServer;
      state = StudioState(
        device: device,
        client: client,
        uiServer: uiServer,
        entryUrl: uiServer.entryUrl,
        currentState: client.currentState,
        helloAck: ack,
        faultInjector: injector,
        deviceDir: deviceDir,
        protocolLog: List<String>.unmodifiable(_logLines),
      );
      // 编辑器标签：设备有目录 → 自动打开 UI 入口；无目录 (内置 Demo) → 清空
      final dir = deviceDir;
      if (dir != null) {
        ref.read(openedFilesProvider.notifier).resetAndOpen(root: dir);
      } else {
        ref.read(openedFilesProvider.notifier).reset();
      }
      return true;
    } catch (e) {
      _logLines.add('ERROR $e');
      state = StudioState(
        error: '$e',
        protocolLog: List<String>.unmodifiable(_logLines),
      );
      return false;
    }
  }

  /// UI 包 → 缓存 (V3 §35 缓存 Key = type + model + version)。
  Future<String> _storeUiPackage(
    UiCache cache,
    ProtocolDevice device,
    Uint8List pkgBytes,
  ) async {
    var deviceType = device.deviceId;
    var deviceModel = 'default';
    final manifestBytes = device.resourceBytes('manifest.json');
    if (manifestBytes != null) {
      try {
        final manifest = DeviceManifest.fromJson(
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>,
        );
        deviceType = manifest.deviceType;
        deviceModel = manifest.deviceModel;
      } catch (_) {
        // 坏 manifest：回退 deviceId
      }
    }
    return cache.store(deviceType, deviceModel, device.uiVersion, pkgBytes);
  }

  /// Smart Light UI 源目录 (Phase 13/37；相对项目根，测试可注入)。
  static String smartLightUiDir = 'devices/smart_light/ui';

  /// Smart Light ui.pkg 构建产物路径。
  static String smartLightPkgPath = 'devices/smart_light/build/ui.pkg';

/// 项目根目录缓存 (解析结果不变)。
  static Directory? _projectRoot;

  /// 解析项目内路径，不依赖进程 CWD。
  ///
  /// macOS 沙箱应用的 CWD 是容器目录 (非项目根)，Windows 的 CWD 是项目根；
  /// 统一策略：绝对路径直接返回；相对路径先在 CWD 下找，找不到则从
  /// 可执行文件位置向上找项目根 (pubspec.yaml + devices/ 标记)。
  /// [exeDir]/[cwd] 仅测试注入。
  static String resolvePath(
    String path, {
    Directory? exeDir,
    Directory? cwd,
  }) {
    if (p.isAbsolute(path)) {
      return path;
    }
    final directBase = (cwd ?? Directory.current).path;
    final direct = p.join(directBase, path);
    if (File(direct).existsSync() || Directory(direct).existsSync()) {
      return direct; // CWD 即项目根 (Windows 场景)
    }
    final root = (exeDir != null || cwd != null)
        ? _findProjectRoot(exeDir: exeDir, cwd: cwd) // 测试注入：不用缓存
        : _projectRoot ??= _findProjectRoot(exeDir: exeDir, cwd: cwd);
    if (root != null) {
      return p.join(root.path, path);
    }
    return direct; // 兜底：保持原行为
  }

  static Directory? _findProjectRoot({Directory? exeDir, Directory? cwd}) {
    final starts = <Directory>[
      ?exeDir,
      File(Platform.resolvedExecutable).parent,
      ?cwd,
      Directory.current,
    ];
    for (final start in starts) {
      var dir = start;
      while (true) {
        if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
            Directory(p.join(dir.path, 'devices')).existsSync()) {
          return dir;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) {
          break; // 到达文件系统根
        }
        dir = parent;
      }
    }
    return null;
  }

  /// 加载 Smart Light UI 包：优先构建产物；不存在则从源目录现场打包。
  /// 返回 null = 无 UI (纯协议调试模式)。文件访问失败同样返回 null，
  /// 由无 UI 提示页兜底，不让异常打穿启动流程。
  Future<Uint8List?> loadSmartLightPkg() =>
      packUiDir(smartLightUiDir, smartLightPkgPath);

  /// 通用：UI 源目录 → ui.pkg (产物存在则直接读，否则现场打包落盘)。
  /// 返回 null = 目录/源不存在。
  Future<Uint8List?> packUiDir(String uiDir, String outPkg) async {
    try {
      final pkgPath = resolvePath(outPkg);
      final uiDirPath = resolvePath(uiDir);
      final pkgFile = File(pkgPath);
      if (pkgFile.existsSync()) {
        return Uint8List.fromList(pkgFile.readAsBytesSync());
      }
      final dir = Directory(uiDirPath);
      if (!dir.existsSync()) {
        return null;
      }
      final files = <String, Uint8List>{};
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        final rel =
            p.relative(entity.path, from: dir.path).replaceAll('\\', '/');
        files[rel] = Uint8List.fromList(entity.readAsBytesSync());
      }
      if (!files.containsKey('manifest.json')) {
        return null;
      }
      final pkg = UiPackage.pack(files);
      pkgFile.parent.createSync(recursive: true);
      pkgFile.writeAsBytesSync(pkg);
      _appendLog('INFO UI 从源目录现场打包 (${files.length} 文件)');
      return pkg;
    } catch (e) {
      _appendLog('WARN UI 包加载失败: $e');
      return null;
    }
  }

  /// UI Hot Reload (Phase 37)：监听 UI 源目录 → 自动重打包 → 重载 WebView。
  void startUiWatch(String sourceDir, String outPkg) {
    stopUiWatch();
    // 路径解析：macOS 沙箱 CWD 非项目根 (与 loadSmartLightPkg 一致)
    _uiWatchDir = resolvePath(sourceDir);
    _uiWatchOut = resolvePath(outPkg);
    try {
      _uiWatchSub = Directory(sourceDir).watch(recursive: true).listen((_) {
        _uiDebounce?.cancel();
        _uiDebounce = Timer(const Duration(milliseconds: 300), () {
          unawaited(rebuildUi());
        });
      });
      _appendLog('INFO UI watch: $sourceDir');
    } catch (e) {
      _appendLog('ERROR UI watch 失败: $e');
    }
  }

  void stopUiWatch() {
    _uiDebounce?.cancel();
    _uiDebounce = null;
    _uiWatchSub?.cancel();
    _uiWatchSub = null;
    // 路径保留：菜单栏可随时重新开启
  }

  /// 菜单栏：日志等级即时切换 (§32 运行时调整)。
  LogLevel get logLevel => _log?.level ?? LogLevel.trace;

  void setLogLevel(LogLevel level) {
    _log?.level = level;
    _appendLog('INFO 日志等级 → ${level.name.toUpperCase()}');
  }

  /// 运行菜单：为当前设备生成代码 (六件套 + ui.pkg)。
  /// 返回 null = 成功；非 null = 错误消息。
  Future<String?> generateCode() async {
    final dir = state.deviceDir;
    if (dir == null) {
      return '当前无设备目录 (请先启动一个设备)';
    }
    try {
      final yamlFile = File(p.join(dir, 'device.yaml'));
      if (!yamlFile.existsSync()) {
        return '缺少 device.yaml';
      }
      final definition =
          DeviceDefinition.fromYaml(yamlFile.readAsStringSync());
      final files = CodeGenerator.generate(definition);
      final outDir = Directory(p.join(dir, 'generated'));
      for (final entry in files.entries) {
        final target = File(p.join(outDir.path, entry.key));
        target.parent.createSync(recursive: true);
        target.writeAsStringSync(entry.value);
      }
      // ui.pkg
      await packUiDir(p.join(dir, 'ui'), p.join(dir, 'build', 'ui.pkg'));
      _appendLog(
        'INFO 代码生成完成: ${files.length} 文件 → ${outDir.path}',
      );
      return null;
    } on DeviceDefinitionException catch (e) {
      return 'device.yaml 无效: ${e.errors.join('; ')}';
    } catch (e) {
      return '生成失败: $e';
    }
  }

  /// 菜单栏：重载 UI 预览 (reloadCount++ → WebView 重载)。
  void reloadUi() {
    if (state.client == null) {
      return;
    }
    _appendLog('INFO UI 预览手动重载');
    state = state.copyWith(reloadCount: state.reloadCount + 1);
  }

  /// 菜单栏：UI Hot Reload 开关。
  bool get isUiWatchRunning => _uiWatchSub != null;

  void toggleUiWatch() {
    if (isUiWatchRunning) {
      stopUiWatch();
      _appendLog('INFO UI Hot Reload 已关闭');
      return;
    }
    final dir = _uiWatchDir;
    final out = _uiWatchOut;
    if (dir != null && out != null) {
      startUiWatch(dir, out);
      _appendLog('INFO UI Hot Reload 已开启');
    } else {
      _appendLog('WARN 无 UI 源目录 (设备未提供 UI)');
    }
  }

  /// 重新打包 UI → 覆盖缓存 → 通知 WebView 重载 (reloadCount++)。
  Future<void> rebuildUi() async {
    final dir = _uiWatchDir;
    final out = _uiWatchOut;
    final device = state.device;
    final client = state.client;
    if (dir == null || out == null || device == null || client == null) {
      return;
    }
    try {
      final files = <String, Uint8List>{};
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        final rel =
            p.relative(entity.path, from: dir).replaceAll('\\', '/');
        files[rel] = Uint8List.fromList(entity.readAsBytesSync());
      }
      if (!files.containsKey('manifest.json')) {
        _appendLog('ERROR UI 目录缺少 manifest.json');
        return;
      }
      final pkg = UiPackage.pack(files);
      File(out)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(pkg);
      // 覆盖缓存 (同版本目录, Corrupted → Reinstall 语义)
      final cache = _cache ?? await UiCache.open();
      await _storeUiPackage(cache, device, pkg);
      _appendLog('INFO UI 已重打包 (${files.length} 文件) → 重载 WebView');
      if (ref.mounted) {
        state = state.copyWith(reloadCount: state.reloadCount + 1);
      }
    } catch (e) {
      _appendLog('ERROR UI 重打包失败: $e');
    }
  }

  /// 断开并释放会话。
  Future<void> stop() async {
    stopUiWatch();
    await _disposeResources();
    if (ref.mounted) {
      state = const StudioState(protocolLog: <String>[]);
    }
  }

  /// 资源释放 (provider dispose 与主动断开共用；不触碰 state/ref)。
  Future<void> _disposeResources() async {
    await _stateSub?.cancel();
    _stateSub = null;
    await _eventSub?.cancel();
    _eventSub = null;
    final client = _client;
    final uiServer = _uiServer;
    _client = null;
    _uiServer = null;
    if (client != null) {
      await uiServer?.stop();
      await client.dispose();
    }
  }

  /// 重置设备 (WORK_V3 §29)：断开 → 硬件/状态复位 → 重连 → 重新同步。
  Future<bool> reset() async {
    final client = state.client;
    final device = state.device;
    if (client == null || device == null) {
      return false;
    }
    try {
      client.stopHeartbeat();
      await device.disconnect();
      await device.reset();
      await device.connect(device.deviceId);
      await client.requestState();
      client.startHeartbeat();
      _appendLog('INFO 设备已重置');
      return true;
    } catch (e) {
      _appendLog('ERROR 重置失败: $e');
      return false;
    }
  }

  /// 发送命令 (Inspector 使用)。
  Future<DeviceResponse?> sendCommand(String cmd, Map<String, dynamic> params) async {
    final client = state.client;
    if (client == null) {
      return null;
    }
    try {
      return await client.command(cmd, params);
    } catch (e) {
      _appendLog('ERROR 命令失败: $e');
      return null;
    }
  }

  void _appendLog(String line) {
    _logLines.add(line);
    if (_logLines.length > _maxLogLines) {
      _logLines.removeRange(0, _logLines.length - _maxLogLines);
    }
    final current = state;
    if (current.isRunning) {
      state = current.copyWith(protocolLog: List<String>.unmodifiable(_logLines));
    }
  }
}

final studioControllerProvider =
    NotifierProvider<StudioController, StudioState>(StudioController.new);
