#include <Arduino.h>

#include "camera_base.h"
#include "student.h"
#include "student_support.h"

bool studentSupportBegin();

namespace {

void processFrame(const camera_fb_t *frame, void *userContext)
{
    (void)userContext;
    if (frame == nullptr || frame->buf == nullptr || frame->format != PIXFORMAT_RGB565) {
        return;
    }

    dl::image::img_t img = {
        .data = frame->buf,
        .width = static_cast<uint16_t>(frame->width),
        .height = static_cast<uint16_t>(frame->height),
        .pix_type = dl::image::DL_IMAGE_PIX_TYPE_RGB565BE,
    };
    studentProcessFrame(img);
}

}  // namespace

void setup()
{
    Serial.begin(115200);
    Serial.setDebugOutput(false);
    if (!studentSupportBegin()) {
        Serial.println("Student storage initialization failed");
        cameraBaseBegin();
        return;
    }
    studentInit();
    cameraBaseSetFrameProcessor(processFrame);
    cameraBaseBegin();
}

void loop()
{
    cameraBaseUpdate();
}
