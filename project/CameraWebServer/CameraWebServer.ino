#include "camera_base.h"

// ================================================================
// 主程序
// 摄像头、Wi-Fi AP 和视频推流已经封装完成。
// 视觉题只需在 processFrame() 中编写算法，不需要修改其他文件。
// ================================================================

void processFrame(const camera_fb_t *frame, void *userContext) {
  // 当前图像固定为 320 x 240 RGB565，每个像素占 16 位。
  uint16_t *pixels = reinterpret_cast<uint16_t *>(frame->buf);
  const int width = frame->width;
  const int height = frame->height;

  // ---------------- 视觉逻辑写在下面 ------------------
  // 像素 (x, y) 的访问方式：pixels[y * width + x]

  (void)pixels;
  (void)width;
  (void)height;
  (void)userContext;

  // frame 和 pixels 仅在本函数内有效，不要保存或归还 framebuffer。
}

void setup() {
  // 必须保留：注册视觉处理函数并启动摄像头和视频流基座。
  cameraBaseSetFrameProcessor(processFrame);
  cameraBaseBegin();

  // ---------------- 初始化代码写在下面 ----------------

}

void loop() {
  // 必须保留：让 ESP32 后台网络任务及时运行；该函数不会长时间阻塞。
  cameraBaseUpdate();

  // ---------------- 循环代码写在下面 ------------------

}
