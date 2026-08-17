using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Threading;
using System.Windows.Forms;

namespace CameraViewerRelease
{
    internal static class A
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            string host = args.Length > 0 ? args[0] : null;
            if (String.IsNullOrWhiteSpace(host))
            {
                using (B prompt = new B())
                {
                    if (prompt.ShowDialog() != DialogResult.OK) return;
                    host = prompt.Host;
                }
            }

            host = Normalize(host);
            if (host == null)
            {
                MessageBox.Show("IP 地址无效。", "ESP32 Camera", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            Application.Run(new C(host));
        }

        private static string Normalize(string value)
        {
            if (value == null) return null;
            value = value.Trim();
            Uri uri;
            if (!value.Contains("://")) value = "http://" + value;
            if (!Uri.TryCreate(value, UriKind.Absolute, out uri)) return null;
            if (uri.Scheme != Uri.UriSchemeHttp || String.IsNullOrWhiteSpace(uri.Host)) return null;
            return uri.Host;
        }
    }

    internal sealed class B : Form
    {
        private readonly TextBox a;
        internal string Host { get { return a.Text; } }

        internal B()
        {
            Text = "连接 ESP32 Camera";
            ClientSize = new Size(420, 128);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Microsoft YaHei UI", 10F);

            Label label = new Label();
            label.Text = "ESP32 IP 地址";
            label.Location = new Point(18, 18);
            label.AutoSize = true;

            a = new TextBox();
            a.Text = "192.168.4.1";
            a.Location = new Point(18, 45);
            a.Size = new Size(384, 28);
            a.SelectAll();

            Button ok = new Button();
            ok.Text = "连接";
            ok.DialogResult = DialogResult.OK;
            ok.Location = new Point(222, 86);
            ok.Size = new Size(86, 28);

            Button cancel = new Button();
            cancel.Text = "取消";
            cancel.DialogResult = DialogResult.Cancel;
            cancel.Location = new Point(316, 86);
            cancel.Size = new Size(86, 28);

            Controls.Add(label);
            Controls.Add(a);
            Controls.Add(ok);
            Controls.Add(cancel);
            AcceptButton = ok;
            CancelButton = cancel;
        }
    }

    internal sealed class C : Form
    {
        private readonly string a;
        private readonly object b = new object();
        private Bitmap c;
        private double d;
        private volatile bool e;
        private Thread f;
        private readonly Queue<long> g = new Queue<long>();

        internal C(string host)
        {
            a = "http://" + host + ":81/stream";
            Text = "ESP32 Camera Stream";
            BackColor = Color.Black;
            FormBorderStyle = FormBorderStyle.None;
            WindowState = FormWindowState.Maximized;
            KeyPreview = true;
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        }

        protected override void OnShown(EventArgs args)
        {
            base.OnShown(args);
            Cursor.Hide();
            e = true;
            f = new Thread(Run);
            f.IsBackground = true;
            f.Name = "MJPEG receiver";
            f.Start();
        }

        protected override void OnKeyDown(KeyEventArgs args)
        {
            if (args.KeyCode == Keys.Escape) Close();
            base.OnKeyDown(args);
        }

        protected override void OnFormClosing(FormClosingEventArgs args)
        {
            e = false;
            Cursor.Show();
            lock (b)
            {
                if (c != null) { c.Dispose(); c = null; }
            }
            base.OnFormClosing(args);
        }

        protected override void OnPaint(PaintEventArgs args)
        {
            args.Graphics.Clear(Color.Black);
            lock (b)
            {
                if (c != null)
                {
                    Rectangle target = Fit(c.Width, c.Height, ClientSize.Width, ClientSize.Height);
                    args.Graphics.DrawImage(c, target);
                }
            }

            string text = d > 0.05 ? d.ToString("0.0") + " FPS" : "--.- FPS";
            using (Font font = new Font("Consolas", 22F, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Brush background = new SolidBrush(Color.FromArgb(190, 0, 0, 0)))
            using (Brush foreground = new SolidBrush(Color.FromArgb(124, 255, 124)))
            {
                SizeF size = args.Graphics.MeasureString(text, font);
                RectangleF panel = new RectangleF(14, 14, size.Width + 22, size.Height + 14);
                args.Graphics.FillRectangle(background, panel);
                args.Graphics.DrawString(text, font, foreground, 25, 21);
            }
        }

        private static Rectangle Fit(int imageWidth, int imageHeight, int areaWidth, int areaHeight)
        {
            double scale = Math.Min((double)areaWidth / imageWidth, (double)areaHeight / imageHeight);
            int width = Math.Max(1, (int)(imageWidth * scale));
            int height = Math.Max(1, (int)(imageHeight * scale));
            return new Rectangle((areaWidth - width) / 2, (areaHeight - height) / 2, width, height);
        }

        private void Run()
        {
            while (e)
            {
                try
                {
                    HttpWebRequest request = (HttpWebRequest)WebRequest.Create(a + "?viewer=" + DateTime.UtcNow.Ticks);
                    request.Proxy = null;
                    request.KeepAlive = true;
                    // A stalled MJPEG TCP stream must be replaced quickly. Keeping
                    // the old socket for five seconds turns a brief RF loss into a
                    // visibly frozen picture.
                    request.Timeout = 1200;
                    request.ReadWriteTimeout = 1200;
                    request.CachePolicy = new System.Net.Cache.RequestCachePolicy(System.Net.Cache.RequestCacheLevel.NoCacheNoStore);
                    using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                    using (Stream stream = response.GetResponseStream())
                    {
                        Receive(stream);
                    }
                }
                catch
                {
                    SetDisconnected();
                    Thread.Sleep(120);
                }
            }
        }

        private void Receive(Stream stream)
        {
            byte[] buffer = new byte[16384];
            MemoryStream jpeg = new MemoryStream(65536);
            bool collecting = false;
            int previous = -1;

            while (e)
            {
                int count = stream.Read(buffer, 0, buffer.Length);
                if (count <= 0) throw new EndOfStreamException();
                for (int i = 0; i < count; i++)
                {
                    int current = buffer[i];
                    if (!collecting)
                    {
                        if (previous == 0xFF && current == 0xD8)
                        {
                            jpeg.SetLength(0);
                            jpeg.WriteByte(0xFF);
                            jpeg.WriteByte(0xD8);
                            collecting = true;
                        }
                    }
                    else
                    {
                        jpeg.WriteByte((byte)current);
                        if (previous == 0xFF && current == 0xD9)
                        {
                            Publish(jpeg.ToArray());
                            collecting = false;
                        }
                    }
                    previous = current;
                }
            }
        }

        private void Publish(byte[] jpeg)
        {
            Bitmap next;
            using (MemoryStream memory = new MemoryStream(jpeg, false))
            using (Image image = Image.FromStream(memory, true, true))
            {
                next = new Bitmap(image);
            }

            long now = Stopwatch.GetTimestamp();
            long window = Stopwatch.Frequency;
            g.Enqueue(now);
            while (g.Count > 1 && now - g.Peek() > window) g.Dequeue();
            if (g.Count > 1)
            {
                long first = g.Peek();
                d = (g.Count - 1) * (double)Stopwatch.Frequency / Math.Max(1, now - first);
            }

            lock (b)
            {
                Bitmap old = c;
                c = next;
                if (old != null) old.Dispose();
            }
            if (IsHandleCreated && !IsDisposed)
            {
                try { BeginInvoke((MethodInvoker)Invalidate); } catch { }
            }
        }

        private void SetDisconnected()
        {
            d = 0;
            g.Clear();
            if (IsHandleCreated && !IsDisposed)
            {
                try { BeginInvoke((MethodInvoker)Invalidate); } catch { }
            }
        }
    }
}
