#pragma once

#include <Arduino.h>
#include "esp_camera.h"

// 摄像头视频基座的公开接口。
// 只需要在 CameraWebServer.ino 中调用 cameraBaseBegin()，
// 不需要理解 Wi-Fi、摄像头驱动或 HTTP 推流的内部实现。

// 初始化串口、OV2640、ESP32 SoftAP 和 MJPEG 服务。
// 成功返回 true；失败原因会输出到 115200 波特率串口。
bool cameraBaseBegin();

// 在 Arduino loop() 中持续调用。该函数不会长时间阻塞。
void cameraBaseUpdate();

// 视觉帧处理回调。回调在 MJPEG 推流任务取得 framebuffer 后、发送前执行。
// frame 仅在回调期间有效，不要保存其指针，也不要调用 esp_camera_fb_return()。
// 当前底座固定传入 QVGA RGB565；回调可以直接读取和修改 frame->buf 像素。
// app_httpd.cpp 会在回调结束后编码成 JPEG；回调应尽快返回。
typedef void (*CameraBaseFrameProcessor)(const camera_fb_t *frame, void *userContext);
void cameraBaseSetFrameProcessor(CameraBaseFrameProcessor processor, void *userContext = nullptr);

// 供不使用上述回调的外部算法手动上报处理耗时；回调方式会自动上报。
void cameraBaseReportProcessingFrame(uint32_t processTimeUs);

// 可选状态接口，方便新生扩展自己的逻辑。
bool cameraBaseReady();
const char *cameraBaseWifiName();
sensor_t *cameraBaseSensor();
