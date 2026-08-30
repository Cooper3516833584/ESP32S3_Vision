#include "student_support.h"

#include <algorithm>
#include <cerrno>
#include <cstdio>

#include "esp_log.h"
#include "esp_spiffs.h"

namespace {

constexpr char kTagText[] = "TARGET";
constexpr int kGlyphWidth = 5;
constexpr int kGlyphHeight = 7;
constexpr int kGlyphScale = 2;
constexpr int kGlyphGap = 1;
constexpr int kTagPadding = 2;
constexpr uint16_t kTagBackground = 0x0000;

constexpr uint8_t kGlyphA[kGlyphHeight] = {0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11};
constexpr uint8_t kGlyphE[kGlyphHeight] = {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F};
constexpr uint8_t kGlyphG[kGlyphHeight] = {0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0E};
constexpr uint8_t kGlyphR[kGlyphHeight] = {0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11};
constexpr uint8_t kGlyphT[kGlyphHeight] = {0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04};

bool isDrawable(const dl::image::img_t &img)
{
    return img.data != nullptr && img.width > 0 && img.height > 0 &&
           img.pix_type == dl::image::DL_IMAGE_PIX_TYPE_RGB565BE;
}

void setPixel(dl::image::img_t &img, int x, int y, uint16_t color)
{
    if (x < 0 || y < 0 || x >= static_cast<int>(img.width) || y >= static_cast<int>(img.height)) {
        return;
    }
    auto *pixels = static_cast<uint8_t *>(img.data);
    const size_t offset = (static_cast<size_t>(y) * img.width + static_cast<size_t>(x)) * 2U;
    pixels[offset] = static_cast<uint8_t>(color >> 8);
    pixels[offset + 1U] = static_cast<uint8_t>(color & 0xFFU);
}

void fillRect(dl::image::img_t &img, int x, int y, int width, int height, uint16_t color)
{
    const int left = std::max(x, 0);
    const int top = std::max(y, 0);
    const int right = std::min(x + width, static_cast<int>(img.width));
    const int bottom = std::min(y + height, static_cast<int>(img.height));
    for (int row = top; row < bottom; ++row) {
        for (int column = left; column < right; ++column) {
            setPixel(img, column, row, color);
        }
    }
}

const uint8_t *glyphFor(char letter)
{
    switch (letter) {
    case 'A': return kGlyphA;
    case 'E': return kGlyphE;
    case 'G': return kGlyphG;
    case 'R': return kGlyphR;
    case 'T': return kGlyphT;
    default: return nullptr;
    }
}

void drawGlyph(dl::image::img_t &img, int x, int y, const uint8_t *glyph)
{
    if (glyph == nullptr) {
        return;
    }
    for (int row = 0; row < kGlyphHeight; ++row) {
        for (int column = 0; column < kGlyphWidth; ++column) {
            if ((glyph[row] & (1U << (kGlyphWidth - 1 - column))) != 0U) {
                fillRect(img,
                         x + column * kGlyphScale,
                         y + row * kGlyphScale,
                         kGlyphScale,
                         kGlyphScale,
                         STUDENT_COLOR_TARGET);
            }
        }
    }
}

}  // namespace

bool studentSupportBegin()
{
    const esp_vfs_spiffs_conf_t config = {
        .base_path = "/fr",
        .partition_label = "fr",
        .max_files = 4,
        .format_if_mount_failed = true,
    };
    const esp_err_t mountResult = esp_vfs_spiffs_register(&config);
    if (mountResult != ESP_OK && mountResult != ESP_ERR_INVALID_STATE) {
        ESP_LOGE("student_support", "Cannot mount /fr: %s", esp_err_to_name(mountResult));
        return false;
    }

    errno = 0;
    if (std::remove(STUDENT_FACE_DB_PATH) != 0 && errno != ENOENT) {
        ESP_LOGE("student_support", "Cannot reset face database (errno=%d)", errno);
        return false;
    }
    ESP_LOGI("student_support", "Face database reset; mount point is /fr");
    return true;
}

void studentDrawRect(dl::image::img_t &img, int x1, int y1, int x2, int y2, uint16_t color)
{
    if (!isDrawable(img)) {
        return;
    }
    if (x1 > x2) {
        std::swap(x1, x2);
    }
    if (y1 > y2) {
        std::swap(y1, y2);
    }
    if (x2 < 0 || y2 < 0 || x1 >= static_cast<int>(img.width) || y1 >= static_cast<int>(img.height)) {
        return;
    }
    x1 = std::clamp(x1, 0, static_cast<int>(img.width) - 1);
    x2 = std::clamp(x2, 0, static_cast<int>(img.width) - 1);
    y1 = std::clamp(y1, 0, static_cast<int>(img.height) - 1);
    y2 = std::clamp(y2, 0, static_cast<int>(img.height) - 1);

    constexpr int lineWidth = 2;
    for (int offset = 0; offset < lineWidth; ++offset) {
        const int left = x1 + offset;
        const int right = x2 - offset;
        const int top = y1 + offset;
        const int bottom = y2 - offset;
        if (left > right || top > bottom) {
            break;
        }
        for (int x = left; x <= right; ++x) {
            setPixel(img, x, top, color);
            setPixel(img, x, bottom, color);
        }
        for (int y = top; y <= bottom; ++y) {
            setPixel(img, left, y, color);
            setPixel(img, right, y, color);
        }
    }
}

void studentDrawTargetTag(dl::image::img_t &img, int x, int y)
{
    if (!isDrawable(img)) {
        return;
    }
    constexpr int textLength = static_cast<int>(sizeof(kTagText) - 1U);
    constexpr int characterStep = (kGlyphWidth + kGlyphGap) * kGlyphScale;
    constexpr int tagWidth = textLength * characterStep - kGlyphGap * kGlyphScale + kTagPadding * 2;
    constexpr int tagHeight = kGlyphHeight * kGlyphScale + kTagPadding * 2;

    int tagX = std::clamp(x, 0, std::max(0, static_cast<int>(img.width) - tagWidth));
    int tagY = y - tagHeight;
    if (tagY < 0) {
        tagY = std::clamp(y, 0, std::max(0, static_cast<int>(img.height) - tagHeight));
    }
    fillRect(img, tagX, tagY, tagWidth, tagHeight, kTagBackground);
    for (int index = 0; index < textLength; ++index) {
        drawGlyph(img,
                  tagX + kTagPadding + index * characterStep,
                  tagY + kTagPadding,
                  glyphFor(kTagText[index]));
    }
}
