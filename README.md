# myhome — Device UI Platform

设备 UI 开发平台，三部分组成：

- **Device Studio**（PC 开发工具，`lib/studio/`）：用 HTML/CSS/JS 给设备写界面，本地模拟调试、
  打包 `ui.pkg`、生成固件代码；
- **手机 App**（`lib/main.dart`）：通过 BLE 连接设备，把 UI 包下发给设备并加载渲染；
- **设备端 SDK**（`sdk/device/`，C 参考实现）：协议运行时 + 开发者硬件适配层。

## 文档

- **面向使用者**：[docs/使用文档.md](docs/使用文档.md) —— 装 Studio、建工程、写界面、
  打包（`.uipkgignore` / 图片压缩）、生成代码、常见问题。Studio 的「帮助 → 使用说明」
  点开就是这份（同一文件，随应用打包）。
- **开发快速上手**：[docs/QUICKSTART.md](docs/QUICKSTART.md) —— 跑 Studio、设计 UI、
  生成固件代码，含各平台构建与安装包发布。
- **设备端接入**：[sdk/device/README.md](sdk/device/README.md) —— 目录、接入方式、一致性契约、
  编译测试、`ui.pkg` 瘦身。
- **设计/过程文档**（`docs/`）：[FRAMEWORK_V3.md](docs/FRAMEWORK_V3.md)（架构）、
  [WORK_V3.md](docs/WORK_V3.md)（工作计划）、[WORK_EXECUTE_V3.md](docs/WORK_EXECUTE_V3.md)
  （执行记录）、[PC_DEV_WORKFLOW.md](docs/PC_DEV_WORKFLOW.md)（PC 端工作流分析）、
  [BLE_PERFORMANCE.md](docs/BLE_PERFORMANCE.md)（BLE 性能实测）；V2 及更早文档保留作历史。

## 仓库结构

```text
lib/studio/       Device Studio（四栏界面：设备列表 | 文件树 | 预览+Console | Inspector）
lib/ui_runtime/   UI 运行时：ui.pkg 打包/校验、本地服务器、deviceApi 注入、打包期图片压缩
lib/protocol/     协议栈：帧 / CRC16 / 分片 / ACK / 重传
lib/device/       设备定义、模板、模拟设备
sdk/device/       设备端 C 参考实现（协议运行时 + 接入说明）
devices/          示例设备（smart_light / light_bar）
tools/device_cli.dart  命令行：validate / ui build / ui watch / ui validate / generate
tools/pack_samples.dart 打包安装包前，把随附源码摆进 Release/samples/（协议运行时 + 示例工程）
```

## 从源码构建

环境：Flutter SDK 3.x（含 Windows 桌面支持）、Visual Studio 2022+（含 C++ 桌面开发）、
Windows 10/11（完整走查见 [docs/QUICKSTART.md](docs/QUICKSTART.md)）。验证：

```bash
flutter doctor
flutter devices          # 出现 Windows (desktop) 即可

# 跑 Device Studio（PC 开发工具）
flutter run -d windows -t lib/studio/studio_main.dart

# 跑手机 App（连接真机）
flutter run                              # 或 -d windows 用桌面窗口调试
```

## 打包发布

```bash
flutter build apk --release        # Android APK → build/app/outputs/flutter-apk/
flutter build ios --release        # iOS（需 macOS + Xcode）
flutter build windows --release    # Windows App（lib/main.dart）

# Device Studio：绿色版 = 整个 Release 目录拷走即用
#   （--obfuscate / --split-debug-info 与 inno_bundle 自己构建时保持一致）
flutter build windows --release --obfuscate --split-debug-info=build/obfuscate \
  -t lib/studio/studio_main.dart

# Device Studio：把随附源码（sdk/device 协议运行时 + light1 示例）摆进 Release/samples/
dart run tools/pack_samples.dart

# Device Studio：安装包（Inno Setup，配置见 pubspec.yaml 的 inno_bundle 段）
#   --no-app：直接用上面构建好的产物；让 inno_bundle 再跑一次 flutter build
#   会把 Release 目录重写一遍，刚摆好的 samples/ 不保险
dart run inno_bundle --release --no-app
```

随附源码（`dart run tools/pack_samples.dart`，见 [lib/tools/release_samples.dart](lib/tools/release_samples.dart)）：
安装包按 Release 目录内容生成，`samples/` 因而整份装到 `<安装目录>\samples\`——
用户照 [docs/使用文档.md](docs/使用文档.md) §7 移植时，自己把它拷进设备 SDK。

发布要点：

- 产物在 `build/<平台>/x64/runner/Release/`，**整个目录**就是发布包（exe + data/ + DLL），
  拷到目标机器双击运行，不需要任何 Flutter 环境；绿色版也带 `samples/`（协议运行时源码 +
  light1 示例工程），用户可以自己拷进设备 SDK；
- 目标机 Windows 10/11 即可（预览渲染用系统自带 WebView2）；
- 发布包应随附 [docs/使用文档.md](docs/使用文档.md)（使用说明）；
  Inno Setup 编译器装一次：<https://jrsoftware.org/isdl.php>，新克隆的环境先跑一次
  `dart run inno_bundle setup`。

## 测试

```bash
flutter test            # Dart 侧全量测试（协议 / UI 运行时 / Studio / 模拟设备）
flutter analyze         # 静态检查
```

设备端 C 代码的编译与一致性测试（golden 向量）见 [sdk/device/README.md](sdk/device/README.md)。
