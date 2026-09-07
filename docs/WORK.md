# WORK.md — 开发工作流程

> 本文档是 [FRAMEWORK_V2.md](./FRAMEWORK_V2.md) 的可执行落地版本：把架构设计拆解为按顺序执行的开发阶段、任务清单与验收标准。
> 架构原则以 FRAMEWORK_V2.md 为准，本文档只回答「现在做什么、怎么算做完」。

**更新日期**：2026-09-07
**当前阶段**：Phase 1（闭环链路 MVP）

---

## 1. 总体原则

1. 先跑通一条链路，再扩展功能（FRAMEWORK_V2 §66）。
2. 底层代码（DeviceClient / Protocol / BLE Transport）是纯 Dart，不依赖 Riverpod，可独立测试（§5）。
3. 上层只依赖 `DeviceSession` 抽象，不直接调用 BLE 插件，换 BLE 库不影响上层（§9、§10）。
4. Phase 1 允许 BLE 直接传 JSON 快速验证；正式版再换 CBOR / 自定义二进制（§44）。

---

## 2. 阶段总览

| 阶段 | 目标 | 状态 |
|------|------|------|
| Phase 0 | 项目初始化 + 依赖 + 骨架 | ✅ 完成 |
| Phase 1 | 闭环链路：Scan → Connect → WebView → Command → Response | 🔄 进行中 |
| Phase 2 | Frame / 分片 / 大数据传输 | ⬜ 未开始 |
| Phase 3 | ACK / NACK / 重试 / 命令队列 | ⬜ 未开始 |
| Phase 4 | State / Patch / Event | ⬜ 未开始 |
| Phase 5 | Manifest / UI Package / UI Cache | ⬜ 未开始 |
| Phase 6 | 优化：Binary Codec / 多设备 / 安全 | ⬜ 未开始 |

---

## 3. Phase 0：项目初始化 ✅

- [x] Flutter 项目 + Riverpod 3
- [x] 依赖：webview_flutter / flutter_reactive_ble / shelf / shelf_web_socket / web_socket_channel / archive / path_provider / permission_handler / path
- [x] 目录结构对齐 FRAMEWORK_V2 §6（`ble/` `device/` `ui_runtime/` `providers/` `app/`）
- [x] Android BLE 权限 + 明文流量、iOS 权限 + ATS 配置
- [x] 基本 widget 测试通过

---

## 4. Phase 1：闭环链路 MVP 🔄

**目标**：手机 → WebView 点击 → HTTP → 代理 → BLE → 设备 → 响应/推送 → WebView UI。用 ESP32 / AC7014 + 一个 index.html 验证完整闭环（§54）。

### 4.1 任务清单

- [x] `DeviceSession` 抽象 + `MockDeviceSession`（无硬件演示全链路）
- [x] 代理服务器：`POST /api/command` + `WS /ws` + 静态 UI 服务
- [x] BLE 层迁移到 flutter_reactive_ble（替换 flutter_blue_plus，规避商业授权）
- [ ] 设备端固件：GATT 透传服务 + index.html（设备侧开发）
- [ ] 真实设备联调：Scan → Connect → Command/Response → Notify

### 4.2 验收标准

1. **Mock 模式**：WebView 页面按钮 → 代理 → Mock → 响应回显；WS 推送更新 UI。（当前即可验证）
2. **真实模式**：连上设备后 WebView 加载设备 index.html，点按钮设备硬件动作，状态推送实时显示。
3. **断连**：设备断开后 App 回到扫描页并释放资源，无崩溃。

### 4.3 联调协议约定（与设备端对齐前必读）

- **GATT UUID**：`lib/core/constants.dart` 中为占位值（FFE0/FFE1/FFE2），必须与设备端固件对齐后冻结。
- **指令 JSON**：`{cmd, params, id}`；响应 `{type:"response", status, data, id}`（§18/§19）。
- **Phase 1 限制**：不做 Frame/分片，单条 JSON < MTU（约 200B）。
- **错误码**：按 §49 分组预留（1xxx 协议 / 2xxx 设备 / 3xxx 指令 / 4xxx 硬件 / 5xxx 资源）。

### 4.4 代码位置对照

| 层 | 文件 | 对应 FRAMEWORK_V2 |
|----|------|-------------------|
| UI Runtime | `lib/ui_runtime/webview_host.dart` + `lib/ui/pages/device_page.dart` | §29 |
| UI Adapter | `lib/ui_runtime/ui_server.dart` | §17 |
| UI Cache | `lib/ui_runtime/ui_cache.dart` | §27 (Phase 1 简化版) |
| DeviceClient | `lib/device/device_session.dart` (抽象) | §9 |
| BLE Transport | `lib/ble/ble_transport.dart` | §46 |
| BLE 扫描 | `lib/ble/ble_scanner.dart` | §10 |
| Riverpod | `lib/providers/*.dart` | §7 |

> 说明：`protocol/`、`device/device_client.dart`、`device/device_manager.dart`、`app/router.dart` 等目录
> 按 FRAMEWORK_V2 §6 预留，随 Phase 2~5 逐步建立（见 §5~§8）。

---

## 5. Phase 2：Frame 与分片 ⬜

**目标**：传输 >MTU 的数据（是 UI Package 下载的前置条件，§55）。

- [ ] 定义 Frame 格式（§12：VER/TYPE/FLAGS/SEQ/LENGTH/PAYLOAD/CRC16）
- [ ] 分片器 Fragment / 重组器 Assembler（§15）
- [ ] 验证 100B / 500B / 1KB / 5KB / 10KB 数据传输

**验收**：单条 10KB 消息经分片往返，内容 CRC 校验一致。

---

## 6. Phase 3：可靠性 ⬜

**目标**：BLE 丢包/断线场景下的可靠传输（§56）。

- [ ] ACK / NACK / 超时 / 重试（§16）
- [ ] SEQ 去重、乱序检测（§14）
- [ ] Command Queue：串行 / 可覆盖（连续调亮度只发最终值，§47）

**验收**：丢包、断线、重连、重复包、乱序、设备忙场景测试全部通过。

---

## 7. Phase 4：State / Patch / Event ⬜

**目标**：设备是状态唯一数据源，增量同步（§21-24）。

- [ ] STATE / PATCH / EVENT 消息类型（§13）
- [ ] state_version 缺失检测 → 触发全量重新同步（§22）
- [ ] Flutter DeviceState（Riverpod）→ WebSocket → WebView 广播

**验收**：设备端状态变化 → App 收到 Patch → WebView UI 自动更新，无全量刷新。

---

## 8. Phase 5：Manifest / UI Package / Cache ⬜

**目标**：设备携带完整 UI，App 自动检测与缓存（§25-28）。

- [ ] manifest.json 定义（协议版本、UI 版本、设备类型、入口、capabilities）
- [ ] ui.pkg 打包格式（manifest + index.html + assets，gzip）
- [ ] 下载 + SHA256 校验
- [ ] UI Cache：deviceId + ui_version → 本地缓存，命中直接加载（§27）
- [ ] Resource API：`GET /api/resource/<path>`（§41）

**验收**：设备升级 UI 版本号 → App 重新下载；未升级 → 秒开（走缓存）。

---

## 9. Phase 6：优化 ⬜

- [ ] Codec 抽象（§45）：JSON → CBOR / MessagePack
- [ ] 随机端口 + Session Token + Origin 校验（§30，替代固定 8080）
- [ ] 多设备同时管理（DeviceManager，§8）
- [ ] 安全：认证 / 加密（§50，门锁、电机类设备必备）

---

## 10. 测试策略

| 层级 | 方式 | 覆盖内容 |
|------|------|----------|
| 协议层（纯 Dart） | 单元测试 | Frame 编解码、分片重组、Patch 应用 |
| 会话层 | Mock 集成测试 | 命令响应配对、超时、推送分发 |
| UI | Widget 测试 | 扫描页、设备页、代理路由 |
| 端到端 | Mock 设备演示 | WebView → 代理 → Mock 全链路（当前已可跑） |

---

## 11. 关键决策记录

| 决策 | 结论 | 原因 |
|------|------|------|
| BLE 库 | flutter_reactive_ble | flutter_blue_plus 2.x 有商业授权限制（§10） |
| Phase 1 编码 | JSON 直传 | 快速闭环，§44 明确允许；正式版换 Binary Codec |
| 状态管理 | Riverpod 只管上层 | 底层纯 Dart 可独立测试（§5） |
| UI 技术 | HTML/JS 直连 Device API | HTMX 可选，协议不依赖 HTMX（§34/§35） |

---

## 12. 当前下一步（按顺序执行）

1. 完成 BLE 层迁移（flutter_reactive_ble）→ analyze / test 通过
2. 设备端固件：GATT 服务 + index.html（与 App 侧 UUID 对齐）
3. 真机联调 Phase 1 闭环
4. 进入 Phase 2
