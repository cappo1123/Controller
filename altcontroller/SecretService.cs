using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Runtime.InteropServices;

namespace SecretServicePanel
{
    // ── Colour palette ──────────────────────────────────────────────
    static class Theme
    {
        public static readonly Color BgDeep       = Color.FromArgb(10, 10, 10);
        public static readonly Color BgPanel      = Color.FromArgb(15, 15, 15);
        public static readonly Color BgSurface    = Color.FromArgb(22, 22, 22);
        public static readonly Color BgInput      = Color.FromArgb(20, 20, 20);
        public static readonly Color Border       = Color.FromArgb(35, 35, 35);
        public static readonly Color BorderLight  = Color.FromArgb(45, 45, 45);
        public static readonly Color Accent       = Color.FromArgb(0, 255, 128);   // Vibrant Terminal Green
        public static readonly Color AccentHover  = Color.FromArgb(50, 255, 170);  // Lighter Green
        public static readonly Color AccentDim    = Color.FromArgb(0, 180, 90);    // Darker Green
        public static readonly Color Danger       = Color.FromArgb(220, 50, 50);
        public static readonly Color Success      = Color.FromArgb(0, 255, 128);
        public static readonly Color TextPrimary  = Color.FromArgb(240, 240, 240);
        public static readonly Color TextSecondary= Color.FromArgb(170, 170, 170);
        public static readonly Color TextDim      = Color.FromArgb(110, 110, 110);
        public static readonly Color BtnDefault   = Color.FromArgb(25, 25, 25);
        public static readonly Color BtnHover     = Color.FromArgb(35, 35, 35);
        public static readonly Color BtnPressed   = Color.FromArgb(20, 20, 20);
        public static readonly Color CatLabel     = Color.FromArgb(0, 255, 128);   // Changed to Green

        public static readonly Font  Title        = new Font("Tahoma", 11F, FontStyle.Bold);
        public static readonly Font  Body         = new Font("Tahoma", 8F);
        public static readonly Font  BodyBold     = new Font("Tahoma", 8F, FontStyle.Bold);
        public static readonly Font  Small        = new Font("Tahoma", 7.5F);
        public static readonly Font  MonoFallback = new Font("Tahoma", 8F);
        public static readonly Font  BtnFont      = new Font("Tahoma", 8F, FontStyle.Bold);
        public static readonly Font  CatFont      = new Font("Tahoma", 7F, FontStyle.Bold);
        public static readonly Font  InputFont    = new Font("Tahoma", 10F);

        private static Font _mono;
        public static Font GetMono()
        {
            if (_mono != null) return _mono;
            try
            {
                _mono = new Font("Tahoma", 8F);
                if (_mono.Name != "Tahoma")
                {
                    _mono.Dispose();
                    _mono = MonoFallback;
                }
            }
            catch
            {
                _mono = MonoFallback;
            }
            return _mono;
        }
    }

    // ── Rounded-corner button ───────────────────────────────────────
    class ModernButton : Button
    {
        private bool _hovered;
        private bool _pressed;
        private int _cornerRadius = 8;
        private Color _baseColor = Theme.BtnDefault;
        private Color _hoverColor = Theme.BtnHover;
        private Color _pressColor = Theme.BtnPressed;
        private Color _accentBorder = Color.Transparent;

        public int CornerRadius { get { return _cornerRadius; } set { _cornerRadius = value; Invalidate(); } }
        public Color BaseColor { get { return _baseColor; } set { _baseColor = value; Invalidate(); } }
        public Color HoverColor { get { return _hoverColor; } set { _hoverColor = value; Invalidate(); } }
        public Color PressColor { get { return _pressColor; } set { _pressColor = value; Invalidate(); } }
        public Color AccentBorder { get { return _accentBorder; } set { _accentBorder = value; Invalidate(); } }

        public ModernButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            ForeColor = Theme.TextPrimary;
            Font = Theme.BtnFont;
            Cursor = Cursors.Hand;
        }

        protected override void OnMouseEnter(EventArgs e) { _hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hovered = false; _pressed = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { _pressed = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { _pressed = false; Invalidate(); base.OnMouseUp(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.SingleBitPerPixelGridFit;

            g.Clear(Parent != null ? Parent.BackColor : Theme.BgDeep);

            var rect = new Rectangle(0, 0, Width - 1, Height - 1);
            Color fill = _pressed ? _pressColor : (_hovered ? _hoverColor : _baseColor);

            using (var path = RoundedRect(rect, _cornerRadius))
            using (var brush = new SolidBrush(fill))
            {
                g.FillPath(brush, path);

                // Green bottom glow on hover — soft upward bleed covering full button
                if (_hovered && !_pressed)
                {
                    var oldClip = g.Clip;
                    using (var clipRegion = new Region(path))
                    {
                        g.SetClip(clipRegion, System.Drawing.Drawing2D.CombineMode.Replace);

                        // Soft glow from top (transparent) to bottom (subtle green)
                        var glowRect = new Rectangle(0, 0, Width, Height + 1);
                        using (var glowBrush = new LinearGradientBrush(
                            glowRect, Color.Transparent, Color.FromArgb(35, 0, 255, 128), 90F))
                        {
                            g.FillRectangle(glowBrush, glowRect);
                        }

                        // Solid bright green line at the very bottom
                        using (var pen = new Pen(Color.FromArgb(220, 0, 255, 128), 2))
                            g.DrawLine(pen, 1, Height - 2, Width - 1, Height - 2);

                        g.Clip = oldClip;
                    }
                }

                // border
                Color borderCol = _hovered ? Theme.BorderLight : Theme.Border;
                if (_accentBorder != Color.Transparent) borderCol = _accentBorder;
                using (var pen = new Pen(borderCol, 1))
                    g.DrawPath(pen, path);
            }

            // text — green on hover
            TextRenderer.DrawText(g, Text, Font, new Rectangle(0, 0, Width, Height), _hovered ? Theme.Accent : Color.FromArgb(200, ForeColor),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }

        private static GraphicsPath RoundedRect(Rectangle bounds, int radius)
        {
            int d = radius * 2;
            var gp = new GraphicsPath();
            gp.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
            gp.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
            gp.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
            gp.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
            gp.CloseFigure();
            return gp;
        }
    }

    // ── Modern toggle switch ────────────────────────────────────────
    class ToggleSwitch : Control
    {
        private bool _checked;
        public bool Checked
        {
            get { return _checked; }
            set { _checked = value; Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); }
        }
        public event EventHandler CheckedChanged;

        public ToggleSwitch()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            Size = new Size(42, 22);
            Cursor = Cursors.Hand;
        }

        protected override void OnClick(EventArgs e) { Checked = !Checked; base.OnClick(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Parent != null ? Parent.BackColor : Theme.BgDeep);

            var trackRect = new Rectangle(0, 1, Width - 1, Height - 2);
            Color trackColor = _checked ? Theme.Accent : Theme.BgSurface;
            using (var path = RoundedRect(trackRect, Height / 2))
            using (var brush = new SolidBrush(trackColor))
            using (var pen = new Pen(_checked ? Theme.Accent : Theme.Border, 1))
            {
                g.FillPath(brush, path);
                g.DrawPath(pen, path);
            }

            int knobSize = Height - 6;
            int knobX = _checked ? Width - knobSize - 3 : 3;
            using (var brush = new SolidBrush(_checked ? Theme.BgDeep : Color.White))
                g.FillEllipse(brush, knobX, 3, knobSize, knobSize);
        }

        private static GraphicsPath RoundedRect(Rectangle b, int r)
        {
            int d = r * 2;
            var gp = new GraphicsPath();
            gp.AddArc(b.X, b.Y, d, d, 180, 90);
            gp.AddArc(b.Right - d, b.Y, d, d, 270, 90);
            gp.AddArc(b.Right - d, b.Bottom - d, d, d, 0, 90);
            gp.AddArc(b.X, b.Bottom - d, d, d, 90, 90);
            gp.CloseFigure();
            return gp;
        }
    }

    // ── Inset panel (used as border wrapper) ────────────────────────
    class InsetPanel : Panel
    {
        private int _radius = 8;
        public int CornerRadius { get { return _radius; } set { _radius = value; Invalidate(); } }

        public InsetPanel()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.BgInput;
            Padding = new Padding(1);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            var rect = new Rectangle(0, 0, Width - 1, Height - 1);
            using (var pen = new Pen(Theme.Border, 1))
            using (var path = RoundedRect(rect, _radius))
                g.DrawPath(pen, path);
        }

        private static GraphicsPath RoundedRect(Rectangle b, int r)
        {
            int d = r * 2;
            var gp = new GraphicsPath();
            gp.AddArc(b.X, b.Y, d, d, 180, 90);
            gp.AddArc(b.Right - d, b.Y, d, d, 270, 90);
            gp.AddArc(b.Right - d, b.Bottom - d, d, d, 0, 90);
            gp.AddArc(b.X, b.Bottom - d, d, d, 90, 90);
            gp.CloseFigure();
            return gp;
        }
    }

    class WrappingFlowPanel : FlowLayoutPanel
    {
        [DllImport("user32.dll")]
        private static extern bool ShowScrollBar(IntPtr hWnd, int wBar, bool bShow);
        private const int SB_BOTH = 3;

        public WrappingFlowPanel()
        {
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            AutoScroll = true;
        }

        private void HideAllBars()
        {
            if (IsHandleCreated && !IsDisposed)
                ShowScrollBar(this.Handle, SB_BOTH, false);
        }

        protected override void OnLayout(LayoutEventArgs levent)
        {
            base.OnLayout(levent);
            HideAllBars();
        }

        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            // Hide on paint or non-client paint, but avoid fighting scroll messages
            if (m.Msg == 0x0085 || m.Msg == 0x000F) 
                HideAllBars();
        }

        public void DoScroll(int delta)
        {
            if (!AutoScroll) return;
            
            // AutoScrollPosition.Y is negative when scrolled down
            int currentY = -this.AutoScrollPosition.Y;
            int step = 44; 
            int newVal = currentY - (Math.Sign(delta) * step);
            
            // WinForms handles clamping automatically when setting AutoScrollPosition
            this.AutoScrollPosition = new Point(0, newVal);
            HideAllBars();
        }
    }

    // ── Custom ListBox to strictly hide scrollbar while keeping virtual height ──
    class HiddenScrollBarListBox : ListBox
    {
        [DllImport("user32.dll")]
        private static extern bool ShowScrollBar(IntPtr hWnd, int wBar, bool bShow);
        private const int SB_VERT = 1;

        public HiddenScrollBarListBox()
        {
            this.DrawMode = DrawMode.OwnerDrawFixed;
            this.IntegralHeight = false;
        }

        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            // Re-hide scrollbar whenever the OS tries to paint or interact with it
            if (m.Msg == 0x0085 || m.Msg == 0x0115 || m.Msg == 0x0114 || m.Msg == 0x000F) 
            {
                if (IsHandleCreated && !IsDisposed)
                    ShowScrollBar(this.Handle, SB_VERT, false);
            }
        }
    }

    // ── Category label for button groups ─────────────────────────────
    class CategoryLabel : Label
    {
        public CategoryLabel(string text)
        {
            Text = text.ToUpper();
            Font = Theme.CatFont;
            ForeColor = Theme.CatLabel;
            AutoSize = false;
            Height = 20;
            TextAlign = ContentAlignment.BottomLeft;
            Padding = new Padding(2, 0, 0, 0);
            Margin = new Padding(4, 8, 4, 0);
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MAIN FORM
    // ════════════════════════════════════════════════════════════════
    public class MainForm : Form, IMessageFilter
    {
        private static ConcurrentDictionary<WebSocket, SemaphoreSlim> _clients = new ConcurrentDictionary<WebSocket, SemaphoreSlim>();
        private static ConcurrentDictionary<string, string> _players = new ConcurrentDictionary<string, string>();
        private HttpListener _listener;
        private CancellationTokenSource _cts;

        // UI controls
        private Panel pnlHeader;
        private Label lblTitle;
        private Label lblStatus;
        private Panel pnlStatusDot;
        private RichTextBox txtLog;
        private TextBox txtCommand;
        private ListBox lstPlayers;
        private Label lblPlayers;
        private ToggleSwitch toggleOnTop;
        private Label lblToggle;
        private ModernButton btnSend;
        private FlowLayoutPanel flpCommands;
        private List<CategoryLabel> _catLabels;

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        [DllImport("user32.dll")]
        private static extern IntPtr WindowFromPoint(Point p);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

        public bool PreFilterMessage(ref Message m)
        {
            if (m.Msg == 0x020A) // WM_MOUSEWHEEL
            {
                // WM_MOUSEWHEEL coordinates are screen coordinates in LParam
                int lParam = unchecked((int)m.LParam.ToInt64());
                Point pos = new Point((short)(lParam & 0xFFFF), (short)((lParam >> 16) & 0xFFFF));
                
                IntPtr hWnd = WindowFromPoint(pos);
                
                // Allow forwarding even when the hovered control has focus
                if (hWnd != IntPtr.Zero)
                {
                    Control hovered = Control.FromHandle(hWnd);
                    if (hovered != null)
                    {
                        int delta = unchecked((short)((m.WParam.ToInt64() >> 16) & 0xFFFF));
                        Control target = hovered;
                        
                        while (target != null)
                        {
                            if (target is WrappingFlowPanel)
                            {
                                ((WrappingFlowPanel)target).DoScroll(delta);
                                return true;
                            }
                            else if (target is ListBox)
                            {
                                var lb = (ListBox)target;
                                int scrollLines = SystemInformation.MouseWheelScrollLines;
                                if (scrollLines == -1) scrollLines = 3;
                                
                                int newTop = lb.TopIndex - (Math.Sign(delta) * scrollLines);
                                if (newTop < 0) newTop = 0;
                                if (newTop >= lb.Items.Count) newTop = Math.Max(0, lb.Items.Count - 1);
                                lb.TopIndex = newTop;
                                return true;
                            }
                            else if (target is RichTextBox)
                            {
                                SendMessage(target.Handle, m.Msg, m.WParam, m.LParam);
                                return true;
                            }
                            target = target.Parent;
                        }

                        SendMessage(hWnd, m.Msg, m.WParam, m.LParam);
                        return true;
                    }
                }
            }
            return false;
        }

        private void UseDarkTitleBar()
        {
            try
            {
                int attribute = 20; // DWMWA_USE_IMMERSIVE_DARK_MODE
                int useDarkMode = 1;
                DwmSetWindowAttribute(this.Handle, attribute, ref useDarkMode, sizeof(int));
            }
            catch { /* Fallback for older Windows versions */ }
        }

        public MainForm()
        {
            Application.AddMessageFilter(this);
            InitializeComponents();
            UseDarkTitleBar();
            StartServerAsync();
        }

        private void InitializeComponents()
        {
            // ── Form setup ──────────────────────────────────────────
            Text = "Secret Service";
            Size = new Size(720, 580);
            MinimumSize = new Size(660, 480);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Theme.BgDeep;
            ForeColor = Theme.TextPrimary;
            Font = Theme.Body;
            DoubleBuffered = true;

            // ── Header ──────────────────────────────────────────────
            pnlHeader = new Panel();
            pnlHeader.Dock = DockStyle.Top;
            pnlHeader.Height = 52;
            pnlHeader.BackColor = Theme.BgPanel;
            pnlHeader.Padding = new Padding(16, 0, 16, 0);
            Controls.Add(pnlHeader);


            lblTitle = new Label();
            lblTitle.Text = "Secret Service";
            lblTitle.Font = Theme.Title;
            lblTitle.ForeColor = Theme.TextPrimary;
            lblTitle.AutoSize = true;
            lblTitle.Location = new Point(16, 14);
            pnlHeader.Controls.Add(lblTitle);

            pnlStatusDot = new Panel();
            pnlStatusDot.Size = new Size(10, 10);
            pnlStatusDot.Location = new Point(155, 21);
            pnlStatusDot.BackColor = Color.FromArgb(250, 204, 21); // yellow = starting
            pnlHeader.Controls.Add(pnlStatusDot);
            pnlStatusDot.Paint += (s, e) => {
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                using (var brush = new SolidBrush(pnlStatusDot.BackColor))
                    e.Graphics.FillEllipse(brush, 0, 0, 9, 9);
            };

            lblStatus = new Label();
            lblStatus.Text = "Starting server...";
            lblStatus.Font = Theme.Small;
            lblStatus.ForeColor = Theme.TextSecondary;
            lblStatus.AutoSize = true;
            lblStatus.Location = new Point(170, 18);
            pnlHeader.Controls.Add(lblStatus);

            // toggle on-top in header
            lblToggle = new Label();
            lblToggle.Text = "Pin";
            lblToggle.Font = Theme.Small;
            lblToggle.ForeColor = Theme.TextDim;
            lblToggle.AutoSize = true;
            lblToggle.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            lblToggle.Location = new Point(this.ClientSize.Width - 82, 17);
            pnlHeader.Controls.Add(lblToggle);

            toggleOnTop = new ToggleSwitch();
            toggleOnTop.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            toggleOnTop.Location = new Point(this.ClientSize.Width - 56, 15);
            toggleOnTop.CheckedChanged += (s, e) => this.TopMost = toggleOnTop.Checked;
            pnlHeader.Controls.Add(toggleOnTop);

            // ── Main content area ──────────────────────────────────
            var pnlMain = new Panel();
            pnlMain.Dock = DockStyle.Fill;
            pnlMain.Padding = new Padding(12);
            Controls.Add(pnlMain);
            pnlMain.BringToFront();

            // ── Bottom section (Commands) ──────────────────────────
            var pnlBottom = new Panel();
            pnlBottom.Dock = DockStyle.Bottom;
            pnlBottom.Height = 280;
            pnlMain.Controls.Add(pnlBottom);

            // ── Top section (Log & Players) ────────────────────────
            var pnlTopGroup = new Panel();
            pnlTopGroup.Dock = DockStyle.Fill;
            pnlMain.Controls.Add(pnlTopGroup);

            // ── Player list (Right side of top) ────────────────────
            var pnlPlayersRight = new Panel();
            pnlPlayersRight.Dock = DockStyle.Right;
            pnlPlayersRight.Width = 160;
            pnlPlayersRight.Padding = new Padding(8, 0, 0, 0);
            pnlTopGroup.Controls.Add(pnlPlayersRight);

            lblPlayers = new Label();
            lblPlayers.Text = "PLAYERS";
            lblPlayers.Font = Theme.CatFont;
            lblPlayers.ForeColor = Theme.CatLabel;
            lblPlayers.Dock = DockStyle.Top;
            lblPlayers.Height = 22;
            pnlPlayersRight.Controls.Add(lblPlayers);

            var playerWrapper = new InsetPanel();
            playerWrapper.Dock = DockStyle.Fill;
            pnlPlayersRight.Controls.Add(playerWrapper);

            lstPlayers = new HiddenScrollBarListBox();
            lstPlayers.Dock = DockStyle.Fill;
            lstPlayers.BackColor = Theme.BgInput;
            lstPlayers.ForeColor = Theme.TextPrimary;
            lstPlayers.Font = Theme.Body;
            lstPlayers.BorderStyle = BorderStyle.None;
            // Native listbox needs this true so it creates a virtual scroll extent
            lstPlayers.ScrollAlwaysVisible = true;
            lstPlayers.IntegralHeight = false;
            lstPlayers.DrawMode = DrawMode.OwnerDrawFixed;
            lstPlayers.ItemHeight = 26;
            lstPlayers.DrawItem += LstPlayers_DrawItem;
            lstPlayers.DoubleClick += LstPlayers_DoubleClick;
            lstPlayers.MouseDown += (s, e) => {
                if (lstPlayers.IndexFromPoint(e.Location) == ListBox.NoMatches)
                    lstPlayers.SelectedIndex = -1;
            };
            
            lstPlayers.MouseWheel += (s, e) => {
                int scrollLines = SystemInformation.MouseWheelScrollLines;
                if (scrollLines < 1) scrollLines = 3;
                int newTop = lstPlayers.TopIndex - (Math.Sign(e.Delta) * scrollLines);
                if (newTop < 0) newTop = 0;
                if (newTop >= lstPlayers.Items.Count) newTop = Math.Max(0, lstPlayers.Items.Count - 1);
                lstPlayers.TopIndex = newTop;
                
                var he = e as HandledMouseEventArgs;
                if (he != null) he.Handled = true;
            };

            playerWrapper.Controls.Add(lstPlayers);

            // ── Log area (Fill of top) ─────────────────────────────
            var logWrapper = new InsetPanel();
            logWrapper.Dock = DockStyle.Fill;
            pnlTopGroup.Controls.Add(logWrapper);

            txtLog = new RichTextBox();
            txtLog.Dock = DockStyle.Fill;
            txtLog.ReadOnly = true;
            txtLog.BackColor = Theme.BgInput;
            txtLog.ForeColor = Theme.TextSecondary;
            txtLog.Font = Theme.GetMono();
            txtLog.BorderStyle = BorderStyle.None;
            txtLog.ScrollBars = RichTextBoxScrollBars.Vertical;
            logWrapper.Controls.Add(txtLog);

            flpCommands = new WrappingFlowPanel();
            flpCommands.Dock = DockStyle.Fill;
            flpCommands.AutoScroll = true;
            flpCommands.BackColor = Theme.BgDeep;
            flpCommands.WrapContents = true;
            flpCommands.Padding = new Padding(0, 0, 0, 40); // Added bottom padding so last buttons aren't at the edge
            pnlBottom.Controls.Add(flpCommands);

            var cmdSep = new Panel();
            cmdSep.Dock = DockStyle.Top;
            cmdSep.Height = 1;
            cmdSep.BackColor = Theme.Border;
            pnlBottom.Controls.Add(cmdSep);

            var pnlCmdBar = new Panel();
            pnlCmdBar.Dock = DockStyle.Top;
            pnlCmdBar.Height = 52;
            pnlBottom.Controls.Add(pnlCmdBar);

            txtCommand = new TextBox();
            txtCommand.Location = new Point(6, 12);
            txtCommand.Width = pnlCmdBar.Width - 84;
            txtCommand.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            txtCommand.Font = Theme.InputFont;
            txtCommand.BackColor = Theme.BgInput;
            txtCommand.ForeColor = Theme.TextPrimary;
            txtCommand.BorderStyle = BorderStyle.None;
            txtCommand.KeyPress += TxtCommand_KeyPress;
            pnlCmdBar.Controls.Add(txtCommand);

            var cmdWrapper = new InsetPanel();
            cmdWrapper.Location = new Point(0, 5);
            cmdWrapper.Width = pnlCmdBar.Width - 78;
            cmdWrapper.Height = 38;
            cmdWrapper.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            pnlCmdBar.Controls.Add(cmdWrapper);
            txtCommand.BringToFront();

            btnSend = new ModernButton();
            btnSend.Text = "Send";
            btnSend.Size = new Size(72, 38);
            btnSend.Location = new Point(pnlCmdBar.Width - 72, 5);
            btnSend.BaseColor = Theme.BtnDefault;
            btnSend.HoverColor = Theme.BtnHover;
            btnSend.PressColor = Theme.BtnPressed;
            btnSend.ForeColor = Theme.TextPrimary;
            btnSend.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            btnSend.Click += BtnSend_Click;
            pnlCmdBar.Controls.Add(btnSend);


            // categorized commands
            var cmdGroups = new Dictionary<string, string[]>();
            cmdGroups["Basic"] = new[] { "jump", "stop", "reset", "bring" };
            cmdGroups["Formations"] = new[] { "worm", "vform", "army", "flank", "circlein", "circleout" };
            cmdGroups["Movement"] = new[] { "spin", "swarm", "orbit", "tornado", "panic", "goto" };
            cmdGroups["Structures"] = new[] { "stack", "mech", "alt mech", "elevator", "carpet", "ufo", "pillar", "motorcycle", "heli", "jumba", "aura" };
            cmdGroups["Combat"] = new[] { "bodyguard", "stalk", "allfling", "fling", "haunted" };
            cmdGroups["Inventory"] = new[] { "equip1" };

            _catLabels = new List<CategoryLabel>();
            foreach (var group in cmdGroups)
            {
                var catLabel = new CategoryLabel(group.Key);
                flpCommands.Controls.Add(catLabel);
                flpCommands.SetFlowBreak(catLabel, true);
                _catLabels.Add(catLabel);

                foreach (string cmd in group.Value)
                {
                    var btn = new ModernButton();
                    btn.Text = cmd;
                    btn.Size = new Size(84, 34);
                    btn.Margin = new Padding(3, 2, 3, 2);
                    btn.Font = Theme.Small;
                    
                    string captured = cmd;
                    btn.Click += (s, e) => SendCommand(captured == "motorcycle" ? "bike" : captured);
                    flpCommands.Controls.Add(btn);
                }
            }

            flpCommands.Layout += (s, e) => {
                int labelWidth = Math.Max(50, flpCommands.ClientSize.Width - 24);
                foreach (var cl in _catLabels) cl.Width = labelWidth;
            };

            this.FormClosing += MainForm_FormClosing;
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            if (flpCommands != null) flpCommands.PerformLayout();
        }

        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
        }

        // ── Owner-draw for modern player list ───────────────────────
        private void LstPlayers_DrawItem(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

            bool selected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
            Color bg = selected ? Theme.Accent : Theme.BgInput;
            Color fg = selected ? Color.White : Theme.TextPrimary;

            using (var brush = new SolidBrush(bg))
                e.Graphics.FillRectangle(brush, e.Bounds);

            string text = lstPlayers.Items[e.Index].ToString();
            TextRenderer.DrawText(e.Graphics, text, Theme.Body, e.Bounds, fg,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.LeftAndRightPadding);

            // subtle bottom separator
            if (!selected)
            {
                using (var pen = new Pen(Theme.Border))
                    e.Graphics.DrawLine(pen, e.Bounds.Left + 4, e.Bounds.Bottom - 1, e.Bounds.Right - 4, e.Bounds.Bottom - 1);
            }
        }

        private void LstPlayers_DoubleClick(object sender, EventArgs e)
        {
            if (lstPlayers.SelectedItem != null)
            {
                string selectedDisplay = lstPlayers.SelectedItem.ToString();
                foreach (var kvp in _players)
                {
                    if (kvp.Value == selectedDisplay)
                    {
                        txtCommand.Text += (txtCommand.Text.EndsWith(" ") || txtCommand.Text.Length == 0 ? "" : " ") + kvp.Key;
                        txtCommand.Focus();
                        txtCommand.SelectionStart = txtCommand.Text.Length;
                        break;
                    }
                }
            }
        }

        private void TxtCommand_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == (char)Keys.Enter)
            {
                e.Handled = true;
                BtnSend_Click(sender, e);
            }
        }

        private void BtnSend_Click(object sender, EventArgs e)
        {
            string cmd = txtCommand.Text.Trim();
            if (!string.IsNullOrEmpty(cmd))
            {
                SendCommand(cmd);
                txtCommand.Clear();
            }
        }

        private void SendCommand(string command)
        {
            if (lstPlayers.SelectedItem != null)
            {
                string selectedDisplay = lstPlayers.SelectedItem.ToString();
                string playerName = null;
                foreach (var kvp in _players)
                {
                    if (kvp.Value == selectedDisplay)
                    {
                        playerName = kvp.Key;
                        break;
                    }
                }

                if (!string.IsNullOrEmpty(playerName))
                {
                    string cmdLower = command.ToLower();
                    string playerLower = playerName.ToLower();
                    // Simple check to see if player name is already in the command as a word
                    bool alreadyHasPlayer = false;
                    string[] words = cmdLower.Split(' ');
                    foreach(string w in words) {
                        if (w == playerLower) {
                            alreadyHasPlayer = true;
                            break;
                        }
                    }

                    if (!alreadyHasPlayer)
                    {
                        command += " " + playerName;
                    }
                }
            }

            Log("» " + command);
            BroadcastMessageAsync(command);
        }

        private void Log(string message)
        {
            if (this.InvokeRequired)
            {
                this.Invoke(new Action<string>(Log), message);
                return;
            }
            string timestamp = DateTime.Now.ToString("HH:mm:ss");
            txtLog.AppendText(string.Format("[{0}] {1}\n", timestamp, message));
            txtLog.ScrollToCaret();
        }

        private void UpdateStatus(string status)
        {
            if (this.InvokeRequired)
            {
                this.Invoke(new Action<string>(UpdateStatus), status);
                return;
            }
            lblStatus.Text = status;

            // Update status dot color
            if (status.Contains("running") || status.Contains("Connected"))
                pnlStatusDot.BackColor = Theme.Success;
            else if (status.Contains("Error"))
                pnlStatusDot.BackColor = Theme.Danger;
            else
                pnlStatusDot.BackColor = Color.FromArgb(250, 204, 21);
            pnlStatusDot.Invalidate();
        }

        // ════════════════════════════════════════════════════════════
        //  SERVER LOGIC (unchanged)
        // ════════════════════════════════════════════════════════════

        private async void StartServerAsync()
        {
            _cts = new CancellationTokenSource();
            int port = 8080;
            _listener = new HttpListener();
            _listener.Prefixes.Add(string.Format("http://localhost:{0}/", port));

            try
            {
                _listener.Start();
                UpdateStatus(string.Format("Server running on port {0}. Waiting for Alts...", port));
                Log("WebSocket Server Started.");
            }
            catch (Exception ex)
            {
                UpdateStatus("Error starting server!");
                Log("Error: " + ex.Message);
                return;
            }

            try
            {
                while (!_cts.Token.IsCancellationRequested)
                {
                    HttpListenerContext context = await _listener.GetContextAsync();

                    if (context.Request.IsWebSocketRequest)
                    {
                        var _ = ProcessRequestAsync(context);
                    }
                    else
                    {
                        context.Response.StatusCode = 400;
                        context.Response.Close();
                    }
                }
            }
            catch (HttpListenerException)
            {
                // Listener stopped
            }
        }

        private async Task ProcessRequestAsync(HttpListenerContext context)
        {
            HttpListenerWebSocketContext webSocketContext = null;

            try
            {
                webSocketContext = await context.AcceptWebSocketAsync(null);
            }
            catch
            {
                context.Response.StatusCode = 500;
                context.Response.Close();
                return;
            }

            WebSocket webSocket = webSocketContext.WebSocket;
            _clients.TryAdd(webSocket, new SemaphoreSlim(1, 1));
            UpdateStatus(string.Format("Connected Alts: {0}", _clients.Count));

            byte[] receiveBuffer = new byte[1024];

            try
            {
                while (webSocket.State == WebSocketState.Open)
                {
                    WebSocketReceiveResult receiveResult = await webSocket.ReceiveAsync(new ArraySegment<byte>(receiveBuffer), CancellationToken.None);

                    if (receiveResult.MessageType == WebSocketMessageType.Close)
                    {
                        await webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None);
                    }
                    else if (receiveResult.MessageType == WebSocketMessageType.Text)
                    {
                        int count = receiveResult.Count;
                        byte[] messageBytes = new byte[count];
                        Buffer.BlockCopy(receiveBuffer, 0, messageBytes, 0, count);
                        string msgString = Encoding.UTF8.GetString(messageBytes);
                        
                        if (msgString.Contains("SYNC_PLAYERS|"))
                        {
                            string syncData = msgString.Substring(msgString.IndexOf("SYNC_PLAYERS|") + 13);
                            string[] players = syncData.Split(',');
                            _players.Clear();
                            foreach (string p in players)
                            {
                                if (!string.IsNullOrEmpty(p))
                                {
                                    string[] parts = p.Split(':');
                                    if (parts.Length == 2)
                                    {
                                        _players[parts[0]] = parts[1];
                                    }
                                }
                            }
                            UpdatePlayerList();
                        }
                        else if (!msgString.StartsWith("STATUS|"))
                        {
                            Log("Received: " + msgString);
                        }

                        // Broadcast to all clients as a relay
                        string relayMsg = "RELAY|" + msgString;
                        byte[] relayBytes = Encoding.UTF8.GetBytes(relayMsg);
                        ArraySegment<byte> relaySegment = new ArraySegment<byte>(relayBytes);

                        foreach (var kvp in _clients)
                        {
                            var client = kvp.Key;
                            var gate = kvp.Value;
                            if (client.State == WebSocketState.Open)
                            {
                                var task = System.Threading.Tasks.Task.Run(async () =>
                                {
                                    await gate.WaitAsync();
                                    try { await client.SendAsync(relaySegment, WebSocketMessageType.Text, true, CancellationToken.None); }
                                    catch { }
                                    finally { gate.Release(); }
                                });
                            }
                        }
                    }
                }
            }
            catch
            {
                // Disconnected
            }
            finally
            {
                if (webSocket != null)
                {
                    SemaphoreSlim sem;
                    if (_clients.TryRemove(webSocket, out sem)) sem.Dispose();
                    webSocket.Dispose();
                    UpdateStatus(string.Format("Connected Alts: {0}", _clients.Count));
                }
            }
        }

        private void BroadcastMessageAsync(string message)
        {
            byte[] bytes = Encoding.UTF8.GetBytes("SERVER|" + message);
            ArraySegment<byte> buffer = new ArraySegment<byte>(bytes);

            foreach (var kvp in _clients)
            {
                var client = kvp.Key;
                var gate = kvp.Value;
                if (client.State == WebSocketState.Open)
                {
                    var task = System.Threading.Tasks.Task.Run(async () =>
                    {
                        await gate.WaitAsync();
                        try { await client.SendAsync(buffer, WebSocketMessageType.Text, true, CancellationToken.None); }
                        catch { }
                        finally { gate.Release(); }
                    });
                }
            }
        }

        private void UpdatePlayerList()
        {
            if (this.InvokeRequired)
            {
                this.Invoke(new Action(UpdatePlayerList));
                return;
            }
            
            lstPlayers.Items.Clear();
            foreach (var kvp in _players)
            {
                lstPlayers.Items.Add(kvp.Value);
            }
        }

        private void MainForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (_cts != null) _cts.Cancel();
            if (_listener != null && _listener.IsListening) _listener.Stop();
            Environment.Exit(0);
        }

        [STAThread]
        static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
