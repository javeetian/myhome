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
Phase 1  Device Definition                            ⬜
Phase 2  Schema Validation                            ⬜
Phase 3  Protocol Frame                               ✅ 复用 V2 (待回归确认)
Phase 4  Codec                                        ✅ 复用 V2
Phase 5  Fragment                                     ✅ 复用 V2
Phase 6  SimulatorTransport                           🟡 V2 DemoDevice 等价 (待接口对齐)
Phase 7  Virtual Device                               🟡 部分 (待拆分 Logic/Hardware)
Phase 8  Virtual Hardware                             ⬜
Phase 9  Device Logic                                 ⬜
Phase 10 DeviceClient                                 ✅ 复用 V2
Phase 11 Device API                                   ✅ 复用 V2
Phase 12 Riverpod                                     ✅ 复用 V2
Phase 13 UI Package                                   🟡 打包有 (校验 CLI 待 Phase 14)
Phase 14 UI Package Validation                        ⬜
Phase 15 UI Runtime                                   ✅ 复用 V2
Phase 16 UI Adapter                                   🟡 (待加 /api/manifest)
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
