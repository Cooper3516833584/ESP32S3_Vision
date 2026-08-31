# 你只需要修改：main/student.cpp

这是江西招新用的 ESP32-S3 人脸识别提高题底座。摄像头、Wi-Fi、视频推流、运行指标、数据库挂载和绘图函数都已准备好；完成基础提高题时，不需要修改其他源文件。

第一次实现请先阅读 [FACE_RECOGNITION_GUIDE.md](FACE_RECOGNITION_GUIDE.md)。其中包含分阶段实现路线、锁定版本的 ESP-DL API 注意事项、多人识别方法、调试流程和验收清单。

## 1. 环境与首次构建

推荐使用 VS Code、Espressif IDF 扩展和 ESP-IDF 5.5.x。本工程已用 ESP-IDF 5.5.5 完成干净构建验证。

1. 在 VS Code 中打开本目录。
2. 执行 `ESP-IDF: Set Espressif Device Target`，选择 `esp32s3`。
3. 执行 `ESP-IDF: Build your project`。
4. 选择开发板串口，执行 `ESP-IDF: Flash your project`。
5. 执行 `ESP-IDF: Monitor your device`，串口波特率为 115200。

命令行等价操作：

```powershell
idf.py set-target esp32s3
idf.py build
idf.py -p COMx flash monitor
```

硬件配置固定为 ESP32-S3、4 MB DIO 40 MHz Flash、OPI PSRAM 80 MHz、CPU 240 MHz。摄像头固定输出 320 × 240 RGB565，framebuffer 位于 PSRAM。

首次编译需要联网，由 ESP-IDF Component Manager 自动下载工程依赖。

## 2. 连接视频

烧录并复位后，开发板建立 2.4 GHz SoftAP：

- Wi-Fi 名称：`esp32s3cam-xxxx`，末四位因板卡而异
- 密码：`11223344`
- 开发板地址：`192.168.4.1`

电脑连接该 Wi-Fi 后运行 `tools\CameraStreamViewer.exe`。查看器使用 `http://192.168.4.1:81/raw`，并可回退到 `http://192.168.4.1:81/stream`。运行指标位于 `http://192.168.4.1/metrics`。

## 3. 学生接口

`studentInit()` 在启动时调用一次，适合创建检测器、识别器和长期状态。不要在每一帧里反复创建模型对象。

`studentProcessFrame(dl::image::img_t &img)` 在视频发送前同步调用。传入图像固定为：

- `img.width == 320`
- `img.height == 240`
- `img.pix_type == dl::image::DL_IMAGE_PIX_TYPE_RGB565BE`

`img.data` 只在本次 `studentProcessFrame()` 调用期间有效。不要保存该指针，也不要自行取得或归还摄像头 framebuffer。

底座在每次启动时挂载 `/fr` 并删除上次的人脸库。识别器数据库路径直接使用：

```cpp
STUDENT_FACE_DB_PATH
```

它的值为 `/fr/face.db`。因此，本次启动后第一张满足你判断条件并成功录入的人脸，可以作为本次运行的目标。

## 4. 绘图接口

所有函数都直接修改当前 RGB565BE 图像，已经处理负坐标、越界、端点颠倒和字节序，不会动态分配内存。

普通人脸框：

```cpp
studentDrawRect(img, x1, y1, x2, y2, STUDENT_COLOR_FACE);
```

目标人物使用绿色框和固定标签：

```cpp
studentDrawRect(img, x1, y1, x2, y2, STUDENT_COLOR_TARGET);
studentDrawTargetTag(img, x1, y1);
```

非目标人物只需画普通框，不需要显示身份文字。

## 5. ESP-DL API 提示

可在 `student.cpp` 直接包含下列官方组件头文件，不需要修改 CMake：

```cpp
#include "human_face_detect.hpp"
#include "human_face_recognition.hpp"
```

- `HumanFaceDetect` 用于检测；本工程默认模型为 `MSRMNP_S8_V1`。
- `HumanFaceRecognizer` 提供 `enroll()` 和 `recognize()`；本工程默认特征模型为 `MFN_S8_V1`。
- 识别结果元素包含身份 `id` 和相似度 `similarity`。
- 模型均从 Flash rodata 加载。

固定版本的 recognition API 不会把一个包含多个人脸的 detection list 自动转换为“每张脸各一个识别结果”。多人场景应检查它对 detection list 的实际处理，并按每个检测框分别判断身份。

建议搜索：

```text
ESP-DL HumanFaceDetect
ESP-DL human face detect example
ESP-DL HumanFaceRecognizer
HumanFaceRecognizer enroll recognize
dl::image::img_t
ESP32-S3 ESP-DL face recognition
```

优先阅读 Espressif 官方 GitHub、Espressif Component Registry 和 ESP-DL 官方文档。

## 6. 题目最低行为

1. 检测画面中的人脸。
2. 启动后自动把第一张满足条件的人脸录入为目标。
3. 后续能够判断目标人物。
4. 多人出现时能够找出目标人物。
5. 所有人脸都有检测框。
6. 只有目标人物显示 `TARGET`。

正确但帧率较低也算完成。模型推理本来就比较重；优化时可从减少昂贵模型调用次数入手，例如隔帧检测/识别、结果或框缓存、多人轮询、IoU 和简单跟踪。独立任务与异步流水线不属于基础要求。

## 7. 版本说明

依赖已记录在 `dependencies.lock`。主要版本为 Arduino-ESP32 3.3.7、esp32-camera 2.1.7、human_face_recognition 0.3.2、human_face_detect 0.4.2。

原任务包建议 human_face_detect 0.5.0，但 human_face_recognition 0.3.2 的官方依赖约束是 `human_face_detect ~0.4.1`，两者不能同时解析。工程因此锁定兼容范围内的最新 0.4.x 版本 0.4.2，没有取消版本约束。可在 [官方组件依赖页](https://components.espressif.com/components/espressif/human_face_recognition/versions/0.3.2/dependencies?language=en) 查看该约束。

## 8. 常见问题

- 系统提示板卡 Wi-Fi“无 Internet”是正常现象。
- 若串口报告未检测到 PSRAM，检查板型、供电和 PSRAM 配置。
- 若摄像头初始化失败，检查摄像头排线和板卡型号。
- 当前板卡默认不要插存储卡，以免影响启动。
- `processing_fps` 和 `last_processing_ms` 只统计 `studentProcessFrame()`；同步算法越慢，视频 FPS 越低，这是预期行为。
