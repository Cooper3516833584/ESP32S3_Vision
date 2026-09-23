#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法：
  bash build_locked.sh
  bash build_locked.sh --upload [--port /dev/cu.usbmodemXXXX]

选项：
  --upload       编译后烧录
  --port PORT    指定 macOS 串口；未指定时自动检测并询问
  --help         显示帮助
EOF
}

fail() { printf '\n错误：%s\n' "$1" >&2; exit 1; }

upload=0
port=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --upload) upload=1; shift ;;
    --port)
      [ "$#" -ge 2 ] || { usage >&2; fail "--port 后面需要填写串口路径。"; }
      port="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; fail "不支持的参数：$1" ;;
  esac
done

os_name=$(uname -s)
cpu_name=$(uname -m)
[ "$os_name" = "Darwin" ] || fail "此脚本用于 macOS。Windows 请使用仓库中的 .cmd 工具。"
case "$cpu_name" in
  arm64) cpu_label="Apple Silicon (arm64)" ;;
  x86_64) cpu_label="Intel (x86_64)" ;;
  *) cpu_label="$cpu_name" ;;
esac
printf '系统：macOS\nCPU：%s\n' "$cpu_label"

script_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$script_dir/.." && pwd)
build_dir="$project_dir/build/locked"
fqbn='esp32:esp32:esp32s3:FlashMode=dio,FlashSize=4M,PSRAM=opi,PartitionScheme=custom,DebugLevel=none,EraseFlash=all'

cli=""
for candidate in \
  "/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/arduino-cli" \
  "$HOME/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/arduino-cli"; do
  if [ -x "$candidate" ]; then cli="$candidate"; break; fi
done
if [ -z "$cli" ] && command -v arduino-cli >/dev/null 2>&1; then cli=$(command -v arduino-cli); fi
if [ -z "$cli" ]; then
  cat >&2 <<'EOF'
错误：没有找到 Arduino IDE 2.x。

请确认 Arduino IDE 已安装在“应用程序”文件夹。
macOS 正常位置：/Applications/Arduino IDE.app

安装 Arduino IDE 后重新运行此工具。本题不需要 Homebrew 或独立安装 Arduino CLI。
EOF
  exit 1
fi

core_json=$("$cli" core list --format json 2>&1) || { printf '%s\n' "$core_json" >&2; fail "无法读取 Arduino Core 列表。请检查 Arduino IDE 安装。"; }
core_version=$(printf '%s' "$core_json" | awk '
  /"id"[[:space:]]*:[[:space:]]*"esp32:esp32"/ { found=1 }
  found && /"installed_version"[[:space:]]*:/ {
    line=$0; sub(/^.*"installed_version"[[:space:]]*:[[:space:]]*"/, "", line); sub(/".*$/, "", line); print line; exit
  }
')
if [ -z "$core_version" ]; then
  cat >&2 <<'EOF'
错误：没有安装 ESP32 Core。

请打开 Arduino IDE → 工具 → 开发板 → 开发板管理器，
搜索 esp32，并安装 esp32 by Espressif Systems 3.3.7。
EOF
  exit 1
fi
if [ "$core_version" != "3.3.7" ]; then
  printf '错误：当前 ESP32 Core 版本是 %s。\n\n本题要求严格使用 esp32 by Espressif Systems 3.3.7。\n请在 Arduino IDE 的开发板管理器中切换到 3.3.7。\n' "$core_version" >&2
  exit 1
fi

if [ "$upload" -eq 1 ]; then
  if [ -n "$port" ]; then
    case "$port" in /dev/cu.*) ;; *) fail "串口路径应使用 macOS 的 /dev/cu.* 形式：$port" ;; esac
    [ -e "$port" ] || fail "指定的串口不存在：$port"
  else
    ports=()
    for candidate in /dev/cu.*; do
      [ -e "$candidate" ] || continue
      case "$candidate" in
        /dev/cu.Bluetooth-Incoming-Port) continue ;;
        *usbmodem*|*usbserial*|*SLAB_USBtoUART*|*wchusbserial*|*wch*|*usb*) ports+=("$candidate") ;;
      esac
    done
    if [ "${#ports[@]}" -eq 0 ]; then
      cat >&2 <<'EOF'
没有检测到可用的 USB 串口。

请检查：
1. ESP32-S3 是否已连接到 Mac；
2. USB 线是否支持数据；
3. Arduino IDE 的“工具 → 端口”中是否出现新设备；
4. 如果开发板使用 USB-UART 芯片，请先确认芯片型号，再判断是否需要驱动。

不知道 USB-UART 芯片型号时不要随便安装驱动。
EOF
      exit 1
    elif [ "${#ports[@]}" -eq 1 ]; then
      printf '检测到开发板串口：\n\n%s\n\n按回车使用该串口。如果这不是你的开发板，请输入 n：' "${ports[0]}"
      read -r answer
      if [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
        printf '请输入串口路径（例如 /dev/cu.usbmodem1101）：'
        read -r port
      else
        port=${ports[0]}
      fi
    else
      printf '检测到多个串口：\n\n'
      for i in "${!ports[@]}"; do printf '[%s] %s\n' "$((i + 1))" "${ports[$i]}"; done
      printf '\n请输入序号：'
      read -r selection
      case "$selection" in ''|*[!0-9]*) fail "串口序号无效。" ;; esac
      [ "$selection" -ge 1 ] && [ "$selection" -le "${#ports[@]}" ] || fail "串口序号超出范围。"
      port=${ports[$((selection - 1))]}
    fi
    case "$port" in /dev/cu.*) ;; *) fail "串口路径应使用 macOS 的 /dev/cu.* 形式：$port" ;; esac
    [ -e "$port" ] || fail "选择的串口不存在：$port"
  fi
fi

mkdir -p "$build_dir"
args=(compile --fqbn "$fqbn" --clean --build-path "$build_dir"
  --build-property build.flash_mode=dio
  --build-property build.img_freq=40m
  --build-property build.flash_freq=40m)
args+=("$project_dir")

if [ "$upload" -eq 1 ]; then printf '\n开始固定配置编译（稍后烧录到：%s）……\n' "$port"; else printf '\n开始固定配置编译……\n'; fi
set +e
"$cli" "${args[@]}"
compile_status=$?
set -e
if [ "$compile_status" -ne 0 ]; then
  printf '\n编译失败。上方 Arduino 输出包含真实错误。请把从第一处 error 到结束的完整内容发送给 AI。\n如果出现 bad CPU type in executable，请核对 Mac 芯片类型和 Arduino IDE 下载的架构版本。\n' >&2
  exit "$compile_status"
fi

check_image_header() {
  image_file=$1
  [ -f "$image_file" ] || fail "未生成预期固件：$image_file"
  header=$(od -An -tu1 -N4 "$image_file" | awk '{print $1, $3, $4}')
  set -- $header
  [ "$#" -eq 3 ] && [ "$1" -eq 233 ] && [ "$2" -eq 2 ] && [ $(( $3 & 15 )) -eq 0 ] || {
    printf '错误：拒绝使用生成的固件。\n检测到固件不是 ESP32-S3 / DIO / 40 MHz。\n请不要继续烧录。\n' >&2
    exit 1
  }
}

find_esptool() {
  board_properties=$("$cli" board details --fqbn "$fqbn" --show-properties 2>/dev/null || true)
  tools_root=$(printf '%s\n' "$board_properties" | awk -F= '$1 == "runtime.tools.esptool_py.path" {print $2; exit}')
  if [ -n "$tools_root" ] && [ -d "$tools_root" ]; then
    find "$tools_root" -type f \( -name esptool -o -name esptool.py -o -name esptool.exe \) -print 2>/dev/null | awk 'NR==1 {candidate=$0} END {print candidate}'
    return
  fi
  tools_root="$HOME/Library/Arduino15/packages/esp32/tools/esptool_py"
  [ -d "$tools_root" ] || return 1
  find "$tools_root" -type f \( -name esptool -o -name esptool.py -o -name esptool.exe \) -print 2>/dev/null | awk 'NR==1 {candidate=$0} END {print candidate}'
}

check_s3_image() {
  image_file=$1
  tool_file=$2
  set +e
  tool_output=$("$tool_file" image-info "$image_file" 2>&1)
  tool_status=$?
  set -e
  printf '%s\n' "$tool_output"
  [ "$tool_status" -eq 0 ] || fail "esptool 无法检查固件：$image_file"
  printf '%s\n' "$tool_output" | grep -E 'Detected image type: *ESP32-S3' >/dev/null || fail "拒绝使用固件：目标不是 ESP32-S3。"
  printf '%s\n' "$tool_output" | grep -E 'Chip ID: *9 \(ESP32-S3\)' >/dev/null || fail "拒绝使用固件：芯片 ID 不是 ESP32-S3。"
}

boot_image="$build_dir/CameraWebServer.ino.bootloader.bin"
app_image="$build_dir/CameraWebServer.ino.bin"
check_image_header "$boot_image"
check_image_header "$app_image"
esptool=$(find_esptool || true)
if [ -z "$esptool" ] || [ ! -x "$esptool" ]; then
  cat >&2 <<'EOF'
ESP32 Core 3.3.7 已检测到，但没有找到它附带的可执行 esptool。

请先在 Arduino IDE 中重新安装 esp32 by Espressif Systems 3.3.7，
然后重新运行本工具。
EOF
  exit 1
fi
check_s3_image "$boot_image" "$esptool"
check_s3_image "$app_image" "$esptool"

if [ "$upload" -eq 1 ]; then
  printf '\n固件配置验证通过，开始烧录到 %s……\n' "$port"
  set +e
  "$cli" upload --fqbn "$fqbn" --input-dir "$build_dir" --port "$port" "$project_dir"
  upload_status=$?
  set -e
  if [ "$upload_status" -ne 0 ]; then
    printf '\n烧录失败。上方保留了 Arduino CLI 完整输出。\n请把从“开始烧录”到当前行的完整输出发送给 AI，并提供：\n- 当前串口：%s\n- 开发板型号\n- 是否按过 BOOT / RESET\n- Arduino IDE 中是否能看到同一串口\n' "$port" >&2
    exit "$upload_status"
  fi
fi

printf '\n==================================================\n编译成功\n\nLOCKED CONFIG VERIFIED\nESP32-S3 / DIO / 40 MHz / 4 MB / OPI PSRAM\n\nBuild directory:\n%s\n' "$build_dir"
if [ "$upload" -eq 1 ]; then printf '\n烧录成功\n串口：%s\n' "$port"; fi
printf '==================================================\n'
