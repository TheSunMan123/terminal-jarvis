# Terminal Jarvis HUD for Codex: one small helper, started by the "Jarvis - Codex" Terminal profile, that
#  1. pins a Jarvis status readout in the empty strip beside the tabs:
#       <> J.A.R.V.I.S.  .  MODEL  .  5H [bars] 49% left (reset 3h02m)  .  WK [bars] 37% left (2d16h)
#     with the numbers read from Codex's own session records (~/.codex/sessions), refreshed every few seconds;
#  2. runs push-to-talk: hold the talk key in the Jarvis window -> Windows voice typing; release -> sent.
# It only acts on the Windows Terminal window titled with the assistant's name, and quits ~20 s after the
# last such window closes. Nothing is sent anywhere.
param([switch]$NoPtt)
$ErrorActionPreference = "Stop"
$Dir = Join-Path $env:LOCALAPPDATA "TerminalJarvis"
$state = Get-Content (Join-Path $Dir "state.json") -Raw | ConvertFrom-Json
$created = $false
$mutex = New-Object System.Threading.Mutex($true, "Local\TerminalJarvisHUD", [ref]$created)
if (-not $created) { exit 0 }
Set-Content -Path (Join-Path $Dir "hud.pid") -Value $PID
$keys = @{ rightalt = 0xA5; capslock = 0x14; rightctrl = 0xA3; f8 = 0x77; f9 = 0x78; scrolllock = 0x91; pause = 0x13 }
$k = ([string]$state.ptt_key).ToLower() -replace '[\s_-]', ''
$vk = if ($NoPtt -or -not $keys.ContainsKey($k)) { 0 } else { $keys[$k] }

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @"
using System; using System.Collections.Generic; using System.Diagnostics; using System.Drawing; using System.Drawing.Drawing2D;
using System.Drawing.Text; using System.IO; using System.Runtime.InteropServices; using System.Text; using System.Text.RegularExpressions;
using System.Threading; using System.Windows.Forms;

public class TJHud : Form {
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetCursorPos(out Point p);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size);
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }

  static string Title; static string Codex;
  List<KeyValuePair<string, Color>> segs = new List<KeyValuePair<string, Color>>();
  System.Windows.Forms.Timer tick = new System.Windows.Forms.Timer(), data = new System.Windows.Forms.Timer();
  DateTime lastSeen = DateTime.Now; float scale = 1f; Font font, tfont;
  static readonly StringFormat Fmt = MakeFmt();
  static StringFormat MakeFmt() { var f = (StringFormat)StringFormat.GenericTypographic.Clone(); f.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces; return f; }
  static readonly Color CY = Color.FromArgb(63, 216, 255), GOLD = Color.FromArgb(255, 194, 71), RED = Color.FromArgb(255, 77, 61),
    DIM = Color.FromArgb(107, 130, 153), TXT = Color.FromArgb(234, 241, 248), BG = Color.FromArgb(6, 16, 27), EDGE = Color.FromArgb(90, 255, 194, 71);

  public static void Start(string title) {
    SetProcessDPIAware();
    Title = title; Codex = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
    Application.EnableVisualStyles();
    Application.Run(new TJHud());
  }
  public TJHud() {
    FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual;
    BackColor = BG; Opacity = 0.96; DoubleBuffered = true; Size = new Size(10, 10); Location = new Point(-2000, -2000);
    segs.Add(new KeyValuePair<string, Color>(Spaced(Title), CY));
    segs.Add(new KeyValuePair<string, Color>("STANDING BY", DIM));
    tick.Interval = 60; tick.Tick += (s, e) => Follow(); tick.Start();
    data.Interval = 4000; data.Tick += (s, e) => Refresh2(); data.Start();
    Refresh2();
  }
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams { get {
    var cp = base.CreateParams; cp.ExStyle |= 0x80 | 0x08000000 | 0x20 | 0x80000 | 0x8; return cp; } }   // tool, noactivate, click-through, layered, topmost

  static string Spaced(string t) {
    string u = t.ToUpper().Replace(" ", "");
    if (u.Length > 8) return t.ToUpper();
    var sb = new StringBuilder(); foreach (char c in u) { sb.Append(c); sb.Append('.'); } return sb.ToString();
  }

  // the Jarvis Terminal window: foreground, Windows Terminal, title = assistant name
  IntPtr FindJarvis(out bool foreground) {
    foreground = false; IntPtr fg = GetForegroundWindow();
    if (IsJarvis(fg)) { foreground = true; return fg; }
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { if (IsWindowVisible(h) && IsJarvis(h)) { found = h; return false; } return true; }, IntPtr.Zero);
    return found;
  }
  public static bool IsJarvis(IntPtr h) {
    if (h == IntPtr.Zero) return false;
    var sb = new StringBuilder(256); GetWindowText(h, sb, 256);
    if (!sb.ToString().Trim().Equals(Title, StringComparison.OrdinalIgnoreCase)) return false;
    uint pid; GetWindowThreadProcessId(h, out pid);
    try { return Process.GetProcessById((int)pid).ProcessName.Equals("WindowsTerminal", StringComparison.OrdinalIgnoreCase); } catch { return false; }
  }

  string shownPtt = "";
  void Follow() {
    if (TJPtt.State != shownPtt) { shownPtt = TJPtt.State; Refresh2(); }
    bool fgJ; IntPtr h = FindJarvis(out fgJ);
    if (h != IntPtr.Zero) lastSeen = DateTime.Now;
    else if ((DateTime.Now - lastSeen).TotalSeconds > 20) { Application.Exit(); return; }
    if (!fgJ || IsIconic(h)) { if (Visible) Hide(); return; }
    RECT r;   // the window's visible edges (GetWindowRect adds invisible resize borders)
    if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) != 0) GetWindowRect(h, out r);
    float ds = Math.Max(1f, GetDpiForWindow(h) / 96f);    // display scale (positions)
    int caption = (int)(138 * ds);                          // minimise / maximise / close: 3 x 46 px
    int gap = (int)(30 * ds);                               // clear air before the minimise button
    int tabs = (int)(345 * ds);                             // keep the first tab + new-tab buttons uncovered
    int room = (r.R - r.L) - caption - gap - tabs;
    // full size whenever it fits; smaller window -> shrink; smaller still -> drop the heading, keep the readout;
    // tiny -> step aside. Never over the tabs or the window buttons.
    bool cmp = false; float k = 1f;
    if (unitFull > 0) {
      float kf = room / (unitFull * ds), kb = room / (unitBare * ds);
      if (kf >= 0.75f) k = Math.Min(1f, kf);
      else if (kb >= 0.6f) { cmp = true; k = Math.Min(1f, kb); }
      else { if (Visible) Hide(); return; }
    }
    k = (float)Math.Floor(k * 20) / 20f;                    // 5 % steps, so resizing doesn't redraw constantly
    float sc = ds * k;
    if (font == null || Math.Abs(sc - scale) > 0.001f || cmp != compact) {   // as big as the tab row allows
      scale = sc; compact = cmp; if (font != null) { font.Dispose(); tfont.Dispose(); }
      font = new Font("Consolas", 17f * scale, FontStyle.Bold, GraphicsUnit.Pixel);
      tfont = new Font("Bahnschrift SemiBold", 25f * scale, FontStyle.Regular, GraphicsUnit.Pixel);
      Measure(); Invalidate();
    }
    if (Width > room + 2) { if (Visible) Hide(); return; }  // readout grew: re-fit on the next tick (60 ms)
    int x = r.R - caption - gap - Width;
    int y = r.T + (int)((40 * ds - Height) / 2);            // centred in the tab row
    if (Left != x || Top != y) Location = new Point(x, y);
    // mouse heading for the window buttons or onto the chip: fade it right down so nothing is ever hidden
    Point m; GetCursorPos(out m);
    bool near = m.Y >= r.T && m.Y < r.T + (int)(44 * ds) && m.X >= x - (int)(6 * ds) && m.X <= r.R;
    double want = near ? 0.18 : 0.96;
    if (Math.Abs(Opacity - want) > 0.01) Opacity = want;
    if (!Visible) Show();
  }

  // heading = arc-reactor emblem + letter-spaced title + gold divider; the readout segments follow
  float Track { get { return 3.5f * scale; } }
  float IconW { get { return 0f; } }   // no emblem: the title stands alone
  float TitleW(Graphics g) {
    float w = 0; foreach (char c in segs[0].Key) w += g.MeasureString(c.ToString(), tfont, PointF.Empty, Fmt).Width + Track;
    return w - Track;
  }
  float HeadW(Graphics g) { return compact ? 0f : IconW + TitleW(g) + 30f * scale; }   // gap + divider + gap
  bool compact = false;            // small window: readout only, no J.A.R.V.I.S. heading
  float unitFull = 0, unitBare = 0; // chip width per unit of scale, with / without the heading

  void Measure() {
    if (font == null) return;
    using (var g = CreateGraphics()) {
      float rd = 0; for (int i = 1; i < segs.Count; i++) rd += g.MeasureString(segs[i].Key, font, PointF.Empty, Fmt).Width;
      unitBare = (rd + 34 * scale) / scale;
      unitFull = (IconW + TitleW(g) + 30f * scale + rd + 34 * scale) / scale;
      float w = HeadW(g) + rd;
      Size = new Size((int)(w + 34 * scale), (int)(36 * scale));
    }
    using (var p = Round(new Rectangle(0, 0, Width, Height), (int)(8 * scale))) Region = new Region(p);
    Invalidate();
  }
  static GraphicsPath Round(Rectangle r, int rad) {
    var p = new GraphicsPath(); int d = rad * 2;
    p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
    p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
  }
  protected override void OnPaint(PaintEventArgs e) {
    if (font == null) return;
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
    float H = Height;
    // body: navy gradient, a faint cyan sheen on top, gold hairline edge
    using (var bg = new LinearGradientBrush(new Rectangle(0, 0, Width, Height), Color.FromArgb(12, 30, 50), BG, LinearGradientMode.Horizontal)) g.FillRectangle(bg, 0, 0, Width, Height);
    using (var sheen = new Pen(Color.FromArgb(55, 63, 216, 255), Math.Max(1f, scale))) g.DrawLine(sheen, 10 * scale, 1.5f * scale, Width - 10 * scale, 1.5f * scale);
    using (var pen = new Pen(EDGE, Math.Max(1f, scale))) using (var p = Round(new Rectangle(0, 0, Width - 1, Height - 1), (int)(8 * scale))) g.DrawPath(pen, p);

    float x = 16 * scale;
    if (!compact) {
    // title: letter-spaced, white-to-cyan gradient, soft glow
    using (var path = new GraphicsPath()) {
      float tx = x, ty = (H - tfont.GetHeight(g)) / 2f - 0.5f * scale;
      foreach (char c in segs[0].Key) {
        path.AddString(c.ToString(), tfont.FontFamily, (int)tfont.Style, tfont.Size, new PointF(tx, ty), Fmt);
        tx += g.MeasureString(c.ToString(), tfont, PointF.Empty, Fmt).Width + Track;
      }
      using (var glow1 = new Pen(Color.FromArgb(28, 63, 216, 255), 7f * scale) { LineJoin = LineJoin.Round }) g.DrawPath(glow1, path);
      using (var glow2 = new Pen(Color.FromArgb(60, 63, 216, 255), 3.5f * scale) { LineJoin = LineJoin.Round }) g.DrawPath(glow2, path);
      using (var fill = new LinearGradientBrush(new RectangleF(0, 4 * scale, 10, H - 8 * scale), Color.FromArgb(244, 252, 255), Color.FromArgb(63, 216, 255), LinearGradientMode.Vertical)) g.FillPath(fill, path);
    }
    x += TitleW(g) + 14 * scale;
    // gold divider
    using (var div = new LinearGradientBrush(new RectangleF(0, 7 * scale, 10, (H - 14 * scale) / 2f), Color.FromArgb(0, 255, 194, 71), Color.FromArgb(200, 255, 194, 71), LinearGradientMode.Vertical) { WrapMode = WrapMode.TileFlipY })
      g.FillRectangle(div, x, 7 * scale, 1.6f * scale, H - 14 * scale);
    x += 16 * scale;
    }

    // readout
    for (int i = 1; i < segs.Count; i++) {
      float y = (H - font.GetHeight(g)) / 2f;
      using (var b = new SolidBrush(segs[i].Value)) g.DrawString(segs[i].Key, font, b, x, y, Fmt);
      x += g.MeasureString(segs[i].Key, font, PointF.Empty, Fmt).Width;
    }
  }

  // ---- numbers from Codex's newest session record ----
  void Refresh2() {
    try {
      string f = Newest(); if (f == null) return;
      string tail = Tail(f, 400000);
      var mm = Regex.Matches(tail, "\"model\":\"([^\"]+)\"");
      var rl = Regex.Matches(tail, "\"rate_limits\":\\{\"limit_id\":\"codex\".*?\"plan_type\"");
      var n = new List<KeyValuePair<string, Color>>();
      n.Add(new KeyValuePair<string, Color>(Spaced(Title), CY));
      if (mm.Count > 0) { n.Add(new KeyValuePair<string, Color>(mm[mm.Count - 1].Groups[1].Value.ToUpper(), GOLD)); }
      if (rl.Count > 0) {
        string block = rl[rl.Count - 1].Value;
        AddWindow(n, Regex.Match(block, "\"primary\":(\\{[^}]*\\}|null)").Groups[1].Value);
        AddWindow(n, Regex.Match(block, "\"secondary\":(\\{[^}]*\\}|null)").Groups[1].Value);
      }
      if (shownPtt != "") {   // push-to-talk in progress: the readout becomes a live mic indicator
        n = new List<KeyValuePair<string, Color>>();
        n.Add(new KeyValuePair<string, Color>(Spaced(Title), CY)); n.Add(Dot());
        n.Add(new KeyValuePair<string, Color>((char)0x25CF + " " + shownPtt, shownPtt == "LISTENING" || shownPtt == "MIC ERROR" ? RED : GOLD));
      }
      bool changed = n.Count != segs.Count; if (!changed) for (int i = 0; i < n.Count; i++) if (n[i].Key != segs[i].Key || n[i].Value != segs[i].Value) { changed = true; break; }
      if (changed) { segs = n; Measure(); }
    } catch { }
  }
  static KeyValuePair<string, Color> Dot() { return new KeyValuePair<string, Color>("  " + (char)0x00B7 + "  ", DIM); }
  static void AddWindow(List<KeyValuePair<string, Color>> n, string w) {
    if (string.IsNullOrEmpty(w) || w == "null") return;
    double used = Num(w, "used_percent"), mins = Num(w, "window_minutes"), resets = Num(w, "resets_at");
    if (double.IsNaN(used)) return;
    double left = Math.Max(0, Math.Min(100, 100 - used));
    string label = mins == 300 ? "5H" : mins == 10080 ? "WK" : mins >= 40000 ? "MO" : mins >= 1440 ? ((int)(mins / 1440)) + "D" : ((int)(mins / 60)) + "H";
    Color c = left < 10 ? RED : left < 30 ? GOLD : CY;
    int cells = (int)Math.Round(left / 10.0);
    n.Add(Dot()); n.Add(new KeyValuePair<string, Color>(label + " ", DIM));
    n.Add(new KeyValuePair<string, Color>(new string((char)0x25B0, cells), c));
    n.Add(new KeyValuePair<string, Color>(new string((char)0x25B1, 10 - cells) + " ", DIM));
    n.Add(new KeyValuePair<string, Color>(((int)Math.Round(left)) + "% left", TXT));
    if (!double.IsNaN(resets)) {
      var span = DateTimeOffset.FromUnixTimeSeconds((long)resets) - DateTimeOffset.UtcNow;
      if (span.TotalSeconds > 0) {
        string t = span.TotalHours >= 48 ? ((int)span.TotalDays) + "d" + span.Hours + "h" : ((int)span.TotalHours) + "h" + span.Minutes.ToString("00") + "m";
        n.Add(new KeyValuePair<string, Color>(" " + (char)0x21BB + "" + t, DIM));
      }
    }
  }
  static double Num(string s, string key) {
    var m = Regex.Match(s, "\"" + key + "\":(-?[0-9.]+)");
    double v; return m.Success && double.TryParse(m.Groups[1].Value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out v) ? v : double.NaN;
  }
  static string Newest() {
    string best = null; DateTime bt = DateTime.MinValue;
    for (int d = 0; d < 3; d++) {
      var day = DateTime.Now.AddDays(-d);
      string dir = Path.Combine(Codex, "sessions", day.ToString("yyyy"), day.ToString("MM"), day.ToString("dd"));
      if (!Directory.Exists(dir)) continue;
      foreach (var f in Directory.GetFiles(dir, "rollout-*.jsonl")) { var t = File.GetLastWriteTime(f); if (t > bt) { bt = t; best = f; } }
      if (best != null) break;
    }
    return best;
  }
  static string Tail(string path, int bytes) {
    using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
      long start = Math.Max(0, fs.Length - bytes); fs.Seek(start, SeekOrigin.Begin);
      var buf = new byte[fs.Length - start]; int read = 0; while (read < buf.Length) { int r = fs.Read(buf, read, buf.Length - read); if (r <= 0) break; read += r; }
      return Encoding.UTF8.GetString(buf, 0, read);
    }
  }
}

// push-to-talk: low-level keyboard hook on the HUD's UI thread; only the talk key, only in the Jarvis window.
// Engine "whisper" (default): ears.py records while the key is held and transcribes on this PC (faster-whisper),
// then the words are typed into Codex and sent. Engine "windows": the old Windows voice typing (Win+H).
public static class TJPtt {
  delegate IntPtr LLProc(int nCode, IntPtr wParam, IntPtr lParam);
  [StructLayout(LayoutKind.Sequential)] struct KBD { public uint vk, scan, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
  [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, LLProc fn, IntPtr mod, uint tid);
  [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string n);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  static LLProc proc = Hook; static IntPtr hook; static uint Vk; static volatile bool held, active;
  static string Engine = "windows", Uv, Script, StatePath, LogPath; static bool AutoSend = true;
  static Process ears; static readonly object earsLock = new object();
  public static volatile string State = "";      // "" | LISTENING | TRANSCRIBING | WARMING UP | MIC ERROR (shown on the chip)

  public static void Install(uint vk, string engine, string uv, string script, string statePath, bool autoSend) {
    Vk = vk; Engine = (engine ?? "windows").ToLower(); Uv = uv; Script = script; StatePath = statePath; AutoSend = autoSend;
    LogPath = Path.Combine(Path.GetDirectoryName(statePath), "ears.log");
    if (vk == 0) return;
    hook = SetWindowsHookEx(13, proc, GetModuleHandle(null), 0);
    if (Engine == "whisper") { EnsureEars(); Application.ApplicationExit += (s, e) => StopEars(); }
  }
  static void Log(string m) { try { File.AppendAllText(LogPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss ") + m + Environment.NewLine); } catch { } }

  // ---- the speech engine: one warm process for the life of the HUD ----
  static void EnsureEars() {
    lock (earsLock) {
      if (ears != null && !ears.HasExited) return;
      if (string.IsNullOrEmpty(Uv) || !File.Exists(Uv) || !File.Exists(Script)) { Log("ears: uv or ears.py missing"); return; }
      try {
        var psi = new ProcessStartInfo(Uv, "run --script \"" + Script + "\" --serve --state \"" + StatePath + "\"");
        psi.UseShellExecute = false; psi.CreateNoWindow = true;
        psi.RedirectStandardInput = true; psi.RedirectStandardOutput = true; psi.RedirectStandardError = true;
        psi.StandardOutputEncoding = Encoding.UTF8;
        psi.EnvironmentVariables["UV_SYSTEM_CERTS"] = "1";
        ears = Process.Start(psi);
        var p = ears;
        new Thread(() => ReadOut(p)) { IsBackground = true }.Start();
        new Thread(() => { try { string e; while ((e = p.StandardError.ReadLine()) != null) { if (e.Trim().Length > 0 && !e.Contains("UV_")) Log("ears: " + e); } } catch { } }) { IsBackground = true }.Start();
      } catch (Exception ex) { Log("ears start failed: " + ex.Message); ears = null; }
    }
  }
  static void StopEars() { lock (earsLock) { try { if (ears != null && !ears.HasExited) { ears.StandardInput.Close(); if (!ears.WaitForExit(1500)) ears.Kill(); } } catch { } ears = null; } }
  static void Send(string cmd) {
    lock (earsLock) { try { if (ears != null && !ears.HasExited) { ears.StandardInput.WriteLine(cmd); ears.StandardInput.Flush(); } } catch (Exception ex) { Log("ears send failed: " + ex.Message); } }
  }
  static void ReadOut(Process p) {
    try {
      string line;
      while ((line = p.StandardOutput.ReadLine()) != null) {
        if (line.StartsWith("TEXT")) {
          string text = "";
          try { text = Encoding.UTF8.GetString(Convert.FromBase64String(line.Length > 5 ? line.Substring(5).Trim() : "")); } catch { }
          State = "";
          text = text.Replace("\r", " ").Replace("\n", " ").Trim();
          if (text.Length > 0 && TJHud.IsJarvis(GetForegroundWindow())) { TypeText(text); if (AutoSend) { Thread.Sleep(60); Tap(0x0D); } }
        } else if (line.StartsWith("ERROR")) {
          Log("ears: " + line); State = "MIC ERROR"; ThreadPool.QueueUserWorkItem(x => { Thread.Sleep(2500); if (State == "MIC ERROR") State = ""; });
        } else if (line == "READY" && State == "WARMING UP") State = "";
      }
    } catch { }
    if (State != "") State = "";
  }
  static void TypeText(string s) {
    var list = new List<INPUT>();
    foreach (char c in s) {
      var d = new INPUT { type = 1 }; d.u.ki = new KEYBDINPUT { vk = 0, scan = c, flags = 0x0004 };            // KEYEVENTF_UNICODE
      var u = new INPUT { type = 1 }; u.u.ki = new KEYBDINPUT { vk = 0, scan = c, flags = 0x0004 | 0x0002 };   // + KEYUP
      list.Add(d); list.Add(u);
    }
    if (list.Count > 0) SendInput((uint)list.Count, list.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }

  static void Tap(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); keybd_event(vk, 0, 2, UIntPtr.Zero); }
  static void WinH() { keybd_event(0x5B, 0, 0, UIntPtr.Zero); Tap(0x48); keybd_event(0x5B, 0, 2, UIntPtr.Zero); }
  static void Pressed() {
    if (Engine != "whisper") { ThreadPool.QueueUserWorkItem(x => WinH()); return; }
    ThreadPool.QueueUserWorkItem(x => { EnsureEars(); Send("start"); });
    State = "LISTENING";
  }
  static void Released() {
    if (Engine != "whisper") {
      ThreadPool.QueueUserWorkItem(x => { Thread.Sleep(450); WinH(); Thread.Sleep(1100); if (TJHud.IsJarvis(GetForegroundWindow())) Tap(0x0D); });
      return;
    }
    State = "TRANSCRIBING";
    ThreadPool.QueueUserWorkItem(x => Send("stop"));
    ThreadPool.QueueUserWorkItem(x => { Thread.Sleep(20000); if (State == "TRANSCRIBING") State = ""; });   // never stick
  }
  static IntPtr Hook(int n, IntPtr w, IntPtr l) {
    if (n >= 0) {
      var k = (KBD)Marshal.PtrToStructure(l, typeof(KBD));
      if (k.vk == Vk && (k.flags & 0x10) == 0) {
        int msg = w.ToInt32(); bool isDown = msg == 0x100 || msg == 0x104, isUp = msg == 0x101 || msg == 0x105;
        if (isDown) {
          if (held) return active ? (IntPtr)1 : CallNextHookEx(hook, n, w, l);
          held = true;
          if (TJHud.IsJarvis(GetForegroundWindow())) { active = true; Pressed(); return (IntPtr)1; }
        } else if (isUp) {
          held = false;
          if (active) { active = false; Released(); return (IntPtr)1; }
        }
      }
    }
    return CallNextHookEx(hook, n, w, l);
  }
}
"@
$engine = if ($state.ptt_engine) { [string]$state.ptt_engine } else { "windows" }
$uv = [string]$state.uv_exe
[TJPtt]::Install([uint32]$vk, $engine, $uv, (Join-Path $Dir "voice\ears.py"), (Join-Path $Dir "state.json"), ($state.ptt_auto_send -ne $false))
[TJHud]::Start([string]$state.assistant)
