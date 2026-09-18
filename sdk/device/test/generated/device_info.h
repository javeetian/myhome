/* 测试用 device_info.h (对应 devices/light1/device.yaml) */
#ifndef DEVICE_INFO_H
#define DEVICE_INFO_H

#define DEVICE_TYPE             "light1"
#define DEVICE_MODEL            "L1"
#define DEVICE_PROTOCOL_VERSION 1
#define DEVICE_API_VERSION      1
#define DEVICE_UI_VERSION       "0.1.0"

static const char* const DEVICE_CAPABILITIES[] = {
    "power",
    "brightness",
    "color_temperature",
};
#define DEVICE_CAPABILITY_COUNT 3

#endif
