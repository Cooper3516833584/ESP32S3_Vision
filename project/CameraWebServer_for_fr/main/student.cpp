#include "student.h"
#include "student_support.h"

void studentInit()
{
    // 程序启动时调用一次，适合初始化模型和长期状态。
}

void studentProcessFrame(dl::image::img_t &img)
{
    // 每收到一帧调用一次。img.data 只在本次调用期间有效。
    (void)img;
}
