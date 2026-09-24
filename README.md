# ESP32S3_Vision

## 目标平台

基础题工具提供 Windows、macOS Apple Silicon 和 macOS Intel 使用流程。macOS 实机验证记录见下文。

提高题使用 Windows 或 macOS 上的 VS Code 与 Espressif IDF 扩展。

## 查看摄像头

推荐使用 Camera Viewer 启动器。请先在有 Internet 时从[仓库 GitHub Releases](https://github.com/Cooper3516833584/ESP32S3_Vision/releases/latest)下载当前版本，再连接 ESP32 热点：

- Windows：`Camera-Viewer-Windows.exe`
- macOS：下载并解压 `Camera-Viewer-macOS.zip`，双击其中的 `Camera Viewer.app`

电脑连接开发板的 `esp32s3cam-xxxx` Wi-Fi 后，双击启动器即可。它会检查设备并打开系统默认浏览器，不会读取或占用视频流。该 Wi-Fi 没有 Internet 属于正常现象。
Windows 发布版包含所需 .NET Runtime，不需要另行安装。

浏览器备用入口：

```text
http://192.168.4.1/
```

Windows 原 `CameraStreamViewer.exe` 仍保留为兼容工具。它与浏览器 Viewer 共用单客户端视频流，请勿与浏览器 Viewer 同时打开。

macOS 首次打开未签名应用时，在 Finder 中右键 `Camera Viewer.app` →“打开”→ 再确认“打开”。不要关闭 Gatekeeper。

## 基础题固定环境

- Arduino IDE 2.x
- esp32 by Espressif Systems 3.3.7
- Flash 4 MB，DIO 40 MHz，OPI PSRAM
- Windows：运行 `project/CameraWebServer/tools` 中的 `.cmd` 工具
- macOS：运行同一目录中带 `macOS` 字样的 `.command` 工具

## 提高题固定环境

- VS Code
- Espressif IDF 扩展
- ESP-IDF 5.5.5
- target：ESP32-S3 (`esp32s3`)

## 已验证环境

- 实机验证记录待补充；目前没有真实 Mac + ESP32-S3 的编译、烧录和浏览器 Viewer 验收记录。
- 本机执行过 Bash 静态检查、模拟 Arduino CLI 错误分支、浏览器 raw decoder、断线重连和 Raw/MJPEG 切换检查；这些不代表 Mac 实机验证。

新生 macOS 操作步骤见 [macOS 新生快速开始](新生AI辅助说明/macOS_新生快速开始.md)。
