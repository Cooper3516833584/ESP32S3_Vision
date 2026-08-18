#include "camera_base.h"

#include <WiFi.h>
#include "esp_wifi.h"
#include "board_config.h"
#include "project_config.h"

bool startCameraServer();
void setupLedFlash();

#if !defined(CONFIG_IDF_TARGET_ESP32S3)
#error "This camera base must be built for ESP32-S3"
#endif

namespace {

char apSsid[33] = {0};
bool baseReady = false;

bool startAccessPoint() {
  const uint16_t chipSuffix = static_cast<uint16_t>(ESP.getEfuseMac() & 0xFFFF);
  snprintf(apSsid, sizeof(apSsid), "%s-%04X", AP_SSID_PREFIX, chipSuffix);

  const IPAddress localIp(AP_IP_OCTET_1, AP_IP_OCTET_2, AP_IP_OCTET_3, AP_IP_OCTET_4);
  const IPAddress gateway = localIp;
  const IPAddress subnet(255, 255, 255, 0);

  WiFi.mode(WIFI_AP);
  WiFi.setSleep(false);
  if (!WiFi.softAPConfig(localIp, gateway, subnet)) {
    Serial.println("AP network configuration failed");
    return false;
  }
  if (!WiFi.softAP(apSsid, AP_PASSWORD, AP_CHANNEL, false, AP_MAX_CLIENTS)) {
    Serial.println("AP start failed");
    return false;
  }

  // HT20 在教室等干扰环境中通常比 HT40 抖动更小。
  esp_wifi_set_ps(WIFI_PS_NONE);
  esp_wifi_set_bandwidth(WIFI_IF_AP, WIFI_BW_HT20);
  esp_wifi_set_protocol(WIFI_IF_AP, WIFI_PROTOCOL_11B | WIFI_PROTOCOL_11G | WIFI_PROTOCOL_11N);
  WiFi.setTxPower(WIFI_POWER_15dBm);
  return true;
}

bool startCamera() {
  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = CAMERA_XCLK_HZ;
  config.frame_size = FRAMESIZE_QVGA;  // 招新统一评测分辨率：320 x 240
  // 视觉回调可以直接读取和修改 RGB565 像素；推流端会在回调结束后
  // 把处理后的 framebuffer 编码成 JPEG。
  config.pixel_format = PIXFORMAT_RGB565;
  config.grab_mode = CAMERA_GRAB_LATEST;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = CAMERA_DEFAULT_JPEG_QUALITY;
  config.fb_count = CAMERA_FRAME_BUFFERS;

  const esp_err_t error = esp_camera_init(&config);
  if (error != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x\n", error);
    return false;
  }

  sensor_t *sensor = esp_camera_sensor_get();
  if (sensor == nullptr) {
    Serial.println("Camera sensor was not found");
    return false;
  }

  // 这一批相同板子的图像左右方向相反，统一在传感器端镜像修正。
  // 在传感器端完成不会增加 ESP32 的逐帧软件处理开销。
  sensor->set_hmirror(sensor, 1);
  sensor->set_framesize(sensor, FRAMESIZE_QVGA);

#if defined(CAMERA_MODEL_ESP32S3_EYE)
  sensor->set_vflip(sensor, 1);
#endif

#if defined(LED_GPIO_NUM)
  setupLedFlash();
#endif
  return true;
}

}  // namespace

bool cameraBaseBegin() {
  if (baseReady) {
    return true;
  }

  Serial.begin(115200);
  Serial.setDebugOutput(false);
  Serial.println();

  if (!psramFound()) {
    Serial.println("ERROR: PSRAM not detected");
    return false;
  }
  if (!startCamera()) {
    return false;
  }

  sensor_t *sensor = esp_camera_sensor_get();
  Serial.println("Hardware information:");
  Serial.printf("Chip      : %s\n", ESP.getChipModel());
  Serial.printf("PSRAM     : %u KB\n", ESP.getPsramSize() / 1024U);
  Serial.printf("Flash     : %u KB\n", ESP.getFlashChipSize() / 1024U);
  Serial.printf("Camera    : PID 0x%04X\n", sensor->id.PID);
  Serial.println("Resolution: 320 x 240");
  Serial.println("Format    : RGB565 (stream encoded as JPEG)");
  Serial.printf("Buffers   : %u\n", CAMERA_FRAME_BUFFERS);
  Serial.printf("XCLK      : %u MHz\n", CAMERA_XCLK_HZ / 1000000U);

  if (!startAccessPoint()) {
    Serial.println("Cannot start camera server without Wi-Fi AP");
    return false;
  }

  if (!startCameraServer()) {
    Serial.println("Camera server start failed");
    return false;
  }
  baseReady = true;

  Serial.println();
  Serial.println("Camera base ready (320 x 240, horizontal mirror enabled)");
  Serial.printf("Wi-Fi name : %s\n", apSsid);
  Serial.printf("Password   : %s\n", AP_PASSWORD);
  Serial.println("Viewer     : tools/CameraStreamViewer.exe (default IP 192.168.4.1)");
  Serial.println("Metrics    : http://192.168.4.1/metrics");
  return true;
}

void cameraBaseUpdate() {
  // HTTP 和摄像头运行在后台任务；短暂 yield 给系统并保持学生 loop() 灵敏。
  delay(1);
}

bool cameraBaseReady() {
  return baseReady;
}

const char *cameraBaseWifiName() {
  return apSsid;
}

sensor_t *cameraBaseSensor() {
  return esp_camera_sensor_get();
}
