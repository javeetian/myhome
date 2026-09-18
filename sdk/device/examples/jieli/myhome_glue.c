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
#include "ble_rcsp_server.h"        /* custom_fff0_notify */

#include "core/runtime/device_runtime.h"

/* app 侧提供的状态序列化 (字段与 device.yaml 的 state 一致) */
extern int myhome_device_state_json(char* out, int cap);

static device_runtime_t g_rt;
static u16 g_mtu = 247;
static u8 g_inited = 0;

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

/* ---------------- 对外接口 ---------------- */

void myhome_init(u16 mtu)
{
    device_runtime_hooks_t hooks;
    g_mtu = (mtu >= 23) ? mtu : 247;
    hooks.send = myhome_send;
    hooks.get_state_json = myhome_state;
    hooks.get_resource = NULL;      /* ui.pkg 资源 (Phase 10 接 SPIFFS) */
    hooks.now_ms = myhome_now_ms;
    hooks.ctx = NULL;
    device_runtime_init(&g_rt, &hooks, g_mtu);
    g_inited = 1;
    printf("[myhome] framework init, mtu=%u\n", g_mtu);
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
