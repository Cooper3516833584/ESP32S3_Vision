using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Net;
using System.Threading;
using System.Windows.Forms;

internal sealed class ViewerForm : Form
{
    private readonly string host;
    private readonly object imageLock = new object();
    private readonly Stopwatch fpsClock = Stopwatch.StartNew();
    private Thread worker;
    private Bitmap currentImage;
    private volatile bool stopping;
    private int frameCounter;
    private double displayFps;
    private volatile bool wrongResolution;
    private string resolutionWarning = "";

    public ViewerForm(string hostAddress)
    {
        host = hostAddress;
        Text = "ESP32-S3 Camera Stream Viewer";
        ClientSize = new Size(960, 720);
        BackColor = Color.Black;
        KeyPreview = true;
        StartPosition = FormStartPosition.CenterScreen;
        SetStyle(ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.UserPaint |
                 ControlStyles.OptimizedDoubleBuffer, true);
        KeyDown += delegate(object sender, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) Close(); };
        Shown += delegate { StartWorker(); };
    }

    private void StartWorker()
    {
        worker = new Thread(ReceiveLoop);
        worker.IsBackground = true;
        worker.Name = "camera-stream";
        worker.Start();
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        stopping = true;
        lock (imageLock)
        {
            if (currentImage != null) currentImage.Dispose();
            currentImage = null;
        }
        base.OnFormClosed(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        lock (imageLock)
        {
            if (currentImage != null)
            {
                Rectangle target = FitInside(ClientRectangle, currentImage.Width, currentImage.Height);
                e.Graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
                e.Graphics.PixelOffsetMode = PixelOffsetMode.Half;
                e.Graphics.DrawImage(currentImage, target);
            }
        }

        string status = displayFps.ToString("0.0") + " FPS";
        using (Font font = new Font(FontFamily.GenericMonospace, 16, FontStyle.Bold))
        using (Brush shadow = new SolidBrush(Color.Black))
        using (Brush text = new SolidBrush(Color.Lime))
        {
            e.Graphics.DrawString(status, font, shadow, 13, 13);
            e.Graphics.DrawString(status, font, text, 11, 11);
        }

        if (wrongResolution)
        {
            string warning = resolutionWarning;
            using (Font font = new Font(FontFamily.GenericSansSerif, 22, FontStyle.Bold))
            {
                SizeF size = e.Graphics.MeasureString(warning, font);
                float x = (ClientSize.Width - size.Width) / 2.0f;
                float y = (ClientSize.Height - size.Height) / 2.0f;
                RectangleF background = new RectangleF(x - 12, y - 8, size.Width + 24, size.Height + 16);
                using (Brush box = new SolidBrush(Color.FromArgb(220, 0, 0, 0)))
                using (Brush text = new SolidBrush(Color.Red))
                {
                    e.Graphics.FillRectangle(box, background);
                    e.Graphics.DrawString(warning, font, text, x, y);
                }
            }
        }
    }

    private static Rectangle FitInside(Rectangle area, int width, int height)
    {
        double scale = Math.Min((double)area.Width / width, (double)area.Height / height);
        int drawWidth = Math.Max(1, (int)(width * scale));
        int drawHeight = Math.Max(1, (int)(height * scale));
        return new Rectangle((area.Width - drawWidth) / 2, (area.Height - drawHeight) / 2,
                             drawWidth, drawHeight);
    }

    private void ReceiveLoop()
    {
        while (!stopping)
        {
            try
            {
                ReceiveRaw();
            }
            catch
            {
                if (stopping) break;
                try
                {
                    ReceiveMjpeg();
                }
                catch
                {
                    if (!stopping) Thread.Sleep(500);
                }
            }
        }
    }

    private HttpWebResponse Open(string path)
    {
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create("http://" + host + ":81" + path);
        request.Proxy = null;
        request.KeepAlive = true;
        request.Timeout = 3000;
        request.ReadWriteTimeout = 5000;
        request.UserAgent = "ESP32-CameraStreamViewer/2";
        return (HttpWebResponse)request.GetResponse();
    }

    private void ReceiveRaw()
    {
        using (HttpWebResponse response = Open("/raw"))
        using (Stream stream = response.GetResponseStream())
        {
            byte[] header = new byte[20];
            while (!stopping)
            {
                ReadExactly(stream, header, 0, header.Length);
                if (header[0] != (byte)'R' || header[1] != (byte)'F' ||
                    header[2] != (byte)'S' || header[3] != (byte)'1')
                    throw new InvalidDataException("Raw frame magic mismatch");

                int format = header[4];
                int width = ReadU16(header, 6);
                int height = ReadU16(header, 8);
                int payloadLength = (int)ReadU32(header, 10);
                int pixelCount = width * height;
                int maximumPacked = pixelCount + (pixelCount + 127) / 128 + 16;
                bool validLength = (format == 1 || format == 2)
                    ? payloadLength == pixelCount * 2
                    : format == 3 && payloadLength > 0 && payloadLength <= maximumPacked;
                if (width <= 0 || height <= 0 || width > 1920 || height > 1080 || !validLength)
                    throw new InvalidDataException("Invalid raw frame size");

                byte[] pixels = new byte[payloadLength];
                ReadExactly(stream, pixels, 0, pixels.Length);
                Bitmap image;
                if (format == 1)
                {
                    image = ConvertRgb565(pixels, width, height);
                }
                else if (format == 2)
                {
                    image = ConvertYuyv(pixels, width, height);
                }
                else if (format == 3)
                {
                    image = ConvertRgb332(DecodePackBits(pixels, pixelCount), width, height);
                }
                else throw new InvalidDataException("Unsupported raw pixel format");
                Publish(image);
            }
        }
    }

    private void ReceiveMjpeg()
    {
        using (HttpWebResponse response = Open("/stream"))
        using (Stream stream = response.GetResponseStream())
        using (MemoryStream jpeg = new MemoryStream(128 * 1024))
        {
            byte[] block = new byte[8192];
            bool inside = false;
            int previous = -1;
            while (!stopping)
            {
                int count = stream.Read(block, 0, block.Length);
                if (count <= 0) throw new EndOfStreamException();
                for (int i = 0; i < count; i++)
                {
                    int value = block[i];
                    if (!inside)
                    {
                        if (previous == 0xFF && value == 0xD8)
                        {
                            jpeg.SetLength(0);
                            jpeg.WriteByte(0xFF);
                            jpeg.WriteByte(0xD8);
                            inside = true;
                        }
                    }
                    else
                    {
                        jpeg.WriteByte((byte)value);
                        if (previous == 0xFF && value == 0xD9)
                        {
                            jpeg.Position = 0;
                            using (Image decoded = Image.FromStream(jpeg, true, true))
                                Publish(new Bitmap(decoded));
                            inside = false;
                        }
                    }
                    previous = value;
                }
            }
        }
    }

    private void Publish(Bitmap image)
    {
        wrongResolution = image.Width != 320 || image.Height != 240;
        resolutionWarning = wrongResolution
            ? "WRONG RESOLUTION: " + image.Width + " x " + image.Height + "  REQUIRED: 320 x 240"
            : "";
        lock (imageLock)
        {
            Bitmap old = currentImage;
            currentImage = image;
            if (old != null) old.Dispose();
        }
        frameCounter++;
        if (fpsClock.ElapsedMilliseconds >= 500)
        {
            displayFps = frameCounter * 1000.0 / fpsClock.ElapsedMilliseconds;
            frameCounter = 0;
            fpsClock.Restart();
        }
        if (!stopping && IsHandleCreated)
        {
            try { BeginInvoke((Action)Invalidate); }
            catch (InvalidOperationException) { }
        }
    }

    private static void ReadExactly(Stream stream, byte[] buffer, int offset, int count)
    {
        while (count > 0)
        {
            int read = stream.Read(buffer, offset, count);
            if (read <= 0) throw new EndOfStreamException();
            offset += read;
            count -= read;
        }
    }

    private static int ReadU16(byte[] data, int offset)
    {
        return data[offset] | data[offset + 1] << 8;
    }

    private static uint ReadU32(byte[] data, int offset)
    {
        return (uint)(data[offset] | data[offset + 1] << 8 |
                      data[offset + 2] << 16 | data[offset + 3] << 24);
    }

    private static int Clip(int value)
    {
        return value < 0 ? 0 : (value > 255 ? 255 : value);
    }

    private static byte[] DecodePackBits(byte[] packed, int outputLength)
    {
        byte[] output = new byte[outputLength];
        int source = 0;
        int target = 0;
        while (source < packed.Length && target < output.Length)
        {
            int control = packed[source++];
            int length = (control & 0x7F) + 1;
            if ((control & 0x80) != 0)
            {
                if (source >= packed.Length || target + length > output.Length)
                    throw new InvalidDataException("Invalid RGB332 run");
                byte value = packed[source++];
                for (int i = 0; i < length; i++) output[target++] = value;
            }
            else
            {
                if (source + length > packed.Length || target + length > output.Length)
                    throw new InvalidDataException("Invalid RGB332 literal");
                Buffer.BlockCopy(packed, source, output, target, length);
                source += length;
                target += length;
            }
        }
        if (source != packed.Length || target != output.Length)
            throw new InvalidDataException("Incomplete RGB332 frame");
        return output;
    }

    private static unsafe Bitmap ConvertRgb332(byte[] source, int width, int height)
    {
        Bitmap bitmap = new Bitmap(width, height, PixelFormat.Format24bppRgb);
        BitmapData bits = bitmap.LockBits(new Rectangle(0, 0, width, height),
                                          ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
        fixed (byte* input = source)
        {
            for (int y = 0; y < height; y++)
            {
                byte* output = (byte*)bits.Scan0 + y * bits.Stride;
                byte* row = input + y * width;
                for (int x = 0; x < width; x++)
                {
                    int value = row[x];
                    output[x * 3] = (byte)((value & 3) * 255 / 3);
                    output[x * 3 + 1] = (byte)(((value >> 2) & 7) * 255 / 7);
                    output[x * 3 + 2] = (byte)(((value >> 5) & 7) * 255 / 7);
                }
            }
        }
        bitmap.UnlockBits(bits);
        return bitmap;
    }

    private static unsafe Bitmap ConvertRgb565(byte[] source, int width, int height)
    {
        Bitmap bitmap = new Bitmap(width, height, PixelFormat.Format24bppRgb);
        BitmapData bits = bitmap.LockBits(new Rectangle(0, 0, width, height),
                                          ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
        fixed (byte* input = source)
        {
            for (int y = 0; y < height; y++)
            {
                byte* output = (byte*)bits.Scan0 + y * bits.Stride;
                byte* row = input + y * width * 2;
                for (int x = 0; x < width; x++)
                {
                    int value = row[x * 2] << 8 | row[x * 2 + 1];
                    output[x * 3] = (byte)((value & 31) * 255 / 31);
                    output[x * 3 + 1] = (byte)(((value >> 5) & 63) * 255 / 63);
                    output[x * 3 + 2] = (byte)(((value >> 11) & 31) * 255 / 31);
                }
            }
        }
        bitmap.UnlockBits(bits);
        return bitmap;
    }

    private static unsafe Bitmap ConvertYuyv(byte[] source, int width, int height)
    {
        Bitmap bitmap = new Bitmap(width, height, PixelFormat.Format24bppRgb);
        BitmapData bits = bitmap.LockBits(new Rectangle(0, 0, width, height),
                                          ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
        fixed (byte* input = source)
        {
            for (int y = 0; y < height; y++)
            {
                byte* output = (byte*)bits.Scan0 + y * bits.Stride;
                byte* row = input + y * width * 2;
                for (int x = 0; x < width; x += 2)
                {
                    int p = x * 2;
                    WriteYuvPixel(output + x * 3, row[p], row[p + 1], row[p + 3]);
                    WriteYuvPixel(output + (x + 1) * 3, row[p + 2], row[p + 1], row[p + 3]);
                }
            }
        }
        bitmap.UnlockBits(bits);
        return bitmap;
    }

    private static unsafe void WriteYuvPixel(byte* output, int y, int u, int v)
    {
        int c = y - 16;
        int d = u - 128;
        int e = v - 128;
        if (c < 0) c = 0;
        output[0] = (byte)Clip((298 * c + 516 * d + 128) >> 8);
        output[1] = (byte)Clip((298 * c - 100 * d - 208 * e + 128) >> 8);
        output[2] = (byte)Clip((298 * c + 409 * e + 128) >> 8);
    }

    [STAThread]
    private static void Main(string[] args)
    {
        string host = args.Length > 0 ? args[0] : "192.168.4.1";
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new ViewerForm(host));
    }
}
