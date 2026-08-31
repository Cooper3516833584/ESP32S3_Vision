# ESP32-S3 人脸识别项目实现指南

本文面向第一次接触 ESP32、摄像头和 ESP-DL 的同学。目标是在不修改底座其他模块的前提下，只完成 `main/student.cpp`，实现以下行为：

1. 检测画面中的所有人脸并画框。
2. 开机后自动录入第一张满足条件的人脸，作为本次运行的目标人物。
3. 后续判断每一张人脸是否为目标人物。
4. 所有人脸都有框，只有目标人物显示绿色框和 `TARGET` 标签。
5. 多人同时出现时，仍能找出目标人物。

> 这是一份实现路线和调试指南，不是可直接提交的完整答案。建议每完成一个阶段就编译、烧录和测试，不要一次写完所有逻辑再排错。

## 1. 开始前先理解底座

底座已经完成以下工作：

- 初始化 ESP32-S3、摄像头、PSRAM 和 Wi-Fi 热点。
- 取得 320 × 240、RGB565 格式的摄像头帧。
- 提供浏览器视频流、原始视频流和运行指标。
- 挂载人脸数据库分区 `/fr`。
- 在每次启动时删除上一次运行留下的人脸数据库。
- 把当前摄像头帧传给学生函数。
- 提供人脸框和 `TARGET` 标签绘制函数。

因此基础任务只允许修改：

```text
main/student.cpp
```

不要修改摄像头驱动、HTTP 服务、分区表、组件版本和 `sdkconfig`。如果修改底座其他文件后出现问题，很难区分是算法错误还是底座被破坏。

程序的数据流如下：

```text
摄像头取得一帧
        ↓
封装为 dl::image::img_t
        ↓
studentProcessFrame(img)
        ├── 人脸检测：画面里有哪些脸？
        ├── 人脸录入：把第一位合格人物存为目标
        ├── 人脸识别：当前脸是否与数据库中的目标相似？
        └── 绘制：普通框或绿色 TARGET 框
        ↓
视频流发送修改后的图像
```

## 2. 环境、构建与连接

推荐环境：

- VS Code
- Espressif IDF 扩展
- ESP-IDF 5.5.x；本工程验证版本为 5.5.5
- 目标芯片 `esp32s3`

在 VS Code 中依次执行：

1. `ESP-IDF: Set Espressif Device Target`，选择 `esp32s3`。
2. `ESP-IDF: Build your project`。
3. 选择正确串口。
4. `ESP-IDF: Flash your project`。
5. `ESP-IDF: Monitor your device`。

命令行等价命令：

```powershell
idf.py set-target esp32s3
idf.py build
idf.py -p COMx flash monitor
```

其中 `COMx` 要替换为开发板实际串口，例如 `COM6`。首次构建需要联网下载依赖。

烧录并重启后，电脑连接开发板热点：

- Wi-Fi：`esp32s3cam-xxxx`
- 密码：`11223344`
- 开发板地址：`192.168.4.1`

然后运行：

```text
tools\CameraStreamViewer.exe
```

运行指标可在浏览器访问：

```text
http://192.168.4.1/metrics
```

## 3. 两个必须实现的学生函数

`main/student.cpp` 中已经有两个空函数。

### 3.1 `studentInit()`

它在开机时调用一次，适合：

- 创建人脸检测器。
- 创建人脸识别器。
- 初始化“是否已录入目标”等长期状态。

模型对象创建成本较高，不能放到每帧调用的 `studentProcessFrame()` 中。

### 3.2 `studentProcessFrame(img)`

它在每帧发送前同步调用。输入固定为：

```cpp
img.width == 320
img.height == 240
img.pix_type == dl::image::DL_IMAGE_PIX_TYPE_RGB565BE
```

特别注意：

- `img.data` 指向当前摄像头 framebuffer。
- 指针只在本次函数调用期间有效，不能保存到全局变量。
- 不要自己申请、取得或归还摄像头 framebuffer。
- 绘图函数会直接修改当前图像，修改结果会出现在视频中。
- 该函数是同步执行的，算法耗时越长，视频帧率越低。

## 4. 人脸检测、录入和识别有什么区别

这三个概念不要混在一起。

### 4.1 检测 Detection

检测回答：画面中哪里有人脸？

检测结果是一个列表，每个元素包含：

- `box`：人脸矩形框，顺序为 `x1, y1, x2, y2`。
- `keypoint`：眼睛、鼻子、嘴角等关键点坐标。
- `score`：检测置信度。

检测不能告诉你这个人是谁。

### 4.2 录入 Enrollment

录入会根据人脸关键点对齐图像、提取人脸特征，并把特征存进数据库。

本题的数据库路径已经定义为：

```cpp
STUDENT_FACE_DB_PATH
```

不要手写另一个路径。底座每次启动会删除旧数据库，所以目标人物每次重启都要重新录入。

### 4.3 识别 Recognition

识别会提取当前人脸的特征，再与数据库中的特征比较，返回：

- `id`：数据库记录编号。
- `similarity`：相似度。

相似度越高，越可能是同一个人。不能只判断“结果不为空”，还应设置合理阈值。

## 5. 第一阶段：只做人脸检测和画框

先不要急着做识别。第一阶段只验证模型和坐标是否正确。

在 `student.cpp` 中加入需要的头文件：

```cpp
#include "human_face_detect.hpp"
#include "human_face_recognition.hpp"

#include <list>
#include <vector>
```

把长期状态放进匿名命名空间，避免与工程其他文件发生重名：

```cpp
namespace {

HumanFaceDetect *detector = nullptr;
HumanFaceRecognizer *recognizer = nullptr;
bool targetEnrolled = false;

} // namespace
```

在 `studentInit()` 中创建对象。工程已经在 Flash rodata 中选择了对应模型：

```cpp
detector = new HumanFaceDetect(HumanFaceDetect::MSRMNP_S8_V1);
recognizer = new HumanFaceRecognizer(
    STUDENT_FACE_DB_PATH,
    HumanFaceFeat::MFN_S8_V1);
targetEnrolled = false;
```

在每帧函数中先检查指针，再运行检测器：

```cpp
if (detector == nullptr || recognizer == nullptr) {
    return;
}

std::list<dl::detect::result_t> &faces = detector->run(img);
```

遍历 `faces`。访问矩形框之前必须检查 `face.box.size() >= 4`，然后调用：

```cpp
studentDrawRect(
    img,
    face.box[0], face.box[1],
    face.box[2], face.box[3],
    STUDENT_COLOR_FACE);
```

本阶段验收：

- 没有人时不画框。
- 一个人时框基本包住脸。
- 多个人时每个人都有框。
- 人靠近边缘时程序不崩溃。

如果本阶段不稳定，不要继续写识别逻辑。

## 6. 第二阶段：设计可靠的自动录入条件

“检测到第一张脸就立即录入”看似简单，但容易把远处的小脸、侧脸、残缺脸或多人场景中的错误人物录入数据库。

基础版建议只在以下条件全部满足时录入：

1. 当前恰好检测到一张脸。
2. 矩形框至少包含四个坐标。
3. 关键点至少包含五个点，也就是十个整数值。
4. 人脸宽度和高度都不小于约 60 像素。
5. 当前尚未成功录入目标。

可以编写一个辅助函数：

```cpp
bool isGoodEnrollmentFace(const dl::detect::result_t &face)
{
    // TODO：检查 box 和 keypoint 的长度。
    // TODO：计算人脸框宽度和高度。
    // TODO：返回尺寸是否满足录入要求。
}
```

满足条件后，不要把完整多人列表交给录入函数，应创建只包含这张脸的列表：

```cpp
std::list<dl::detect::result_t> oneFace{face};
esp_err_t result = recognizer->enroll(img, oneFace);
```

只有当：

```cpp
result == ESP_OK
```

时，才能把 `targetEnrolled` 设置为 `true`。录入失败时应该下帧继续尝试。

建议加入日志：

```cpp
#include "esp_err.h"
#include "esp_log.h"
```

例如在录入成功和失败时输出状态。不要每帧大量打印日志，否则串口输出本身也会影响帧率。

本阶段验收：

- 开机后无人时不录入。
- 两个人同时出现时不录入。
- 单人距离太远时不录入。
- 合格单人靠近后只录入一次。
- 录入失败不会被误认为成功。

## 7. 第三阶段：识别目标人物

成功录入后，对检测到的每张脸分别识别。

### 7.1 为什么必须逐脸调用

本工程锁定的 `human_face_recognition 0.3.2` 中，`recognize(img, faces)` 在 `faces` 含多张脸时不会返回“一张脸对应一个结果”。它只选择列表中的一张脸进行识别。

因此下面这种思路是错误的：

```cpp
// 错误思路：不能认为结果数量与 faces 数量一一对应。
auto matches = recognizer->recognize(img, faces);
```

正确思路是遍历检测结果，每次创建单脸列表：

```cpp
for (const dl::detect::result_t &face : faces) {
    if (face.keypoint.size() < 10) {
        continue;
    }

    std::list<dl::detect::result_t> oneFace{face};
    std::vector<dl::recognition::result_t> matches =
        recognizer->recognize(img, oneFace);

    // TODO：检查 matches 是否为空。
    // TODO：读取 matches.front().similarity。
    // TODO：根据阈值记录这张脸是否为目标。
}
```

### 7.2 相似度阈值

可以先从 `0.60F` 左右开始测试：

```cpp
constexpr float TARGET_THRESHOLD = 0.60F;
```

阈值不是越高越好：

- 太低：陌生人容易被误判为目标。
- 太高：目标人物换角度或光线后容易识别失败。

最终阈值应通过多人、不同距离、不同光照的实际测试确定。调试时可以低频打印 `id` 和 `similarity`，观察目标与非目标的分布，而不是凭感觉反复改数字。

### 7.3 保存每张脸的判断结果

推荐建立一个与 `faces` 顺序对应的标记数组，例如：

```cpp
std::vector<uint8_t> isTarget(faces.size(), 0);
```

识别第 `index` 张脸成功后设置：

```cpp
isTarget[index] = 1;
```

识别循环结束后，再按相同顺序遍历 `faces` 进行绘图。务必保证索引每次循环只增加一次，并且没有越界。

## 8. 第四阶段：按身份绘图

建议先完成所有检测和识别，再统一绘图。不要先画粗框再把已修改的图像交给识别模型。

普通人脸：

```cpp
studentDrawRect(img, x1, y1, x2, y2, STUDENT_COLOR_FACE);
```

目标人物：

```cpp
studentDrawRect(img, x1, y1, x2, y2, STUDENT_COLOR_TARGET);
studentDrawTargetTag(img, x1, y1);
```

一种清晰的规则是：

- 先给所有合法人脸画普通框。
- 如果该脸是目标，再用绿色框覆盖普通框并绘制标签。

绘图函数已经处理负坐标、超出画面和端点颠倒；但访问 `face.box[0]` 等元素前，学生代码仍必须检查数组长度。

刚刚录入成功的那一帧可以直接把录入的人脸标为目标，不必在同一帧再次运行识别模型。这样既避免重复推理，也能立即给出绿色反馈。

## 9. 推荐的每帧处理顺序

完整逻辑建议按以下顺序组织：

```text
1. 检查 detector 和 recognizer 是否已初始化
2. 运行人脸检测
3. 创建与人脸数量相同的“是否为目标”标记
4. 如果尚未录入：
   4.1 只接受“单人 + 合格尺寸 + 关键点完整”
   4.2 创建单脸列表并调用 enroll
   4.3 仅在 ESP_OK 时更新状态
5. 如果已经录入且本帧不是刚录入：
   5.1 逐张脸创建单脸列表
   5.2 分别调用 recognize
   5.3 根据结果非空且相似度达标设置标记
6. 遍历检测结果：
   6.1 所有人脸画普通框
   6.2 目标人物覆盖绿色框并画 TARGET
7. 返回，绝不保存 img.data
```

建议把录入条件、结果判断等小逻辑拆成辅助函数。函数名应说明目的，例如 `isGoodEnrollmentFace()`，不要使用 `a()`、`tmp()` 这类无法表达含义的名称。

## 10. 状态与生命周期

理解变量存活时间可以避免很多崩溃。

适合长期保存的内容：

- 检测器指针。
- 识别器指针。
- 是否已经录入目标。
- 优化阶段使用的帧计数器或缓存框。

只能在当前帧使用的内容：

- `img.data`。
- `detector->run(img)` 返回的检测结果引用。
- 根据当前检测结果创建的单脸列表和匹配结果。

检测结果引用通常由模型对象内部管理，下一次调用检测器后可能被覆盖，因此不能把它的地址保存起来跨帧使用。若高级优化确实需要缓存，应复制自己需要的坐标值，而不是保存引用。

## 11. 调试方法

### 11.1 一次只验证一个阶段

推荐顺序：

1. 工程原始骨架能编译。
2. 模型对象能初始化。
3. 单人检测框正确。
4. 多人检测框正确。
5. 自动录入条件正确。
6. 单人目标识别正确。
7. 非目标不会被误判。
8. 多人时目标识别正确。
9. 重启后数据库按预期重置。

### 11.2 使用串口日志

适合记录的事件：

- 模型初始化完成。
- 检测到的人脸数量发生变化。
- 开始尝试录入。
- 录入成功或错误码。
- 低频输出识别 ID 和相似度。

不要在双重像素循环、每个关键点或每一帧无条件打印大量内容。

### 11.3 查看处理性能

访问：

```text
http://192.168.4.1/metrics
```

重点关注：

- `processing_fps`：学生处理函数每秒完成次数。
- `last_processing_ms`：最近一帧学生处理耗时。

人脸检测和特征提取本来就比较重，基础版本帧率不高是正常现象。应先保证行为正确，再优化速度。

## 12. 必做测试清单

提交前至少完成以下人工测试：

| 编号 | 场景 | 预期结果 |
|---|---|---|
| A | 画面中无人 | 无框、不录入、不崩溃 |
| B | 重启后远处出现一张小脸 | 有检测能力，但尺寸不足时不录入 |
| C | 重启后合格单人正对镜头 | 成功录入，并显示绿色框和 `TARGET` |
| D | 目标人物再次出现 | 能识别为目标 |
| E | 只有非目标人物 | 有普通框，不显示 `TARGET` |
| F | 目标与非目标同时出现 | 每张脸有框，只有目标为绿色并有标签 |
| G | 两个非目标人物同时出现 | 都是普通框 |
| H | 人脸位于图像边缘 | 正常裁剪绘图，不崩溃 |
| I | 断电重启 | 旧数据库被清除，重新等待目标录入 |
| J | 连续运行数分钟 | 无重启、无明显持续内存下降 |

多人测试不能省略。单人识别成功并不代表多人逻辑正确。

## 13. 常见错误及处理

### 13.1 IDF 版本不匹配

错误类似：

```text
project depends on idf (>=5.5.2,<5.6)
```

说明当前终端使用的不是 ESP-IDF 5.5.x。切换到 5.5.x 环境，不要擅自删除工程版本约束。

### 13.2 找不到 ESP-DL 头文件

确认包含的是：

```cpp
#include "human_face_detect.hpp"
#include "human_face_recognition.hpp"
```

并确认首次依赖下载完成。底座已经配置组件，不需要自行往 `main/CMakeLists.txt` 填绝对路径。

### 13.3 固件超过 Flash 分区

工程已经使用 4 MB Flash 专用分区和体积优化，并只保留模型所需的 RGB565 到 RGB888 转换。不要重新启用无关模型、无关像素格式或性能优先编译配置。

可执行：

```powershell
idf.py size
```

查看固件大小。应用分区为 3840 KiB，仍需保留一定余量。

### 13.4 检测到脸但录入失败

检查：

- 是否真的只有一张脸。
- 人脸是否太小、太偏或被遮挡。
- `keypoint.size()` 是否足够。
- 是否把空列表或错误的检测结果传给 `enroll()`。
- 串口是否报告 `/fr` 挂载失败。

### 13.5 单人识别正常，多人识别错误

最常见原因是把整个 `faces` 列表一次传给 `recognize()`，然后错误地认为返回结果与人脸一一对应。必须为每张脸创建独立的单元素检测列表。

### 13.6 所有人都被判断成目标

检查：

- 是否只判断了 `matches.empty()`，却没有检查 `similarity`。
- 阈值是否过低。
- `isTarget` 标记是否每帧重新初始化。
- 人脸索引是否与检测列表顺序一致。

### 13.7 目标本人经常识别失败

检查录入时的脸是否足够清晰、正面和明亮。然后记录相似度，适度调整阈值。不要一次把阈值大幅降低，否则可能增加陌生人误判。

### 13.8 视频很卡

确认模型对象只在 `studentInit()` 创建一次。基础版本每张脸每帧都进行特征提取，帧率降低是预期现象。先通过全部功能测试，再进行下一节优化。

### 13.9 画框颜色或位置不正确

必须使用底座提供的 `studentDrawRect()`，不要把 RGB565 当作普通 16 位主机字节序直接写入。确认矩形坐标顺序是 `x1, y1, x2, y2`。

## 14. 完成基础功能后的优化方向

优化应建立在功能正确和可重复测试的基础上。

### 14.1 隔帧识别

检测可以每帧运行，较昂贵的识别每隔若干帧运行一次，中间帧复用短期身份状态。间隔过大会造成标签明显滞后。

### 14.2 多人轮询识别

多人时每帧只识别其中一张脸，并在后续帧轮换，可降低单帧耗时。需要使用 IoU、中心点距离或简单跟踪，保证身份结果与正确的人脸框对应。

### 14.3 检测结果缓存

每隔若干帧运行检测，中间帧显示上次的框。人物移动较快时框会漂移，因此需要权衡速度与实时性。

### 14.4 减少每帧动态分配

基础版的 `std::list` 和 `std::vector` 使用简单，但多人逐帧创建容器会产生动态分配。高级实现可以复用容器或限制最大处理人脸数，但不能破坏 ESP-DL API 所要求的数据结构。

### 14.5 不建议一开始做异步任务

把摄像头、推理和绘图拆到多个 FreeRTOS 任务会引入 framebuffer 生命周期、锁、队列和帧覆盖问题。它不属于基础要求，也不适合作为第一次实现的起点。

## 15. 代码质量检查

提交前检查：

- [ ] 只修改了 `main/student.cpp`。
- [ ] 检测器和识别器只初始化一次。
- [ ] 没有保存 `img.data` 或检测结果引用。
- [ ] 访问 `box`、`keypoint`、`matches.front()` 前检查了长度或是否为空。
- [ ] 只有录入返回 `ESP_OK` 才更新状态。
- [ ] 多人识别采用逐脸单元素列表。
- [ ] 每帧重新初始化身份标记。
- [ ] 先推理、后绘图。
- [ ] 所有人脸有框，只有目标人物显示 `TARGET`。
- [ ] 没有在每帧重新创建模型。
- [ ] 没有随意更改组件版本、分区或 Flash 配置。
- [ ] 构建成功且固件没有超过应用分区。
- [ ] 完成了单人、非目标、多人、边缘和重启测试。

## 16. 推荐学习顺序

遇到困难时，按以下顺序查资料：

1. 先读本工程 `README.md`、`main/student.h` 和 `main/student_support.h`。
2. 理解 C++ 的指针、引用、容器遍历、对象生命周期和返回值检查。
3. 查阅 Espressif 官方 ESP-DL 文档和组件源码。
4. 搜索锁定版本的 API 名称，不要直接照搬其他大版本示例。
5. 用串口日志和 `/metrics` 验证自己的假设。

推荐关键词：

```text
ESP-DL HumanFaceDetect
ESP-DL HumanFaceRecognizer enroll recognize
dl::detect::result_t box keypoint
dl::image::img_t RGB565BE
ESP32-S3 ESP-DL face recognition
```

最终目标不是“让代码偶尔认出一次”，而是能够解释每个状态、每个返回值和多人处理为什么正确，并用测试证明实现稳定。
