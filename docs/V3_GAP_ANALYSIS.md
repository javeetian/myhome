# V3 差距分析：现有实现 vs FRAMEWORK_V3 / WORK_V3

**日期：** 2026-09-08
**状态：** 分析文档（未改代码）
**对照基线：** 现有代码 = V2 架构 Phase 0-12 全部完成（193 测试）

---

# 1. V3 的变化范围（先说结论）

V3 不只是"增加 PC 端开发"，而是三件大事：

| 变化 | 说明 |
|---|---|
| ① Device Studio | PC 桌面开发中心（设备列表/UI 预览/Inspector/Protocol Console/故障注入） |
| ② Device Definition + Code Generator | device.yaml 作为唯一数据源 → 生成 Dart/C/Simulator/Manifest |
| ③ C Device SDK | MCU 侧运行时（协议/命令路由/状态管理）+ Hardware Adapter 模式 |

协议栈、UI Runtime、DeviceClient 等 V2 已完成的架构在 V3 中原样保留。

---

# 2. 现有实现 vs WORK_V3 38 个 Phase 对照

| V3 Phase | 内容 | 现状 | 说明 |
|---|---|---|---|
| 0 | 工程初始化 (Windows/macOS 桌面) | ⚠️ 部分 | 缺 windows/ 平台目录；macOS 可加 |
| 1-2 | Device Definition + 校验 | ❌ 全新 | device.yaml 解析/验证/CLI |
| 3 | Protocol Frame | ✅ | ble_frame/crc16/sequencer |
| 4 | Codec | ✅ | JsonCodec + 抽象 |
| 5 | Fragment | ✅ | 分片/重组/全异常矩阵 |
| 6 | SimulatorTransport | ✅ 等价 | 现有 DemoDevice (进程内回环) 即此物，接口名不同 |
| 7 | Virtual Device | 🟡 部分 | DemoDevice 有完整协议行为，但 Device Logic 与 Virtual Hardware 未分离 |
| 8 | Virtual Hardware | ❌ 全新 | VirtualPwm/Gpio/Sensor 抽象 |
| 9 | Device Logic | 🟡 部分 | 命令处理在 DemoDevice 内，未独立成层 |
| 10 | DeviceClient | ✅ | 完整 (hello/resource/state/心跳) |
| 11 | Device API 分层 | ✅ | UI → DeviceClient 边界清晰 |
| 12 | Riverpod | ✅ | 会话/状态/Manager/UI Runtime |
| 13-14 | ui.pkg 构建与校验 | 🟡 部分 | 打包有 (UiPackage)；校验 CLI 无；manifest 字段有差异 (§4.2) |
| 15 | UI Runtime | ✅ | 随机端口 + token + 静态服务 |
| 16 | UI Adapter | 🟡 小差 | V3 增加 GET /api/manifest (§4.4) |
| 17 | WebSocket | ✅ | state/event/patch 推送 |
| 18-20 | Device Studio / Inspector / Protocol Console | ❌ 全新 | 桌面开发中心；现有仅 Developer 面板（移动 App 内） |
| 21 | Fault Injection | 🟡 部分 | 底层能力在测试 Fake 里 (丢 ACK/NACK/延迟)，未产品化为 Studio 功能 |
| 22 | Reconnect | 🟡 小差 | 重连语义有 (§21)，但 ConnectionPhase 无 reconnecting 状态 (§4.5) |
| 23 | State / Patch | ✅ | Gap 检测 + 全量补全 |
| 24 | Command Queue (Replaceable) | 🟡 部分 | 串行 Window=1 有；Replaceable/Cancelable 未实现 (V2 同) |
| 25 | Code Generator | ❌ 全新 | device.yaml → C/Dart/Simulator/Manifest |
| 26 | C Device SDK | ❌ 全新 | sdk/device/ C 库 |
| 27 | Hardware Adapter | ❌ 全新 | C 函数指针结构体 + Dart VirtualHardware |
| 28-29 | 真实设备 + BLE | ✅ 代码侧 | BleTransport 已实现，真机验收待硬件 |
| 30 | Simulator/Real 一致性测试 | ⏸ | 需真机；测试基建已具备 (FakeBleDevice dogfooding) |
| 31 | Package Cache | 🟡 小差 | 缓存 Key 为 deviceId+uiVersion；V3 要求 type+model+version+hash (§4.6) |
| 32 | Logging | ✅ | AppLog 格式与 V3 §36 一致 |
| 33-35 | 测试/压力/崩溃恢复 | 🟡 部分 | 异常矩阵基本覆盖；压力测试与 WebView 崩溃恢复未做 |
| 36 | Security (Session Token) | ✅ | token + Origin 校验 |
| 37 | UI Hot Reload | ❌ 全新 | 文件监听 → 重打包 → WebView 重载 |
| 38 | Studio 完善 | ❌ | 随 18-20 |

**统计：已具备 12 / 部分具备 9 / 全新 13 / 待硬件 2（共 36 有效项）**

---

# 3. 现有资产直接复用的映射

| V3 概念 | 现有代码 | 复用方式 |
|---|---|---|
| Virtual Device | lib/device/demo_device.dart | 协议行为参考实现；待拆 Device Logic / Virtual Hardware |
| SimulatorTransport | DemoDevice implements BleTransport | 接口名不同，语义等价；可加别名抽象 |
| ui.pkg | lib/ui_runtime/ui_package.dart | 打包/解包直接复用 |
| UI Runtime | lib/ui_runtime/ui_server.dart 等 | Device Studio 直接嵌入 |
| Protocol Console 数据源 | ReliableChannel stats + AppLog | TX/RX/SEQ 已在埋点，加帧级日志即可出 Console |
| Fault Injection 内核 | FakeBleDevice 的脚本化能力 | 上移到 lib/ 产品化（丢包/延迟/NACK/断线） |
| 测试黄金标准 | 193 个测试 | 导出向量 → C 固件单测 |
| Code Generator 的协议侧输入 | protocol/*.dart 的字节级规范 | Frame/CRC/JSON 字段即生成模板的规范源 |

---

# 4. 关键差异与冲突（必须决策的清单）

## 4.1 JS API 命名（UI 开发者可见，影响最大）

| | V3 文档 | 现有实现 |
|---|---|---|
| 命令 | `device.command(name, params)` | `deviceApi.command(cmd, params)` |
| 状态 | `device.getState()` | `deviceApi.getState()` |
| 订阅 | `device.on("state", fn)` | `deviceApi.onState(fn)` / `onEvent(name, fn)` |

**建议**：bridge 中同时挂 `window.device`（V3 事件风格 + 命令风格别名），保留 `deviceApi` 兼容。

## 4.2 Manifest 格式

| 字段 | V3 | 现有 DeviceManifest |
|---|---|---|
| 包名 | `package` | 无 |
| 版本 | `version` | `ui_version` |
| 哈希 | `hash{algorithm,value}` | `package{size,sha256}` |
| API 版本 | `api_version` | 无 |

**建议**：解析器同时接受两种字段名（别名映射），打包器输出 V3 格式。

## 4.3 FrameType 注册表

V3 §20 列表**缺少 STATE_REQUEST(0x32)**（Phase 11 已实现），但 V3 §27/§37 语义上要求 REQUEST_FULL_STATE。**建议**：V3 文档补 0x32 条目（文档对齐实现，非代码问题）。

## 4.4 HTTP API

V3 §15 增加 `GET /api/manifest`；现有 `/api/device` 已携带 manifest 信息。**建议**：加 `/api/manifest` 路由作为别名/正式端点。

## 4.5 连接状态机

V3 §36 增加 `error → reconnecting → connecting`；现有 ConnectionPhase 无 reconnecting。**建议**：枚举加 reconnecting + 会话层自动重连策略（V2 未做自动重连）。

## 4.6 缓存 Key

V3：`device_type/model/version/hash`；现有：`deviceId/uiVersion`。**建议**：UiCache 目录升级为 `type/model/version/` 层级，deviceId 作映射索引（小改）。

## 4.7 Windows WebView（V3 文档未解决的问题）

V3 §28/§30 要求 Device Studio 用 Flutter Desktop + WebView，但 **webview_flutter 不支持 Windows**（仅 android/ios/macos）。三选一：
- A. macOS 上开发（WebView 原生支持，零改动）
- B. Windows 集成 `webview_windows`（第三方，WebViewHost 条件适配 ~50 行）
- C. 浏览器渲染（已有分析见 PC_DEV_WORKFLOW.md，零改动）

---

# 5. 建议实施路径（映射到 V3 里程碑）

```text
V3 里程碑 1 (PC 闭环)：
  Phase 0 补 Windows/macOS 平台
  DemoDevice 加载外部 ui.pkg + 拆分 Virtual Hardware (Phase 7/8/9)
  Device Studio 首版：设备选择 + UI 预览(浏览器) + Inspector + Protocol Console
  (Phase 18-20，复用现有 UiServer/Stats/AppLog)

V3 里程碑 2 (协议可视化与故障注入)：
  Protocol Console 帧级展示 + Fault Injection 面板 (Phase 20/21)

V3 里程碑 3 (定义驱动)：
  device.yaml 解析 + 校验 CLI (Phase 1/2)
  Code Generator：yaml → manifest + C 骨架 + Dart 模拟器骨架 (Phase 25)
  UI Hot Reload (Phase 37)

V3 里程碑 4 (真实设备)：
  C Device SDK + Hardware Adapter (Phase 26/27)
  真机验收 + Simulator/Real 一致性测试 (Phase 28-30)
```

**不做的（V3 §48 明确）**：Cloud / OTA / 账号 / 设备商城 / 复杂 UI Editor。

---

# 6. 结论

1. **V2 完成的协议栈/UI Runtime/DeviceClient 是 V3 的地基，全部复用**（12 项直接具备）。
2. V3 真正的增量是 **Device Studio（PC 开发中心）+ Device Definition 驱动 + Code Generator + C SDK** 四件事，其中 Studio 首版大部分可用现有代码组装。
3. 文档层面有 4 处需对齐的差异（JS API 命名、manifest 字段、FrameType 0x32、/api/manifest），其中 0x32 是文档漏写，其余建议兼容别名过渡。
4. Windows WebView 约束 V3 未覆盖，需按 §4.7 三选一决策。
