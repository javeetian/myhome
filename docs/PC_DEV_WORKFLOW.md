# PC 端 UI 开发与设备模拟工作流（分析）

**日期：** 2026-09-08
**状态：** 分析文档（未改任何代码）
**目标：** UI 开发、打包 ui.pkg、模拟 App、模拟设备全部在电脑上完成；验证通过后，设备侧产物直接拷贝到设备 SDK（ESP32 / AC7014）编译。

---

# 1. 目标拆解

```text
┌────────────────────────────────────────────────────────────┐
│  PC 开发闭环                                                │
│                                                            │
│  ① UI 开发   dev_ui/ 目录写 HTML/CSS/JS (deviceApi)        │
│       ↓                                                    │
│  ② 打包      tool/pack_ui.dart → dev_ui/build/ui.pkg       │
│       ↓                                                    │
│  ③ 模拟 App  Flutter 桌面版 (协议栈 + UiServer)            │
│              + 浏览器打开 entryUrl (WebView 替代)           │
│       ↓                                                    │
│  ④ 模拟设备  DemoDevice (协议栈 dogfooding 进程内回环)      │
│       ↓                                                    │
│  ⑤ 设备移植  ui.pkg + manifest 直接拷贝固件 SPIFFS         │
│              协议栈按 Dart 参考实现移植为 C                 │
└────────────────────────────────────────────────────────────┘
```

---

# 2. 现状盘点（已具备 / 缺口）

## 2.1 已具备（零改动可直接用）

| 能力 | 位置 | 说明 |
|---|---|---|
| ui.pkg 打包/解包 | lib/ui_runtime/ui_package.dart | tar.gz，字节确定性（可复现构建） |
| 完整协议栈 | lib/protocol/* | Frame/CRC16/Fragment/ACK/重试/全消息类型，193 个测试覆盖 |
| 模拟设备 | lib/device/demo_device.dart | HELLO/RESOURCE/STATE/PING/命令 全协议行为参考实现 |
| App 侧 UI Runtime | lib/ui_runtime/* | manifest→缓存→ui.pkg→本地服务器→deviceApi 注入 |
| 设备会话+心跳+断线 | lib/providers/* | 连接/握手/同步/失联全流程 |
| 调试面板 | lib/ui/pages/developer_panel.dart | 统计/状态/错误排查 |

## 2.2 关键约束（分析发现）

1. **webview_flutter 不支持 Windows**（仅 android/ios/macos）。
   → 模拟 App 的渲染层改用**系统浏览器**打开 entryUrl，零改动：
     UiServer 绑定 127.0.0.1 随机端口 + token 路径前缀，
     Origin 校验允许本机（Phase 8 已实现），浏览器可直接访问。
2. **项目无 Windows 平台目录**（只有 android/ios/web）。
   → `flutter create --platforms=windows .` 补齐（平台脚手架，非业务代码）。
3. **BLE 扫描在 Windows 不可用** → 不影响：模拟设备走进程内回环，
   不经过 BLE Plugin（分层架构的价值，WORK_V2 §55）。
4. **DemoDevice 的 UI 是内置常量** → 加载外部 ui.pkg 需要最小改动
   （见 §5 清单第 2 项，约 15 行）。

---

# 3. 各环节详解

## 3.1 UI 开发（dev_ui/ 目录）

```text
dev_ui/
├── manifest.json        # protocol=1, ui_version, device, entry, capabilities
├── index.html           # 入口页面
├── style.css
├── app.js
└── assets/...
```

- 页面直接使用 **deviceApi**（Phase 9 注入的官方运行时）：
  `deviceApi.command('led_on')` / `deviceApi.onState(fn)` / `deviceApi.onEvent(...)`
  零样板代码，无需关心 token / WebSocket / fetch 细节。
- 页面全部使用相对路径（`fetch('api/command')`、`assets/icon.png`）。
- **浏览器直接打开 dev_ui/index.html 只能预览静态效果**（deviceApi 不存在），
  交互调试走 §3.3 模拟链路。

## 3.2 打包（tool/pack_ui.dart，新增工具脚本）

```bash
dart run tool/pack_ui.dart dev_ui dev_ui/build/ui.pkg
# 或 watch 模式：文件变化自动重打包
```

内部调用现有 `UiPackage.pack()`（tar.gz + 固定 mtime 可复现构建）。
附带输出 manifest 摘要与 SHA256（可选写入 manifest 的 package 字段）。

## 3.3 模拟 App（Windows 桌面 + 浏览器渲染）

```bash
flutter create --platforms=windows .     # 一次性
flutter run -d windows                   # 或 --dart-define=DEV_UI_PKG=dev_ui/build/ui.pkg
```

1. App 启动 → 扫描页点「Mock 设备演示」
2. 会话流程照常：连接(回环) → HELLO → manifest → ui.pkg → 缓存 → UiServer 启动
3. **浏览器打开 entryUrl**（随机端口 + token 前缀），完整交互：
   点按钮 → fetch → UiServer → DeviceClient → 协议 → DemoDevice → 响应/状态推送 → 浏览器 UI 更新
4. 断线/心跳失联/重连、多设备切换全部可在 PC 上验证

> entryUrl 获取：开发模式下 App 内展示（见 §5 最小改动第 3 项）。
> 在此之前可用日志/调试面板定位（`logRequests` 会打印请求路径）。

## 3.4 模拟设备（DemoDevice）

- 已有完整协议行为：HELLO_ACK（能力/UI 版本）、RESOURCE（manifest/ui.pkg）、
  STATE（连接推初始 + 5s 温度推送）、EVENT、PING/PONG、命令（led/set_brightness/ping）。
- 加载外部 ui.pkg 后（§5 第 2 项），**DevDemo 即"设备固件模拟器"**：
  UI 改完 → 重打包 → 重开演示 → 秒级验证。
- 进阶（可选，非 MVP）：独立进程模拟器 + TCP Transport，模拟真实 BLE 的
  延迟/断连 —— 需要新增 TcpTransport（约 100 行），建议固件联调前再做。

## 3.5 设备移植（Dart → C）

**直接拷贝（零移植成本）：**

| 产物 | 去向 |
|---|---|
| ui.pkg（含 manifest.json） | 固件 SPIFFS 文件系统 |
| GATT UUID（lib/ble/ble_constants.dart） | 固件 GATT 服务定义 |
| 协议字段名/类型/错误码（JsonCodec 逐字规范） | 固件 JSON 处理 |
| 帧布局/字节序/CRC 参数（lib/protocol/ble_frame.dart, crc16.dart） | 固件协议栈 |

**需要移植为 C（Dart 参考实现即行为规范）：**

| Dart 参考实现 | 固件模块 | 关键行为 |
|---|---|---|
| ble_frame.dart | frame.c | 7B 头(大端) + payload + CRC16(0x1021, init 0xFFFF) |
| fragment.dart | fragment.c | 8B Fragment 头(MSG_ID/INDEX/TOTAL/LENGTH)，按 INDEX 重组 |
| reliable_channel.dart（收侧） | transport.c | 入站：ACK/NACK 路由 + 数据帧组装；同 SEQ 去重 |
| demo_device.dart 的协议行为 | device_api.c | HELLO→ACK、RESOURCE→字节、STATE_REQUEST→STATE、PING→PONG、命令处理、连接推初始状态 |
| 状态语义 | state.c | 版本递增、Patch 生成、Gap 时全量兜底 |

**移植质量保障：Dart 测试向量导出**
- 新增 `tool/export_test_vectors.dart`（可选）：把 Dart 测试中的
  帧字节序列 / 消息 JSON 导出为 JSON 文件，作为固件 C 单测的黄金输入输出。

---

# 4. 开发时序（每轮 UI 迭代）

```text
编辑 dev_ui/*  →  (watch 自动打包)  →  App 重开演示 (或热重启)
→  浏览器刷新 entryUrl  →  点按钮验证  →  断线/异常场景脚本验证
→  满意后：ui.pkg 拷入固件 SPIFFS + 固件协议栈 C 移植（一次性完成）
```

---

# 5. 最小改动清单（业务代码）

按依赖排序，均为小改动；不改动则 §3 大部分仍可用（仅 UI 替换与 entryUrl 展示受限）：

| # | 改动 | 位置 | 规模 | 作用 |
|---|---|---|---|---|
| 1 | 补 Windows 平台目录 | `flutter create --platforms=windows .` | 脚手架 | 桌面运行 |
| 2 | DemoDevice 支持外部 ui.pkg | lib/device/demo_device.dart | ~15 行 | 加载 dev_ui/build/ui.pkg（构造参数或 --dart-define 路径） |
| 3 | 开发模式展示 entryUrl | developer_panel.dart 或 scan_page | ~3 行 | 一键复制 URL 到浏览器 |
| 4 | 打包/监视脚本 | tool/pack_ui.dart | ~60 行 | 新工具，不动 lib/ |
| 5 | （可选）测试向量导出 | tool/export_test_vectors.dart | ~80 行 | 固件 C 单测黄金标准 |

生产行为零影响：改动均为可选参数 / 开发工具 / 新增文件。

---

# 6. 结论

- **现有架构已天然支持 PC 闭环**：分层设计（DeviceClient/Protocol/Transport/UI Runtime）
  使模拟设备与模拟 App 与真实 BLE 完全解耦（WORK_V2 §55 的直接红利）。
- **唯一环境缺口**是 Windows WebView → 用浏览器替代，零改动。
- **解锁完整闭环只需 2 个小改动**（DemoDevice 读外部 ui.pkg + entryUrl 展示）。
- 设备侧交付物中 **ui.pkg / UUID / 协议规范可直接拷贝**；
  C 固件只需按 Dart 参考实现移植协议栈（约 5 个模块），
  且可用 Dart 测试向量做黄金对照。
