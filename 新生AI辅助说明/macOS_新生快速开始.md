# ESP32-S3 CAM 招新题 macOS 快速开始

## 1. 先确认你的 Mac 是 Apple Silicon 还是 Intel

打开 Apple 菜单 → 关于本机。显示 Apple M1/M2/M3/M4/M5 等型号时，下载 Apple Silicon 软件；显示 Intel 时，下载 Intel 版。Apple Silicon 优先使用原生版本。

## 2. 安装 Arduino IDE 2.x

下载并安装对应芯片架构的 Arduino IDE 2.x，首次打开一次。基础题不需要 Homebrew、Python 或单独的 Arduino CLI。

## 3. 安装 ESP32 Core 3.3.7

Arduino IDE → 工具 → 开发板 → 开发板管理器，搜索 `esp32`，安装 `esp32 by Espressif Systems 3.3.7`。一键工具会严格检查版本，不会替你升级或降级。

## 4. 第一次连接开发板

使用支持数据的 USB 线连接开发板。在 Arduino IDE → 工具 → 端口查看新出现的串口。macOS 常见形式为 `/dev/cu.usbmodem...` 或 `/dev/cu.usbserial...`。

如果没有新串口，先查明开发板使用 ESP32-S3 原生 USB 还是 USB-UART 芯片。不知道芯片型号时，提供板卡正反面照片和商品型号，不要随便安装驱动。

## 5. 基础题一键编译

打开仓库的 `project/CameraWebServer`，在 Finder 双击 `tools/一键编译（macOS固定DIO40）.command`。脚本调用 Arduino IDE 自带 CLI，使用仓库固定配置，并检查 ESP32-S3、DIO、40 MHz、4 MB、OPI PSRAM。窗口会保留编译输出，按回车关闭。

## 6. 基础题一键烧录

连接开发板后双击 `tools/一键烧录（macOS固定DIO40）.command`。检测到一个串口时按回车确认；有多个时输入编号。也可在终端执行：

```bash
bash "project/CameraWebServer/tools/build_locked.sh" --upload --port /dev/cu.usbmodemXXXX
```

如果 macOS 首次阻止 `.command`，可在 Finder 中右键该文件 →“打开”→ 再确认打开。不要关闭 Gatekeeper 或系统安全设置。

如果 Finder 提示文件没有执行权限，可在仓库根目录的终端执行一次：

```bash
chmod +x "project/CameraWebServer/tools/build_locked.sh"
chmod +x "project/CameraWebServer/tools/"*.command
```

不需要 sudo。

## 7. Mac 串口是什么样

Windows 常见 `COM5`；macOS 常见 `/dev/cu.usbmodem1101`、`/dev/cu.usbserial-0001`。Finder 烧录入口会自动筛选 USB 串口，也可以用 Arduino IDE → 工具 → 端口确认。需要查连接前后变化时，可看“系统信息 → USB”或运行 `ls /dev/cu.*`。

## 8. 连接 ESP32 Wi-Fi

烧录并启动后，在 Mac Wi-Fi 菜单连接 `esp32s3cam-xxxx`，密码 `11223344`。系统提示该 Wi-Fi 没有 Internet 属于正常现象；做题时保持连接这个 SSID。如果开发板重启后 Mac 自动切回其他 Wi-Fi，请重新选择 `esp32s3cam-xxxx`。

## 9. 在浏览器查看画面

连接 `esp32s3cam-xxxx` 后，在 Safari 或 Chrome 地址栏输入：

```text
http://192.168.4.1/
```

页面默认使用低延迟 Raw 流，也可切换 MJPEG 兼容模式。页面显示视频、学生画在 framebuffer 上的标记、处理指标和断线状态。

目前 GitHub 没有可下载的 `Camera Viewer.app` 发布包；完成题目不需要它。

## 10. 提高题 ESP-IDF 5.5.5

安装 macOS 版 VS Code 和 Espressif IDF 扩展，在扩展设置向导中配置 ESP-IDF 5.5.5。打开 `project/CameraWebServer_for_fr`，确认目标芯片 `esp32s3`，选择 `/dev/cu.*` 串口，然后依次执行 Build、Flash、Monitor。Monitor 波特率为 115200。程序启动后仍连接 `esp32s3cam-xxxx`，浏览器打开 `http://192.168.4.1/` 查看人脸框和 TARGET。

## 11. 常见问题

- **Arduino IDE 或工具报告 `bad CPU type in executable`**：先确认 Mac 芯片类型、Arduino IDE 是否下载了 Apple Silicon 版，以及错误来自 IDE 本身还是具体工具。不要先重装全部环境。Rosetta 仅作为某个必需 Intel-only 工具的后备方案。
- **没有串口**：确认数据线、Arduino IDE 的端口列表和开发板 USB 芯片型号；不知道芯片时先提供照片和商品型号，不要猜驱动。
- **构建提示 Core 版本不对**：检查开发板管理器中 `esp32 by Espressif Systems` 是否恰为 3.3.7。
- **查看器提示其他 Viewer 占用**：关闭其他打开视频的浏览器标签页和视频软件；Windows 兼容工具 `CameraStreamViewer.exe` 也会占用视频流。然后点“重新连接”。
- **浏览器打不开页面**：确认当前 Wi-Fi 是 `esp32s3cam-xxxx`，再检查地址是否为 `http://192.168.4.1/`。开发板刚复位时等它重启；Mac 若切回其他 Wi-Fi，需重新选择热点。
- **页面打开但没有视频**：记录页面上的连接状态，关闭其他 Viewer 或浏览器视频标签页，再点“重新连接”。
- **烧录失败**：保留完整 CLI 输出，并记录串口、板卡型号、是否按过 BOOT/RESET、Arduino IDE 是否显示同一串口。不要只凭错误末尾判断驱动或线材问题。

## 12. 发给 AI 排错时需要提供什么

先说明基础题或提高题、macOS 版本、Apple Silicon 或 Intel、开发板准确型号、操作步骤和完整错误输出。若是查看画面问题，提供当前 Wi-Fi 名称、浏览器访问 `http://192.168.4.1/` 的结果、页面连接状态与截图。烧录问题附串口路径；摄像头/热点问题附从复位开始的完整 115200 日志和开发板照片；画面问题附当前学生代码。不要让 AI 猜硬件、接口或报错原因；每次先排一个问题。
