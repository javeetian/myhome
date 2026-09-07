
```markdown
# 蓝牙设备控制架构设计：设备端UI + Flutter通用容器

## 1. 核心设计理念

**目标**：用手机App控制蓝牙设备时，将控制界面（UI）和通信协议**完全解耦到设备端**，手机App仅作为通用渲染与透传容器。

**价值**：
- 新增设备无需更新App，只需更新设备固件和UI。
- 一套App可管理所有设备。
- 开发隔离：H5开发者专注UI/UX，嵌入式工程师专注硬件驱动。

---

## 2. 整体技术架构

```text
┌─────────────────────────────────────────────────────────────┐
│  设备端 (AC7014 / ESP32等)                                 │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  HTMX UI页面 (HTML/CSS/JS)                          │ │
│  │  + 协议定义 (JSON格式，完全自定义)                  │ │
│  │  + 硬件驱动逻辑                                      │ │
│  │  + SPIFFS存储静态资源 (图片等)                      │ │
│  └───────────────────────────────────────────────────────┘ │
│                          ↕ BLE (GATT)                     │
└─────────────────────────────────────────────────────────────┘
                           ↕
┌─────────────────────────────────────────────────────────────┐
│  手机端 (Flutter App)                                      │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  WebView (加载设备端HTMX页面)                        │ │
│  │     ↕ HTTP/WebSocket请求 (指向localhost)             │ │
│  │  App内置代理服务器 (HTTP/WS 转 BLE)                 │ │
│  │     ↕ BLE读写 + Notify监听                          │ │
│  │  Flutter BLE插件 (flutter_blue_plus)               │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 关键技术选型

| 模块 | 技术方案 | 说明 |
|------|----------|------|
| App框架 | Flutter | 跨平台，生态丰富 |
| UI渲染 | `webview_flutter` | 加载设备端HTMX页面 |
| BLE通信 | `flutter_blue_plus` / `flutter_reactive_ble` | BLE读写与Notify监听 |
| App内代理 | `shelf` + `web_socket_channel` | HTTP/WebSocket转BLE |
| 通信协议 | JSON (设备端自定义) | 每个项目可独立定义 |
| 数据传输 | BLE GATT (特征值读写 + Notify) | 双向通信 |
| UI动态化 | HTMX + 增量状态同步 | 变量驱动UI更新 |
| 页面跳转 | WebView原生支持 `<a>` 链接 | 多页面由设备端维护 |
| 图片资源 | 设备端SPIFFS存储，WebView相对路径引用 | 随固件分发 |
| 原生感增强 | SystemChrome + 禁用滚动回弹 + meta标签 | 消除浏览器特征 |

---

## 4. 核心工作流程

### 4.1 首次连接与UI加载
1. 手机扫描BLE设备 → 连接。
2. 从设备GATT服务读取UI压缩包 (如 `ui.html.gz`)。
3. App解压 → WebView加载。

### 4.2 操作指令流程 (HTMX AJAX)
1. 用户在WebView点击按钮 → HTMX发起HTTP请求到 `http://localhost:8080/api/...`。
2. App内置代理服务器接收请求 → 转成BLE数据写入设备特征值。
3. 设备接收BLE数据 → 解析JSON → 执行硬件操作。
4. 设备通过BLE Notify返回结果 → App代理接收 → 转为HTTP响应。
5. WebView收到响应 → HTMX更新DOM。

### 4.3 状态监听流程 (WebSocket)
1. WebView建立WebSocket连接 `ws://localhost:8080/ws`。
2. App代理接收WS消息 → 转BLE写入设备。
3. 设备主动推送状态 (BLE Notify) → App接收。
4. App通过WebSocket将数据推送给WebView → JS回调更新UI。

---

## 5. 通信协议设计 (设备端自定义)

### 5.1 协议格式 (JSON)

**手机 → 设备 (指令)**
```json
{
  "cmd": "led_on",
  "mode": "sync",       // 或 "async"
  "params": {"brightness": 80},
  "id": 12345
}
```

**设备 → 手机 (响应/推送)**
```json
{
  "type": "response",   // 或 "push"
  "status": "ok",
  "data": {"temperature": 25.5},
  "id": 12345
}
```

### 5.2 同步 vs 异步命令
| 模式 | 行为 | 适用场景 |
|------|------|----------|
| **同步 (Sync)** | 发完等待设备立即返回结果 | 读操作 (如读取温度) |
| **异步 (Async)** | 发完不等待，通过监听通道稍后推送结果 | 控制操作 (如开灯) |

### 5.3 粘包处理
- BLE链路层已提供分帧和CRC校验，应用层无需再处理底层粘包。
- 若JSON长度 > MTU (247字节)，可在JSON两端加 `\x02` / `\x03` 标记，或协商MTU至最大值。

---

## 6. UI动态同步机制

### 6.1 核心原则
设备端是“唯一真实数据源”。所有UI变化都源于设备端数据状态的变化，手机端只负责渲染。

### 6.2 同步策略
| 策略 | 适用场景 | 传输量 |
|------|----------|--------|
| **全量同步** | 首次连接、版本升级 | 较大 (一次性) |
| **增量同步 (Patch)** | 日常操作、点击添加按钮等 | 极小 (实时) |

### 6.3 状态更新示例
**设备 → App (BLE Notify)**
```json
{
  "type": "state_update",
  "key": "color_list",
  "value": ["#FF0000", "#00FF00", "#0000FF"]
}
```

**App → WebView (runJavascript)**
```javascript
window.onStateUpdate('color_list', ["#FF0000", "#00FF00", "#0000FF"]);
```

**WebView 响应**
```javascript
window.onStateUpdate = function(key, value) {
    if (key === 'color_list') {
        renderColorButtons(value); // 重新渲染
    }
};
```

---

## 7. HTML UI 瘦身与优化

### 7.1 文件压缩
- 使用 `HTMLMinifier`、`CSSNano`、`UglifyJS` 等工具去除空格、换行、注释，通常能减少 20%-30% 体积。

### 7.2 架构优化
- **数据驱动UI**：传输“数据增量”而非“完整HTML”。
- **懒加载**：大图使用HTMX的 `hx-trigger="load"` 按需加载。

### 7.3 UI渲染备选方案 (讨论)
| 方案 | 优点 | 缺点 |
|------|------|------|
| Canvas渲染 | 数据量极小 | 需自行实现布局和事件，工程复杂度高 |
| Klover DSL | 源文件精简 | 项目活跃开发中，未大面积验证 |
| XML-based UIDL | 高抽象层级 | 生态和工具链不够成熟 |

**结论**：当前阶段，**HTML + 压缩 + 增量数据同步** 是综合成本最低、最可靠的方案。

---

## 8. 让HTML界面更像原生App

### 8.1 视觉“伪装”
```html
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
  body { overscroll-behavior: none; }
  * { -webkit-touch-callout: none; }
</style>
```

### 8.2 Flutter WebView 原生配置
```dart
// 隐藏状态栏/导航栏
SystemChrome.setEnabledSystemUIOverlays([]);

// 禁用iOS弹性滚动 (在 onWebViewCreated 中)
webViewController = controller;
// 通过 platform 通道设置 scrollView.bounces = false
```

### 8.3 PWA (Progressive Web App) 增强 (可选)
- `manifest.json` 设置 `"display": "standalone"` → 独立窗口。
- `Service Worker` → 离线缓存。
- **注意**：在国内推送功能受限，可作为锦上添花而非核心功能。

---

## 9. 关键问题与解决方案汇总

| 问题 | 解决方案 |
|------|----------|
| 如何传输UI界面？ | BLE GATT特征值读取，设备端存储 `ui.html.gz` |
| 如何区分同步/异步命令？ | JSON协议中用 `mode: "sync"/"async"` 字段 |
| 如何处理粘包？ | BLE本身有分帧，JSON用 `{}` 计数分割即可 |
| 动态UI如何同步？ | 设备维护状态对象，增量推送变化，WebView JS响应更新 |
| 图片资源怎么处理？ | 设备端SPIFFS存储，WebView通过相对路径引用 |
| 多页面如何跳转？ | `webview_flutter` 默认支持 `<a>` 链接跳转 |
| 界面太大，蓝牙传输慢？ | 压缩HTML + 只传数据增量，不传完整界面 |
| 如何让界面像原生App？ | SystemChrome隐藏系统栏 + 禁用网页滚动特效 + meta标签 |

---

## 10. 下一步行动建议

1. **验证AC7014芯片**：确认是否支持GATT Server、MTU协商、大文件传输。
2. **MVP开发**：
   - Flutter端：实现 `webview_flutter` + `flutter_blue_plus` + 简易HTTP代理 (`shelf`)。
   - 设备端：实现GATT服务，存储一份最简单的HTMX测试页面。
3. **性能测试**：实测BLE传输速率，确认UI加载和交互响应是否流畅。
4. **协议设计**：在设备端HTMX页面中，定义好JSON协议格式和命令列表。
5. **优化迭代**：根据测试结果，考虑引入HTML压缩、增量同步等优化手段。

---

## 附录：核心依赖与资源

| 组件 | Flutter包/技术 | 用途 |
|------|---------------|------|
| WebView | `webview_flutter` | 加载设备端HTMX页面 |
| BLE | `flutter_blue_plus` / `flutter_reactive_ble` | BLE通信 |
| HTTP代理 | `shelf` | App内建HTTP服务器 |
| WebSocket | `web_socket_channel` | App内建WebSocket服务器 |
| JSON解析 | `dart:convert` | 协议解析 |

```yaml
# pubspec.yaml 关键依赖
dependencies:
  flutter:
    sdk: flutter
  webview_flutter: ^4.4.0
  flutter_blue_plus: ^1.32.0
  shelf: ^1.4.0
  web_socket_channel: ^2.4.0
```

---

**文档生成时间**：2026-09-07
**项目状态**：架构设计阶段，待进一步开发验证
```

---
