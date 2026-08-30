#pragma once

#include <cstdint>

#include "dl_image_define.hpp"

inline constexpr const char *STUDENT_FACE_DB_PATH = "/fr/face.db";

inline constexpr uint16_t STUDENT_COLOR_FACE = 0xFFE0;    // 黄
inline constexpr uint16_t STUDENT_COLOR_TARGET = 0x07E0;  // 绿

void studentDrawRect(dl::image::img_t &img, int x1, int y1, int x2, int y2, uint16_t color);
void studentDrawTargetTag(dl::image::img_t &img, int x, int y);
