using System;
using System.Collections.Generic;
using System.Text.Json;

namespace CIPP.Reporting
{
    /// <summary>
    /// Branding as saved by Get-CIPPBrandingSettings (or a preset), parsed from JSON. Mirrors the shape
    /// the client theme consumes: brand colours, per-role colour overrides, footer/watermark config, and
    /// the logo/cover as data-URLs. Missing toggles stay null so the theme applies its "!== false" defaults.
    /// </summary>
    public sealed class BrandingInput
    {
        public string? Colour { get; init; }
        public string? SecondaryColour { get; init; }
        public string? FooterText { get; init; }
        public string? CoverFooterText { get; init; }
        public bool? ShowFooter { get; init; }
        public bool? ShowPageNumbers { get; init; }
        public string? WatermarkText { get; init; }
        public bool? WatermarkEnabled { get; init; }
        public string? Logo { get; init; }        // data-URL
        public string? CoverImage { get; init; }   // data-URL (an uploaded cover)
        public string? CoverStock { get; init; }   // a bundled /reportImages/ path, or "none"
        private Dictionary<string, string> RoleColours { get; init; } = new();
        private Dictionary<string, string> FlatColours { get; init; } = new();

        /// <summary>roleColours[setting] first, then a flat property of the same name (preset/template case).</summary>
        public string? RoleColour(string setting)
        {
            if (RoleColours.TryGetValue(setting, out var v)) return v;
            return FlatColours.TryGetValue(setting, out var f) ? f : null;
        }

        public static BrandingInput FromJson(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return new BrandingInput();
            JsonDocument doc;
            try { doc = JsonDocument.Parse(json); }
            catch { return new BrandingInput(); }
            using var _ = doc;
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return new BrandingInput();

            string? Str(string name) => root.TryGetProperty(name, out var e) && e.ValueKind == JsonValueKind.String ? e.GetString() : null;
            bool? Bool(string name) => root.TryGetProperty(name, out var e) && (e.ValueKind == JsonValueKind.True || e.ValueKind == JsonValueKind.False) ? e.GetBoolean() : (bool?)null;

            var roles = new Dictionary<string, string>();
            if (root.TryGetProperty("roleColours", out var rc) && rc.ValueKind == JsonValueKind.Object)
            {
                foreach (var p in rc.EnumerateObject())
                    if (p.Value.ValueKind == JsonValueKind.String) roles[p.Name] = p.Value.GetString()!;
            }
            // Flat colour overrides (a preset/template can set e.g. "headingColour" directly).
            var flat = new Dictionary<string, string>();
            foreach (var p in root.EnumerateObject())
                if (p.Name.EndsWith("Colour", StringComparison.Ordinal) && p.Value.ValueKind == JsonValueKind.String)
                    flat[p.Name] = p.Value.GetString()!;

            return new BrandingInput
            {
                Colour = Str("colour"),
                SecondaryColour = Str("secondaryColour"),
                FooterText = Str("footerText"),
                CoverFooterText = Str("coverFooterText"),
                ShowFooter = Bool("showFooter"),
                ShowPageNumbers = Bool("showPageNumbers"),
                WatermarkText = Str("watermarkText"),
                WatermarkEnabled = Bool("watermarkEnabled"),
                Logo = Str("logo"),
                CoverImage = Str("coverImage"),
                CoverStock = Str("coverStock"),
                RoleColours = roles,
                FlatColours = flat,
            };
        }
    }

    /// <summary>
    /// Everything a component needs while rendering - the ReportProvider equivalent. Passed to every
    /// component so none of them reach for global state or inline a colour.
    /// </summary>
    public sealed class ReportContext
    {
        public required ReportTheme Theme { get; init; }
        public required IReadOnlyDictionary<string, string> Variables { get; init; }
        public string PageSize { get; init; } = "A4";
        public bool Landscape { get; init; }
        public string TenantName { get; init; } = "Organization";
        public string ReportName { get; init; } = "Report";
        public string GeneratedOn { get; init; } = "";
        public byte[]? Logo { get; init; }
        public byte[]? CoverImage { get; init; }

        /// <summary>Usable content width in points (paper - page padding both sides). Mirrors contentWidth().</summary>
        public double ContentWidth => ReportStyles.ContentWidth(PageSize, Landscape);

        /// <summary>Usable content height in points (paper - page padding both sides).</summary>
        public double ContentHeight => ReportStyles.ContentHeight(PageSize, Landscape);
    }
}
