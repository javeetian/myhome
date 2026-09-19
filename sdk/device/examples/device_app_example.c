/**
 * light1 设备应用 (开发者代码, WORK_V3 §45)
 *
 * 你只需要写这个文件：实现 device_api.h 声明的命令函数 + 硬件操作。
 * 协议路由、参数校验、分片、ACK、握手全部由 framework/ 提供。
 *
 * 生成的接口 (generated/c/device_api.h)：
 *   int light_set_power(bool power, char* resp, int len);
 *   int light_set_brightness(uint8_t value, char* resp, int len);
 *   int light_set_color_temperature(uint16_t value, char* resp, int len);
 *
 * 返回值约定：
 *   返回 snprintf 写入长度 → 正常响应 (运行时自动补 request_id)
 *   返回 3001/3002        → 参数错误 / 未知命令 (运行时组错误响应)
 */
/* ★ 必须先包含胶水头：它引入 Jieli SDK 类型并定义 MYHOME_SDK_BOOL，
 *   使生成的头文件跳过 <stdbool.h> (与 SDK 的 bool typedef 冲突) */
#include "myhome_glue.h"

#include "device_api.h"
#include "device_state.h"
#include "device_info.h"
#include "hardware_adapter.h"
#include "jiffies.h"

/* 注意：不能用 <stdio.h> —— 与 SDK fs.h 的 FILE 定义冲突 */
#include "printf.h"   /* SDK: snprintf/printf */
#include "string.h"

/* ---------------- 设备状态 (唯一数据源) ---------------- */

static device_state_t g_state = {
    .version = 1,
    .power = false,
    .brightness = 80,
    .color_temperature = 4000,
};

/* ---------------- 硬件操作 (TODO: 换成你的板级驱动) ---------------- */

/*
 * 真实硬件接入点。Jieli SDK 的 LED/PWM 接口按板子而定，
 * 常见做法：
 *   - 单色灯/指示灯:  GPIO 输出 (gpio_set_direction / gpio_write)
 *   - 调光灯:         PWM 占空比 (pwm_init / pwm_set_duty)
 *   - 双色温灯:       两路 PWM 混合
 * 下面用变量占位，替换为实际驱动调用即可。
 */
static void hw_set_power(bool on)
{
    /* TODO: gpio_write(LED_GPIO, on ? 1 : 0); */
    printf("[light1] hw power=%d\n", on);
}

static void hw_set_brightness(uint8_t value)
{
    /* TODO: pwm_set_duty(PWM_CH_LED, value); */
    printf("[light1] hw brightness=%u\n", value);
}

static void hw_set_color_temperature(uint16_t value)
{
    /* TODO: 双路 PWM 混合 (暖/冷) */
    printf("[light1] hw color_temp=%u\n", value);
}

const hardware_adapter_t g_hardware = {
    .set_power = hw_set_power,
    .set_brightness = hw_set_brightness,
    .set_color_temperature = hw_set_color_temperature,
    .get_temperature = NULL,   /* 无温度传感器 */
};

/* ---------------- 状态 → JSON (运行时 STATE 上报调用) ---------------- */

int myhome_device_state_json(char* out, int cap)
{
    return snprintf(out, (unsigned long)cap,
                    "{\"power\":%s,\"brightness\":%u,\"color_temperature\":%u}",
                    g_state.power ? "true" : "false", g_state.brightness,
                    g_state.color_temperature);
}

/* ---------------- 命令实现 (device_api.h 声明) ---------------- */

int light_set_power(bool power, char* response_json, int response_len)
{
    g_state.power = power;
    if (g_hardware.set_power) {
        g_hardware.set_power(power);
    }
    /* 状态变化 → 版本 +1 并推送 STATE 给手机 (§16) */
    g_state.version++;
    myhome_state_changed();

    return snprintf(response_json, (unsigned long)response_len,
                    "{\"status\":\"ok\",\"data\":{\"power\":%s}}",
                    power ? "true" : "false");
}

int light_set_brightness(uint8_t value, char* response_json, int response_len)
{
    g_state.brightness = value;
    if (g_hardware.set_brightness) {
        g_hardware.set_brightness(value);
    }
    g_state.version++;
    myhome_state_changed();
    device_publish_event("light1.state_changed", "{\"field\":\"brightness\"}");

    return snprintf(response_json, (unsigned long)response_len,
                    "{\"status\":\"ok\",\"data\":{\"brightness\":%u}}", value);
}

int light_set_color_temperature(uint16_t value, char* response_json,
                                int response_len)
{
    g_state.color_temperature = value;
    if (g_hardware.set_color_temperature) {
        g_hardware.set_color_temperature(value);
    }
    g_state.version++;
    myhome_state_changed();

    return snprintf(response_json, (unsigned long)response_len,
                    "{\"status\":\"ok\",\"data\":{\"color_temperature\":%u}}",
                    value);
}

/* ---------------- device_state.h 要求的 SDK 侧函数 ---------------- */

/** 直接改状态结构体后调用：同步版本并推送 (§37 状态模型)。 */
void device_state_changed(const device_state_t* state)
{
    if (state != NULL) {
        g_state = *state;
    }
    g_state.version++;
    myhome_state_changed();
}

/* ---------------- 资源服务：ui.pkg 分块读取 (§27) ----------------
 *
 * 设备端 UI 包存放在文件系统里，App 按 offset 分块拉取。
 * 查找顺序：先试 MYHOME_RES_DIR 目录，再试根路径 (便于部署调试)。
 *
 * 部署方法：把 Studio 生成的 ui.pkg 烧到设备文件系统的
 *   /myhome/ui.pkg
 * (路径前缀可用 MYHOME_RES_DIR 调整；若走固件内嵌数组，改成 memcpy 即可)
 */
#define MYHOME_RES_DIR "/myhome/"

/** 打开资源文件 (返回 NULL = 不存在)。[out_path] 回填实际命中路径。 */
static FILE* open_resource(const char* name, char* out_path, int cap)
{
    FILE* f;
    snprintf(out_path, (unsigned long)cap, "%s%s", MYHOME_RES_DIR, name);
    f = fopen(out_path, "r");
    if (f == NULL) {
        /* 回退：根路径 */
        snprintf(out_path, (unsigned long)cap, "%s", name);
        f = fopen(out_path, "r");
    }
    return f;
}

/* 大小缓存：分块下载期间 runtime 每块都会问一次大小，避免重复打开文件 */
static char g_size_path[64];
static int g_size_value = -1;

int myhome_resource_size(const char* path)
{
    char full[64];
    FILE* f;
    int size;

    if (path == NULL) {
        return -1;
    }
    if (g_size_value >= 0 && strcmp(g_size_path, path) == 0) {
        return g_size_value;   /* 命中缓存 (同一资源传输期间不变) */
    }
    f = open_resource(path, full, sizeof(full));
    if (f == NULL) {
        printf("[light1] resource not found: %s\n", path);
        return -1;
    }
    size = (int)flen(f);
    fclose(f);

    strncpy(g_size_path, path, sizeof(g_size_path) - 1);
    g_size_path[sizeof(g_size_path) - 1] = 0;
    g_size_value = size;
    printf("[light1] resource %s -> %s (%d bytes)\n", path, full, size);
    return size;
}

int myhome_resource_read(const char* path, u32 offset, u8* out, int cap)
{
    char full[64];
    FILE* f;
    int n;

    if (path == NULL || out == NULL || cap <= 0) {
        return -1;
    }
    f = open_resource(path, full, sizeof(full));
    if (f == NULL) {
        return -1;
    }
    if (fseek(f, offset, SEEK_SET) != 0) {
        fclose(f);
        return -1;
    }
    n = fread(out, 1, (u32)cap, f);
    fclose(f);
    return n;
}

/* ---------------- 应用启动 (在 app_main 或 BLE 初始化后调用) ---------------- */

void light1_app_init(void)
{
    /* MTU: 与 ble_vendor_set_default_att_mtu 设置一致；不确定时传 247 */
    myhome_init(247);

    /* 上电状态同步到硬件 */
    if (g_hardware.set_power) {
        g_hardware.set_power(g_state.power);
    }
    if (g_hardware.set_brightness) {
        g_hardware.set_brightness(g_state.brightness);
    }
    printf("[light1] app init done\n");
}
