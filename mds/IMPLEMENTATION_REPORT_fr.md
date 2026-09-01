# Implementation Report

## Versions

- Build date: 2026-08-30
- Target: ESP32-S3
- ESP-IDF: 5.5.5 (manifest accepts `>=5.5.2,<5.6`)
- Arduino-ESP32: 3.3.7
- esp32-camera: 2.1.7
- human_face_detect: 0.4.2
- human_face_recognition: 0.3.2
- esp-dl resolved transitively: 3.3.10

The requested pair `human_face_detect ==0.5.0` and `human_face_recognition ==0.3.2` cannot be resolved together. The recognition component declares `human_face_detect ~0.4.1`; therefore the project pins the newest compatible 0.4.x release, 0.4.2, rather than removing version constraints. The constraint is recorded both in the manifest comments and in `dependencies.lock`.

ESP-IDF 5.5.2 was not installed on this host. Version 5.5.5 is inside the requested 5.5.x range and is the exact IDF version recorded by the lock file generated on this host.

## Reference audit

The reference was read without rewriting it. Git status at delivery still reports only the pre-existing user modification:

```text
M project/CameraWebServer/sketch.yaml
```

Preserved reference behavior:

- ESP32-S3-EYE pin mapping and sensor orientation
- QVGA 320 × 240, RGB565, 20 MHz XCLK
- two PSRAM framebuffers, `CAMERA_GRAB_LATEST`
- SoftAP `esp32s3cam-%04X`, password `11223344`, channel 6, address `192.168.4.1`
- HT20 and Wi-Fi power saving disabled
- `/raw`, `/stream`, `/metrics` and the original HTTP control routes
- synchronous frame callback and processing metrics
- RGB565 big-endian interpretation used by the raw codec

Unmodified migrated files were hash-compared with the reference and match exactly: `board_config.h`, `camera_pins.h`, `project_config.h`, and `raw_frame_codec.h`.

## Files added

- `CMakeLists.txt`
- `.gitignore`
- `sdkconfig.defaults`
- `dependencies.lock`
- `README.md`
- `IMPLEMENTATION_REPORT.md`
- `main/CMakeLists.txt`
- `main/idf_component.yml`
- `main/main.cpp`
- `main/student.h`
- `main/student.cpp`
- `main/student_support.h`
- `main/student_support.cpp`
- `partitions.csv`
- `tools/CameraStreamViewer.exe`

`dependencies.lock` is intentionally retained for repeatable component resolution. `managed_components` and generated build files are ignored; they were deleted once and successfully recreated from the defaults, manifest, lock file, and local component cache during the final clean-build test.

## Files modified from reference

- `camera_base.cpp`: only strict ESP-IDF C++ format-specifier compatibility changes (`%lu` for the platform's unsigned-long size values).
- `app_httpd.cpp`: removed the obsolete unused `fb_gfx.h` include, corrected strict format specifiers for 32-bit metrics, and changed one generic unsupported-control log message so the final source scan is clean.
- Arduino `.ino` entry logic was migrated into `main/main.cpp`; network, camera, stream and raw-codec implementations were not redesigned.

The copied Viewer is byte-identical to the reference:

```text
SHA-256 E1C11665CB4006BF9E345525061BB1D6AFC0440E78E0D7B7845A424CCF086220
```

## Student interface

Only `main/student.cpp` needs student editing.

The final file is an empty, compilable skeleton containing only `studentInit()` and `studentProcessFrame()`. It contains no detector, recognizer, enrollment policy, identity loop, cache, tracker, task, or reference solution.

The bridge wraps the camera framebuffer without copying:

```text
data     = frame->buf
width    = frame->width
height   = frame->height
pix_type = DL_IMAGE_PIX_TYPE_RGB565BE
```

It calls `studentProcessFrame(img)` synchronously. `img.data` is valid only during that call. Existing processing timing encloses the registered callback and continues to update `processing_fps` and `last_processing_ms`.

Public support consists of:

- `STUDENT_FACE_DB_PATH` (`/fr/face.db`)
- `STUDENT_COLOR_FACE`
- `STUDENT_COLOR_TARGET`
- `studentDrawRect(...)`
- `studentDrawTargetTag(...)`

Drawing writes RGB565BE bytes explicitly, clips coordinates, accepts reversed endpoints, safely ignores fully off-screen rectangles, uses a fixed two-pixel outline, allocates no dynamic memory, and renders only the six required 5 × 7 glyphs for `TARGET`.

## Storage and startup

Startup order is:

```text
serial/log initialization
mount SPIFFS partition `fr` at `/fr`
remove `/fr/face.db` (missing file is accepted)
studentInit()
register the synchronous bridge
initialize camera
start SoftAP and HTTP servers
```

SPIFFS uses `format_if_mount_failed = true` and `max_files = 4`. If storage initialization fails, the camera base can still start but the student callback is not registered, preventing student recognition code from using an unavailable database path.

## Fixed component API verification

A temporary compile probe was built and then deleted. It verified visibility and compilation of:

- `HumanFaceDetect(HumanFaceDetect::MSRMNP_S8_V1)`
- `HumanFaceRecognizer(STUDENT_FACE_DB_PATH, HumanFaceFeat::MFN_S8_V1)`
- `HumanFaceDetect::run(img)`
- `HumanFaceRecognizer::enroll(img, detections)`
- `HumanFaceRecognizer::recognize(img, detections)`
- recognition result field `id`

Source inspection of the locked components found:

- Detector results are `std::list<dl::detect::result_t>` and contain `box` plus face keypoints.
- Recognizer construction accepts a database path, feature-model enum, and optional lazy-load flag.
- `enroll` returns `esp_err_t`.
- `recognize` returns `std::vector<dl::recognition::result_t>`; each result has `uint16_t id` and `float similarity`.
- For an empty detection list, recognition returns no results.
- For one detection, recognition processes that face.
- For multiple detections, recognition still processes only one detection. In 0.3.2 the `std::max_element` comparator is reversed relative to its apparent intent, so the implementation effectively selects the smallest-area box. It must not be interpreted as automatic per-face recognition.

No temporary probe or private reference student solution remains in the target directory.

## Model configuration

The generated `sdkconfig` restored the requested choices from `sdkconfig.defaults`:

- `CONFIG_FLASH_HUMAN_FACE_DETECT_MSRMNP_S8_V1=y`
- `CONFIG_HUMAN_FACE_DETECT_MSRMNP_S8_V1=y`
- `CONFIG_HUMAN_FACE_DETECT_MODEL_IN_FLASH_RODATA=y`
- `CONFIG_FLASH_HUMAN_FACE_FEAT_MFN_S8_V1=y`
- `CONFIG_HUMAN_FACE_FEAT_MFN_S8_V1=y`
- `CONFIG_HUMAN_FACE_FEAT_MODEL_IN_FLASH_RODATA=y`

The default student skeleton does not instantiate the models, so the linker removes their unused code and model blobs. When a student creates the configured detector and recognizer, the selected rodata model packages are linked automatically without a CMake change.

## Build result

Flash configuration has been normalized to 4 MB in this repair. No firmware build, hardware test, or full face-recognition image-size validation was performed in this repair. Any earlier generated artifacts used the previous Flash layout and are not evidence that the complete face-recognition firmware fits the new 4 MB configuration.

## Partition usage

```text
nvs       0x009000  0x005000   20 KiB
app0      0x010000  0x3C0000 3840 KiB
fr        0x3D0000  0x020000  128 KiB
coredump  0x3F0000  0x010000   64 KiB
```

The partition table ends at `0x400000` (4 MiB). Full face-recognition firmware size and 4 MB capacity sufficiency were not validated in this repair.

## Hardware test

Hardware runtime verification: not performed in this repair.

The host lists COM4, COM6, COM9, COM15, COM16, and COM17, but access to device identity metadata was denied. No port could be safely identified as the requested board, so no flash, serial-monitor, camera, PSRAM, reset-loop, SPIFFS reboot, SoftAP, or physical inference claim is made.

## Viewer regression

Static regression: PASS.

- Viewer hash is identical to the reference.
- `/raw` remains on port 81 and retains RGB332 + PackBits framing.
- `/stream` remains on port 81.
- `/metrics` remains on port 80 and includes video plus processing measurements.
- QVGA, RGB565 byte interpretation, horizontal orientation settings, buffer count and grab mode are preserved.

Runtime Viewer display, drawing color/orientation, and network reconnection were not verified because a board could not be safely selected.

## Known limitations

- Hardware and camera runtime remain unverified.
- The fixed recognition component processes only one face from a multi-face detection list; student code must account for that API behavior.
- Frame processing is intentionally synchronous. Expensive inference lowers video FPS.
- The empty student skeleton intentionally contains no completed face-recognition behavior.
- Component restoration without `managed_components` requires either registry access or a populated local component cache; the final clean restoration succeeded from the populated cache while the registry was unavailable.

## Final checklist

- [x] Reference directory not rewritten
- [x] ESP-IDF project targets ESP32-S3
- [x] Arduino setup/loop autostart enabled
- [x] CPU 240 MHz, DIO 40 MHz, 4 MB Flash, OPI PSRAM 80 MHz configured in defaults
- [x] Original camera, SoftAP, raw stream, MJPEG stream, metrics and Viewer preserved
- [x] Student edits only `main/student.cpp`
- [x] Frame bridge is zero-copy RGB565BE and synchronous
- [x] SPIFFS `/fr` mount and per-boot face database removal implemented before `studentInit()`
- [x] Clipped RGB565BE rectangle and fixed `TARGET` helpers implemented without allocation
- [x] MSR + MNP and MFN S8 v1 configured in Flash rodata
- [x] Fixed API signatures, identity field and multi-detection behavior inspected
- [x] Temporary probe/reference/debug code removed
- [x] Final source scan for the prohibited identity label returned zero matches outside generated dependencies/artifacts
- [x] Partition table ends at 0x400000 and retains `/fr`
- [ ] Full face-recognition firmware size and 4 MB capacity sufficiency validated
- [ ] Hardware flash/runtime/Viewer/inference/reboot behavior verified
