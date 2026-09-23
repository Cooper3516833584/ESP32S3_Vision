# ESP32S3_Vision

## 支持平台

基础题：Windows、macOS Apple Silicon、macOS Intel。

提高题：Windows、macOS（使用 VS Code 与 Espressif IDF 扩展）。

## 查看摄像头

推荐：连接开发板的 `esp32s3cam-xxxx` Wi-Fi 后，用 Safari、Chrome 或 Edge 打开：

```text
http://192.168.4.1/
```

该 Wi-Fi 没有 Internet 属于正常现象。Windows 原有 `CameraStreamViewer.exe` 仍保留。

## 基础题固定环境

- Arduino IDE 2.x
- esp32 by Espressif Systems 3.3.7
- Flash 4 MB，DIO 40 MHz，OPI PSRAM
- macOS 用户运行 `project/CameraWebServer/tools` 中的 `.command` 工具

## 提高题固定环境

- VS Code
- Espressif IDF 扩展
- ESP-IDF 5.5.5
- target：ESP32-S3 (`esp32s3`)

新生 macOS 操作步骤见 [macOS 新生快速开始](新生AI辅助说明/macOS_新生快速开始.md)。
