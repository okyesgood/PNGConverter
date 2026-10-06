using System.Text;
using System.Text.Json;
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Specialized;

namespace PngToJpgWeb;

public sealed class MainForm : Form
{
    private readonly string _baseDir = AppContext.BaseDirectory;
    private readonly AppConfig _config;
    private readonly ListBox _log = new() { Dock = DockStyle.Fill, BackColor = Color.White, ForeColor = Color.FromArgb(54, 70, 92), HorizontalScrollbar = true };
    private readonly Label _summary = new() { AutoSize = true, Text = "等待输入 PNG 文件或文件夹…", ForeColor = Color.FromArgb(91, 111, 138) };
    private readonly ProgressBar _progress = new() { Dock = DockStyle.Fill, Minimum = 0, Height = 8 };
    private readonly Button _chooseFiles = new() { Text = "选择 PNG 文件", AutoSize = true };
    private readonly Button _chooseFolder = new() { Text = "选择文件夹", AutoSize = true };
    private readonly Button _start = new() { Text = "开始处理", AutoSize = true };
    private readonly Button _cancel = new() { Text = "取消处理", AutoSize = true, Enabled = false };
    private readonly ComboBox _preset = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 180 };
    private readonly NumericUpDown _quality = new() { Minimum = 1, Maximum = 100, Width = 70 };
    private readonly NumericUpDown _customWidth = new() { Minimum = 1, Maximum = 10000, Width = 72, Value = 970 };
    private readonly NumericUpDown _customHeight = new() { Minimum = 1, Maximum = 10000, Width = 72, Value = 600 };
    private readonly ComboBox _metadata = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 145 };
    private readonly CheckBox _deleteOriginal = new() { Text = "处理后删除原 PNG", AutoSize = true, Checked = true };
    private readonly List<string> _pendingInputs = new();
    private CancellationTokenSource? _cts;

    public MainForm()
    {
        Text = "Amazon 图片发布转换 4.27.0（浅色科技版）"; Width = 1100; Height = 720; MinimumSize = new(760, 520);
        BackColor = Color.FromArgb(244, 247, 251); ForeColor = Color.FromArgb(25, 39, 58); AllowDrop = true;
        _config = AppConfig.Load(Path.Combine(_baseDir, "config.json"));
        _preset.Items.AddRange(new object[] { "智能混合", "详情图 1601×1601", "基础 A+ 970×600", "高级 A+ 桌面端", "高级 A+ 移动端", "自定义尺寸", "保持原尺寸" });
        _preset.SelectedIndex = PresetIndex(_config.OutputPreset);
        _quality.Value = Math.Clamp(_config.JpegQuality, 1, 100);
        _customWidth.Value = Math.Clamp(_config.CustomWidth, 1, 10000); _customHeight.Value = Math.Clamp(_config.CustomHeight, 1, 10000);
        _metadata.Items.AddRange(new object[] { "清理 AI/隐私信息", "保留元数据" });
        _metadata.SelectedIndex = string.Equals(_config.MetadataMode, "preserve", StringComparison.OrdinalIgnoreCase) ? 1 : 0;
        var drop = new Panel { Dock = DockStyle.Fill, BackColor = Color.FromArgb(232, 241, 250), Padding = new Padding(2), AllowDrop = true, Cursor = Cursors.Hand };
        var dropTitle = new Label { Text = "DROP PNG FILES HERE", Dock = DockStyle.Top, Height = 42, TextAlign = ContentAlignment.BottomCenter, Font = new Font("Segoe UI", 16, FontStyle.Bold), ForeColor = Color.FromArgb(25, 73, 111) };
        var dropHint = new Label { Text = "拖入或点击选择图片/文件夹，加入处理队列", Dock = DockStyle.Top, Height = 34, TextAlign = ContentAlignment.TopCenter, Font = new Font("Microsoft YaHei UI", 10), ForeColor = Color.FromArgb(91, 126, 160) };
        drop.Controls.Add(dropHint); drop.Controls.Add(dropTitle);
        var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, WrapContents = false, Padding = new Padding(0, 8, 0, 8), BackColor = Color.Transparent };
        actions.Controls.AddRange(new Control[] { MakeLabel("输出"), _preset, MakeLabel("质量"), _quality, MakeLabel("自定义"), _customWidth, MakeLabel("×"), _customHeight, MakeLabel("元数据"), _metadata, _start, _cancel, _deleteOriginal });
        _customWidth.Enabled = _customHeight.Enabled = _preset.SelectedIndex == 5;
        _preset.SelectedIndexChanged += (_, _) => _customWidth.Enabled = _customHeight.Enabled = _preset.SelectedIndex == 5;
        var top = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4, Padding = new Padding(18, 16, 18, 10), BackColor = Color.FromArgb(244, 247, 251) };
        top.RowStyles.Add(new RowStyle(SizeType.Absolute, 112)); top.RowStyles.Add(new RowStyle(SizeType.Absolute, 50)); top.RowStyles.Add(new RowStyle(SizeType.Absolute, 24)); top.RowStyles.Add(new RowStyle(SizeType.Absolute, 1));
        top.Controls.Add(drop, 0, 0); top.Controls.Add(actions, 0, 1); top.Controls.Add(_summary, 0, 2);
        var sectionTitle = new Label { Text = "处理活动", Dock = DockStyle.Top, Height = 28, Font = new Font("Microsoft YaHei UI", 10, FontStyle.Bold), ForeColor = Color.FromArgb(38, 70, 104), Padding = new Padding(2, 0, 0, 0) };
        var logCard = new Panel { Dock = DockStyle.Fill, BackColor = Color.White, Padding = new Padding(12, 8, 12, 12) };
        logCard.Controls.Add(_log); logCard.Controls.Add(sectionTitle);
        var bottom = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, Padding = new Padding(18, 0, 18, 16), BackColor = Color.FromArgb(244, 247, 251) };
        bottom.RowStyles.Add(new RowStyle(SizeType.Absolute, 14)); bottom.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); bottom.Controls.Add(_progress, 0, 0); bottom.Controls.Add(logCard, 0, 1);
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, BackColor = Color.FromArgb(244, 247, 251) }; root.RowStyles.Add(new RowStyle(SizeType.Absolute, 220)); root.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); root.Controls.Add(top, 0, 0); root.Controls.Add(bottom, 0, 1); Controls.Add(root);
        ApplyTheme();
        DragEventHandler dragEnter = (_, e) =>
        {
            e.Effect = e.Data?.GetDataPresent(DataFormats.FileDrop) == true
                ? DragDropEffects.Copy
                : DragDropEffects.None;
        };
        DragEventHandler dragDrop = async (_, e) =>
        {
            if (e.Data?.GetDataPresent(DataFormats.FileDrop) != true) return;
            var paths = ReadDropPaths(e.Data);
            if (paths.Count > 0) QueueInputs(paths);
            else AddLog("未识别到拖入的文件或文件夹。请从资源管理器拖入 PNG。");
        };
        DragEnter += dragEnter; DragDrop += dragDrop;
        // 子控件会拦截 WinForms 拖放事件，因此拖放卡片和提示文字也必须注册。
        foreach (Control target in new Control[] { drop, dropTitle, dropHint })
        {
            target.AllowDrop = true;
            target.DragEnter += dragEnter;
            target.DragDrop += dragDrop;
        }
        _chooseFiles.Click += (_, _) => ChooseFiles();
        _chooseFolder.Click += (_, _) => ChooseFolder();
        var picker = new ContextMenuStrip();
        picker.Items.Add("选择 PNG 文件", null, (_, _) => ChooseFiles());
        picker.Items.Add("选择文件夹", null, (_, _) => ChooseFolder());
        foreach (Control target in new Control[] { drop, dropTitle, dropHint }) target.Click += (_, _) => picker.Show(target, target.PointToClient(Cursor.Position));
        _start.Click += async (_, _) => { var inputs = _pendingInputs.Distinct(StringComparer.OrdinalIgnoreCase).ToList(); if (inputs.Count == 0) { AddLog("请先拖入或选择 PNG 文件/文件夹。"); return; } await StartAsync(inputs); };
        _cancel.Click += (_, _) => _cts?.Cancel();
    }

    private void ChooseFiles()
    {
        using var d = new OpenFileDialog { Filter = "PNG 图片|*.png", Multiselect = true };
        if (d.ShowDialog() == DialogResult.OK) QueueInputs(d.FileNames);
    }

    private void ChooseFolder()
    {
        using var d = new FolderBrowserDialog();
        if (d.ShowDialog() == DialogResult.OK) QueueInputs(new[] { d.SelectedPath });
    }

    private static Label MakeLabel(string text) => new() { Text = text, AutoSize = true, ForeColor = Color.FromArgb(91, 111, 138), Padding = new Padding(10, 9, 0, 0), Font = new Font("Microsoft YaHei UI", 9) };
    private static Button CreatePrimaryButton(string text, Button button) { button.Text = text; button.AutoSize = true; button.Height = 34; button.FlatStyle = FlatStyle.Flat; button.FlatAppearance.BorderSize = 0; button.BackColor = Color.FromArgb(20, 126, 235); button.ForeColor = Color.White; button.Font = new Font("Microsoft YaHei UI", 9, FontStyle.Bold); button.Padding = new Padding(12, 0, 12, 0); return button; }
    private static Button CreateSecondaryButton(string text, Button button) { button.Text = text; button.AutoSize = true; button.Height = 34; button.FlatStyle = FlatStyle.Flat; button.FlatAppearance.BorderColor = Color.FromArgb(164, 183, 205); button.BackColor = Color.FromArgb(235, 241, 248); button.ForeColor = Color.FromArgb(38, 70, 104); button.Font = new Font("Microsoft YaHei UI", 9); button.Padding = new Padding(10, 0, 10, 0); return button; }
    private void ApplyTheme() { _log.BorderStyle = BorderStyle.FixedSingle; _log.Font = new Font("Cascadia Mono", 9); _preset.BackColor = Color.FromArgb(235, 241, 248); _preset.ForeColor = Color.FromArgb(38, 70, 104); _quality.BackColor = Color.FromArgb(235, 241, 248); _quality.ForeColor = Color.FromArgb(38, 70, 104); _progress.Style = ProgressBarStyle.Continuous; }

    private async Task StartAsync(List<string> inputs)
    {
        if (_cts != null) return; _cts = new(); _cancel.Enabled = true; _start.Enabled = false; _log.Items.Clear();
        ApplyUiConfig();
        try
        {
            var files = inputs.SelectMany(p => File.Exists(p)
                    ? new[] { p }
                    : Directory.Exists(p)
                        ? Directory.EnumerateFiles(p, "*.*", SearchOption.AllDirectories)
                        : Array.Empty<string>())
                .Where(p => Path.GetExtension(p).Equals(".png", StringComparison.OrdinalIgnoreCase))
                .Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            if (files.Count == 0) { AddLog($"没有找到 PNG 文件（已接收 {inputs.Count} 个路径）。"); return; }
            _progress.Maximum = files.Count; _progress.Value = 0; _summary.Text = $"共 {files.Count} 张图片，处理中…";
            var converter = new Converter(_config); var results = new List<ConversionResult>();
            foreach (var file in files)
            {
                _cts.Token.ThrowIfCancellationRequested();
                ConversionResult result;
                var output = Path.ChangeExtension(file, ".jpg");
                try
                {
                    using var probe = new Bitmap(file); var plan = ImagePlanner.Plan(probe.Width, probe.Height, _config);
                    result = plan.Skip ? new ConversionResult(file, output, ConversionStatus.Skipped, plan.Purpose, plan.Rule, probe.Width, probe.Height, 0, 0, new FileInfo(file).Length, 0, TimeSpan.Zero, "非标准比例，已跳过") : await Task.Run(() => converter.Convert(file, output, plan, _cts.Token));
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex)
                {
                    result = new ConversionResult(file, output, ConversionStatus.Failed, "未知", "读取失败", 0, 0, 0, 0, File.Exists(file) ? new FileInfo(file).Length : 0, 0, TimeSpan.Zero, ex.Message);
                }
                results.Add(result); AddLog(Format(result)); _progress.Value++;
            }
            var ok = results.Count(x => x.Status == ConversionStatus.Success); var skipped = results.Count(x => x.Status == ConversionStatus.Skipped); var failed = results.Count(x => x.Status == ConversionStatus.Failed);
            _summary.Text = $"完成：成功 {ok}，跳过 {skipped}，失败 {failed}"; WriteReports(results);
            if (_deleteOriginal.Checked)
                foreach (var item in results.Where(x => x.Status == ConversionStatus.Success)) try { File.Delete(item.Input); } catch { AddLog($"删除失败：{item.Input}"); }
        }
        catch (OperationCanceledException) { AddLog("用户已取消处理。"); }
        catch (Exception ex) { AddLog("批次失败：" + ex.Message); }
        finally { _cts.Dispose(); _cts = null; _cancel.Enabled = false; _start.Enabled = true; _pendingInputs.Clear(); }
    }

    private void QueueInputs(IEnumerable<string> inputs)
    {
        _pendingInputs.AddRange(inputs.Where(p => File.Exists(p) || Directory.Exists(p)));
        _summary.Text = _pendingInputs.Count == 0 ? "等待输入 PNG 文件或文件夹…" : $"已添加 {_pendingInputs.Count} 个文件/文件夹，点击“开始处理”";
    }

    private void AddLog(string text) { _log.Items.Add($"[{DateTime.Now:HH:mm:ss}] {text}"); _log.TopIndex = Math.Max(0, _log.Items.Count - 1); }
    private static List<string> ReadDropPaths(IDataObject data)
    {
        if (data.GetDataPresent(DataFormats.FileDrop))
        {
            if (data.GetData(DataFormats.FileDrop) is string[] paths) return paths.Where(File.Exists).Concat(paths.Where(Directory.Exists)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            if (data.GetData(DataFormats.FileDrop) is StringCollection collection) return collection.Cast<string>().Where(p => File.Exists(p) || Directory.Exists(p)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        }
        return new List<string>();
    }
    private static string Format(ConversionResult r) => r.Status == ConversionStatus.Success ? $"成功 | {Path.GetFileName(r.Input)} | {r.Width}x{r.Height} -> {r.OutputWidth}x{r.OutputHeight} | {r.Purpose}" : $"{r.Status} | {Path.GetFileName(r.Input)} | {r.Rule} | {r.Error}";
    private void WriteReports(List<ConversionResult> results)
    {
        var dir = Path.Combine(_baseDir, "logs"); Directory.CreateDirectory(dir); var stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss"); File.WriteAllText(Path.Combine(dir, $"run_{stamp}.json"), JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
        var sb = new StringBuilder("InputFile,OutputFile,Status,Purpose,Rule,Width,Height,OutputWidth,OutputHeight,InputBytes,OutputBytes,Error\r\n"); foreach (var r in results) sb.AppendLine(string.Join(",", new[] { r.Input, r.Output, r.Status.ToString(), r.Purpose, r.Rule, r.Width.ToString(), r.Height.ToString(), r.OutputWidth.ToString(), r.OutputHeight.ToString(), r.InputBytes.ToString(), r.OutputBytes.ToString(), r.Error }.Select(Csv))); File.WriteAllText(Path.Combine(dir, $"run_{stamp}.csv"), sb.ToString(), Encoding.UTF8);
    }
    private void ApplyUiConfig()
    {
        _config.OutputPreset = _preset.SelectedIndex switch
        { 1 => "detail", 2 => "basic-a+", 3 => "advanced-desktop", 4 => "advanced-mobile", 5 => "custom", 6 => "original", _ => "smart-mixed" };
        _config.JpegQuality = (int)_quality.Value;
        _config.CustomWidth = (int)_customWidth.Value;
        _config.CustomHeight = (int)_customHeight.Value;
        _config.MetadataMode = _metadata.SelectedIndex == 1 ? "preserve" : "sanitize";
        _config.ClearMetadata = _config.MetadataMode == "sanitize";
    }
    private static int PresetIndex(string? preset) => (preset ?? "smart-mixed").ToLowerInvariant() switch
    { "detail" or "product" => 1, "basic-a+" or "basic-a-plus" => 2, "advanced-desktop" => 3, "advanced-mobile" => 4, "custom" => 5, "original" => 6, _ => 0 };
    private static string Csv(string? value) => "\"" + (value ?? "").Replace("\"", "\"\"") + "\"";
}
