/**
 * myhome 设备框架 · Jieli SDK 平台胶水实现
 *
 * 依赖 (Jieli SDK)：
 *   custom_fff0_notify()   apps/common/third_party_profile/jieli/rcsp/ble_rcsp_server.h
 *   jiffies_msec()         interface/system/generic/jiffies.h
 *
 * app 侧需提供 (见 light1/device_app.c)：
 *   int  myhome_device_state_json(char* out, int cap);   // 当前状态 JSON
 */
#include "myhome_glue.h"

#include "jiffies.h"
#include "timer.h"                  /* SDK: sys_timer_add (软件定时器) */
#include "ble_rcsp_server.h"        /* custom_fff0_notify */

#include "core/runtime/device_runtime.h"   /* -I<framework> */

/* app 侧提供的状态序列化 (字段与 device.yaml 的 state 一致) */
extern int myhome_device_state_json(char* out, int cap);

static device_runtime_t g_rt;
static u16 g_mtu = 247;
static u8 g_inited = 0;

/** 10ms 周期任务句柄 (0 = 未注册)。 */
static u16 g_tick_timer = 0;

/* ---------------- 运行时回调 ---------------- */

/** 把字节写给手机：复用 RCSP 的 FFF3 通知通道 */
static void myhome_send(const uint8_t* data, u16 len, void* ctx)
{
    (void)ctx;
    custom_fff0_notify((const u8*)data, len);
}

/** 运行时索取当前状态 JSON (STATE / STATE_REQUEST 响应) */
static int myhome_state(char* out, int cap, void* ctx)
{
    (void)ctx;
    return myhome_device_state_json(out, cap);
}

/** 时间源 (分片超时用) */
static u32 myhome_now_ms(void)
{
    return (u32)jiffies_msec();
}

/* ---------------- 资源服务 (ui.pkg 等, §27 分块) ----------------
 *
 * 由 app 侧 (device_app.c) 实现，从设备存储读取：
 *   int myhome_resource_size(const char* path);
 *   int myhome_resource_read(const char* path, u32 offset, u8* out, int cap);
 * 未实现时 (弱符号兜底) RESOURCE_REQUEST 返回 5001 —— App 侧提示
 * "资源下载失败"，此时先跑通协议其余部分。
 *
 * 参考实现 (Jieli 文件系统, 视具体 SDK 版本调整 API):
```c
int myhome_resource_size(const char* path) {
    FILE* f = fopen(path, "r");            // 或 fopen(path, "rb")
    if (!f) return -1;
    fseek(f, 0, SEEK_END);
    int size = (int)ftell(f);
    fclose(f);
    return size;
}
int myhome_resource_read(const char* path, u32 offset, u8* out, int cap) {
    FILE* f = fopen(path, "r");
    if (!f) return -1;
    fseek(f, offset, SEEK_SET);
    int n = fread(out, 1, cap, f);
    fclose(f);
    return n;
}
```
 * 也可直接把 ui.pkg 编译进固件 (数组 + memcpy)，避免文件系统依赖。
 */
__attribute__((weak)) int myhome_resource_size(const char* path)
{
    (void)path;
    return -1;   /* 未实现 = 无资源 */
}

__attribute__((weak)) int myhome_resource_read(const char* path, u32 offset,
                                               u8* out, int cap)
{
    (void)path;
    (void)offset;
    (void)out;
    (void)cap;
    return -1;
}

/** 运行时钩子：资源大小 */
static int myhome_resource_size_hook(const char* path, void* ctx)
{
    (void)ctx;
    return myhome_resource_size(path);
}

/** 运行时钩子：读取分块 */
static int myhome_resource_chunk_hook(const char* path, uint32_t offset,
                                      uint8_t* out, int cap, void* ctx)
{
    (void)ctx;
    return myhome_resource_read(path, (u32)offset, (u8*)out, cap);
}

/* ---------------- 对外接口 ---------------- */

/** 10ms 周期任务：分片组装超时清理 (§8.6)。
 *  用软件定时器而非 tick 中断；精度被 tick 量化 (10ms 整数倍)。 */
static void myhome_tick_task(void* priv)
{
    (void)priv;
    myhome_tick();
}

void myhome_init(u16 mtu)
{
    device_runtime_hooks_t hooks;
    g_mtu = (mtu >= 23) ? mtu : 247;
    hooks.send = myhome_send;
    hooks.get_state_json = myhome_state;
    hooks.get_resource_size = myhome_resource_size_hook;
    hooks.get_resource_chunk = myhome_resource_chunk_hook;
    hooks.now_ms = myhome_now_ms;
    hooks.ctx = NULL;
    device_runtime_init(&g_rt, &hooks, g_mtu);
    g_inited = 1;

    /* 自动挂 10ms 软件定时器 (app 不需要再手动调 myhome_tick) */
    if (g_tick_timer == 0) {
        g_tick_timer = sys_timer_add(NULL, myhome_tick_task, 10);
    }
    printf("[myhome] framework init, mtu=%u, tick_timer=%u\n", g_mtu, g_tick_timer);
}

void myhome_deinit(void)
{
    if (g_tick_timer != 0) {
        sys_timer_del(g_tick_timer);
        g_tick_timer = 0;
    }
    g_inited = 0;
}

void myhome_ble_on_write(u8* buffer, u16 buffer_size)
{
    /* 兜底：app 未显式初始化时，第一条 BLE 数据到达自动初始化 */
    if (!g_inited) {
        myhome_init(247);
    }
    device_runtime_on_bytes(&g_rt, (const uint8_t*)buffer, buffer_size);
}

void myhome_tick(void)
{
    device_runtime_tick(&g_rt, myhome_now_ms());
}

void myhome_on_disconnect(void)
{
    device_runtime_reset(&g_rt);
}

void myhome_state_changed(void)
{
    device_runtime_notify_state_changed(&g_rt);
}

void myhome_send_event(const char* name, const char* data_json)
{
    device_runtime_send_event(&g_rt, name, data_json);
}

void myhome_dump_stats(void)
{
    printf("[myhome] rx=%lu tx=%lu bad=%lu dup=%lu state_v=%lu\n",
           (unsigned long)g_rt.rx_frames, (unsigned long)g_rt.tx_frames,
           (unsigned long)g_rt.bad_frames, (unsigned long)g_rt.duplicate_frames,
           (unsigned long)device_runtime_state_version(&g_rt));
}

/* ---------------- 生成代码要求的 SDK 侧函数 ---------------- */

/**
 * 事件发布 (device_api.h 声明)。
 * 生成的命令函数里可调用它上报业务事件。
 */
void device_publish_event(const char* name, const char* json)
{
    myhome_send_event(name, json);
}
