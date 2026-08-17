# ESP32-S3 低延迟视频流底座

这个工程让 ESP32-S3 建立 2.4 GHz Wi-Fi AP，并把摄像头的 QVGA JPEG 画面通过
MJPEG 发送给电脑。新生拿到工程后的基本流程是：

1. 编译
2. 烧录
3. 连接开发板 Wi-Fi
4. 打开 `tools\CameraStreamViewer.exe`
5. 在 `CameraWebServer.ino` 中继续写代码

## 1. 编译与烧录

招新测试时使用固定脚本：

- `tools\一键编译（固定DIO40）.cmd`
- `tools\一键烧录（固定DIO40）.cmd`

烧录脚本会询问串口号，例如 `COM5`。电脑需要先安装 Arduino IDE 2.x，并在
Boards Manager 中安装 `esp32 by Espressif Systems 3.3.7`。脚本使用 Arduino IDE
内置的 Arduino CLI，根据 `esp32:esp32:esp32s3` 生成 bootloader 和应用固件，并固定：

- 芯片：ESP32-S3
- Flash Mode：DIO
- Flash Frequency：40 MHz
- Flash Size：16 MB
- PSRAM：OPI PSRAM
- Partition Scheme：Custom
- Core Debug Level：None

构建完成后，脚本会检查 bootloader 和应用镜像的 DIO、40 MHz 镜像头，并使用
ESP32 Core 自带的 esptool 确认两个镜像的目标芯片都是 ESP32-S3。

## 2. 连接与查看视频

烧录并复位后，串口监视器选择 115200 波特率。启动信息会显示芯片、PSRAM、
Flash、摄像头 PID、分辨率、格式、缓冲区数量和 XCLK，随后显示类似：

```text
Camera base ready (320 x 240, horizontal mirror enabled)
Wi-Fi name : esp32s3cam-A1B2
Password   : 11223344
Viewer     : tools/CameraStreamViewer.exe (default IP 192.168.4.1)
Metrics    : http://192.168.4.1/metrics
```

电脑连接这个 Wi-Fi。系统提示“无 Internet”是正常的，请保持连接。开发板地址固定为
`192.168.4.1`。

### 视频效果与 FPS 查看

电脑连接开发板 Wi-Fi 后，运行：

`tools\CameraStreamViewer.exe`

查看器会显示实时摄像头画面，并在左上角显示电脑端实际成功接收并解码的 JPEG 视频 FPS。

招新测试时直接使用该查看器观察：

- 视频是否能够持续正常显示
- 实际显示 FPS
- 是否存在明显卡顿
- 后续视觉识别结果是否能够实时更新

查看器网络异常后会自动重连，按 `Esc` 退出。

## 3. 新生主要修改位置

新生主要编辑 `CameraWebServer.ino`。默认主程序只有两个需要保留的调用：

```cpp
void setup() {
  cameraBaseBegin();

  // 学生初始化代码
}

void loop() {
  cameraBaseUpdate();

  // 学生代码
}
```

主要文件职责：

- `CameraWebServer.ino`：新生主程序和主要编辑区。
- `camera_base.h`：底座公开接口。
- `camera_base.cpp`：摄像头、SoftAP 和推流启动。
- `app_httpd.cpp`：HTTP、MJPEG 和简单运行指标。
- `project_config.h`：网络、JPEG 质量和低延迟参数。
- `board_config.h`、`camera_pins.h`：板卡型号和摄像头引脚。

`AP_CHANNEL` 保持手动配置。教室环境如果干扰明显，可以在 1 / 6 / 11 中修改。

## 4. 视频参数与数据路径

默认视频路径保持简单：

```text
摄像头 JPEG → esp_camera_fb_get() → MJPEG → CameraStreamViewer.exe
```

固定的主要参数是：

- 分辨率：QVGA（320 × 240）
- 格式：JPEG
- JPEG quality：15（数值越小画质越高、数据越大）
- 帧缓存：2 个，位于 PSRAM
- Grab mode：`CAMERA_GRAB_LATEST`
- XCLK：20 MHz
- Wi-Fi：HT20、关闭省电
- TCP：`TCP_NODELAY`、400 ms 发送超时、单视频客户端

本项目硬件要求 ESP32-S3 带 8 MB PSRAM；未检测到 PSRAM 时底座会直接停止启动。

## 5. 运行指标与后续视觉算法

打开 <http://192.168.4.1/metrics> 可以查看：

- `stream_active`、`ap_clients`
- `frames`、`send_failures`
- `last_frame_ms`、`last_frame_bytes`、`fps`
- `free_heap`、`min_free_heap`、`free_psram`
- `uptime_ms`
- `processing_fps`、`last_processing_ms`

视频 FPS 反映 MJPEG 推流情况；最终视觉功能还应关注算法实际处理 FPS。算法每处理完
一帧后可调用：

```cpp
cameraBaseReportProcessingFrame(processTimeUs);
```

未调用时，`processing_fps` 和 `last_processing_ms` 保持为 `0`。

推流线程会持续调用 `esp_camera_fb_get()`。后续实现色块识别或人脸识别时，不建议在
多个任务中同时长期取帧；应先统一设计取帧和算法处理方式。本底座暂不加入共享
framebuffer、回调或消息队列。

## 6. 常见硬件注意事项

- 使用稳定 5 V、至少 1 A 的电源；CH340 连接 TX、RX、GND，并确保所有设备共地。
- 杜邦线尽量短，插拔摄像头、内存卡和串口线之前先断电。
- 当前板子的内存卡会干扰启动，默认不要插卡。
- 本底座需要能够原生输出 JPEG 的摄像头；当前配置使用 OV2640。
- 若串口显示 PSRAM、摄像头或 HTTP Server 启动失败，先检查板卡配置、供电和排线。
