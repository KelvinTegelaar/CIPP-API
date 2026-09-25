using System;
using System.Collections.Generic;

namespace CIPP.Reporting
{
    /// <summary>
    /// Layout constants ported from frontend/src/components/CippPdf/reportPdfStyles.js - page metrics,
    /// paddings and the font sizes the components draw at, so server output matches the client's spacing.
    /// </summary>
    public static class ReportStyles
    {
        public const double PagePadding = 32;      // margin down each side of a content page

        // Font sizes (points).
        public const double PageTitle = 20;
        public const double PageSubtitle = 11;
        public const double SectionTitle = 14;
        public const double Body = 9;
        public const double Heading1 = 16;
        public const double Heading2 = 14;
        public const double Heading3 = 12;
        public const double TableCell = 8;
        public const double TableHeaderCell = 7;
        public const double StatusText = 9;
        public const double BulletText = 9;
        public const double CodeBlock = 8;
        public const double FooterText = 7;
        public const double StatNumber = 20;
        public const double StatLabel = 7;
        public const double StatCaption = 7;
        public const double InfoTitle = 10;
        public const double InfoText = 8;
        public const double AlertTitle = 11;
        public const double AlertText = 9;
        public const double CoverTitle = 48;
        public const double CoverSubtitle = 14;
        public const double CoverLabel = 10;

        private static readonly Dictionary<string, double> PageWidths = new(StringComparer.OrdinalIgnoreCase)
        {
            ["A4"] = 595.28, ["LETTER"] = 612, ["LEGAL"] = 612, ["A3"] = 841.89, ["A5"] = 419.53,
        };
        private static readonly Dictionary<string, double> PageHeights = new(StringComparer.OrdinalIgnoreCase)
        {
            ["A4"] = 841.89, ["LETTER"] = 792, ["LEGAL"] = 1008, ["A3"] = 1190.55, ["A5"] = 595.28,
        };

        /// <summary>Usable table/content width: paper (long edge if landscape) minus page padding both sides.</summary>
        public static double ContentWidth(string size, bool landscape)
        {
            var key = (size ?? "A4").ToUpperInvariant();
            var w = PageWidths.TryGetValue(key, out var pw) ? pw : PageWidths["A4"];
            var h = PageHeights.TryGetValue(key, out var ph) ? ph : PageHeights["A4"];
            var paper = landscape ? h : w;
            return paper - PagePadding * 2;
        }

        /// <summary>Usable content height: paper (short edge if landscape) minus page padding both sides.</summary>
        public static double ContentHeight(string size, bool landscape)
        {
            var key = (size ?? "A4").ToUpperInvariant();
            var w = PageWidths.TryGetValue(key, out var pw) ? pw : PageWidths["A4"];
            var h = PageHeights.TryGetValue(key, out var ph) ? ph : PageHeights["A4"];
            var paper = landscape ? w : h;
            return paper - PagePadding * 2;
        }
    }
}
