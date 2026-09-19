#include "device_json.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* 定位 `"key":` 之后的值起始位置；找不到返回 NULL */
static const char* find_value(const char* json, const char* key) {
    size_t key_len = strlen(key);
    /* static：调用方跑在 BLE 回调的任务上下文里，任务栈只有 ~4KB，
     * 这里虽只有 64 字节，但会被层层调用，统一按"大缓冲不进栈"处理 */
    static char pattern[64];
    if (key_len + 3 >= sizeof(pattern)) {
        return NULL;
    }
    pattern[0] = '"';
    memcpy(pattern + 1, key, key_len);
    pattern[key_len + 1] = '"';
    pattern[key_len + 2] = ':';
    pattern[key_len + 3] = '\0';

    const char* pos = strstr(json, pattern);
    if (pos == NULL) {
        return NULL;
    }
    pos += key_len + 3;
    while (*pos == ' ' || *pos == '\t') {
        pos++;
    }
    return pos;
}

int device_json_get_bool(const char* json, const char* key, bool* out) {
    const char* pos = find_value(json, key);
    if (pos == NULL) {
        return -1;
    }
    if (strncmp(pos, "true", 4) == 0) {
        *out = true;
        return 0;
    }
    if (strncmp(pos, "false", 5) == 0) {
        *out = false;
        return 0;
    }
    return -1;
}

int device_json_get_uint(const char* json, const char* key, uint32_t* out) {
    const char* pos = find_value(json, key);
    if (pos == NULL) {
        return -1;
    }
    char* end = NULL;
    const long value = strtol(pos, &end, 10);
    if (end == pos || value < 0) {
        return -1;
    }
    *out = (uint32_t)value;
    return 0;
}

int device_json_get_float(const char* json, const char* key, float* out) {
    const char* pos = find_value(json, key);
    if (pos == NULL) {
        return -1;
    }
    char* end = NULL;
    const float value = strtof(pos, &end);
    if (end == pos) {
        return -1;
    }
    *out = value;
    return 0;
}

int device_json_get_raw(const char* json, const char* key,
                        const char** out_ptr, uint16_t* out_len) {
    const char* pos = find_value(json, key);
    if (pos == NULL) {
        return -1;
    }
    /* 仅处理对象/数组 (命令的 params 等) */
    const char open = *pos;
    if (open != '{' && open != '[') {
        return -1;
    }
    const char close = (open == '{') ? '}' : ']';
    int depth = 0;
    int in_string = 0;
    const char* cur = pos;
    while (*cur != '\0') {
        const char c = *cur;
        if (in_string) {
            if (c == '\\') { /* 跳过转义字符 */
                cur++;
                if (*cur == '\0') {
                    break;
                }
            } else if (c == '"') {
                in_string = 0;
            }
        } else if (c == '"') {
            in_string = 1;
        } else if (c == open) {
            depth++;
        } else if (c == close) {
            depth--;
            if (depth == 0) {
                *out_ptr = pos;
                *out_len = (uint16_t)(cur - pos + 1);
                return 0;
            }
        }
        cur++;
    }
    return -1; /* 括号不匹配 */
}

int device_json_get_string(const char* json, const char* key,
                           char* out, size_t out_cap) {
    const char* pos = find_value(json, key);
    if (pos == NULL || *pos != '"') {
        return -1;
    }
    pos++;
    size_t i = 0;
    while (*pos != '"' && *pos != '\0' && i + 1 < out_cap) {
        out[i++] = *pos++;
    }
    out[i] = '\0';
    return 0;
}
