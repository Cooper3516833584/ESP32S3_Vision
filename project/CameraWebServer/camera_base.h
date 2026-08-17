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

// 可选：视觉算法每处理完一帧后调用，用于在 /metrics 中显示算法处理 FPS。
void cameraBaseReportProcessingFrame(uint32_t processTimeUs);

// 可选状态接口，方便新生扩展自己的逻辑。
bool cameraBaseReady();
const char *cameraBaseWifiName();
sensor_t *cameraBaseSensor();
