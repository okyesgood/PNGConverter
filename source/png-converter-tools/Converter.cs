using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace PngToJpgWeb;

public sealed class Converter
{
    private readonly AppConfig _config;
    public Converter(AppConfig config) => _config = config;

    public ConversionResult Convert(string input, string output, OutputPlan plan, CancellationToken token)
    {
        var started = DateTime.UtcNow;
        string? temp = null;
        try
        {
            token.ThrowIfCancellationRequested();
            using var source = new Bitmap(input);
            if ((long)source.Width * source.Height > _config.MaxInputPixels)
                throw new InvalidDataException($"图片像素超过限制 {_config.MaxInputPixels:N0}。");
            if (plan.Skip) return Result(ConversionStatus.Skipped, input, output, plan, source.Width, source.Height, 0, 0, started, "未识别比例，已跳过");
            temp = output + ".tmp-" + Guid.NewGuid().ToString("N");
            Directory.CreateDirectory(Path.GetDirectoryName(output)!);
            using (var target = new Bitmap(plan.Width, plan.Height, PixelFormat.Format24bppRgb))
            using (var graphics = Graphics.FromImage(target))
            {
                graphics.Clear(string.Equals(_config.Background, "black", StringComparison.OrdinalIgnoreCase) ? Color.Black : Color.White);
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.SmoothingMode = SmoothingMode.HighQuality;
                graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                var scale = Math.Min(plan.Width / (double)source.Width, plan.Height / (double)source.Height);
                var w = Math.Max(1, (int)Math.Round(source.Width * scale));
                var h = Math.Max(1, (int)Math.Round(source.Height * scale));
                graphics.DrawImage(source, (plan.Width - w) / 2, (plan.Height - h) / 2, w, h);
                MetadataSanitizer.PrepareForJpeg(target, _config);
                var codec = ImageCodecInfo.GetImageEncoders().First(x => x.MimeType == "image/jpeg");
                using var parameters = new EncoderParameters(1);
                parameters.Param[0] = new EncoderParameter(Encoder.Quality, Math.Clamp(_config.JpegQuality, 1, 100));
                target.Save(temp, codec, parameters);
            }
            using (var check = Image.FromFile(temp))
            {
                if (check.RawFormat.Guid != ImageFormat.Jpeg.Guid || check.Width != plan.Width || check.Height != plan.Height)
                    throw new InvalidDataException("输出 JPG 验证失败。");
            }
            File.Move(temp, output, true);
            return Result(ConversionStatus.Success, input, output, plan, source.Width, source.Height, plan.Width, plan.Height, started, null);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex) { return Result(ConversionStatus.Failed, input, output, plan, 0, 0, 0, 0, started, ex.Message); }
        finally { if (temp != null) try { if (File.Exists(temp)) File.Delete(temp); } catch { } }
    }

    private static ConversionResult Result(ConversionStatus status, string input, string output, OutputPlan plan, int w, int h, int ow, int oh, DateTime started, string? error) =>
        new(input, output, status, plan.Purpose, plan.Rule, w, h, ow, oh, File.Exists(input) ? new FileInfo(input).Length : 0, File.Exists(output) ? new FileInfo(output).Length : 0, DateTime.UtcNow - started, error);
}
