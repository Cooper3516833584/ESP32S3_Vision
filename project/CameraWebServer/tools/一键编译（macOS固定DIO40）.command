#!/bin/bash
tool_dir="$(cd "$(dirname "$0")" && pwd)"
bash "$tool_dir/build_locked.sh"
result=$?
if [ "$result" -eq 0 ]; then echo "结果：编译成功。"; else echo "结果：编译失败（退出码 $result）。"; fi
printf '按回车关闭此窗口。'
read -r _
exit "$result"
