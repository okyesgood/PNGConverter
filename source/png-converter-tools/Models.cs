using System.Text.Json;
using System.Text.Json.Serialization;

namespace PngToJpgWeb;

public sealed class AppConfig
{
    public int JpegQuality { get; set; } = 90;
    public string Background { get; set; } = "white";
    public long MaxInputPixels { get; set; } = 100_000_000;
    public string OutputPreset { get; set; } = "smart-mixed";
    public int CustomWidth { get; set; } = 970;
    public int CustomHeight { get; set; } = 600;

    public static AppConfig Load(string path)
    {
        try
        {
            if (File.Exists(path))
                return JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(path)) ?? new();
        }
        catch { }
        return new();
    }

}

public enum ConversionStatus { Success, Skipped, Failed }
public sealed record ConversionResult(string Input, string? Output, ConversionStatus Status, string Purpose, string Rule, int Width, int Height, int OutputWidth, int OutputHeight, long InputBytes, long OutputBytes, TimeSpan Duration, string? Error = null);
public sealed record OutputPlan(int Width, int Height, string Purpose, string Rule, bool Skip);
