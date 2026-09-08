#include "device_json.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* 定位 `"key":` 之后的值起始位置；找不到返回 NULL */
static const char* find_value(const char* json, const char* key) {
    size_t key_len = strlen(key);
    char pattern[64];
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
