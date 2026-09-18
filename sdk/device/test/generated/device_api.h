/* 测试用 device_api.h 桩 */
#ifndef DEVICE_API_H
#define DEVICE_API_H
#include <stdbool.h>
#include <stdint.h>
int device_handle_command(const char* cmd, const char* params_json,
                          char* response_json, int response_len);
#endif
