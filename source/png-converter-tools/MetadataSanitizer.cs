using System.Drawing;
using System.Drawing.Imaging;

namespace PngToJpgWeb;

/// <summary>Controls metadata policy. JPEG re-encoding through a fresh Bitmap drops source EXIF/IPTC/XMP/PNG text chunks.</summary>
public static class MetadataSanitizer
{
    public static void PrepareForJpeg(Bitmap target, AppConfig config)
    {
        if (!string.Equals(config.MetadataMode, "preserve", StringComparison.OrdinalIgnoreCase) && config.ClearMetadata)
        {
            // Do not copy PropertyItems from the source. A newly-created Bitmap has no source metadata.
            // Keep only pixel data and the encoder-selected JPEG settings; ICC/C2PA are not copied.
            foreach (var item in target.PropertyItems)
                try { target.RemovePropertyItem(item.Id); } catch (ArgumentException) { }
        }
    }
}
