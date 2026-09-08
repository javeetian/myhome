# WORK_EXECUTE_V3.md

# WORK_V3 执行情况记录

**版本：** V3.0
**文档类型：** EXECUTE / 执行记录
**最后更新：** 2026-09-08
**对应计划：** [WORK_V3.md](WORK_V3.md)（计划文档保持不变，执行状态只记录在本文件）
**架构依据：** [FRAMEWORK_V3.md](FRAMEWORK_V3.md)
**差异分析：** [V3_GAP_ANALYSIS.md](V3_GAP_ANALYSIS.md)

---

# 0. 文档定位

```text
WORK_V3.md        → 计划 ("每个阶段做什么、如何验证")
WORK_EXECUTE_V3.md → 执行 ("实际做了什么、验证结果、遗留问题、决策记录")
```

V2 资产复用说明：WORK_V2 Phase 0-12 已完成（193 测试），
WORK_V3 中与之对应的阶段（Frame/Codec/Fragment/DeviceClient/Riverpod/
UI Runtime/State-Patch/日志/Session Token/缓存）标注 **复用 V2**，
执行记录只写验证结果与差异处理，不重复记录实现细节。

---

# 1. 执行状态总览

```text
Phase 0  工程初始化 (Windows/macOS + webview_windows)  ✅ 完成 (2026-09-08)
Phase 1  Device Definition                            ✅ 完成 (2026-09-08)
Phase 2  Schema Validation                            ✅ 完成 (2026-09-08)
Phase 3  Protocol Frame                               ✅ 复用 V2 (104/104 回归)
Phase 4  Codec                                        ✅ 复用 V2
Phase 5  Fragment                                     ✅ 复用 V2
Phase 6  SimulatorTransport                           ✅ 完成 (接口对齐决策)
Phase 7  Virtual Device                               ✅ 完成 (ProtocolDevice 基类)
Phase 8  Virtual Hardware                             ✅ 完成 (2026-09-08)
Phase 9  Device Logic                                 ✅ 完成 (2026-09-08)
Phase 10 DeviceClient                                 ✅ 复用 V2 (回归通过)
Phase 11 Device API                                   ✅ 复用 V2
Phase 12 Riverpod                                     ✅ 复用 V2
Phase 13 UI Package                                   ✅ 完成 (device ui build)
Phase 14 UI Package Validation                        ✅ 完成 (device ui validate)
Phase 15 UI Runtime                                   ✅ 复用 V2
Phase 16 UI Adapter                                   ✅ 完成 (补齐 /api/manifest)
Phase 17 WebSocket                                    ✅ 复用 V2
Phase 18 Device Studio                                ⬜
Phase 19 Inspector                                    ⬜
Phase 20 Protocol Console                             ⬜
Phase 21 Fault Injection                              🟡 (内核在测试 Fake，待产品化)
Phase 22 Reconnect                                    🟡 (待加 reconnecting 状态)
Phase 23 State / Patch                                ✅ 复用 V2
Phase 24 Command Queue (Replaceable)                  🟡 (待实现)
Phase 25 Code Generator                               ⬜
Phase 26 C Device SDK                                 ⬜
Phase 27 Hardware Adapter                             ⬜
Phase 28 真实设备                                      ⏸ 待硬件
Phase 29 BLE Transport                                ✅ 复用 V2
Phase 30 Simulator/Real 一致性测试                     ⏸ 待硬件
Phase 31 Package Cache                                 ✅ 复用 V2 (Key 升级待定, 见 §4.6 差异分析)
Phase 32 Logging                                      ✅ 复用 V2
Phase 33 Testing                                      🟡 (异常矩阵基本覆盖)
Phase 34 Stress Test                                  ⬜
Phase 35 Crash Recovery                               ⬜
Phase 36 Security (Session Token)                     ✅ 复用 V2
Phase 37 UI Hot Reload                                ⬜
Phase 38 Studio 完善                                   ⬜
```

---

# 2. 关键决策记录（执行前确定）

| 决策 | 结论 | 原因 |
|---|---|---|
| Windows WebView | **webview_windows** 方案（用户拍板） | webview_flutter 不支持 Windows；V3_GAP_ANALYSIS §4.7 |
| 目录结构 | 不搬迁现有工程；项目根即平台仓库，内部建 devices/ tools/ sdk/ | 保持 git 历史连续；WORK_V3 §50 为推荐布局，单仓库变体 |
| JS API | bridge 同时挂 window.device (V3 风格) + 保留 deviceApi | V3_GAP_ANALYSIS §4.1 |
| Manifest | 解析器双字段名兼容；打包器输出 V3 格式 | V3_GAP_ANALYSIS §4.2 |
| FrameType | 0x32 STATE_REQUEST 保留（V3 文档补条目） | V3_GAP_ANALYSIS §4.3 |
| 执行顺序 | 严格按 WORK_V3 Phase 顺序；复用项跑回归验证 | WORK_V3 §47 优先级 |

---

# 3. 执行规则

- 每个 Phase：代码 + 单测 + 文档（本文件）；真机项标注待硬件
- 每个里程碑完成：git 提交（用户确认节奏）
- 本文件是唯一执行状态来源

---

# 4. Phase 执行记录

## Phase 0 — 工程初始化 ✅

**日期：** 2026-09-08
**验收 (WORK_V3 §4)：** Windows 构建通过 (`build/windows/x64/runner/Release/myhome.exe`)

### 交付物

- Windows/macOS 平台脚手架（`flutter create --platforms=windows,macos`）
- webview_windows 0.4.0 + **WebView 平台分派**（条件导入隔离，不影响 Android/iOS/web 编译）：
  - lib/ui_runtime/webview_host.dart（工厂）+ _io（分派）+ _windows（Edge WebView2）+ _mobile（webview_flutter）+ _stub（web）
  - lib/core/webview_env*.dart（WebView2 环境全局初始化，main.dart 接入）
- V3 目录结构（单仓库变体）：`devices/ tools/ sdk/device/ sdk/simulator/`

### 过程中修复的问题

1. **webview_windows 0.4.0 构建失败**：插件使用 `/await`（experimental coroutine），
   MSVC 14.51+（VS2026）将其判为 error（STL1011）。
   修复：windows/CMakeLists.txt 的 APPLY_STANDARD_SETTINGS 加
   `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`（待插件升级后移除）。

### 验证

| 项 | 结果 |
|---|---|
| flutter build windows | ✅ |
| flutter analyze | ✅ |
| 全套 193 测试回归 | ✅ |

### 决策与遗留

- 目录采用单仓库变体（项目根 = 平台仓库），不搬迁现有工程（见 §2 决策）
- macOS 平台目录已生成，Windows 环境无法验证；macOS 验收待 Mac 机器

---

## Phase 1-2 — Device Definition + Schema Validation ✅

**日期：** 2026-09-08
**硬件依赖：** 无（纯 Dart）

### 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/device/device_definition.dart | WORK_V3 §5-§7 | DeviceDefinition / StateDefinition / CommandDefinition / ParamDefinition / EventDefinition + ValueType (bool/uint8/uint16/int32/float/string)；fromYaml 一次性收集全部错误 |
| devices/smart_light/device.yaml | §2/§6 | Smart Light 参考设备：power/brightness/color_temperature + 3 命令 + state_changed 事件 |
| tools/device_cli.dart | §43 | `device validate <device.yaml>`：PASS(exit 0) / ERROR(exit 1) / 用法错误(exit 2) |
| test/device/device_definition_test.dart | §6 | 11 例 |

### 验证

- CLI 实测：`validate devices/smart_light/device.yaml` → PASS (state=3, commands=3, events=1)
- CLI 实测：不存在文件 → ERROR exit 1
- 全套测试 204/204（新增 11 例：解析 2 + 错误矩阵 9）

### 错误矩阵覆盖（WORK_V3 §6 清单）

missing device.id / missing protocol.version / unsupported type / params 非 map /
duplicate command / 参数类型错误 / min>max / YAML 语法错误 / 多错误一次性收集 ✅

### 决策

- 校验策略：一次收集全部错误（而非遇错即停），开发者一次看全问题
- ValueType 白名单（6 类型），未知类型明确报 unsupported type（为 Phase 25 Code Generator 的类型系统打底）

---

## Phase 3-5 — Protocol Frame / Codec / Fragment（复用 V2）✅

**日期：** 2026-09-08
**结论：** V2 实现完整覆盖 WORK_V3 §7-§9 全部验收矩阵，回归 104/104 通过。

- Phase 3 Frame：正常/空/最大 Payload/CRC 错/Length 错/Version 错/非法 Type ✅
- Phase 4 Codec：COMMAND/RESPONSE/EVENT/STATE/PATCH (+HELLO/RESOURCE/STATE_REQUEST/PING/PONG) ✅
- Phase 5 Fragment：乱序/重复/丢失/超时/错误 TOTAL/错误 LENGTH + 大小矩阵 (100B-50KB) ✅

---

## Phase 6 — SimulatorTransport（接口对齐）✅

**决策：** 不另设 DeviceTransport 抽象。现有 **BleTransport 即统一接口**
（WORK_V3 §33 要求 BleTransport 与 SimulatorTransport 接口相同 —— 现状已满足：
DemoDevice/VirtualLight 作为 SimulatorTransport 直接 implements BleTransport，
DeviceClient 零感知切换真实/模拟）。WORK_V3 §18 接口草图与 V2 实现的
字段名差异见 V3_GAP_ANALYSIS.md §4，语义等价。

---

## Phase 7-9 — Virtual Device / Virtual Hardware / Device Logic ✅

**日期：** 2026-09-08
**硬件依赖：** 无（全链路 DeviceClient ↔ VirtualLight 测试）

### 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| lib/device/protocol_device.dart | §4 核心原则 | **ProtocolDevice 基类**：真实/模拟设备共享的协议行为（Frame 解码/分片/ACK/HELLO/RESOURCE/STATE_REQUEST/PING），子类只写设备信息与业务命令 |
| lib/device/virtual_hardware.dart | §8/§26 | VirtualPwm / VirtualGpio / VirtualSensor + LightHardware（对应 C 侧 Hardware Adapter §27/§31） |
| lib/device/light_device_logic.dart | §9/§27 | LightDeviceLogic：三命令分发 + 严格参数校验 + 边界钳位，纯业务层零协议依赖 |
| lib/device/virtual_light.dart | §2/§7 | VirtualLight：smart_light 协议 + 状态版本管理 + 5s 温度采样 + state_changed 事件 |
| lib/device/demo_device.dart | 重构 | 基于 ProtocolDevice 基类重写（协议代码移除，行为不变） |

### 过程中修复的问题

1. **设备初始状态早期丢失**：设备在 transport.connect() 返回前推送初始状态，
   而 DeviceClient 的入站 listen 与 _connected 守卫在 connect 之后才建立。
   修复：listen 与 _connected 先于 transport.connect（§16.6 语义修正）。

### 验证（新增 18 例，全套 222/222）

| 用例 | 结果 |
|---|---|
| VirtualPwm 钳位 / Gpio / Sensor 漂移 / LightHardware 初始值 | ✅ 4 |
| Device Logic：状态快照 / 三命令 / 参数校验 3001 / 未知命令 3002 / 越界不改硬件 | ✅ 7 |
| VirtualLight 全链路：初始状态 / HELLO 能力 / 命令→响应→版本递增→事件 / 业务错误 / 未知命令 / getState | ✅ 6 |
| 协议层回归 (Phase 3-5) | ✅ 104 |

---

## Phase 10-12 — DeviceClient / Device API / Riverpod（复用 V2）✅

**日期：** 2026-09-08
**结论：** V2 实现完整覆盖 WORK_V3 §14-§16，回归通过（device_client_test / session / provider 全链路）。

---

## Phase 13-14 — UI Package Build + Validation ✅

**日期：** 2026-09-08
**硬件依赖：** 无

### 交付物

| 文件 | 对应 § | 内容 |
|---|---|---|
| tools/device_cli.dart | §43 | `device ui build <目录> [输出]`：目录 → ui.pkg（构建前校验 manifest/entry）；`device ui validate <ui.pkg>` |
| lib/ui_runtime/ui_package_validator.dart | §18 | 校验矩阵：corrupted / Missing manifest / entry not found / Protocol version mismatch / Invalid manifest / Hash mismatch / Illegal path，错误一次性收集 |
| lib/device/device_manifest.dart | V3 §9 | **双格式兼容**：fromJson 接受 V2(ui_version+package.sha256) 与 V3(version+protocol{version}+hash{value}+api_version)；toJson 输出 V3 格式 |
| devices/smart_light/ui/ | §2 | Smart Light 第一个 UI：manifest.json(V3) + index.html（电源/亮度/色温/温度，纯 deviceApi 零样板） |

### 验证

- CLI 实测：`ui build devices/smart_light/ui` → 1693 bytes / 2 files / sha256 摘要
- CLI 实测：`ui validate ui.pkg` → PASS (exit 0)
- 全套测试 231/231（新增 9 例：V3 manifest 2 + validator 7）

---

## Phase 15-17 — UI Runtime / Adapter / WebSocket（复用 + 补齐）✅

**日期：** 2026-09-08

- UI Runtime / WebSocket：V2 复用（随机端口 + token + 注入 + 推送，回归通过）
- **补齐 /api/manifest**（FRAMEWORK_V3 §15）：UiAdapter.handleManifest →
  UiServer 路由，manifest 未加载 404；测试覆盖（ui_server_test）

---
