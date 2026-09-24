import AppKit
import Darwin
import Foundation

private let viewerURL = URL(string: "http://192.168.4.1/")!
private let healthURL = URL(string: "http://192.168.4.1/health")!
private let viewerMarker = "<meta name=\"esp32s3-vision-viewer\" content=\"1\">"

private enum ProbeResult {
    case ready
    case unavailable
    case wrongDevice
}

private func isValidHealthResponse(statusCode: Int, data: Data) -> Bool {
    guard statusCode == 200,
          let object = try? JSONSerialization.jsonObject(with: data),
          let value = object as? [String: Any],
          let ok = value["ok"] as? Bool,
          let device = value["device"] as? String,
          let viewer = value["viewer"] as? Int else {
        return false
    }
    return ok && device == "ESP32S3_Vision" && viewer == 1
}

private func isValidViewerPage(statusCode: Int, data: Data) -> Bool {
    guard statusCode == 200, let html = String(data: data, encoding: .utf8) else {
        return false
    }
    return html.contains(viewerMarker)
}

private func probeDevice(completion: @escaping (ProbeResult) -> Void) {
    var request = URLRequest(url: healthURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2.0)
    request.httpMethod = "GET"
    request.setValue("close", forHTTPHeaderField: "Connection")

    URLSession.shared.dataTask(with: request) { data, response, error in
        if error != nil {
            completion(.unavailable)
            return
        }
        guard let http = response as? HTTPURLResponse, let body = data else {
            completion(.unavailable)
            return
        }
        if isValidHealthResponse(statusCode: http.statusCode, data: body) {
            completion(.ready)
            return
        }

        // A 404 may come from firmware flashed before /health existed. Check only the
        // short root page marker; never touch the video-stream endpoints while probing.
        guard http.statusCode == 404 else {
            completion(.wrongDevice)
            return
        }
        var pageRequest = URLRequest(url: viewerURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2.0)
        pageRequest.httpMethod = "GET"
        pageRequest.setValue("close", forHTTPHeaderField: "Connection")
        URLSession.shared.dataTask(with: pageRequest) { pageData, pageResponse, pageError in
            if pageError != nil {
                completion(.unavailable)
                return
            }
            guard let pageHTTP = pageResponse as? HTTPURLResponse, let pageBody = pageData else {
                completion(.unavailable)
                return
            }
            completion(isValidViewerPage(statusCode: pageHTTP.statusCode, data: pageBody) ? .ready : .wrongDevice)
        }.resume()
    }.resume()
}

@main
final class CameraViewerApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var retryButton: NSButton!
    private var reopenButton: NSButton!

    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            let valid = Data("{\"ok\":true,\"device\":\"ESP32S3_Vision\",\"viewer\":1}".utf8)
            let invalid = Data("{\"ok\":true,\"device\":\"other\",\"viewer\":1}".utf8)
            guard isValidHealthResponse(statusCode: 200, data: valid),
                  !isValidHealthResponse(statusCode: 200, data: invalid),
                  !isValidHealthResponse(statusCode: 503, data: valid),
                  isValidViewerPage(statusCode: 200, data: Data(viewerMarker.utf8)),
                  !isValidViewerPage(statusCode: 200, data: Data("not our viewer".utf8)) else {
                fputs("Camera Viewer self-test failed\n", stderr)
                exit(1)
            }
            print("Camera Viewer probe self-test passed")
            return
        }

        let application = NSApplication.shared
        let delegate = CameraViewerApp()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        checkDevice()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 330),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
        window.title = "Camera Viewer"
        window.center()

        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        let title = NSTextField(labelWithString: "ESP32-S3 Camera Viewer")
        title.font = .boldSystemFont(ofSize: 22)
        title.alignment = .center
        title.frame = NSRect(x: 24, y: 270, width: 422, height: 30)
        content.addSubview(title)

        statusLabel = NSTextField(labelWithString: "正在检测 ESP32-S3 Camera……")
        statusLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        statusLabel.alignment = .center
        statusLabel.frame = NSRect(x: 25, y: 225, width: 420, height: 28)
        content.addSubview(statusLabel)

        detailLabel = NSTextField(wrappingLabelWithString: "")
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.alignment = .center
        detailLabel.frame = NSRect(x: 28, y: 115, width: 414, height: 95)
        content.addSubview(detailLabel)

        retryButton = makeButton("重新检测", action: #selector(retry))
        retryButton.frame = NSRect(x: 20, y: 60, width: 128, height: 34)
        content.addSubview(retryButton)

        reopenButton = makeButton("重新打开 Viewer", action: #selector(reopenViewer))
        reopenButton.frame = NSRect(x: 162, y: 60, width: 148, height: 34)
        reopenButton.isHidden = true
        content.addSubview(reopenButton)

        let wifiButton = makeButton("打开 Wi-Fi 设置", action: #selector(openWiFiSettings))
        wifiButton.frame = NSRect(x: 326, y: 60, width: 124, height: 34)
        content.addSubview(wifiButton)

        let exitButton = makeButton("退出", action: #selector(exitApp))
        exitButton.frame = NSRect(x: 185, y: 18, width: 100, height: 30)
        content.addSubview(exitButton)

        detailLabel.stringValue = "请让 Mac 连接 ESP32-S3 自建 Wi-Fi：\nesp32s3cam-xxxx    密码：11223344\n该 Wi-Fi 没有互联网属于正常现象。"
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func checkDevice() {
        retryButton.isEnabled = false
        reopenButton.isHidden = true
        statusLabel.stringValue = "正在检测 ESP32-S3 Camera……"
        detailLabel.stringValue = "请确认 Mac 已连接 esp32s3cam-xxxx。密码：11223344。\n刚烧录或重启后，设备可能还需要几秒启动。"

        probeDevice { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.retryButton.isEnabled = true
                switch result {
                case .ready:
                    self.statusLabel.stringValue = "✓ 已找到 ESP32-S3 Camera"
                    self.detailLabel.stringValue = "正在打开系统默认浏览器……\n如果画面没有出现，请点击“重新打开 Viewer”。"
                    self.reopenButton.isHidden = false
                    self.openViewer()
                case .unavailable:
                    self.statusLabel.stringValue = "还没有连接到 ESP32-S3 Camera"
                    self.detailLabel.stringValue = "请在屏幕右上角 Wi-Fi 菜单连接：\nesp32s3cam-xxxx    密码：11223344\n没有互联网属于正常现象。若设备刚重启，请稍等后重新检测。"
                case .wrongDevice:
                    self.statusLabel.stringValue = "访问到了 192.168.4.1，但设备不匹配"
                    self.detailLabel.stringValue = "没有检测到 ESP32S3_Vision Camera Viewer。\n请确认当前 Wi-Fi 是本题开发板的 esp32s3cam-xxxx。"
                }
            }
        }
    }

    private func openViewer() {
        if !NSWorkspace.shared.open(viewerURL) {
            statusLabel.stringValue = "已找到设备，但浏览器没有打开"
            detailLabel.stringValue = "请手动打开浏览器并访问：\nhttp://192.168.4.1/"
        }
    }

    @objc private func retry() { checkDevice() }
    @objc private func reopenViewer() { openViewer() }

    @objc private func openWiFiSettings() {
        if let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            _ = NSWorkspace.shared.open(settings)
            statusLabel.stringValue = "请在系统设置中选择 Wi-Fi"
            detailLabel.stringValue = "连接 esp32s3cam-xxxx，密码 11223344。\n然后返回此窗口并点击“重新检测”。"
        } else {
            statusLabel.stringValue = "请点击屏幕右上角的 Wi-Fi 图标"
            detailLabel.stringValue = "连接 esp32s3cam-xxxx，密码 11223344。\n然后返回此窗口并点击“重新检测”。"
        }
    }

    @objc private func exitApp() { NSApp.terminate(nil) }
}
