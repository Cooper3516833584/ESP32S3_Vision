using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Windows.Forms;

namespace ESP32S3Vision.CameraViewer;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--self-test")
        {
            return Probe.SelfTest();
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new LauncherForm());
        return 0;
    }
}

internal enum ProbeResult
{
    Ready,
    Unavailable,
    WrongDevice
}

internal static class Probe
{
    private const string HealthUrl = "http://192.168.4.1/health";
    private const string ViewerUrl = "http://192.168.4.1/";
    private const string ViewerMarker = "<meta name=\"esp32s3-vision-viewer\" content=\"1\">";

    internal static bool IsValidHealth(int statusCode, string body)
    {
        if (statusCode != 200) return false;
        try
        {
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;
            return root.TryGetProperty("ok", out var ok) && ok.ValueKind == JsonValueKind.True
                && root.TryGetProperty("device", out var device) && device.GetString() == "ESP32S3_Vision"
                && root.TryGetProperty("viewer", out var viewer) && viewer.GetInt32() == 1;
        }
        catch (JsonException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (FormatException)
        {
            return false;
        }
    }

    internal static bool IsValidViewerPage(int statusCode, string body) =>
        statusCode == 200 && body.Contains(ViewerMarker, StringComparison.Ordinal);

    internal static async Task<ProbeResult> CheckAsync(CancellationToken cancellationToken)
    {
        using var client = new HttpClient(new HttpClientHandler { AllowAutoRedirect = false })
        {
            Timeout = TimeSpan.FromSeconds(2.5)
        };
        using var healthResponse = await client.GetAsync(HealthUrl, HttpCompletionOption.ResponseContentRead, cancellationToken);
        var healthBody = await healthResponse.Content.ReadAsStringAsync(cancellationToken);
        if (IsValidHealth((int)healthResponse.StatusCode, healthBody)) return ProbeResult.Ready;

        // Older firmware may not have /health. The finite root page marker is a safe
        // fallback; the launcher never requests video frames or metrics.
        if (healthResponse.StatusCode != HttpStatusCode.NotFound) return ProbeResult.WrongDevice;
        using var pageResponse = await client.GetAsync(ViewerUrl, HttpCompletionOption.ResponseContentRead, cancellationToken);
        if (!pageResponse.IsSuccessStatusCode) return ProbeResult.WrongDevice;
        var page = await pageResponse.Content.ReadAsStringAsync(cancellationToken);
        return IsValidViewerPage((int)pageResponse.StatusCode, page) ? ProbeResult.Ready : ProbeResult.WrongDevice;
    }

    internal static int SelfTest()
    {
        const string valid = "{\"ok\":true,\"device\":\"ESP32S3_Vision\",\"viewer\":1}";
        const string wrongDevice = "{\"ok\":true,\"device\":\"other\",\"viewer\":1}";
        if (!IsValidHealth(200, valid) || IsValidHealth(200, wrongDevice) || IsValidHealth(503, valid)
            || !IsValidViewerPage(200, ViewerMarker) || IsValidViewerPage(200, "not our viewer")
            || IsValidViewerPage(404, ViewerMarker))
        {
            Console.Error.WriteLine("Camera Viewer health-probe self-test failed.");
            return 1;
        }
        Console.WriteLine("Camera Viewer health-probe self-test passed.");
        return 0;
    }
}

internal sealed class LauncherForm : Form
{
    private const string ViewerUrl = "http://192.168.4.1/";
    private readonly Label status = new();
    private readonly Label detail = new();
    private readonly Button retry = new();
    private readonly Button reopen = new();
    private CancellationTokenSource? checkCancellation;

    internal LauncherForm()
    {
        Text = "Camera Viewer";
        ClientSize = new System.Drawing.Size(490, 320);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;

        var title = new Label
        {
            Text = "ESP32-S3 Camera Viewer",
            Font = new System.Drawing.Font("Segoe UI", 18, System.Drawing.FontStyle.Bold),
            TextAlign = System.Drawing.ContentAlignment.MiddleCenter,
            Bounds = new System.Drawing.Rectangle(20, 24, 450, 38)
        };
        status.SetBounds(25, 78, 440, 32);
        status.Font = new System.Drawing.Font("Segoe UI", 12, System.Drawing.FontStyle.Bold);
        status.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
        detail.SetBounds(38, 122, 414, 95);
        detail.Font = new System.Drawing.Font("Segoe UI", 10);
        detail.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;

        retry.Text = "重新检测";
        retry.SetBounds(28, 236, 125, 34);
        retry.Click += async (_, _) => await CheckDeviceAsync();
        reopen.Text = "重新打开 Viewer";
        reopen.SetBounds(174, 236, 145, 34);
        reopen.Visible = false;
        reopen.Click += (_, _) => OpenViewer();
        var wifi = new Button { Text = "打开 Wi-Fi 设置", Bounds = new System.Drawing.Rectangle(338, 236, 125, 34) };
        wifi.Click += (_, _) => OpenWifiSettings();
        var exit = new Button { Text = "退出", Bounds = new System.Drawing.Rectangle(190, 278, 100, 30) };
        exit.Click += (_, _) => Close();

        Controls.AddRange([title, status, detail, retry, reopen, wifi, exit]);
        Shown += async (_, _) => await CheckDeviceAsync();
    }

    private async Task CheckDeviceAsync()
    {
        checkCancellation?.Cancel();
        checkCancellation?.Dispose();
        checkCancellation = new CancellationTokenSource();
        retry.Enabled = false;
        reopen.Visible = false;
        status.Text = "正在检测 ESP32-S3 Camera……";
        detail.Text = "请确认电脑已连接 esp32s3cam-xxxx，密码：11223344。\r\n刚烧录或重启后，设备可能还需要几秒启动。";

        try
        {
            var result = await Probe.CheckAsync(checkCancellation.Token);
            switch (result)
            {
                case ProbeResult.Ready:
                    status.Text = "✓ 已找到 ESP32-S3 Camera";
                    detail.Text = "正在打开系统默认浏览器……\r\n如果画面没有出现，请点击“重新打开 Viewer”。";
                    reopen.Visible = true;
                    OpenViewer();
                    break;
                case ProbeResult.WrongDevice:
                    status.Text = "访问到了 192.168.4.1，但设备不匹配";
                    detail.Text = "没有检测到 ESP32S3_Vision Camera Viewer。\r\n请确认当前 Wi-Fi 是本题开发板的 esp32s3cam-xxxx。";
                    break;
                default:
                    status.Text = "还没有连接到 ESP32-S3 Camera";
                    detail.Text = "请连接 esp32s3cam-xxxx，密码：11223344。\r\n该 Wi-Fi 没有 Internet 属于正常现象。设备刚重启时，请稍等后重新检测。";
                    break;
            }
        }
        catch (HttpRequestException)
        {
            status.Text = "还没有连接到 ESP32-S3 Camera";
            detail.Text = "请连接 esp32s3cam-xxxx，密码：11223344。\r\n该 Wi-Fi 没有 Internet 属于正常现象。设备刚重启时，请稍等后重新检测。";
        }
        catch (TaskCanceledException) when (checkCancellation?.IsCancellationRequested != true)
        {
            status.Text = "检测超时";
            detail.Text = "请确认电脑已连接 esp32s3cam-xxxx。若开发板刚启动，请稍等后重新检测。";
        }
        catch (OperationCanceledException)
        {
            // A user-triggered retry or window close cancelled this request.
        }
        finally
        {
            retry.Enabled = true;
        }
    }

    private void OpenViewer()
    {
        try
        {
            Process.Start(new ProcessStartInfo { FileName = ViewerUrl, UseShellExecute = true });
        }
        catch
        {
            status.Text = "已找到设备，但默认浏览器没有打开";
            detail.Text = "请手动打开浏览器并访问：\r\nhttp://192.168.4.1/";
        }
    }

    private void OpenWifiSettings()
    {
        try
        {
            Process.Start(new ProcessStartInfo { FileName = "ms-settings:network-wifi", UseShellExecute = true });
        }
        catch
        {
            detail.Text = "请点击任务栏右侧的 Wi-Fi 图标，选择 esp32s3cam-xxxx。密码：11223344。";
        }
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        checkCancellation?.Cancel();
        checkCancellation?.Dispose();
        base.OnFormClosed(e);
    }
}
