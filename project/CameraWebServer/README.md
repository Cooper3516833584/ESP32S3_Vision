# ESP32-S3 低延迟视频流教学框架

这个工程让 ESP32-S3 自己建立 2.4 GHz Wi-Fi AP。电脑直接连接开发板，
不经过手机热点或路由器转发，并用配套 Windows 查看器观看 MJPEG 视频流。

## 1. 快速使用

### 固定构建入口（招新时必须使用）

不要直接点击任意版本 Arduino IDE 的“上传”按钮。IDE 可以用于编辑代码，但最终
构建和烧录必须运行：

- `tools\一键编译（固定DIO40）.cmd`
- `tools\一键烧录（固定DIO40）.cmd`

烧录脚本会询问串口号，例如 `COM5`。新生需要先安装 Arduino IDE 2.x，并在
Boards Manager 中安装 `esp32 by Espressif Systems 3.3.7`。脚本会自动寻找 IDE
内置的 Arduino CLI、检查核心版本，然后强制生成 DIO、40MHz、16MB 镜像。构建结束后
脚本会检查 bootloader 和应用镜像头；不是 DIO 40MHz 就直接报错，不会作为合格
产物使用。

工程仍是标准 Arduino 草图，新生也可以直接用自己的 IDE 编译和烧录；此时使用
的是其 IDE 提供的官方菜单设置，通常
只有 DIO 80MHz，不保证生成 40MHz 镜像。不能阻止使用者故意绕开固定脚本，直接
选择其他板卡设置自行构建。评测时只接受固定脚本生成的固件。

Arduino IDE 推荐设置：

- Board：`ESP32S3 Dev Module`
- Flash Mode：`DIO 40MHz`（这块样板在 80MHz 下读取 Flash 不稳定）
- Flash Size：`16MB (128Mb)`
- PSRAM：`OPI PSRAM`
- Partition Scheme：`Custom`
- Core Debug Level：`None`
- Erase All Flash Before Sketch Upload：首次烧录时选择 `Enabled`

烧录并复位后，串口监视器选择 115200 波特率。终端会显示类似：

```text
Camera AP ready
Wi-Fi name : CameraLab-A1B2
Password   : camera123
Viewer     : tools/CameraStreamViewer.exe (default IP 192.168.4.1)
Metrics    : http://192.168.4.1/metrics
```

电脑连接这个 Wi-Fi。系统提示“无 Internet”是正常的，请保持连接，然后双击
`tools\CameraStreamViewer.exe`，使用默认 IP `192.168.4.1`。查看器只显示全屏视频，
左上角 FPS 由电脑端按实际解码成功的 JPEG 帧计算，按 `Esc` 退出。浏览器根页面
不显示视频，避免通过开发者工具直接修改显示数字。

> 注意：Arduino ESP32 3.3.7 官方未附带 ESP32-S3 的 40MHz Bootloader。
> 当前电脑中的 `DIO 40MHz` 是本地扩展选项。正式批量用于招新前，应使用
> ESP-IDF 构建真正的 40MHz Bootloader，或更换能够稳定运行官方 80MHz 配置的板子。

## 2. 新生主要修改哪里

新生主要编辑 `CameraWebServer.ino`。摄像头、Wi-Fi AP 和 HTTP 推流已经封装，
默认主程序只有两个必须保留的调用：

```cpp
void setup() {
  cameraBaseBegin();
  // 在这里写自己的初始化代码
}

void loop() {
  cameraBaseUpdate();
  // 在这里写自己的循环代码
}
```

什么都不增加时，程序就是当前的视频基座：建立 AP、采集经过水平镜像修正的
320 × 240 JPEG，并供电脑端查看器显示视频和实际接收 FPS。

文件职责：

- `CameraWebServer.ino`：新生主程序和主要编辑区。
- `camera_base.h`：基座公开的少量函数，可查看并调用。
- `camera_base.cpp`：摄像头、引脚、SoftAP 和推流启动的封装实现，仍保留源码。
- `app_httpd.cpp`：低延迟 MJPEG 服务实现。
- `project_config.h`：网络、JPEG 质量和性能参数。
- `board_config.h`、`camera_pins.h`：这一批相同硬件的型号和引脚配置。

`project_config.h` 中可调整：

- `AP_SSID_PREFIX`：Wi-Fi 名称前缀；程序会自动附加芯片编号。
- `AP_PASSWORD`：Wi-Fi 密码，至少 8 个字符。
- `AP_CHANNEL`：2.4 GHz 信道，教室里建议只在 1、6、11 中选择。
- `CAMERA_DEFAULT_JPEG_QUALITY`：JPEG 数值越小画质越高、流量越大。
- `STREAM_SINGLE_CLIENT`：是否限制为一个视频客户端。

为保证所有人评测条件一致，分辨率在基座中固定为 `FRAMESIZE_QVGA`（320 × 240）。
需要做开放实验时仍可修改 `camera_base.cpp`，但正式 FPS 评测应恢复为 320 × 240。

## 3. 为什么这个版本延迟更低

数据路径只有：

```text
摄像头 JPEG → ESP32 帧缓存 → HTTP MJPEG → 电脑
```

关键策略：

- ESP32 建立 AP，去掉手机热点的客户端转发和高延迟抖动。
- 使用摄像头原生 JPEG，不在 CPU 上做 RGB→JPEG 转换。
- `CAMERA_GRAB_LATEST`：发送受阻后直接取最新画面，不补发旧画面。
- 两个 PSRAM 帧缓存：摄像头采集与网络发送可以流水工作。
- TCP `TCP_NODELAY`：边界和帧头立即发出，不等待小包合并。
- 400 ms 流发送超时：故障连接会被快速断开，避免陈旧画面不断排队。
- 默认只允许一个流客户端，防止多个浏览器争抢带宽和帧缓存。
- HTTP 禁用缓存，浏览器不会复用旧图像。

无线链路、自动曝光和浏览器解码仍会产生少量延迟，因此不存在绝对“零延迟”。
这个框架的目标是避免可控的软件排队和热点转发延迟。

## 4. 性能观测

打开 <http://192.168.4.1/metrics> 可以看到：

- `fps`：最近一帧对应的瞬时帧率。
- `last_frame_ms`：最近一帧采集加发送耗时。
- `last_frame_bytes`：最近 JPEG 帧大小。
- `send_failures`：网络发送失败次数。
- `free_heap` / `min_free_heap`：内部内存状态。
- `free_psram`：PSRAM 剩余量。
- `ap_clients`：连接 AP 的设备数量。

若帧大小突然增加，通常是画面细节、噪声或 JPEG 质量导致；若帧大小稳定但
`last_frame_ms` 突增，通常是无线干扰或客户端接收变慢。

### 独立验收（不要相信网页上显示的数字）

面试官在自己的电脑上运行单独保管的可信副本（不要放进发给新生的工程）：

```powershell
python verify_stream.py --seconds 10 --min-fps 20 --max-p95-ms 100
```

脚本直接读取 `:81/stream`，统计实际收到的 JPEG 帧数、帧间隔 P95、最大卡顿、
码率和不同帧比例。候选人只修改网页上的 FPS 数字不会改变验收结果。测试时让
摄像头拍摄移动物体，以便重复帧检测有意义。

招新验收使用的脚本应由面试官单独保管并现场运行，不要使用候选人提交目录中的
脚本副本。若需要更强的防篡改，应由外部设备测量视频，而不是把秘密或判定逻辑
藏在候选人能够读取和修改的固件里。

## 5. 硬件注意事项

- 使用稳定 5V、至少 1A 的电源；CH340 只连接 TX、RX、GND。
- 所有设备必须共地，杜邦线尽量短。
- 当前板子的内存卡会干扰启动，默认不要插卡。
- 插拔摄像头、内存卡和串口线之前先断电。
- 如果摄像头是 GC2640 而不是 OV2640，它不能直接输出 JPEG，不适合这个高帧率
  MJPEG 路径；应改用 OV2640 或为 RGB 数据设计其他传输方案。

## 6. 适合新生继续做的功能

1. 给 `/metrics` 增加 RSSI、运行时间和平均 FPS。
2. 在网页增加“低延迟/高画质”一键档位。
3. 增加拍照保存，但不要在推流热路径中同步写 SD 卡。
4. 使用 WebSocket 发送传感器数据，与 MJPEG 视频端口分离。
5. 增加 AP 信道扫描，在启动时自动选择干扰较少的信道。
