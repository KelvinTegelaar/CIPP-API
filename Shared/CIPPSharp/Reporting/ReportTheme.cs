using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;

namespace CIPP.Reporting
{
    /// <summary>
    /// Server-side port of frontend/src/components/CippPdf/reportTheme.js. The single place a report
    /// works out what it looks like: two brand colours, readable text on each, a chart series, and the
    /// footer/watermark configuration. Kept as a faithful 1:1 port so a server-rendered report matches
    /// the client preview colour-for-colour. Pure (no OfficeIMO dependency) so it is unit-testable
    /// against the JS values.
    /// </summary>
    public static class ReportColours
    {
        public const string Danger = "#742A2A";
        public const string Warning = "#744210";
        public const string Success = "#22543D";
        public const string Info = "#2C5282";
        public const string Ink = "#1A202C";
        public const string Body = "#2D3748";
        public const string Muted = "#4A5568";
        public const string Faint = "#718096";
        public const string Line = "#E2E8F0";
        public const string Panel = "#F7FAFC";
        public const string White = "#FFFFFF";
        // Callout background tints (match the client InfoBox/AlertBox/ClearBox).
        public const string AlertBg = "#FFF5F5";
        public const string OkBg = "#F0FDF4";
        public const string WarnBg = "#FEF5E7";
    }

    /// <summary>Colour maths ported from reportTheme.js - hex normalisation, WCAG luminance, mixing.</summary>
    public static class ColourMath
    {
        public const string DefaultBrandColour = "#F77F00";
        private const double WhiteTextMinContrast = 2.5;
        private static readonly Regex HexPattern = new("^#?([0-9a-f]{3}|[0-9a-f]{6})$", RegexOptions.IgnoreCase);

        /// <summary>#RGB / #RRGGBB / bare digits -> canonical #RRGGBB, or null if unparseable.</summary>
        public static string? NormaliseHex(string? value)
        {
            if (value is null) return null;
            var trimmed = value.Trim();
            if (!HexPattern.IsMatch(trimmed)) return null;
            var digits = trimmed.Replace("#", string.Empty);
            if (digits.Length == 3)
            {
                var chars = new char[6];
                for (var i = 0; i < 3; i++) { chars[i * 2] = digits[i]; chars[i * 2 + 1] = digits[i]; }
                digits = new string(chars);
            }
            return "#" + digits.ToUpperInvariant();
        }

        // hsl(H, S%, L%) - the palette form the dashboard sankeys emit (e.g. "hsl(210, 70%, 50%)"). Commas
        // or spaces between the three parts; the % on S/L is optional. Anything else returns null.
        private static readonly Regex HslPattern = new(
            @"^hsl\(\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(\d+(?:\.\d+)?)%?\s*[, ]\s*(\d+(?:\.\d+)?)%?\s*\)$",
            RegexOptions.IgnoreCase);

        private static (int r, int g, int b)? TryHslToRgb(string? value)
        {
            if (value is null) return null;
            var m = HslPattern.Match(value.Trim());
            if (!m.Success) return null;
            var h = double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
            var s = double.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture) / 100.0;
            var l = double.Parse(m.Groups[3].Value, CultureInfo.InvariantCulture) / 100.0;
            h = ((h % 360) + 360) % 360 / 360.0;
            s = Math.Max(0, Math.Min(1, s));
            l = Math.Max(0, Math.Min(1, l));
            if (s == 0)
            {
                var g = (int)Math.Round(l * 255);
                return (g, g, g);
            }
            var q = l < 0.5 ? l * (1 + s) : l + s - l * s;
            var p = 2 * l - q;
            static double Hue(double p, double q, double t)
            {
                if (t < 0) t += 1;
                if (t > 1) t -= 1;
                if (t < 1.0 / 6) return p + (q - p) * 6 * t;
                if (t < 1.0 / 2) return q;
                if (t < 2.0 / 3) return p + (q - p) * (2.0 / 3 - t) * 6;
                return p;
            }
            return (
                (int)Math.Round(Hue(p, q, h + 1.0 / 3) * 255),
                (int)Math.Round(Hue(p, q, h) * 255),
                (int)Math.Round(Hue(p, q, h - 1.0 / 3) * 255));
        }

        /// <summary>Hex, hsl() (or the default brand colour when unparseable) as 0-255 channels.</summary>
        public static (int r, int g, int b) ToRgb(string? hex)
        {
            // The canonical #RRGGBB every palette entry and constant already is, parsed without the regexes.
            if (hex is { Length: 7 } && hex[0] == '#'
                && int.TryParse(hex.AsSpan(1), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out var rgb))
                return ((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
            var hsl = TryHslToRgb(hex);
            if (hsl.HasValue) return hsl.Value;
            var normalised = NormaliseHex(hex) ?? DefaultBrandColour;
            var d = normalised.Substring(1);
            return (
                int.Parse(d.Substring(0, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture),
                int.Parse(d.Substring(2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture),
                int.Parse(d.Substring(4, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture));
        }

        private static string ToHex(double r, double g, double b)
        {
            static string Ch(double v) => ((int)Math.Max(0, Math.Min(255, Math.Round(v)))).ToString("X2", CultureInfo.InvariantCulture);
            return "#" + Ch(r) + Ch(g) + Ch(b);
        }

        private static double RelativeLuminance(string hex)
        {
            var (r, g, b) = ToRgb(hex);
            static double Ch(int value)
            {
                var s = value / 255.0;
                return s <= 0.03928 ? s / 12.92 : Math.Pow((s + 0.055) / 1.055, 2.4);
            }
            return 0.2126 * Ch(r) + 0.7152 * Ch(g) + 0.0722 * Ch(b);
        }

        private static double ContrastRatio(string a, string b)
        {
            var la = RelativeLuminance(a);
            var lb = RelativeLuminance(b);
            var lighter = Math.Max(la, lb);
            var darker = Math.Min(la, lb);
            return (lighter + 0.05) / (darker + 0.05);
        }

        /// <summary>White on the brand colour where legible, else near-black - matches readableTextOn.</summary>
        public static string ReadableTextOn(string? background)
        {
            var hex = NormaliseHex(background) ?? DefaultBrandColour;
            return ContrastRatio(hex, ReportColours.White) >= WhiteTextMinContrast ? ReportColours.White : ReportColours.Ink;
        }

        public static string Mix(string hex, string target, double amount)
        {
            var (fr, fg, fb) = ToRgb(hex);
            var (tr, tg, tb) = ToRgb(target);
            var ratio = Math.Max(0, Math.Min(1, amount));
            return ToHex(fr + (tr - fr) * ratio, fg + (tg - fg) * ratio, fb + (tb - fb) * ratio);
        }

        public static string Lighten(string hex, double amount) => Mix(hex, "#FFFFFF", amount);
        public static string Darken(string hex, double amount) => Mix(hex, "#000000", amount);
    }

    /// <summary>One colour role, resolved from branding with a fallback derived from the brand colours.</summary>
    internal sealed record ColourRole(string Key, string Setting, Func<string, string, string> From);

    public sealed class ReportTheme
    {
        public string Primary { get; }
        public string Secondary { get; }
        public string OnPrimary { get; }
        public IReadOnlyDictionary<string, string> Palette { get; }
        public string OnTable { get; }
        public string OnInfographic { get; }
        public IReadOnlyList<string> Series { get; }
        // Footer
        public bool FooterShow { get; }
        public bool FooterEnabled { get; }
        public string FooterTemplate { get; }
        public bool ShowPageNumbers { get; }
        // Watermark
        public bool WatermarkEnabled { get; }
        public string WatermarkText { get; }
        public string CoverFooterText { get; }

        public const int FooterMaxLength = 200;
        public const int WatermarkMaxLength = 40;

        // Mirrors REPORT_COLOUR_ROLES. `from(primary, secondary)` is the fallback derivation.
        private static readonly ColourRole[] Roles =
        {
            new("chart", "chartColour", (p, _) => p),
            new("chartAccent", "chartAccentColour", (_, s) => s),
            new("title", "titleColour", (_, _) => ReportColours.Ink),
            new("coverText", "coverTextColour", (_, _) => ReportColours.Ink),
            new("subtitle", "subtitleColour", (_, _) => ReportColours.Muted),
            new("heading", "headingColour", (p, _) => p),
            new("body", "bodyColour", (_, _) => ReportColours.Body),
            new("footer", "footerColour", (_, _) => ReportColours.Faint),
            new("card", "cardColour", (_, s) => s),
            new("table", "tableColour", (p, _) => p),
            new("infographic", "infographicColour", (p, _) => p),
            new("infographicBackground", "infographicBackgroundColour", (_, _) => "#000000"),
            new("watermark", "watermarkColour", (p, _) => p),
        };

        private ReportTheme(BrandingInput b)
        {
            Primary = ColourMath.NormaliseHex(b.Colour) ?? ColourMath.DefaultBrandColour;
            Secondary = ColourMath.NormaliseHex(b.SecondaryColour) ?? Primary;
            OnPrimary = ColourMath.ReadableTextOn(Primary);

            var palette = new Dictionary<string, string>();
            foreach (var role in Roles)
            {
                var configured = b.RoleColour(role.Setting);
                palette[role.Key] = ColourMath.NormaliseHex(configured) ?? role.From(Primary, Secondary);
            }
            Palette = palette;

            OnTable = ColourMath.ReadableTextOn(palette["table"]);
            OnInfographic = ColourMath.ReadableTextOn(palette["infographicBackground"]);
            Series = BuildSeries(palette["chart"], palette["chartAccent"]);

            FooterShow = b.ShowFooter != false;
            FooterEnabled = b.ShowFooter != false && !string.IsNullOrEmpty(b.FooterText);
            FooterTemplate = b.FooterText ?? string.Empty;
            ShowPageNumbers = b.ShowPageNumbers != false;
            WatermarkEnabled = b.WatermarkEnabled != false && !string.IsNullOrEmpty(b.WatermarkText);
            WatermarkText = b.WatermarkText ?? string.Empty;
            CoverFooterText = b.CoverFooterText ?? string.Empty;
        }

        public static ReportTheme Create(BrandingInput branding) => new(branding);

        private static List<string> BuildSeries(string primary, string secondary)
        {
            if (primary == secondary)
            {
                return new List<string>
                {
                    primary, ColourMath.Lighten(primary, 0.35), ReportColours.Info,
                    ColourMath.Darken(primary, 0.3), ColourMath.Lighten(primary, 0.65)
                };
            }
            return new List<string>
            {
                primary, secondary, ColourMath.Lighten(primary, 0.4),
                ColourMath.Lighten(secondary, 0.4), ColourMath.Darken(primary, 0.25)
            };
        }

        /// <summary>%variable% substitution - case-insensitive, unknown tokens left as written.</summary>
        public static string ApplyVariables(string? template, IReadOnlyDictionary<string, string> variables)
        {
            if (string.IsNullOrEmpty(template)) return string.Empty;
            var lookup = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var kv in variables) lookup[kv.Key.Trim('%').ToLowerInvariant()] = kv.Value;
            return Regex.Replace(template, "%([\\w()]+)%", m =>
                lookup.TryGetValue(m.Groups[1].Value.ToLowerInvariant(), out var v) ? v : m.Value);
        }

        public static string ApplyFooter(string? template, IReadOnlyDictionary<string, string> variables)
        {
            var s = ApplyVariables(template, variables);
            return s.Length > FooterMaxLength ? s.Substring(0, FooterMaxLength) : s;
        }

        public static string ApplyWatermark(string? template, IReadOnlyDictionary<string, string> variables)
        {
            var s = ApplyVariables(template, variables);
            return s.Length > WatermarkMaxLength ? s.Substring(0, WatermarkMaxLength) : s;
        }
    }
}
