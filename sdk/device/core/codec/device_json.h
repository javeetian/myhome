/* 轻量 JSON 字段提取 (SDK core 契约函数)。
 * 生成代码 (device_commands.c) 依赖这些函数解析命令参数。
 *
 * 注意：本实现面向固件生成的扁平 JSON 参数 (`{"key": value}`)，
 * 支持嵌套一层；不是完整 JSON 解析器。返回 0 = 成功。
 */
#ifndef DEVICE_JSON_H
#define DEVICE_JSON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

int device_json_get_bool(const char* json, const char* key, bool* out);
int device_json_get_uint(const char* json, const char* key, uint32_t* out);
int device_json_get_float(const char* json, const char* key, float* out);
int device_json_get_string(const char* json, const char* key,
                           char* out, size_t out_cap);

/**
 * 取原始值子串 (不复制)：用于对象/数组字段 (如命令的 params)。
 * 成功时 *out_ptr 指向 [json] 内部，*out_len 为子串长度 (含首尾括号)；
 * 调用方保证 json 生命周期内有效。返回 0 = 成功。
 */
int device_json_get_raw(const char* json, const char* key,
                        const char** out_ptr, uint16_t* out_len);

#endif /* DEVICE_JSON_H */
