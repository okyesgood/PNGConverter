namespace PngToJpgWeb;

public static class ImagePlanner
{
    public static OutputPlan Plan(int width, int height, AppConfig config)
    {
        var preset = (config.OutputPreset ?? "smart-mixed").Trim().ToLowerInvariant();
        if (preset is "detail" or "product") return new(1601, 1601, "Amazon 详情图", "手动预设", false);
        if (preset is "basic-a+" or "basic-a-plus") return new(970, 600, "基础 A+", "手动预设", false);
        if (preset is "advanced-desktop") return new(1464, 600, "高级 A+ 桌面端", "手动预设", false);
        if (preset is "advanced-mobile") return new(1200, 900, "高级 A+ 移动端", "手动预设", false);
        if (preset is "custom") return new(Math.Max(1, config.CustomWidth), Math.Max(1, config.CustomHeight), "自定义尺寸", "手动预设", false);
        if (preset is "original") return new(width, height, "原尺寸", "保持原尺寸", false);

        if (width == 1464 && height == 600) return new(1464, 600, "高级 A+ 桌面端", "精确尺寸", false);
        if (width == 1200 && height == 900) return new(1200, 900, "高级 A+ 移动端", "精确尺寸", false);
        var ratio = height == 0 ? 0 : width / (double)height;
        if (Math.Abs(ratio - 1) <= .03) return new(1601, 1601, "Amazon 详情图", "1:1 比例", false);
        if (Math.Abs(ratio - (1564d / 986d)) <= .04) return new(970, 600, "基础 A+", "1564:986 比例", false);
        if (Math.Abs(ratio - (16d / 9d)) <= .03) return new(width, height, "16:9 视频缩略图", "16:9 保持原尺寸", false);
        return new(width, height, "未识别", "非标准比例，安全跳过", true);
    }
}
