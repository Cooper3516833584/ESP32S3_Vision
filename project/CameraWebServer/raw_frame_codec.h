#pragma once

#include <Arduino.h>
#include "esp_camera.h"

static inline uint8_t rawClipByte(int value) {
  return value < 0 ? 0 : (value > 255 ? 255 : value);
}

static inline uint8_t rawRgb332(int red, int green, int blue) {
  return (red & 0xE0) | ((green >> 3) & 0x1C) | (blue >> 6);
}

// ESP32 已经完成标注后，再把每像素量化为 8 位 RGB332。
// 识别使用的仍是量化前的原始像素。
static inline bool rawMakeRgb332(const camera_fb_t *frame, uint8_t *pixels) {
  const size_t count = (size_t)frame->width * frame->height;
  if (frame->format == PIXFORMAT_RGB565) {
    for (size_t i = 0; i < count; i++) {
      const uint16_t value = ((uint16_t)frame->buf[i * 2] << 8) | frame->buf[i * 2 + 1];
      pixels[i] = ((value >> 8) & 0xE0)
                | ((value >> 6) & 0x1C)
                | ((value >> 3) & 0x03);
    }
    return true;
  }

  if (frame->format == PIXFORMAT_YUV422) {
    for (size_t i = 0; i < count; i += 2) {
      const size_t source = i * 2;
      const int y0 = frame->buf[source];
      const int u = frame->buf[source + 1];
      const int y1 = frame->buf[source + 2];
      const int v = frame->buf[source + 3];
      const int d = u - 128;
      const int e = v - 128;
      const int redPart = 409 * e + 128;
      const int greenPart = -100 * d - 208 * e + 128;
      const int bluePart = 516 * d + 128;

      int c = max(0, y0 - 16) * 298;
      pixels[i] = rawRgb332(
        rawClipByte((c + redPart) >> 8),
        rawClipByte((c + greenPart) >> 8),
        rawClipByte((c + bluePart) >> 8)
      );
      c = max(0, y1 - 16) * 298;
      pixels[i + 1] = rawRgb332(
        rawClipByte((c + redPart) >> 8),
        rawClipByte((c + greenPart) >> 8),
        rawClipByte((c + bluePart) >> 8)
      );
    }
    return true;
  }

  return false;
}

// PackBits：最高位 1 表示重复段，0 表示原样段；长度均为低 7 位 + 1。
// 最坏情况只比 RGB332 多约 0.8%，但平坦背景和文字区域会明显缩小。
static inline size_t rawPackBits(const uint8_t *input, size_t count,
                                 uint8_t *output, size_t capacity) {
  size_t source = 0;
  size_t target = 0;
  while (source < count) {
    size_t run = 1;
    while (source + run < count && run < 128 && input[source + run] == input[source]) {
      run++;
    }

    if (run >= 3) {
      if (target + 2 > capacity) return 0;
      output[target++] = 0x80 | (uint8_t)(run - 1);
      output[target++] = input[source];
      source += run;
      continue;
    }

    const size_t literalStart = source++;
    while (source < count && source - literalStart < 128) {
      run = 1;
      while (source + run < count && run < 3 && input[source + run] == input[source]) {
        run++;
      }
      if (run >= 3) break;
      source++;
    }
    const size_t literalLength = source - literalStart;
    if (target + 1 + literalLength > capacity) return 0;
    output[target++] = (uint8_t)(literalLength - 1);
    memcpy(output + target, input + literalStart, literalLength);
    target += literalLength;
  }
  return target;
}

