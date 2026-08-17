#pragma once

// ================================================================
// 网络、画质和性能参数集中放在这个文件中。
// ================================================================

// ESP32 会建立自己的 2.4 GHz Wi-Fi。最终名称会附加芯片后四位，
// 例如 CameraLab-A1B2，方便教室里同时使用多块板。
#define AP_SSID_PREFIX "esp32s3cam"
#define AP_PASSWORD "11223344"  // WPA2 密码至少 8 个字符
#define AP_CHANNEL 6             // 拥挤时只建议尝试 1、6、11
#define AP_MAX_CLIENTS 2         // 一个看视频，另一个用于调试

// 固定访问地址：http://192.168.4.1
#define AP_IP_OCTET_1 192
#define AP_IP_OCTET_2 168
#define AP_IP_OCTET_3 4
#define AP_IP_OCTET_4 1

// 招新统一使用 QVGA（320 x 240）+ JPEG 15。
// JPEG quality 数值越小画质越高、数据越大；建议范围 12~20。
#define CAMERA_DEFAULT_JPEG_QUALITY 15
#define CAMERA_FRAME_BUFFERS 2
#define CAMERA_XCLK_HZ 20000000

// 只允许一个 MJPEG 客户端，避免多个浏览器互相拖慢。
#define STREAM_SINGLE_CLIENT 1

// 慢客户端最多阻塞发送的毫秒数。快速断开故障 TCP 流，避免一次无线丢包
// 被重传和长超时放大成数秒钟的旧画面冻结。
#define STREAM_SEND_TIMEOUT_MS 400
