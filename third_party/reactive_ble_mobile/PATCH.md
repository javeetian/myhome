# reactive_ble_mobile 本地补丁

本目录是 `reactive_ble_mobile` 5.5.0 的 vendored 副本（来自 pub 缓存），
通过 `pubspec.yaml` 的 `dependency_overrides` 生效。**只改了一处**。

## 补丁：requestConnectionPriority 的固定 2 秒等待 → 1ms

**文件**：`android/src/main/kotlin/com/signify/hue/flutterreactiveble/ble/ReactiveBleClient.kt`
（`requestConnectionPriority` 内，上游约 360-380 行）

```diff
                 is EstablishedConnection ->
                     connectionResult.rxConnection.requestConnectionPriority(
                         priority.code,
-                        2,
-                        TimeUnit.SECONDS,
+                        1,
+                        TimeUnit.MILLISECONDS,
                     )
```

**为什么**：

1. 这个 `2, TimeUnit.SECONDS` 传进 RxAndroidBle 1.16.0 后，被包进
   `ConnectionPriorityChangeOperation`，其 `getCallback()` 直接返回 `Single.timer(2s)` ——
   **是人为固定延迟，不是等 Android 的连接参数更新回调**（Android 公共 API 没有该回调）。
2. 更关键：这 2 秒里该操作**一直占着 RxAndroidBle 的每连接操作队列**
   （`SingleResponseOperation` 要等 callback 终止才释放），所以紧随其后的
   `discoverServices()` / `requestMtu()` / 读写都会被压在队列后面。
3. 实测（Android，杰里 BLE 设备）：手机在 GATT 连上后请求 `highPerformance`，
   服务发现被拖到 1.7–3.4s（无此请求时约 860ms，请求且参数稳定后仅 65ms）。
   即"请求高优先级"本来是为了提速，用 2 秒阻塞换 15ms 间隔得不偿失。
4. RxAndroidBle 校验 delay 必须 `> 0`（`delay <= 0` 直接抛
   `IllegalArgumentException: Delay must be bigger than 0`），所以取 `1ms` 而不是 0。
   真正的 `gatt.requestConnectionPriority()` 在 `startOperation()` 里**已同步发出**，
   这个等待值只影响"多久后报告成功"。

## 升级 FRB 时怎么办

1. 用新版 `reactive_ble_mobile` 覆盖本目录；
2. 在新版里重新找到 `requestConnectionPriority` 的等待参数，改回 `1, TimeUnit.MILLISECONDS`；
3. 跑一遍真机验证：连接阶段的服务发现耗时应 ~100ms 量级（见 docs/BLE_PERFORMANCE.md 的验证清单）；
4. 若上游某天修掉了这个硬编码，**删掉本目录和 pubspec 里的 dependency_overrides** 即可。
