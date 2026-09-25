using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using OfficeIMO.Drawing;
using OfficeIMO.Pdf;

namespace CIPP.Reporting
{
    /// <summary>
    /// The reusable component kit - the server port of reportPdfPrimitives.jsx. Every component takes the
    /// <see cref="ReportContext"/> (theme/styles/variables) and the current OfficeIMO <see cref="PdfContentBuilder"/>,
    /// and encapsulates all OfficeIMO calls. Reports compose these; no report inlines a raw OfficeIMO call.
    /// </summary>
    public static class ReportComponents
    {
        private const double CodeParagraphSize = ReportStyles.CodeBlock;

        // Make any raw string safe for the PDF standard fonts (strips/maps emoji etc.).
        private static string San(string? s) => ReportMarkdown.Sanitize(s);

        // -- colour bridge --
        public static PdfColor Pdf(string hex)
        {
            var (r, g, b) = ColourMath.ToRgb(hex);
            return PdfColor.FromRgb((byte)r, (byte)g, (byte)b);
        }

        // -- images --
        /// <summary>Decode a data-URL/base64 image (or resolve a bundled /reportImages/ path) into bytes OfficeIMO can draw anywhere, or null.</summary>
        public static byte[]? DecodeImage(string? dataUrl)
        {
            if (string.IsNullOrWhiteSpace(dataUrl)) return null;
            var s = dataUrl.Trim();

            // A bundled stock image referenced by the frontend path it has always used, e.g.
            // "/reportImages/board.jpg". The browser used to fetch these from public/reportImages; the
            // server ships the same files beside the assembly under reportImages/, so resolve the path to
            // those bytes. Only the file name is honoured (no traversal), and only files that ship return.
            var stock = ReportImagesPathPattern.Match(s);
            if (stock.Success) return ReportImage(stock.Groups[1].Value);

            // A branding logo or uploaded cover is the same data URL on every render for a tenant, so it is
            // decoded (and an SVG rasterised) once, and every render hands OfficeIMO the same array - which
            // also lets OfficeIMO's per-array prepared-image cache hit across renders. Keyed by the data URL
            // itself: a lookup is a fast string hash and compare, where a digest of a large upload is not.
            var key = s;
            if (DecodedImageCache.TryGetValue(key, out var cached)) return cached;
            var comma = s.IndexOf("base64,", StringComparison.OrdinalIgnoreCase);
            if (comma >= 0) s = s.Substring(comma + "base64,".Length);
            byte[]? bytes;
            try { bytes = NormaliseImage(Convert.FromBase64String(s.Trim())); } catch { bytes = null; }
            // ponytail: clear-on-overflow, not LRU; a byte budget keeps a burst of distinct brandings bounded.
            // An entry bigger than a quarter of the budget (an upload of roughly 3 MB, counting its data URL)
            // is not kept, so one huge image cannot clear everything else for itself. Each cached array also
            // keeps OfficeIMO's prepared copy of it alive, so what this retains is a few times the budget.
            var size = 2L * key.Length + (bytes?.Length ?? 0);
            if (size > DecodedImageCacheBudget / 4) return bytes;
            if (Interlocked.Add(ref decodedImageCacheBytes, size) > DecodedImageCacheBudget)
            {
                DecodedImageCache.Clear();
                Interlocked.Exchange(ref decodedImageCacheBytes, size);
            }
            DecodedImageCache[key] = bytes;
            return bytes;
        }

        private const long DecodedImageCacheBudget = 32L * 1024 * 1024;
        private static long decodedImageCacheBytes;
        private static readonly ConcurrentDictionary<string, byte[]?> DecodedImageCache = new(StringComparer.Ordinal);

        // Every raster OfficeIMO decodes (PNG, JPEG, GIF, BMP, TIFF, WebP) is handed to it as-is. An SVG
        // is only accepted by the drawing API, not by flow images or page backgrounds, so it is rasterised
        // once here through OfficeIMO's own SVG reader - transparent background, ~1200px on the long side,
        // crisp at logo and cover sizes and a few KB for a typical logo - and then behaves like a PNG.
        // Anything OfficeIMO cannot identify is dropped here rather than left to fail at serialisation.
        // Add-CIPPImage enforces the same list at upload time.
        private const double SvgRasterSize = 1200;
        private static byte[]? NormaliseImage(byte[] bytes)
        {
            try
            {
                if (!OfficeImageReader.TryIdentifyByContent(bytes, null, out var info)) return null;
                if (info.Format != OfficeImageFormat.Svg) return bytes;
                if (!OfficeSvgDrawingReader.TryRead(bytes, out var drawing) || drawing.Width <= 0 || drawing.Height <= 0) return null;
                return OfficeDrawingRasterRenderer.ToPng(drawing, SvgRasterSize / Math.Max(drawing.Width, drawing.Height), null);
            }
            catch { return null; }
        }

        private static readonly Regex ReportImagesPathPattern =
            new(@"(?:^|/)reportImages/([A-Za-z0-9_.\-]+\.(?:jpg|jpeg|png|gif|webp))$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        // Stock report images (cover/hero photos) ship beside the assembly under reportImages/, mirroring
        // how the twemoji PNG set and the fallback font are placed. Loaded once per file and cached.
        private static readonly Lazy<string?> ReportImageDir = new(() =>
        {
            try
            {
                var d = Path.GetDirectoryName(typeof(ReportComponents).Assembly.Location);
                if (string.IsNullOrEmpty(d)) return null;
                var dir = Path.Combine(d, "reportImages");
                return Directory.Exists(dir) ? dir : null;
            }
            catch { return null; }
        });

        private static readonly ConcurrentDictionary<string, byte[]?> ReportImageCache = new(StringComparer.OrdinalIgnoreCase);

        /// <summary>Load a bundled stock report image by file name (no path segments), or null if it is not shipped.</summary>
        public static byte[]? ReportImage(string? fileName)
        {
            if (string.IsNullOrWhiteSpace(fileName)) return null;
            var key = Path.GetFileName(fileName); // defence in depth: strip any path
            return ReportImageCache.GetOrAdd(key, k =>
            {
                var dir = ReportImageDir.Value;
                if (dir is null) return null;
                try
                {
                    var path = Path.Combine(dir, k);
                    return File.Exists(path) ? File.ReadAllBytes(path) : null;
                }
                catch { return null; }
            });
        }

        /// <summary>
        /// The box a branding logo is drawn in: the client sets a fixed height (cover 100pt, page header
        /// 30pt) and lets the width follow the image's aspect ratio; the width cap keeps a banner-shaped
        /// logo off the cover date and out of the page-header title column.
        /// </summary>
        public static (double w, double h) LogoBox(byte[] bytes, double height, double maxWidth)
        {
            var (pxW, pxH) = ImageSize(bytes);
            var w = pxW * (height / pxH);
            if (w > maxWidth) { height *= maxWidth / w; w = maxWidth; }
            return (Math.Round(w), Math.Round(height));
        }

        /// <summary>The MIME type a drawing needs beside the bytes, from the content itself; null when OfficeIMO cannot identify it (skipped rather than failing).</summary>
        public static string? ImageContentType(byte[] b)
        {
            try { return OfficeImageReader.TryIdentifyByContent(b, null, out var info) ? info.MimeType : null; }
            catch { return null; }
        }

        /// <summary>Pixel size of any image OfficeIMO identifies (a 4:3 guess for anything it cannot).</summary>
        public static (int w, int h) ImageSize(byte[] b)
        {
            try
            {
                if (OfficeImageReader.TryIdentifyByContent(b, null, out var info) && info.Width > 0 && info.Height > 0)
                    return (info.Width, info.Height);
            }
            catch { /* fall through to the guess */ }
            return (800, 600);
        }

        // -- inline runs --
        // `size` is the base font size for the paragraph's runs (markdown has no size marks, so every run
        // in a paragraph shares it). Without an explicit size OfficeIMO falls back to its ~12pt default,
        // which is why body copy rendered far larger than the client's 9pt.
        private static void ApplyRuns(PdfParagraphBuilder b, IReadOnlyList<TextRun> runs, string bodyColour, double size)
        {
            if (runs.Count == 0) { b.Text(" "); return; }
            b.Color(Pdf(bodyColour)).FontSize(size);
            foreach (var r in runs)
            {
                // Emoji split out to inline colour images (or a monochrome glyph) so the surrounding copy
                // keeps its font/weight and an emoji never lands in a bold/italic run the fallback can't draw.
                foreach (var seg in SegmentEmoji(r.Text))
                {
                    switch (seg.Kind)
                    {
                        case EmojiSegKind.Image:
                            b.InlineImage(seg.Image!, size, size, seg.Text, OfficeImageFit.Contain, EmojiOffset(size));
                            break;
                        case EmojiSegKind.Mono:
                            b.Bold(false).Italic(false).Underline(false).Strike(false).Font(PdfStandardFont.Helvetica).Color(Pdf(seg.Tint ?? bodyColour)).Text(seg.Text);
                            break;
                        default:
                            b.Bold(r.Bold).Italic(r.Italic).Underline(r.Underline).Strike(r.Strike)
                             .Font(r.Code ? PdfStandardFont.Courier : PdfStandardFont.Helvetica).Color(Pdf(bodyColour)).Text(seg.Text);
                            break;
                    }
                }
            }
        }

        // -- primitives --
        public static void Heading(ReportContext ctx, PdfContentBuilder item, int level, IReadOnlyList<TextRun> runs)
        {
            var text = RunsToPlain(runs);
            var colour = level switch { 1 => ReportColours.Ink, 2 => ctx.Theme.Palette["heading"], _ => ReportColours.Body };
            var size = level switch { 1 => ReportStyles.Heading1, 2 => ReportStyles.Heading2, _ => ReportStyles.Heading3 };
            // A markdown heading is drawn as a bold paragraph (rather than item.H1/H2/H3) so an emoji in the
            // heading renders as an inline colour image instead of a monochrome font glyph.
            item.Paragraph(b => { b.FontSize(size); EmitInline(b, text, colour, size, bold: true); },
                PdfAlign.Left, null, new PdfParagraphStyle { LineHeight = 1.15, SpacingAfter = 6 });
        }

        // The text style a run of copy is drawn with. Threaded from the enclosing component so body copy,
        // callout text and captions each render at their own size/colour/alignment - the server mirror of
        // the client's context-driven styles.
        public readonly struct TextStyle
        {
            public double Size { get; init; }
            public string Colour { get; init; }
            public PdfAlign Align { get; init; }
            public double LineHeight { get; init; }
            public double SpacingAfter { get; init; }
        }

        // OfficeIMO leads a flow paragraph off the document's 11pt default size rather than its runs' size (a
        // larger run raises its line by the same ratio) and seats the first baseline FlowBaseline under the
        // paragraph's top. A client line is its lineHeight x the size, with the baseline 0.9x the size under
        // the line top. So a client lineHeight becomes a LineHeight scaled by size / 11, and a paragraph of
        // runs larger than 9pt needs (0.9 x size - FlowBaseline) of space above it to seat its baseline.
        internal const double FlowBaseSize = 11, FlowBaseline = 8.1;
        private static double FlowLineHeight(double clientLineHeight, double size) => clientLineHeight * size / Math.Max(size, FlowBaseSize);

        // Body copy (client bodyText): 9pt at lineHeight 1.5, 8pt after, justified.
        public static TextStyle BodyStyle(ReportContext ctx) => new()
        {
            Size = ReportStyles.Body, Colour = ctx.Theme.Palette["body"], Align = PdfAlign.Justify, LineHeight = FlowLineHeight(1.5, ReportStyles.Body), SpacingAfter = 8,
        };

        public static void Paragraph(ReportContext ctx, PdfContentBuilder item, IReadOnlyList<TextRun> runs, TextStyle? style = null)
        {
            var st = style ?? BodyStyle(ctx);
            item.Paragraph(b => ApplyRuns(b, runs, st.Colour, st.Size), st.Align, null,
                new PdfParagraphStyle { LineHeight = st.LineHeight, SpacingAfter = st.SpacingAfter });
        }

        // Section title (client sectionTitle): 14pt bold heading colour on the page's 14pt line, marginBottom 8.
        // The space above seats the baseline 0.9x the size under the line top, and comes out of the 8 below.
        private const double SectionTitleSeat = 0.9 * ReportStyles.SectionTitle - FlowBaseline;
        public static void SectionTitle(ReportContext ctx, PdfContentBuilder item, string title)
            => item.Paragraph(b => { b.FontSize(ReportStyles.SectionTitle); EmitInline(b, title, ctx.Theme.Palette["heading"], ReportStyles.SectionTitle, bold: true); },
                PdfAlign.Left, null, new PdfParagraphStyle
                {
                    LineHeight = FlowLineHeight(14 / ReportStyles.SectionTitle, ReportStyles.SectionTitle),
                    SpacingBefore = SectionTitleSeat,
                    SpacingAfter = 8 - SectionTitleSeat,
                });

        // A callout's list rendered as one paragraph, a line break between items (a panel ignores list
        // styling, so this matches the client's single-text-block callout bullets). `marker(i)` prefixes
        // each line (a bullet dot, or "N. " for numbered).
        private static void BulletLines(ReportContext ctx, PdfContentBuilder item, IReadOnlyList<string> items, TextStyle ts, Func<int, string> marker)
        {
            if (items.Count == 0) return;
            item.Paragraph(b =>
            {
                b.FontSize(ts.Size).Color(Pdf(ts.Colour));
                for (var i = 0; i < items.Count; i++)
                {
                    if (i > 0) b.LineBreak();
                    b.Color(Pdf(ts.Colour)).Text(marker(i));
                    EmitToBuilder(b, San(items[i]), ts.Colour, ts.Size);
                }
            }, PdfAlign.Left, null, new PdfParagraphStyle { LeftIndent = 12, SpacingAfter = ts.SpacingAfter, LineHeight = ts.LineHeight });
        }

        public static void Bullets(ReportContext ctx, PdfContentBuilder item, IEnumerable<string> items, double? size = null)
            => BulletParagraphs(ctx, item, new List<string>(items), size ?? ReportStyles.BulletText, _ => "•  ");

        // A bullet/numbered list drawn as one paragraph per item (marker + emoji-aware text) rather than
        // item.Bullets, so an emoji in a list item renders as an inline colour image. Marker in the heading
        // colour; matches the old ListStyle (indent 12, 4pt item spacing, 1.3 line height).
        private static void BulletParagraphs(ReportContext ctx, PdfContentBuilder item, IReadOnlyList<string> items, double size, Func<int, string> marker)
        {
            var body = ctx.Theme.Palette["body"];
            var markerColour = ctx.Theme.Palette["heading"];
            for (var i = 0; i < items.Count; i++)
            {
                var idx = i;
                item.Paragraph(b =>
                {
                    b.FontSize(size);
                    b.Bold(true).Color(Pdf(markerColour)).Text(marker(idx));
                    EmitToBuilder(b, San(items[idx]), body, size);
                }, PdfAlign.Left, null, new PdfParagraphStyle { LeftIndent = 12, SpacingAfter = 4, LineHeight = 1.3 });
            }
        }

        public static void Numbered(ReportContext ctx, PdfContentBuilder item, IEnumerable<string> items, int start, double? size = null)
            => BulletParagraphs(ctx, item, new List<string>(items), size ?? ReportStyles.BulletText, i => (start + i) + ".  ");

        // The branded cover, drawn as a page-sized OfficeDrawing over an optional full-bleed cover photo
        // (client CoverPage): date top-right, a rounded pill label chip, the two-tone title, the subtitle
        // and tenant vertically placed, and the confidential note at the bottom. A drawing lets the chip
        // be a real rounded pill and the confidential note sit at the page foot - neither is possible in
        // the plain content flow.
        public static void RenderCoverDrawing(ReportContext ctx, PdfContentBuilder item)
        {
            var w = ctx.ContentWidth - 2;
            // A drawing exactly the content height is rejected as too tall (as with width): landscape trips
            // this because the A4 long edge is a hair over the page height, so shave 2pt off both here.
            var h = ctx.ContentHeight - 2;
            const double leftPad = 28;
            var coverText = ctx.Theme.Palette["coverText"];
            var subtitleC = ctx.Theme.Palette["subtitle"];
            var primary = ctx.Theme.Primary;
            var dw = new OfficeDrawing(w, h);

            // Vertical anchors mirror the client cover's fixed paddings (page pad 60, a header row of the
            // logo and date with a 40pt margin under it, hero paddingTop 24) rather than a proportion of
            // page height, so the block lands where the react-pdf cover puts it. The drawing origin already
            // sits at the page margin, so each client "from page top" figure is offset by PagePadding here.
            const double coverPad = 60, headerGap = 40, heroPad = 24, logoHeight = 100;
            var headerTop = coverPad - ReportStyles.PagePadding;

            // The client cover's text sits on react-pdf's natural Helvetica leading: a line box 1.1x the size
            // with the baseline 0.9x the size under its top. AddText puts the baseline a full size under its
            // box top, so a line is drawn 0.1x its size above the top of the client line it stands for, and
            // `y` below always tracks the client's line tops.
            const double lineBox = 1.1;
            void Line(string text, double x, double top, double width, double size, string colour, OfficeTextAlignment align, bool bold = false)
                => AddT(dw, text, x, top - 0.1 * size, width, size * 1.2, size, colour, align, bold);

            // Client coverHeader: the branding logo on the left at 100pt (width by aspect ratio, capped so
            // a banner never reaches the date), the date on the right, the two vertically centred on each
            // other. Without a logo the row is just the date line. The date keeps the cover's 60pt page
            // inset on the right, like everything else on the cover.
            var logoType = ctx.Logo is { Length: > 0 } ? ImageContentType(ctx.Logo) : null;
            var logoBox = logoType is null ? (w: 0.0, h: 0.0) : LogoBox(ctx.Logo!, logoHeight, 260);
            var dateLine = 9 * lineBox;
            var headerH = Math.Max(dateLine, logoBox.h);
            if (logoType is not null)
                dw.AddImage(ctx.Logo!, logoType, new OfficeImageProjection(
                    new OfficeImagePlacement(leftPad, headerTop, logoBox.w, logoBox.h), new OfficeImageSourceCrop(0, 0, 0, 0), 0, null, null, false, false));
            if (!string.IsNullOrEmpty(ctx.GeneratedOn))
                Line(San(ctx.GeneratedOn).ToUpperInvariant(), 0, headerTop + (headerH - dateLine) / 2, ctx.ContentWidth - leftPad, 9, coverText, OfficeTextAlignment.Right);

            var coverLabel = (ctx.Variables.TryGetValue("coverlabel", out var cl) && !string.IsNullOrWhiteSpace(cl)) ? cl : "ASSESSMENT REPORT";
            coverLabel = San(coverLabel).ToUpperInvariant();
            var chipW = Math.Min(w - leftPad * 2, 26 + coverLabel.Length * 6.4);
            // Client coverLabel: the 10pt label on its natural line inside 8pt of padding, so a 27pt pill.
            var chipH = 8 + ReportStyles.CoverLabel * lineBox + 8;
            var y = headerTop + headerH + headerGap + heroPad;   // client coverHero content top (chip)
            var chip = OfficeShape.RoundedRectangle(chipW, chipH, chipH / 2); chip.FillColor = OC(primary);
            dw.AddShape(chip, leftPad, y);
            Line(coverLabel, leftPad, y + 8, chipW, ReportStyles.CoverLabel, ctx.Theme.OnPrimary, OfficeTextAlignment.Center, true);
            y += chipH + 30;                          // client coverLabel marginBottom 30

            // Cover title: an explicit covertitle/coveraccent override (client coverTitle/coverAccent, e.g.
            // the BEC report's "BEC Compromise" / "Analysis") else the report name split on its last word.
            string lead, accent;
            if (ctx.Variables.TryGetValue("covertitle", out var ctv) && !string.IsNullOrWhiteSpace(ctv))
            {
                lead = San(ctv).ToUpperInvariant();
                accent = (ctx.Variables.TryGetValue("coveraccent", out var cav) && !string.IsNullOrWhiteSpace(cav)) ? San(cav).ToUpperInvariant() : string.Empty;
            }
            else
            {
                var words = San(ctx.ReportName).ToUpperInvariant().Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                lead = words.Length > 1 ? string.Join(" ", words[..^1]) : (words.Length == 1 ? words[0] : string.Empty);
                accent = words.Length > 1 ? words[^1] : string.Empty;
            }
            // A long line shrinks to fit rather than running off the page ("QUARTERLY SECURITY" did):
            // Helvetica Bold capitals average about 0.7em, so the size that fits is the box over that.
            double FitTitle(string s) => Math.Min(ReportStyles.CoverTitle, (w - leftPad) / Math.Max(1, s.Length * 0.7));
            var titleSize = Math.Min(FitTitle(lead), FitTitle(accent));
            if (!string.IsNullOrEmpty(lead)) { Line(lead, leftPad, y, w - leftPad, titleSize, coverText, OfficeTextAlignment.Left, true); y += titleSize * lineBox; }
            if (!string.IsNullOrEmpty(accent)) { Line(accent, leftPad, y, w - leftPad, titleSize, primary, OfficeTextAlignment.Left, true); y += titleSize * lineBox; }
            if (!string.IsNullOrEmpty(lead) || !string.IsNullOrEmpty(accent)) y += 20;  // client title marginBottom 20

            // Client coverHero is the page less its 60pt padding each side; the text under the title wraps
            // inside it. Its footer note is the last thing on the cover: it wraps in the same width (counting
            // its 1pt letter spacing) and its last line box ends at the 60pt page pad. The client keeps 32pt
            // above it (coverFooter marginTop) and spills a cover that outgrows the page onto a second one;
            // the cover here is one fixed drawing, so the block may run into that 32pt - a landscape cover
            // with a logo needs it for the tenant line - and only a line that would touch the note is dropped.
            var heroW = ctx.ContentWidth + 2 * ReportStyles.PagePadding - 2 * coverPad;
            // Branding's cover note wins and the report's own wording is the fallback (client ReportDocument),
            // so a configured note is not silently ignored by every report that words its own. Like the client,
            // the note is held to the footer's length once its variables are filled.
            var note = "CONFIDENTIAL & PROPRIETARY";
            if (!string.IsNullOrEmpty(ctx.Theme.CoverFooterText)) note = ctx.Theme.CoverFooterText;
            else if (ctx.Variables.TryGetValue("coverfooternote", out var cfn) && !string.IsNullOrWhiteSpace(cfn)) note = cfn;
            var noteLines = WrapLines(San(ReportTheme.ApplyFooter(note, ctx.Variables)).ToUpperInvariant(), heroW, 9, bold: false, tracking: 1);
            var noteTop = ctx.ContentHeight + ReportStyles.PagePadding - coverPad - noteLines.Count * 9 * lineBox;
            // Draws `text` wrapped to `width` on `pitch`-point lines from the client line top `top` and returns
            // the height of the lines drawn. Each line is placed like any other cover line: react-pdf seats the
            // baseline 0.9x the size under the line top even in a taller line (the subtitle's 21pt one).
            double Wrapped(string text, double top, double width, double size, double pitch, string colour, bool bold = false)
            {
                var drawn = 0.0;
                foreach (var line in WrapLines(text, width, size, bold))
                {
                    if (top + drawn + pitch > noteTop - 4) break;
                    Line(line, leftPad, top + drawn, width, size, colour, OfficeTextAlignment.Left, bold);
                    drawn += pitch;
                }
                return drawn;
            }

            if (ctx.Variables.TryGetValue("coversubtitle", out var cs) && !string.IsNullOrWhiteSpace(cs))
            {
                // The client subtitle: maxWidth 400 at its lineHeight 1.5 (21pt a line), then marginBottom 40.
                y += Wrapped(San(cs), y, Math.Min(400, heroW), ReportStyles.CoverSubtitle, ReportStyles.CoverSubtitle * 1.5, coverText) + 40;
            }

            // The subject line under the title: usually the tenant, but a covertenant override names a
            // different subject (the BEC report puts the compromised user here instead of the tenant).
            // Client coverMetaCard: maxWidth 500, then the label's marginBottom 8.
            var coverTenant = (ctx.Variables.TryGetValue("covertenant", out var cvt) && !string.IsNullOrWhiteSpace(cvt)) ? cvt : ctx.TenantName;
            if (!string.IsNullOrEmpty(coverTenant))
                y += Wrapped(San(coverTenant), y, Math.Min(500, heroW), 18, 18 * lineBox, coverText, bold: true) + 8;
            // Optional cover meta (client CoverMeta): extra detail lines under the tenant (4pt under each),
            // then a note 8pt under them.
            if (ctx.Variables.TryGetValue("covermeta", out var cm) && !string.IsNullOrWhiteSpace(cm))
                foreach (var line in cm.Replace("\r", "").Split('\n'))
                    y += Wrapped(San(line), y, heroW, 12, 12 * lineBox, subtitleC) + 4;
            if (ctx.Variables.TryGetValue("covermetanote", out var cmn) && !string.IsNullOrWhiteSpace(cmn))
                Wrapped(San(cmn), y + 8, heroW, 11, 11 * lineBox, subtitleC);

            for (var i = 0; i < noteLines.Count; i++)
                Line(noteLines[i], 0, noteTop + i * 9 * lineBox, w, 9, ctx.Theme.Palette["footer"], OfficeTextAlignment.Center);

            item.Drawing(dw, PdfAlign.Left);
        }

        // Full-bleed hero content (client HeroPage overlay): the big highlight figure plus overtitle/
        // headline/subtext block, vertically centred and left-aligned, with the footer note bottom-right.
        // Drawn as one page-sized OfficeDrawing (transparent) over the section's background image, because
        // flow layout can neither vertically centre nor pin the footer to the bottom-right corner.
        public static void RenderHeroDrawing(ReportContext ctx, PdfContentBuilder item, ReportNode block)
        {
            var w = ctx.ContentWidth - 2;
            // See RenderCoverDrawing: a page-tall drawing is rejected in landscape without this 2pt shave.
            var h = ctx.ContentHeight - 2;
            var highlightColour = ctx.Theme.Palette["infographic"];
            var onDark = ctx.Theme.OnInfographic;
            var overtitle = block.Str("overtitle") ?? block.Str("heroOvertitle");
            var highlight = block.Str("highlight") ?? block.Str("heroHighlight");
            var headline = block.Str("headline") ?? block.Str("heroHeadline") ?? block.Str("title");
            var subText = block.Str("subText") ?? block.Str("heroSubText");
            var footerText = block.Str("footerText") ?? block.Str("heroFooterText");
            const double leftPad = 28, textW = 440;
            var subLines = string.IsNullOrEmpty(subText) ? Array.Empty<string>() : subText.Replace("\r", "").Split('\n');

            var blockH = (string.IsNullOrEmpty(overtitle) ? 0 : 24) + (string.IsNullOrEmpty(highlight) ? 0 : 84)
                + (string.IsNullOrEmpty(headline) ? 0 : 24) + subLines.Length * 19;
            var y = Math.Max(40, (h - blockH) / 2);

            var dw = new OfficeDrawing(w, h);
            if (!string.IsNullOrEmpty(overtitle)) { AddT(dw, San(overtitle), leftPad, y, textW, 22, 18, onDark, OfficeTextAlignment.Left, true); y += 24; }
            if (!string.IsNullOrEmpty(highlight)) { AddT(dw, San(highlight), leftPad, y, textW, 82, 72, highlightColour, OfficeTextAlignment.Left, true); y += 84; }
            if (!string.IsNullOrEmpty(headline)) { AddT(dw, San(headline), leftPad, y, textW, 22, 18, onDark, OfficeTextAlignment.Left, true); y += 24; }
            foreach (var line in subLines) { AddT(dw, San(line), leftPad, y, textW, 18, 14, onDark, OfficeTextAlignment.Left, true); y += 19; }

            if (!string.IsNullOrEmpty(footerText))
            {
                var fLines = footerText.Replace("\r", "").Split('\n');
                var fy = h - 40 - (fLines.Length - 1) * 16;
                foreach (var line in fLines) { AddT(dw, San(line), 0, fy, w - leftPad, 16, 12, onDark, OfficeTextAlignment.Right, true); fy += 16; }
            }
            item.Drawing(dw, PdfAlign.Left);
        }

        /// <summary>Rich bullets (client BulletList with {label, text}): an orange marker, a bold label, then
        /// body text - each an item.Paragraph with per-run colour so the marker and label differ from the text.</summary>
        public static void RichBullets(ReportContext ctx, PdfContentBuilder item, List<object?> items)
        {
            // Client BulletList: the list is inset 12 with 12 under it; each item is a row of the 8pt bold
            // marker (6pt after it, 1pt down, on the page's 14pt line) and the 9pt text at lineHeight 1.4, 6pt
            // under the item. The text column hangs: a wrapped line starts under the text, not the marker, so
            // the paragraph is indented to the text and the first line pulled back to the marker, with a tab
            // stop at the text column. A one-line item is as tall as the marker's 15pt line, not the 12.6pt
            // text line, so it keeps the 2.4pt difference below it.
            const double markerSize = 8, markerGap = 6, listInset = 12, itemGap = 6, listGap = 12;
            var textLine = 1.4 * ReportStyles.BulletText;
            for (var i = 0; i < items.Count; i++)
            {
                var it = items[i];
                var label = ReportNode.RowStr(it, "label");
                var text = ReportNode.RowStr(it, "text") ?? string.Empty;
                var marker = ReportNode.RowStr(it, "marker"); // custom marker (e.g. "1.") else a bullet dot
                marker = string.IsNullOrEmpty(marker) ? "•" : San(marker);
                var hang = TextEm(marker, bold: true) * markerSize + markerGap;
                var copy = string.IsNullOrEmpty(label) ? text : label + " " + text;
                // ponytail: the label is measured as regular text, a hair narrow for its bold face.
                var oneLine = WrappedLines(copy, ctx.ContentWidth - listInset - hang, ReportStyles.BulletText, bold: false) == 1;
                var style = new PdfParagraphStyle
                {
                    LeftIndent = listInset + hang,
                    FirstLineIndent = -hang,
                    LineHeight = FlowLineHeight(1.4, ReportStyles.BulletText),
                    SpacingAfter = itemGap + (oneLine ? 1 + 14 - textLine : 0) + (i == items.Count - 1 ? listGap : 0),
                };
                style.AddTabStop(0.01);
                item.Paragraph(b =>
                {
                    b.FontSize(ReportStyles.BulletText);
                    b.Bold(true).Color(Pdf(ctx.Theme.Palette["heading"])).FontSize(markerSize).Text(marker).Text("\t").FontSize(ReportStyles.BulletText);
                    var body = ctx.Theme.Palette["body"];
                    if (!string.IsNullOrEmpty(label)) EmitToBuilder(b, San(label) + " ", body, ReportStyles.BulletText, bold: true);
                    EmitToBuilder(b, San(text), body, ReportStyles.BulletText, bold: false);
                }, PdfAlign.Left, null, style);
            }
        }

        /// <summary>Brand-coloured table: header band in the tenant's table colour, striped rows, repeating header.</summary>
        public static PdfTableStyle BrandedTableStyle(ReportContext ctx) => new()
        {
            HeaderFill = Pdf(ctx.Theme.Palette["table"]),
            HeaderTextColor = Pdf(ctx.Theme.OnTable),
            HeaderBold = true,
            HeaderFontSize = ReportStyles.TableHeaderCell,
            RowStripeFill = Pdf(ReportColours.Panel),
            BorderColor = Pdf(ReportColours.Line),
            BorderWidth = 0.5,
            RowSeparatorColor = Pdf(ReportColours.Line),
            RowSeparatorWidth = 0.5,
            TextColor = Pdf(ReportColours.Body),
            FontSize = ReportStyles.TableCell,
            RepeatHeaderRowCount = 1,
            CellPaddingX = 12,   // client TABLE_ROW_PADDING (horizontal cell inset)
            CellPaddingY = 6,    // client tableRow paddingVertical
        };

        /// <summary>
        /// A plain table of text rows, the first row its header (a markdown, HTML or database table; client
        /// ReportBuilderPDF renderTable). The client draws it as the same DataTable as a rich table, with
        /// equal columns and the first column bold, so it is one: the header row names the columns and every
        /// other row is squared off to that many cells.
        /// </summary>
        public static void Table(ReportContext ctx, PdfContentBuilder item, IReadOnlyList<string[]> rows)
        {
            if (rows.Count == 0) return;
            var count = rows[0].Length > 0 ? rows[0].Length : rows.Max(r => r.Length);
            string Cell(string[] row, int i) => i < row.Length ? row[i] ?? string.Empty : string.Empty;
            var columns = Enumerable.Range(0, count).Select(i => (object?)new Dictionary<string, object?>
            {
                ["header"] = Cell(rows[0], i), ["key"] = "c" + i, ["width"] = 1.0, ["bold"] = i == 0,
            }).ToList();
            var body = rows.Skip(1).Select(r => (object?)Enumerable.Range(0, count).ToDictionary(i => "c" + i, i => (object?)Cell(r, i))).ToList();
            RichTable(ctx, item, columns, body, 0);
        }

        // Shared status vocabulary (client STATUS_TONES): a status word coloured by tone.
        private static string ToneColour(string? tone) => tone switch
        {
            "pass" => ReportColours.Success,
            "warn" => ReportColours.Warning,
            "fail" => ReportColours.Danger,
            "muted" => ReportColours.Faint,
            _ => ReportColours.Body,
        };

        private static bool RowBool(object? row, string key)
            => row is Dictionary<string, object?> d && d.TryGetValue(key, out var v) && v is bool b && b;

        /// <summary>
        /// The client DataTable: column specs (header/key/width weight/bold/align) with per-cell rendering.
        /// A column with <c>toneField</c> draws its value as italic status text coloured by the row's tone
        /// field (Compliant=green, Review=red, ...); a <c>bold</c> column draws its value bold. Header band
        /// in the brand table colour, uppercase; striped body rows; rows beyond <c>limit</c> drop to a note.
        /// With no rows, <c>emptyText</c> is drawn inside the border as one full-width italic row (client
        /// DataTable emptyText: 8pt faint italic, padding 12); without it the table is a bare header, as a
        /// markdown or HTML table is (client renderTable has no empty state).
        /// </summary>
        public static void RichTable(ReportContext ctx, PdfContentBuilder item, List<object?> columns, List<object?> rows, int limit, string? emptyText = null)
        {
            if (columns.Count == 0) return;
            var widths = new List<double>();
            var aligns = new List<PdfColumnAlign>();
            var header = new List<PdfTableCell>();
            foreach (var c in columns)
            {
                var w = ReportNode.RowNum(c, "width"); if (w <= 0) w = 1;
                widths.Add(w);
                aligns.Add((ReportNode.RowStr(c, "align")) switch { "center" => PdfColumnAlign.Center, "right" => PdfColumnAlign.Right, _ => PdfColumnAlign.Left });
                // Header runs (not a plain string) so an emoji in a column header renders as a colour image;
                // the brand header fill/uppercase come from the table style, the text colour is OnTable bold.
                header.Add(CellRuns((ReportNode.RowStr(c, "header") ?? string.Empty).ToUpperInvariant(), ctx.Theme.OnTable, bold: true, size: ReportStyles.TableHeaderCell));
            }

            var shown = limit > 0 ? rows.Take(limit).ToList() : rows;
            var hidden = rows.Count - (limit > 0 ? Math.Min(limit, rows.Count) : rows.Count);
            var cells = new List<PdfTableCell[]> { header.ToArray() };
            foreach (var r in shown)
            {
                var rowCells = new PdfTableCell[columns.Count];
                for (var ci = 0; ci < columns.Count; ci++)
                {
                    var col = columns[ci];
                    var key = ReportNode.RowStr(col, "key") ?? string.Empty;
                    var text = San(ReportNode.RowStr(r, key) ?? string.Empty);
                    var toneField = ReportNode.RowStr(col, "toneField");
                    var colourField = ReportNode.RowStr(col, "colourField");
                    if (!string.IsNullOrEmpty(toneField))
                    {
                        var colour = ToneColour(ReportNode.RowStr(r, toneField));
                        rowCells[ci] = CellRuns(text, colour, bold: false, italic: true, size: ReportStyles.StatusText);
                    }
                    else if (!string.IsNullOrEmpty(colourField))
                    {
                        // Bold text in an arbitrary per-row colour (client column.colour(row), e.g. risk bands).
                        var colour = ReportNode.RowStr(r, colourField);
                        rowCells[ci] = CellRuns(text, string.IsNullOrEmpty(colour) ? ReportColours.Body : colour, bold: true);
                    }
                    else if (RowBool(col, "bold"))
                    {
                        rowCells[ci] = CellRuns(text, ReportColours.Body, bold: true);
                    }
                    else
                    {
                        rowCells[ci] = CellRuns(text, ReportColours.Body);
                    }
                }
                cells.Add(rowCells);
            }

            var emptyRow = shown.Count == 0 && !string.IsNullOrEmpty(emptyText);
            if (emptyRow)
            {
                var runs = new List<PdfTextRun>();
                EmitRuns(runs, San(emptyText!), ReportColours.Faint, ReportStyles.TableCell, bold: false, italic: true);
                cells.Add(new[] { new PdfTableCell(runs, columnSpan: columns.Count) });
            }

            var style = BrandedTableStyle(ctx);
            ApplyDataTableGeometry(ctx, style, widths, cells.Count, hidden > 0, emptyRow);
            style.Alignments = aligns;
            // A status word stands in the client page's 14pt line rather than the 10.4pt cell line, so its
            // cell carries the difference as padding: the word sits 0.9pt lower and a one-line row is 27pt.
            for (var ci = 0; ci < columns.Count; ci++)
            {
                if (string.IsNullOrEmpty(ReportNode.RowStr(columns[ci], "toneField"))) continue;
                for (var ri = 1; ri <= shown.Count; ri++)
                {
                    var pad = style.CellPaddings!.TryGetValue((ri, ci), out var p) ? p : new PdfCellPadding();
                    pad.Top = (pad.Top ?? style.CellPaddingTop) + 0.9;
                    pad.Bottom = (pad.Bottom ?? style.CellPaddingBottom) + 1.4;
                    style.CellPaddings[(ri, ci)] = pad;
                }
            }
            // Client body rows are wrap={false}: a row that does not fit moves whole to the next page. OfficeIMO
            // throws on an unsplittable row taller than a page, so a row is kept whole only when its height,
            // measured by word-wrapping each cell with the Helvetica metrics, is under half a page (the
            // margin covers the measure differing from OfficeIMO's own wrap).
            var totalWeight = widths.Sum();
            var keepWhole = new List<bool?> { null }; // the header row keeps the style default
            foreach (var r in shown)
            {
                var lines = 1;
                for (var ci = 0; ci < columns.Count; ci++)
                {
                    var textWidth = Math.Max(1, (ctx.ContentWidth - 2 * (TableInset + TableBorder)) * widths[ci] / totalWeight - TableGutter);
                    var text = ReportNode.RowStr(r, ReportNode.RowStr(columns[ci], "key") ?? string.Empty) ?? string.Empty;
                    var bold = RowBool(columns[ci], "bold") || !string.IsNullOrEmpty(ReportNode.RowStr(columns[ci], "colourField"));
                    lines = Math.Max(lines, WrappedLines(text, textWidth, ReportStyles.TableCell, bold));
                }
                keepWhole.Add(lines * ReportStyles.TableCell * 1.3 + style.CellPaddingTop + style.CellPaddingBottom < ctx.ContentHeight / 2 ? false : null);
            }
            style.RowAllowBreakAcrossPages = keepWhole;
            item.Table(cells, PdfAlign.Left, style);
            if (hidden > 0)
                Note(ctx, item, $"... and {hidden} more. Export the table from the report page for the full list.");
        }

        // The client DataTable's box (styles.table/tableHeader/tableRow + tableColumns): the row is inset 12pt
        // inside a 1pt border and each column but the last keeps a 6pt gutter on its right, so a cell's text
        // width is its share of the inset row less the gutter. OfficeIMO pads every cell alike, so the edge
        // columns carry the inset (and the border) as their own padding and are widened by it, which gives
        // every column exactly the client's text width. No vertical rules: the outline is straight per-cell
        // borders on the perimeter, because a table-level border draws the full grid. The corners stay square:
        // OfficeIMO strokes a rounded cell border as the cell's whole rounded box clipped to a strip, which on
        // a multi-column table leaves 6pt stubs across the header band. Rows are divided by the client's pale
        // 1pt panel line, which sits inside the row's box (so a row is 13pt of padding plus its 10.4pt lines),
        // and the header band is 28pt for one line of 7pt text on a 14pt pitch. The pads are split to put the
        // text where the client's sits. 16pt follows the table, 4pt when the truncation note does.
        private const double TableInset = 12, TableGutter = 6, TableBorder = 1;
        private static void ApplyDataTableGeometry(ReportContext ctx, PdfTableStyle style, List<double> weights, int rowCount, bool noteFollows, bool emptyRow = false)
        {
            var cols = weights.Count;
            var edge = TableInset + TableBorder;
            var total = weights.Sum();
            var inner = ctx.ContentWidth - 2 * edge;
            style.ColumnWidthWeights = weights.Select((w, i) => w / total * inner + (i == 0 ? edge : 0) + (i == cols - 1 ? edge : 0)).ToList();
            style.BorderWidth = 0;
            style.RowSeparatorColor = Pdf(ReportColours.Panel);
            style.RowSeparatorWidth = 1;
            style.HeaderSeparatorColor = Pdf(ctx.Theme.Palette["table"]); // no line under the band
            style.HeaderSeparatorWidth = 1;
            style.LineHeight = 1.3;                                      // client tableCell lineHeight
            style.HeaderFontSize = 14 / 1.3;                             // header leading 14 (runs stay 7pt)
            style.CellPaddingLeft = 0;
            style.CellPaddingRight = TableGutter;
            style.CellPaddingTop = 7.3;
            style.CellPaddingBottom = 5.7;
            style.SpacingAfter = noteFollows ? 4 : 16;
            // The client's header repeats on each page and its rows move whole, so a table starts on the page
            // as soon as the header and one row fit there (OfficeIMO's default waits for two).
            style.MinimumBodyRowsOnFirstPage = 1;
            var line = Pdf(ReportColours.Line);
            style.CellPaddings = new Dictionary<(int, int), PdfCellPadding>();
            style.CellBorders = new Dictionary<(int, int), PdfCellBorder>();
            for (var r = 0; r < rowCount; r++)
            {
                for (var c = 0; c < cols; c++)
                {
                    // The client's outline sits outside the rows, so the header band starts and the last row
                    // ends a border's width further in than a cell border drawn on the cell edge: the header's
                    // top pad and the last row's bottom pad each carry it.
                    var first = c == 0; var last = c == cols - 1; var top = r == 0; var bottom = r == rowCount - 1;
                    if (first || last || top || bottom)
                        style.CellPaddings[(r, c)] = new PdfCellPadding
                        {
                            Left = first ? edge : null,
                            Right = last ? edge : null,
                            Top = top ? 5.4 + TableBorder : null,
                            Bottom = (top ? 6.7 + TableBorder : style.CellPaddingBottom) + (bottom ? TableBorder : 0),
                        };
                    if (first || last || top || bottom)
                        style.CellBorders[(r, c)] = new PdfCellBorder { Color = line, Width = TableBorder, Left = first, Right = last, Top = top, Bottom = bottom };
                }
            }
            // The empty-state row (client tableEmpty: 12pt all round inside the 1pt border) is one cell
            // spanning every column, so it carries the row's whole outline itself. The client's row is
            // 38pt with the text's cap top 13.5pt under the band; the pads put the text there.
            if (emptyRow)
            {
                for (var c = 1; c < cols; c++) { style.CellPaddings.Remove((1, c)); style.CellBorders.Remove((1, c)); }
                style.CellPaddings[(1, 0)] = new PdfCellPadding { Left = TableBorder + 12, Right = TableBorder + 12, Top = 13.5, Bottom = 15.3 + TableBorder };
                style.CellBorders[(1, 0)] = new PdfCellBorder { Color = line, Width = TableBorder, Left = true, Right = true, Top = false, Bottom = true };
            }
        }

        public static void Code(ReportContext ctx, PdfContentBuilder item, string text)
            => item.Paragraph(b =>
            {
                b.Font(PdfStandardFont.Courier).FontSize(CodeParagraphSize).Color(Pdf(ReportColours.Body));
                var lines = San(text).Replace("\r\n", "\n").Split('\n');
                for (var i = 0; i < lines.Length; i++) { if (i > 0) b.LineBreak(); b.Text(lines[i]); }
            });

        public static void Hr(ReportContext ctx, PdfContentBuilder item) => item.HR();

        // A small italic aside after a truncated list (client styles.truncationNote): 8pt faint italic,
        // indented to the table's inner padding.
        public static void Note(ReportContext ctx, PdfContentBuilder item, string text)
            => item.Paragraph(b => { b.Italic(true).FontSize(ReportStyles.TableCell); EmitInline(b, text, ReportColours.Faint, ReportStyles.TableCell); },
                PdfAlign.Left, null, new PdfParagraphStyle { LeftIndent = 12, SpacingAfter = 4 });

        // -- callouts (InfoBox / AlertBox / ClearBox) --
        // Callouts are drawn as a single-cell bordered TABLE, not a Panel: OfficeIMO panels apply a fixed
        // internal paragraph leading and ignore per-call line-height/spacing, which opens a loose gap
        // between the title and body and between body lines. A table cell honours run sizing and cell
        // padding exactly (the same reason StatCard is a cell), so the callout matches the client's tight
        // spacing. The title is a bold run, then a small line-break run sets the title/body gap, then the
        // body runs; a left accent stripe is a per-cell LeftBorder over the cell's full border.
        private const double CalloutPadX = 12;      // client infoBox/alertBox padding (horizontal)
        private const double CalloutPadY = 12;      // client infoBox/alertBox padding (vertical)
        private const double CellAscent = 0.74;     // a table cell's first baseline under its padding, x the table font size
        private const double CardCornerRadius = 6; // rounded corners on callout boxes and stat cards (client border-radius)
        private const double CalloutGap = 12;    // space after an InfoBox/ClearBox (client infoBox marginBottom 12)
        private const double AlertGap = 16;      // space after an AlertBox (client alertBox marginBottom 16)
        private const double SectionGap = 12;    // space before a new section's heading (client section marginBottom 12)

        private static PdfTextRun Run(string text, string colour, double size, bool bold = false, bool italic = false, bool underline = false, bool strike = false)
            => new(San(text), bold, underline, Pdf(colour), italic, strike, size);

        // The brand tint for the three report emoji when they fall back to the monochrome font (no colour
        // image bundled); every other emoji renders untinted. Null for anything that is not a report emoji.
        public static string? EmojiTint(int cp) =>
            cp == ReportMarkdown.EmojiWarning ? "#DD9B26" :   // amber
            cp == ReportMarkdown.EmojiCheck ? "#2F9E44" :     // green
            cp == ReportMarkdown.EmojiInfo ? "#3182CE" :      // blue
            null;

        // An emoji renders at the run's font size, dropped a touch below the baseline so it sits like a glyph.
        private const double EmojiBaselineFactor = -0.12;
        private static double EmojiOffset(double size) => size * EmojiBaselineFactor;

        private enum EmojiSegKind { Text, Image, Mono }
        private readonly struct EmojiSegment
        {
            public EmojiSegKind Kind { get; init; }
            public string Text { get; init; }    // Text: the copy; Image: alt text; Mono: the glyph
            public byte[]? Image { get; init; }   // Image: the colour PNG bytes
            public string? Tint { get; init; }    // Mono: brand tint hex, or null
        }

        // Split (already-sanitized) text into text / colour-image / monochrome-glyph segments. An emoji
        // grapheme cluster (including a multi-code-point ZWJ sequence, flag or skin-tone) routes to a bundled
        // Twemoji colour image when one exists, else to the monochrome fallback font (tinted for the three
        // report emoji); everything else stays as text, so ordinary copy is untouched.
        private static IEnumerable<EmojiSegment> SegmentEmoji(string text)
        {
            var list = new List<EmojiSegment>();
            // Most copy has no character above U+00FF, so no emoji: one text segment, without walking it
            // cluster by cluster (a string per character).
            if (!text.AsSpan().ContainsAnyExceptInRange('\0', 'ÿ'))
            {
                if (text.Length > 0) list.Add(new EmojiSegment { Kind = EmojiSegKind.Text, Text = text });
                return list;
            }
            var sb = new System.Text.StringBuilder();
            void FlushText() { if (sb.Length > 0) { list.Add(new EmojiSegment { Kind = EmojiSegKind.Text, Text = sb.ToString() }); sb.Clear(); } }
            var e = System.Globalization.StringInfo.GetTextElementEnumerator(text);
            while (e.MoveNext())
            {
                var cluster = (string)e.Current;
                if (cluster.Length == 1 && cluster[0] <= 'ÿ') { sb.Append(cluster); continue; }
                var bytes = TwemojiAssets.Enabled ? TwemojiAssets.Bytes(cluster) : null;
                if (bytes is not null) { FlushText(); list.Add(new EmojiSegment { Kind = EmojiSegKind.Image, Image = bytes, Text = cluster }); continue; }
                if (cluster.Length <= 2 && ReportMarkdown.RenderEmojiGlyphs)
                {
                    var cp = char.ConvertToUtf32(cluster, 0);
                    if (ReportMarkdown.EmojiCoverage.Contains(cp) || EmojiTint(cp) is not null)
                    { FlushText(); list.Add(new EmojiSegment { Kind = EmojiSegKind.Mono, Text = cluster, Tint = EmojiTint(cp) }); continue; }
                }
                sb.Append(cluster);
            }
            FlushText();
            return list;
        }

        // Emit text as OfficeIMO runs for table-cell content (callouts): each emoji becomes an inline colour-
        // image run (or a monochrome glyph run when no image is bundled), the rest keeps the given colour and
        // marks. A monochrome glyph carries no weight or decoration of its own, so it is emitted plain.
        private static void EmitRuns(List<PdfTextRun> dest, string text, string colour, double size,
            bool bold = false, bool italic = false, bool underline = false, bool strike = false,
            double? emojiSize = null, double? emojiOffset = null)
        {
            // An emoji image defaults to the run's font size, but a caller can shrink it and set its baseline
            // offset (the stat card's big number sizes the emoji to ~the digit height and drops it onto the
            // number's cap box, so it doesn't raise the line's ascent and push the number below a sibling card
            // whose number has no emoji).
            var es = emojiSize ?? size;
            var eo = emojiOffset ?? EmojiOffset(es);
            foreach (var seg in SegmentEmoji(San(text)))
            {
                switch (seg.Kind)
                {
                    case EmojiSegKind.Image:
                        dest.Add(PdfTextRun.Inline(new PdfInlineImage(seg.Image!, es, es, seg.Text, OfficeImageFit.Contain, eo)));
                        break;
                    case EmojiSegKind.Mono:
                        dest.Add(new PdfTextRun(seg.Text, false, false, Pdf(seg.Tint ?? colour), false, false, size));
                        break;
                    default:
                        dest.Add(new PdfTextRun(seg.Text, bold, underline, Pdf(colour), italic, strike, size));
                        break;
                }
            }
        }

        // A table cell whose text renders emoji as inline colour images (via EmitRuns) at the given colour
        // and weight, so a body cell like "ok ✅" shows a colour glyph rather than a monochrome one.
        private static PdfTableCell CellRuns(string text, string colour, bool bold = false, bool italic = false, double? size = null)
        {
            var runs = new List<PdfTextRun>();
            EmitRuns(runs, text, colour, size ?? ReportStyles.TableCell, bold, italic);
            return new PdfTableCell(runs);
        }

        // Emit inline text (with colour-image emoji) into a paragraph builder. For callers that compose on a
        // builder outside the component kit - the page header title/subtitle in ReportPdf.
        public static void EmitInline(PdfParagraphBuilder b, string text, string colour, double size, bool bold = false)
            => EmitToBuilder(b, San(text), colour, size, bold);

        // Convert parsed inline runs to OfficeIMO runs at a callout's size/colour, marks carried through,
        // with kept emoji split into their own tinted runs.
        private static IEnumerable<PdfTextRun> ToPdfRuns(IEnumerable<TextRun> runs, string colour, double size)
        {
            var dest = new List<PdfTextRun>();
            foreach (var r in runs) EmitRuns(dest, r.Text, colour, size, r.Bold, r.Italic, r.Underline, r.Strike);
            return dest;
        }

        // A callout body flattened to one run list: each logical line separated by a line-break run, so the
        // cell renders it as tight consecutive lines. `lines` keeps the source '\n' splits (label/value
        // detail lists); otherwise the markdown blocks are flattened (paragraphs, and bullets as "- " lines).
        private static List<PdfTextRun> CalloutBodyRuns(ReportContext ctx, string content, bool lines, double size, string colour)
        {
            var outRuns = new List<PdfTextRun>();
            void AddLine(IEnumerable<PdfTextRun> lineRuns)
            {
                if (outRuns.Count > 0) outRuns.Add(Run("\n", colour, size));
                outRuns.AddRange(lineRuns);
            }
            if (lines)
            {
                foreach (var ln in San(content).Replace("\r\n", "\n").Split('\n'))
                    AddLine(ToPdfRuns(ReportMarkdown.MarkdownRuns(ln), colour, size));
            }
            else
            {
                foreach (var node in ReportMarkdown.MarkdownToNodes(content))
                {
                    switch (node.Type)
                    {
                        case "paragraph":
                            AddLine(ToPdfRuns(node.Get<List<TextRun>>("runs") ?? new List<TextRun>(), colour, size));
                            break;
                        case "bullets":
                            foreach (var s in StringItems(node)) AddLine(new[] { Run("•  " + s, colour, size) });
                            break;
                        case "numbered":
                            var n = (int)(node.Num("start") ?? 1);
                            foreach (var s in StringItems(node)) AddLine(new[] { Run($"{n++}.  " + s, colour, size) });
                            break;
                        default:
                            var t = node.Str("content") ?? node.Str("text");
                            if (!string.IsNullOrEmpty(t)) AddLine(ToPdfRuns(ReportMarkdown.MarkdownRuns(t), colour, size));
                            break;
                    }
                }
            }
            if (outRuns.Count == 0) outRuns.Add(Run(" ", colour, size));
            return outRuns;
        }

        // The callout as stacked table rows: a title row (with its own bottom margin) over a body row (with
        // a tight body line height), or a single body row when untitled. One bordered cell stack lets the
        // title/body gap and the body line spacing each be set exactly - a single cell forces one uniform
        // line advance (the title can't get its own margin), and a panel's leading can't be set at all.
        private static List<PdfTableCell[]> CalloutRows(string? title, string titleColour, double titleSize, List<PdfTextRun> bodyRuns, double bodySize)
        {
            // One cell, one row: a multi-row table always draws a divider between rows (OfficeIMO borders are
            // a grid), so title and body live in the same cell. A cell line is as tall as its largest run at
            // the style's 1.4 leading and every line's baseline sits at the same depth in it, so the title
            // line is sized to the client's baseline-to-baseline step from the title to the body: the title's
            // 14pt page line plus its 6pt marginBottom, less the 0.9x-size baseline difference of the two.
            // (A bare line break carries no size, so a no-break space at that size ends the title line.)
            var runs = new List<PdfTextRun>();
            if (!string.IsNullOrEmpty(title))
            {
                EmitRuns(runs, title!, titleColour, titleSize, bold: true);
                runs.Add(Run("\u00A0", titleColour, (14 + 6 - 0.9 * (titleSize - bodySize)) / 1.4));
                runs.Add(Run("\n", titleColour, bodySize));
            }
            runs.AddRange(bodyRuns);
            return new List<PdfTableCell[]> { new[] { new PdfTableCell(runs) } };
        }

        private static PdfTableStyle CalloutStyle(string bgHex, string? stripeHex, double stripeWidth, string borderHex, double borderWidth, double bodySize, double firstSize)
        {
            // The client pads 12 inside the border (the stripe, on the left) and sets a line's baseline 0.9x its
            // size under the line top; OfficeIMO sets a cell's first baseline CellAscent x the table's font size
            // under its padding, and ends the cell that much above the last line's foot. The top and bottom
            // pads carry the difference, so every line lands where the client's does.
            var padding = new PdfCellPadding
            {
                Left = CalloutPadX + (stripeHex is null ? borderWidth : stripeWidth),
                Right = CalloutPadX + borderWidth,
                Top = CalloutPadY + borderWidth + 0.9 * firstSize - CellAscent * bodySize,
                Bottom = CalloutPadY + borderWidth - (0.9 - CellAscent) * bodySize,
            };
            // Single cell -> the table's BorderWidth draws just the perimeter box (no interior grid). The left
            // edge is overridden with the accent stripe via a per-cell LeftBorder when the callout has one.
            var style = new PdfTableStyle
            {
                HeaderRowCount = 0,
                FontSize = bodySize,
                LineHeight = 1.4,
                BorderColor = Pdf(borderHex),
                BorderWidth = borderWidth,
                CornerRadius = CardCornerRadius,  // softly rounded box; stripe/border are clipped to the rounded corners
                RowSeparatorWidth = 0,
                CellPaddingX = CalloutPadX,
                CellPaddingY = CalloutPadY,
                CellPaddings = new Dictionary<(int, int), PdfCellPadding>
                {
                    [(0, 0)] = padding,
                },
                SpacingAfter = 0,                 // the gap after a callout is an explicit Spacer, not the table's
                KeepTogether = true,              // a callout never splits across a page (client keeps each whole)
                CellFills = new Dictionary<(int, int), PdfColor> { [(0, 0)] = Pdf(bgHex) },
            };
            if (stripeHex is not null)
                style.CellBorders = new Dictionary<(int, int), PdfCellBorder>
                {
                    // only the left stripe; disable the class-default grey sides so 3.4.x's general
                    // cell-border renderer doesn't lay grey over the accent at the rounded corners.
                    [(0, 0)] = new PdfCellBorder { LeftBorder = new PdfCellBorderSide { Color = Pdf(stripeHex), Width = stripeWidth }, Top = false, Right = false, Bottom = false },
                };
            return style;
        }

        /// <summary>
        /// A titled note with an accent stripe down its left edge (client InfoBox). `tone` (ok/warn) tints
        /// the background and title; `colour` recolours the stripe (and the title when tintTitle). `content`
        /// is markdown, or line-broken label/value text when `lines`.
        /// </summary>
        public static void InfoBox(ReportContext ctx, PdfContentBuilder item, string? title, string? tone,
            string? colour, bool tintTitle, string content, bool lines = false)
        {
            var (accent, bg, titleColour) = InfoBoxColours(ctx, tone, colour, tintTitle);
            var body = CalloutBodyRuns(ctx, content, lines, ReportStyles.InfoText, ctx.Theme.Palette["subtitle"]);
            item.Table(CalloutRows(title, titleColour, ReportStyles.InfoTitle, body, ReportStyles.InfoText), PdfAlign.Left,
                CalloutStyle(bg, accent, 4, ReportColours.Line, 1, ReportStyles.InfoText, string.IsNullOrEmpty(title) ? ReportStyles.InfoText : ReportStyles.InfoTitle));
            item.Spacer(CalloutGap);
        }

        // An InfoBox's stripe accent, background tint and title colour: `tone` (ok/warn) picks the tint,
        // `colour` overrides the stripe (and the title when tintTitle).
        private static (string accent, string bg, string title) InfoBoxColours(ReportContext ctx, string? tone, string? colour, bool tintTitle)
        {
            var accent = string.IsNullOrEmpty(colour) ? ctx.Theme.Palette["card"] : colour!;
            var (bg, title) = tone switch
            {
                "ok" => (ReportColours.OkBg, ReportColours.Success),
                "warn" => (ReportColours.WarnBg, ReportColours.Warning),
                _ => (ReportColours.Panel, ctx.Theme.Palette["body"]),
            };
            if (tintTitle && !string.IsNullOrEmpty(colour)) title = colour!;
            return (accent, bg, title);
        }

        /// <summary>A warning callout: red-tinted background with a full accent-coloured border (client AlertBox).</summary>
        public static void AlertBox(ReportContext ctx, PdfContentBuilder item, string? title, string? colour, string content, bool lines = false)
        {
            var accent = string.IsNullOrEmpty(colour) ? ctx.Theme.Palette["card"] : colour!;
            var body = CalloutBodyRuns(ctx, content, lines, ReportStyles.AlertText, ctx.Theme.Palette["body"]);
            item.Table(CalloutRows(title, accent, ReportStyles.AlertTitle, body, ReportStyles.AlertText), PdfAlign.Left,
                CalloutStyle(ReportColours.AlertBg, null, 0, accent, 2, ReportStyles.AlertText, string.IsNullOrEmpty(title) ? ReportStyles.AlertText : ReportStyles.AlertTitle));
            item.Spacer(AlertGap);
        }

        /// <summary>The all-clear counterpart to AlertBox - a green InfoBox for a check that found nothing.</summary>
        public static void ClearBox(ReportContext ctx, PdfContentBuilder item, string? title, string content, bool lines = false)
            => InfoBox(ctx, item, title, "ok", null, false, content, lines);

        // Body copy stepped in under a heading (client Paragraph indent: marginLeft 12, marginTop 8). Used
        // for the BEC summary lines that introduce a check's detail callouts.
        public static void IndentedParagraph(ReportContext ctx, PdfContentBuilder item, string text)
        {
            item.Spacer(4);
            var body = ctx.Theme.Palette["body"];
            item.Paragraph(b => { b.FontSize(ReportStyles.Body); EmitToBuilder(b, San(text), body, ReportStyles.Body); },
                PdfAlign.Left, null, new PdfParagraphStyle { LeftIndent = 12, LineHeight = 1.3, SpacingAfter = 0 });
        }

        // Write text into a paragraph builder: emoji as inline colour images (or a monochrome glyph), the
        // rest as coloured text - the paragraph equivalent of EmitRuns, for contexts that compose directly
        // on a PdfParagraphBuilder.
        private static void EmitToBuilder(PdfParagraphBuilder b, string text, string colour, double size, bool bold = false)
        {
            foreach (var seg in SegmentEmoji(text))
            {
                switch (seg.Kind)
                {
                    case EmojiSegKind.Image:
                        b.InlineImage(seg.Image!, size, size, seg.Text, OfficeImageFit.Contain, EmojiOffset(size));
                        break;
                    case EmojiSegKind.Mono:
                        b.Bold(false).Color(Pdf(seg.Tint ?? colour)).Text(seg.Text);
                        break;
                    default:
                        b.Bold(bold).Color(Pdf(colour)).Text(seg.Text);
                        break;
                }
            }
        }

        /// <summary>
        /// A grid of InfoBoxes laid out `cols` per row (client `Columns` of callouts, e.g. the Shadow AI
        /// risk-level pairs). Each item is a node with title/content/tone/colour/tintTitle. Short final rows
        /// are padded so columns keep their width.
        /// </summary>
        public static void InfoBoxColumns(ReportContext ctx, PdfContentBuilder item, List<object?> items, int cols)
        {
            if (items.Count == 0) return;
            if (cols < 1) cols = 1;
            var width = 100.0 / cols;
            for (var start = 0; start < items.Count; start += cols)
            {
                var slice = items.Skip(start).Take(cols).ToList();
                item.Row(r =>
                {
                    r.Gap(10);
                    foreach (var node in slice)
                        r.PercentColumn(width, col => InfoBoxCol(ctx, col,
                            ReportNode.RowStr(node, "title"), ReportNode.RowStr(node, "tone"),
                            ReportNode.RowStr(node, "colour"), RowBool(node, "tintTitle"),
                            ReportNode.RowStr(node, "content") ?? string.Empty));
                    for (var k = slice.Count; k < cols; k++) r.PercentColumn(width, _ => { });
                });
                item.Spacer(CalloutGap);
            }
        }

        // One InfoBox rendered inside a row column, as the same single-cell table used full width.
        private static void InfoBoxCol(ReportContext ctx, PdfContentBuilder col, string? title, string? tone,
            string? colour, bool tintTitle, string content)
        {
            var (accent, bg, titleColour) = InfoBoxColours(ctx, tone, colour, tintTitle);
            var body = CalloutBodyRuns(ctx, content, false, ReportStyles.InfoText, ctx.Theme.Palette["subtitle"]);
            col.Table(CalloutRows(title, titleColour, ReportStyles.InfoTitle, body, ReportStyles.InfoText), PdfAlign.Left,
                CalloutStyle(bg, accent, 4, ReportColours.Line, 1, ReportStyles.InfoText, string.IsNullOrEmpty(title) ? ReportStyles.InfoText : ReportStyles.InfoTitle));
        }

        // Series colour for a chart entry: its own colour, else the theme series cycled by index.
        private static string SeriesColour(ReportContext ctx, string? own, int index)
        {
            if (!string.IsNullOrEmpty(own)) return own;
            var s = ctx.Theme.Series;
            return s.Count > 0 ? s[index % s.Count] : ctx.Theme.Palette["chart"];
        }

        // A row of stat cards. Each card is a single-column table inside its own row column, because a
        // panel inside a row column left-aligns its text regardless of alignment, whereas a table cell
        // honours Alignments.Center - so the number and label sit centred like the client statCard. The
        // gaps between cards come from the row gap; the brand accent is the card's top border.
        public static void StatRow(ReportContext ctx, PdfContentBuilder item, List<object?> stats)
        {
            if (stats.Count == 0) return;
            var accent = ctx.Theme.Palette["card"];
            var width = 100.0 / stats.Count; // column widths are percentages and must sum to ~100
            // The number's room: the card's share of the row, less its side pads and a point of slack.
            var valueWidth = (ctx.ContentWidth - StatGap * (stats.Count - 1)) / stats.Count - 2 * StatPadX - 1;
            // Each card is its own single-cell table, so a caption or a wrapped label makes only that card
            // taller. The client's statsGrid stretches every card to the tallest, so each card's lines under
            // the figure are measured (14pt label lines, then a caption 4pt under them on 14pt lines) and a
            // shorter card makes up the difference in its bottom padding.
            // ponytail: a caption card's label is measured without the 4pt strut that ends it, so a label
            // within ~5pt of the card width can wrap unpredicted; measure the strut in if that shows up.
            var textHeights = stats.Select(s =>
            {
                var label = San((ReportNode.RowStr(s, "label") ?? string.Empty).ToUpperInvariant());
                var caption = ReportNode.RowStr(s, "caption");
                var h = StatLine * WrappedLines(label, valueWidth, ReportStyles.StatLabel, bold: true);
                return string.IsNullOrEmpty(caption) ? h : h + 4 + StatLine * WrappedLines(San(caption), valueWidth, ReportStyles.StatCaption, bold: false);
            }).ToList();
            var tallest = textHeights.Max();
            item.Row(r =>
            {
                r.Gap(StatGap);
                for (var i = 0; i < stats.Count; i++)
                {
                    var s = stats[i];
                    var value = ReportNode.RowStr(s, "value") ?? string.Empty;
                    var label = (ReportNode.RowStr(s, "label") ?? string.Empty).ToUpperInvariant();
                    var caption = ReportNode.RowStr(s, "caption");
                    var colour = ReportNode.RowStr(s, "colour") ?? accent;
                    var stretch = tallest - textHeights[i];
                    r.PercentColumn(width, col => StatCard(ctx, col, value, label, caption, colour, accent, stretch, valueWidth));
                }
            });
            item.Spacer(14);                           // client statsGrid marginBottom
        }

        private const double StatGap = 10, StatPadX = 6;

        // Client statCard: the figure on a 23pt line (20pt at lineHeight 1.15) with 7pt under it, then the 7pt
        // label and any caption on the page's 14pt lines. A cell line is its largest run x LineHeight but never
        // under the table's size x LineHeight, so StatLeading makes the figure's line the client's step from
        // the figure's baseline to the label's, and a table size of StatLine / StatLeading makes every other
        // line (a label, a wrapped label line, a caption) the 14pt page line.
        private const double StatLine = 14;
        private const double StatLeading = (ReportStyles.StatNumber * 1.15 + 7 + 0.9 * (ReportStyles.StatLabel - ReportStyles.StatNumber)) / ReportStyles.StatNumber;

        // Helvetica and Helvetica-Bold advance widths (per 1000 em) for the WinAnsi code points ' '..U+00FF, the
        // metrics OfficeIMO lays the standard font out with (the oblique faces share them): ASCII, then 0x7F-0x9F
        // (the cp1252 specials, which TextEm reaches through WinAnsiSpecials), then Latin-1. The accented
        // capitals are as wide as their base letters (up to 778), so pricing them at a flat 556 let a cover line
        // be packed past its box and cut off mid-word. Anything outside WinAnsi still counts as a digit-wide 556.
        private static readonly int[] HelveticaWidths =
        {
            278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556,
            556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778,
            722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278,
            278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
            556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
            556, 556, 556, 222, 556, 333, 1000, 556, 556, 333, 1000, 667, 333, 1000, 556, 611, 556, 556, 222, 222,
            333, 333, 350, 556, 1000, 333, 1000, 500, 333, 944, 556, 500, 667, 278, 333, 556, 556, 556, 556, 260,
            556, 333, 737, 370, 556, 584, 333, 737, 333, 400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365,
            556, 834, 834, 834, 611, 667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278,
            278, 722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611, 556, 556, 556,
            556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278, 556, 556, 556, 556, 556, 556, 556,
            584, 611, 556, 556, 556, 556, 500, 556, 500,
        };
        private static readonly int[] HelveticaBoldWidths =
        {
            278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556,
            556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611, 975, 722, 722, 722, 722, 667, 611, 778,
            722, 278, 556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333,
            278, 333, 584, 556, 333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
            611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584,
            556, 556, 556, 278, 556, 500, 1000, 556, 556, 333, 1000, 667, 333, 1000, 556, 611, 556, 556, 278, 278,
            500, 500, 350, 556, 1000, 333, 1000, 556, 333, 944, 556, 500, 667, 278, 333, 556, 556, 556, 556, 280,
            556, 333, 737, 370, 556, 584, 333, 737, 333, 400, 584, 333, 333, 333, 611, 556, 278, 333, 333, 365,
            556, 834, 834, 834, 611, 722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 278, 278, 278,
            278, 722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611, 556, 556, 556,
            556, 556, 556, 889, 556, 556, 556, 556, 556, 278, 278, 278, 278, 611, 611, 611, 611, 611, 611, 611,
            584, 611, 611, 611, 611, 611, 556, 611, 556,
        };

        // What cp1252 puts at 0x80..0x9F (its five unassigned bytes kept as themselves), so a curly quote, dash
        // or bullet finds its WinAnsi width.
        private const string WinAnsiSpecials = "\u20AC\u0081\u201A\u0192\u201E\u2026\u2020\u2021\u02C6\u2030\u0160\u2039\u0152\u008D\u017D\u008F\u0090\u2018\u2019\u201C\u201D\u2022\u2013\u2014\u02DC\u2122\u0161\u203A\u0153\u009D\u017E\u0178";

        // A character's code in WinAnsi, the standard fonts' encoding (the cp1252 specials at 0x80..0x9F, anything
        // else its Latin-1 byte), or -1 when WinAnsi has no code for it.
        internal static int WinAnsiCode(char ch)
        {
            var special = WinAnsiSpecials.IndexOf(ch);
            return special >= 0 ? 0x80 + special : ch <= 0xFF ? ch : -1;
        }

        // A run of text's advance in em.
        internal static double TextEm(string s, bool bold)
        {
            var widths = bold ? HelveticaBoldWidths : HelveticaWidths;
            return s.Sum(ch =>
            {
                var special = WinAnsiSpecials.IndexOf(ch);
                var code = special >= 0 ? 0x80 + special : ch;
                return (code >= ' ' && code <= 0xFF ? widths[code - ' '] : 556) / 1000.0;
            });
        }

        // How many lines `text` takes in a column `width` points wide: each '\n' line word-wrapped greedily,
        // a word wider than the column broken across as many lines as it fills.
        internal static int WrappedLines(string text, double width, double size, bool bold)
        {
            var lines = 0;
            var space = 0.278 * size;
            foreach (var line in text.Replace("\r", "").Split('\n'))
            {
                lines++;
                var x = 0.0;
                foreach (var word in line.Split(' '))
                {
                    var w = TextEm(word, bold) * size;
                    if (x > 0 && x + space + w > width) { lines++; x = 0; }
                    else if (x > 0) x += space;
                    var extra = Math.Max(0, (int)Math.Ceiling(w / width) - 1);
                    lines += extra;
                    x += w - extra * width;
                }
            }
            return lines;
        }

        // `text` broken into the lines WrappedLines counts: greedy word wrap, with a word wider than the
        // column cut where it fills a line (never inside a surrogate pair). `tracking` is the client's
        // letterSpacing, which react-pdf adds after every character when it decides where a line breaks.
        internal static List<string> WrapLines(string text, double width, double size, bool bold, double tracking = 0)
        {
            var lines = new List<string>();
            double Em(string s) => TextEm(s, bold) * size + tracking * s.Length;
            foreach (var para in text.Replace("\r", "").Split('\n'))
            {
                var line = string.Empty;
                foreach (var word in para.Split(' '))
                {
                    if (line.Length > 0 && Em(line + " " + word) > width) { lines.Add(line); line = string.Empty; }
                    var rest = line.Length > 0 ? line + " " + word : word;
                    while (Em(rest) > width && rest.Length > 1)
                    {
                        var n = rest.Length - 1;
                        while (n > 1 && Em(rest[..n]) > width) n--;
                        if (char.IsHighSurrogate(rest[n - 1]) && n > 1) n--;
                        lines.Add(rest[..n]);
                        rest = rest[n..];
                    }
                    line = rest;
                }
                lines.Add(line);
            }
            return lines;
        }

        // The stat number's font size: 20pt, or smaller when the figure would not fit its card on one line.
        // The client lets a long figure run into the card's padding; the kit would break it inside the
        // digits ("SEK 105,62" / "6"), so it scales the figure down to fit instead. A shrunk figure keeps
        // one 20pt space (StatCard's strut), so that space is left out of the scaling. An emoji is 0.55em.
        private const double SpaceEm = 0.278;
        private static double StatValueSize(string value, double maxWidth)
        {
            var em = 0.0;
            foreach (var seg in SegmentEmoji(San(value)))
                em += seg.Kind == EmojiSegKind.Text ? TextEm(seg.Text, bold: true) : 0.55;
            if (em * ReportStyles.StatNumber <= maxWidth) return ReportStyles.StatNumber;
            var scaled = StatStrutAt(value) >= 0 ? em - SpaceEm : em;
            return Math.Max(ReportStyles.StatLabel, (maxWidth - SpaceEm * ReportStyles.StatNumber) / scaled);
        }

        // Where a shrunk figure's 20pt strut goes: its first space ("KRW 13,580,460"), else -1 (appended).
        private static int StatStrutAt(string value) => value.IndexOfAny(new[] { ' ', '\u00A0' });

        private static void StatCard(ReportContext ctx, PdfContentBuilder col, string value, string label, string? caption, string colour, string accent, double stretch = 0, double valueWidth = double.MaxValue)
        {
            // One cell, the number over the label as separate runs split by a line break, so there is no
            // internal row divider - just the outer card border and its brand top accent.
            var runs = new List<PdfTextRun>();
            // Size a number-adjacent emoji to ~the digit height and seat it on the digit cap box, so it does
            // not raise the line's ascent - otherwise the number rides lower than a sibling card with no emoji
            // (proportions measured for alignment: emoji ~0.55x the number, dropped ~0.18x onto the baseline).
            // A figure too wide for the card shrinks. One of its spaces stays 20pt as a strut: OfficeIMO sizes
            // a line by its text runs, so the strut keeps the 20pt line - the card keeps its height, the label
            // stays level with the sibling cards' and the figure sits on their baseline. A figure with no
            // space gets the strut after it.
            var size = StatValueSize(value, valueWidth);
            if (size < ReportStyles.StatNumber)
            {
                var at = StatStrutAt(value);
                var head = at < 0 ? value : value[..at];
                EmitRuns(runs, head, colour, size, bold: true, emojiSize: size * 0.55, emojiOffset: size * -0.18);
                runs.Add(new PdfTextRun("\u00A0", true, false, Pdf(colour), false, false, ReportStyles.StatNumber));
                if (at >= 0) EmitRuns(runs, value[(at + 1)..], colour, size, bold: true, emojiSize: size * 0.55, emojiOffset: size * -0.18);
            }
            else
            {
                EmitRuns(runs, value, colour, size, bold: true, emojiSize: size * 0.55, emojiOffset: size * -0.18);
            }
            runs.Add(Run("\n", colour, ReportStyles.StatNumber));
            EmitRuns(runs, label, ReportColours.Muted, ReportStyles.StatLabel, bold: true);
            // A caption sits 4pt under the label's 14pt line: a no-break space that tall ends the label line.
            if (!string.IsNullOrEmpty(caption))
            {
                runs.Add(new PdfTextRun("\u00A0", true, false, Pdf(ReportColours.Muted), false, false, (StatLine + 4) / StatLeading));
                runs.Add(Run("\n", ctx.Theme.Palette["subtitle"], ReportStyles.StatCaption));
                EmitRuns(runs, caption!, ctx.Theme.Palette["subtitle"], ReportStyles.StatCaption);
            }
            var rows = new List<PdfTableCell[]> { new[] { new PdfTableCell(runs) } };
            var style = new PdfTableStyle
            {
                HeaderRowCount = 0,
                FontSize = StatLine / StatLeading,
                LineHeight = StatLeading,
                BorderColor = Pdf(ReportColours.Line),
                BorderWidth = 1,
                CornerRadius = CardCornerRadius,  // softly rounded card; top accent bar is clipped to the rounded corners
                RowSeparatorWidth = 0,
                CellPaddingX = 6,
                CellPaddingY = 8,
                // The first baseline where the client's figure sits (3pt accent, 10pt padding, 0.9x the figure
                // size under its line top), and the card's foot 10pt of padding and the 1pt border under the
                // last 14pt line, stretched to the row's tallest card.
                CellPaddings = new Dictionary<(int, int), PdfCellPadding>
                {
                    [(0, 0)] = new PdfCellPadding
                    {
                        Left = StatPadX, Right = StatPadX,
                        Top = 3 + 10 + 0.9 * ReportStyles.StatNumber - CellAscent * StatLine / StatLeading,
                        Bottom = 10 + 1 - 0.9 * ReportStyles.StatLabel + CellAscent * StatLine / StatLeading + stretch,
                    },
                },
                Alignments = new List<PdfColumnAlign> { PdfColumnAlign.Center },
                CellFills = new Dictionary<(int, int), PdfColor> { [(0, 0)] = Pdf(ReportColours.White) },
                CellBorders = new Dictionary<(int, int), PdfCellBorder>
                {
                    // only the top accent bar; disable the class-default grey sides so 3.4.x's general
                    // cell-border renderer doesn't lay grey over the accent at the rounded corners.
                    [(0, 0)] = new PdfCellBorder { TopBorder = new PdfCellBorderSide { Color = Pdf(accent), Width = 3 }, Left = false, Right = false, Bottom = false },
                },
            };
            col.Table(rows, PdfAlign.Left, style);
        }

        // Labelled progress bars (client ProgressList): each item is its own bordered row box holding a
        // bold label, a data bar over a grey track, and a bold value. One 1-row table per item gives the
        // per-row border and lets the label/value be bold via cell runs; the row gap comes from a spacer.
        public static void Progress(ReportContext ctx, PdfContentBuilder item, List<object?> items)
        {
            if (items.Count == 0) return;
            for (var i = 0; i < items.Count; i++)
            {
                var it = items[i];
                var label = ReportNode.RowStr(it, "label") ?? string.Empty;
                var value = ReportNode.RowNum(it, "value");
                var max = ReportNode.RowNum(it, "max"); if (max <= 0) max = 100;
                var pct = Math.Max(0, Math.Min(1, value / max));
                var display = ReportNode.RowStr(it, "display");
                if (string.IsNullOrEmpty(display)) display = Math.Round(pct * 100) + "%";
                var colour = ReportNode.RowStr(it, "colour") ?? SeriesColour(ctx, null, i);
                var rows = new List<PdfTableCell[]>
                {
                    new[]
                    {
                        CellRuns(label, ctx.Theme.Palette["body"], bold: true),
                        new PdfTableCell(string.Empty),
                        CellRuns(display!, ReportColours.Body, bold: true),
                    },
                };
                var style = new PdfTableStyle
                {
                    HeaderRowCount = 0,
                    BorderColor = Pdf(ReportColours.Line),
                    BorderWidth = 1,
                    RowSeparatorWidth = 0,
                    CellPaddingX = 10,
                    CellPaddingY = 7,
                    ColumnWidthWeights = new List<double> { 28, 58, 14 },
                    Alignments = new List<PdfColumnAlign> { PdfColumnAlign.Left, PdfColumnAlign.Left, PdfColumnAlign.Right },
                    VerticalAlignments = new List<PdfCellVerticalAlign> { PdfCellVerticalAlign.Middle, PdfCellVerticalAlign.Middle, PdfCellVerticalAlign.Middle },
                    CellFills = new Dictionary<(int, int), PdfColor> { [(0, 1)] = Pdf(ReportColours.Line) },
                    CellDataBars = new Dictionary<(int, int), PdfCellDataBar> { [(0, 1)] = new PdfCellDataBar { Color = Pdf(colour), Ratio = pct, StartRatio = 0 } },
                };
                item.Table(rows, PdfAlign.Left, style);
                item.Spacer(6);
            }
        }

        // -- charts (vector) --
        // Real vector charts, ported 1:1 from the client charts.jsx which draws SVG into a 400x200 viewBox.
        // Built as an OfficeDrawing (a fixed-size composite that flows as one block and reserves its
        // height - unlike item.Canvas, which paints page-absolute and lets neighbours overlap it). The
        // drawing shares the SVG coordinate system (top-left origin, y down), so the geometry is copied
        // verbatim: the 400x200 plot is centred in a bordered white frame, title above, caption below.
        // Client chartContainer/chartCanvas: a 1pt border and 16pt padding round the title (10pt on the 14pt
        // page line, 12pt under it), the canvas and the 8pt under it, and a caption 8pt under that.
        private const double ChartViewW = 400, ChartViewH = 200, ChartCanvasGap = 8;
        private const double ChartTitleSize = 10, ChartLabelSize = 7, ChartCaptionSize = 8;

        internal static OfficeColor OC(string hex)
        {
            var (r, g, b) = ColourMath.ToRgb(hex);
            return OfficeColor.FromRgb((byte)r, (byte)g, (byte)b);
        }

        private static string FmtNum(double v)
            => v == Math.Floor(v) ? ((long)v).ToString(CultureInfo.InvariantCulture) : v.ToString("0.##", CultureInfo.InvariantCulture);

        // Positioned text into an OfficeDrawing at an explicit size/colour/alignment (AddText takes the
        // size via the font, so every label supplies a Helvetica OfficeFontInfo).
        private static void AddT(OfficeDrawing dw, string text, double x, double y, double w, double h,
            double size, string colourHex, OfficeTextAlignment align, bool bold = false, bool wrap = false, double? lineHeight = null)
            // The extended overload's wrapText makes a long block (the cover subtitle) fold inside its box
            // instead of overrunning the page; the short overload leaves WrapText off (read-only afterwards).
            // `lineHeight` is the line pitch in points (null: 1.2x the size).
            => dw.AddText(text, x, y, w, h,
                new OfficeFontInfo("Helvetica", size, bold ? OfficeFontStyle.Bold : OfficeFontStyle.Regular),
                OC(colourHex), align, lineHeight: lineHeight, wrapText: wrap);

        public static void Chart(ReportContext ctx, PdfContentBuilder item, string? kind, List<object?> data,
            string? title = null, string? caption = null, double? max = null, string? centreLabel = null,
            double? availableWidth = null)
        {
            var k = (kind ?? "bar").ToLowerInvariant();
            // A drawing exactly the content width is rejected as too wide; availableWidth lets a chart draw
            // inside a narrower column (half-width side-by-side charts) instead of the full page width.
            var w = (availableWidth ?? ctx.ContentWidth) - 2;
            const double border = 1, pad = 16, titleH = 14, titleGap = 12, captionGap = 8, captionH = ChartCaptionSize * 1.4;
            var hasTitle = !string.IsNullOrEmpty(title);
            var hasCaption = !string.IsNullOrEmpty(caption);
            var plotTop = border + pad + (hasTitle ? titleH + titleGap : 0);
            // The plot's own coordinate width: the 400pt design width, or the drawing if it is narrower
            // (a half-width chart), so the geometry scales down to fit rather than overflowing the frame.
            var vw = Math.Min(ChartViewW, w);
            var leftPad = Math.Max(0, (w - vw) / 2);

            var entries = data.Select((d, i) => (
                label: ReportNode.RowStr(d, "label") ?? string.Empty,
                value: ReportNode.RowNum(d, "value"),
                colour: SeriesColour(ctx, ReportNode.RowStr(d, "colour"), i))).ToList();

            // A donut grows past the 200pt canvas only when its legend packs into more rows than fit it.
            var viewH = k == "donut" && entries.Count > 0 ? DonutViewHeight(entries, vw) : ChartViewH;
            var captionTop = plotTop + viewH + ChartCanvasGap + captionGap;
            var totalH = (hasCaption ? captionTop + captionH : plotTop + viewH + ChartCanvasGap) + pad + border;

            var dw = new OfficeDrawing(w, totalH);
            var frame = OfficeShape.RoundedRectangle(w, totalH, 6);
            frame.FillColor = OC(ReportColours.White); frame.StrokeColor = OC(ReportColours.Line); frame.StrokeWidth = 1;
            dw.AddShape(frame, 0, 0);
            if (hasTitle)
                AddT(dw, San(title!), 0, border + pad, w, titleH, ChartTitleSize, ctx.Theme.Palette["body"], OfficeTextAlignment.Center, true);

            if (entries.Count == 0)
                AddT(dw, "No data available for this chart.", 0, plotTop + viewH / 2 - 6, w, 12, ReportStyles.Body, ReportColours.Faint, OfficeTextAlignment.Center);
            else if (k == "donut") DrawDonut(ctx, dw, entries, leftPad, plotTop, centreLabel, vw);
            else if (k == "trend") DrawTrend(ctx, dw, entries, leftPad, plotTop, max, vw);
            else DrawBar(ctx, dw, entries, leftPad, plotTop, vw);

            if (hasCaption)
                AddT(dw, San(caption!), 0, captionTop, w, captionH, ChartCaptionSize, ctx.Theme.Palette["chart"], OfficeTextAlignment.Center, true);

            item.Drawing(dw, PdfAlign.Left);
            item.Spacer(20);                           // client chartContainer marginBottom
        }

        /// <summary>A chart block flagged to render at half the page width (so two can sit side by side).</summary>
        public static bool IsHalfWidthChart(ReportNode block)
            => block.Type == "chart" && string.Equals(block.Str("width"), "half", StringComparison.OrdinalIgnoreCase);

        // Render a chart block, optionally into a given width (a half-width column). Shared by the block
        // dispatch (a lone half-width chart) and the side-by-side pair renderer.
        private static void ChartFromBlock(ReportContext ctx, PdfContentBuilder item, ReportNode block, double? availableWidth)
            => Chart(ctx, item, block.Str("chartKind"), block.ListOf("chartData") ?? new List<object?>(),
                block.Str("title"), block.Str("caption") ?? block.Str("chartCaption"),
                block.Num("max") ?? ParseNumber(block.Str("chartMax")), block.Str("centreLabel") ?? block.Str("chartCentreLabel"),
                availableWidth);

        /// <summary>Two half-width charts side by side in one row (the caller has checked both qualify).</summary>
        public static void RenderChartPair(ReportContext ctx, PdfContentBuilder item, ReportNode a, ReportNode b, bool firstOnPage)
        {
            const double gap = 16;
            var colWidth = (ctx.ContentWidth - gap) / 2;
            item.Row(r =>
            {
                r.Gap(gap);
                r.PercentColumn(50, col => ChartFromBlock(ctx, col, a, colWidth));
                r.PercentColumn(50, col => ChartFromBlock(ctx, col, b, colWidth));
            });
        }

        private static (double x, double y) Polar(double cx, double cy, double r, double deg)
            => (cx + r * Math.Cos(deg * Math.PI / 180), cy + r * Math.Sin(deg * Math.PI / 180));

        // Append cubic-bezier segments approximating a circular arc from a0 to a1 (radians) at radius r.
        // Assumes the current path point is already at a0. Handles either sweep direction via the sign of
        // (a1 - a0), splitting into <=90 degree segments (the standard 4/3*tan(dθ/4) control-point method).
        private static void ArcBeziers(List<OfficePathCommand> cmds, double cx, double cy, double r, double a0, double a1)
        {
            var segs = Math.Max(1, (int)Math.Ceiling(Math.Abs(a1 - a0) / (Math.PI / 2)));
            var d = (a1 - a0) / segs;
            var t = a0;
            for (var s = 0; s < segs; s++)
            {
                var t2 = t + d;
                var k = 4.0 / 3.0 * Math.Tan(d / 4);
                var x0 = cx + r * Math.Cos(t); var y0 = cy + r * Math.Sin(t);
                var x3 = cx + r * Math.Cos(t2); var y3 = cy + r * Math.Sin(t2);
                var c1x = x0 - k * r * Math.Sin(t); var c1y = y0 + k * r * Math.Cos(t);
                var c2x = x3 + k * r * Math.Sin(t2); var c2y = y3 - k * r * Math.Cos(t2);
                cmds.Add(OfficePathCommand.CubicBezierTo(c1x, c1y, c2x, c2y, x3, y3));
                t = t2;
            }
        }

        private static void DrawBar(ReportContext ctx, OfficeDrawing dw,
            List<(string label, double value, string colour)> entries, double ox, double oy, double viewW = ChartViewW)
        {
            const double plotLeft = 40, plotTop = 20, plotHeight = 130;
            var plotWidth = viewW - plotLeft - 20; // 340 at the full 400 design width
            const double plotBottom = plotTop + plotHeight;
            var maxValue = Math.Max(entries.Max(e => e.value), 0); if (maxValue <= 0) maxValue = 1;
            var slot = plotWidth / entries.Count;
            var barWidth = Math.Min(slot * 0.6, 46);

            // Lines are placed at their start point with endpoints relative to it (a shape's coordinates
            // are normalised to its own box, so absolute endpoints would collapse to the origin).
            var axis = OfficeShape.Line(0, 0, plotWidth, 0);
            axis.StrokeColor = OC(ReportColours.Line); axis.StrokeWidth = 1; dw.AddShape(axis, ox + plotLeft, oy + plotBottom);

            for (var i = 0; i < entries.Count; i++)
            {
                var e = entries[i];
                var height = Math.Max(e.value / maxValue * plotHeight, e.value > 0 ? 2 : 1);
                var x = plotLeft + i * slot + (slot - barWidth) / 2;
                var y = plotBottom - height;
                var barRadius = Math.Min(2, Math.Min(barWidth, height) / 2);
                var bar = OfficeShape.RoundedRectangle(barWidth, height, barRadius);
                bar.FillColor = OC(e.colour); dw.AddShape(bar, ox + x, oy + y);
                AddT(dw, FmtNum(e.value), ox + plotLeft + i * slot, oy + y - 11, slot, 9, ChartLabelSize, ctx.Theme.Palette["body"], OfficeTextAlignment.Center);
                var label = e.label.Length > 14 ? e.label.Substring(0, 13) + "…" : e.label;
                AddT(dw, San(label), ox + plotLeft + i * slot, oy + plotBottom + 5, slot, 9, ChartLabelSize, ReportColours.Muted, OfficeTextAlignment.Center);
            }
        }

        // Donut geometry in chart coords (the client's): the ring's centre and radius, and where the legend starts.
        private const double DonutCy = 85, DonutOuterR = 60, DonutInnerR = 25, DonutLegendY = 172, LegendRowH = 14;
        private const double LegendSwatch = 8, LegendSwatchGap = 4, LegendEntryGap = 18, LegendCharW = 3.6;

        // Legend entries packed into rows that fit the given width: they flow left to right and wrap when
        // the next entry would overrun, so a narrow (half-width) donut stacks its legend rather than
        // running its labels off the edge (which OfficeIMO rejects). Shared by the height reservation and
        // the drawing so both agree on the row count.
        private static List<List<(string label, double value, string colour)>> PackLegend(
            List<(string label, double value, string colour)> entries, double viewW)
        {
            var budget = Math.Max(60, viewW - 20);
            var rows = new List<List<(string label, double value, string colour)>>();
            var current = new List<(string label, double value, string colour)>();
            double used = 0;
            foreach (var e in entries)
            {
                var text = San($"{e.label} ({FmtNum(e.value)})");
                var entryW = LegendSwatch + LegendSwatchGap + text.Length * LegendCharW;
                var add = (current.Count == 0 ? 0 : LegendEntryGap) + entryW;
                if (current.Count > 0 && used + add > budget) { rows.Add(current); current = new List<(string, double, string)>(); used = 0; add = entryW; }
                current.Add(e); used += add;
            }
            if (current.Count > 0) rows.Add(current);
            return rows;
        }

        /// <summary>The height a donut needs: the client's 200pt canvas, which holds the ring and three legend
        /// rows (the third runs into the 8pt under it), and a row more for each legend row past that.</summary>
        private static double DonutViewHeight(List<(string label, double value, string colour)> entries, double viewW = ChartViewW)
        {
            var rows = Math.Max(1, PackLegend(entries.Where(e => e.value > 0).ToList(), viewW).Count);
            return Math.Max(ChartViewH, DonutLegendY + (rows - 1) * LegendRowH + 4 - ChartCanvasGap);
        }

        private static void DrawDonut(ReportContext ctx, OfficeDrawing dw,
            List<(string label, double value, string colour)> entries, double ox, double oy, string? centreLabel = null,
            double viewW = ChartViewW)
        {
            var visible = entries.Where(e => e.value > 0).ToList();
            var total = visible.Sum(e => e.value);
            var viewH = DonutViewHeight(entries, viewW);
            if (total <= 0)
            {
                AddT(dw, "No data available for this chart.", ox, oy + viewH / 2 - 6, viewW, 12, ReportStyles.Body, ReportColours.Faint, OfficeTextAlignment.Center);
                return;
            }
            // Local chart coords (0..viewW, 0..viewH); all slices share one path box placed at the chart
            // offset, so they align (a bare Path() normalises each to its own box and misplaces them).
            double cx = viewW / 2, cy = DonutCy, outerR = DonutOuterR, innerR = DonutInnerR;
            double preceding = 0;
            foreach (var e in visible)
            {
                var startAngle = -90 + preceding / total * 360;
                var angle = Math.Min(e.value / total * 360, 359.99);
                var endAngle = startAngle + angle;
                var os = Polar(cx, cy, outerR, startAngle);
                var ie = Polar(cx, cy, innerR, endAngle);
                var cmds = new List<OfficePathCommand> { OfficePathCommand.MoveTo(os.x, os.y) };
                ArcBeziers(cmds, cx, cy, outerR, startAngle * Math.PI / 180, endAngle * Math.PI / 180);
                cmds.Add(OfficePathCommand.LineTo(ie.x, ie.y));
                ArcBeziers(cmds, cx, cy, innerR, endAngle * Math.PI / 180, startAngle * Math.PI / 180);
                cmds.Add(OfficePathCommand.Close());
                var slice = OfficeShape.Path(viewW, viewH, cmds);
                slice.FillColor = OC(e.colour); slice.StrokeColor = OC(ReportColours.White); slice.StrokeWidth = 1;
                dw.AddShape(slice, ox, oy);
                preceding += e.value;
            }
            // Total in the middle, with an optional caption under it (client centreLabel): baselines 2pt above
            // and 10pt below the centre, a text box's baseline sitting its font size under its top.
            AddT(dw, FmtNum(total), ox + viewW / 2 - 40, oy + cy - 2 - 14, 80, 16, 14, ReportColours.Ink, OfficeTextAlignment.Center);
            if (!string.IsNullOrEmpty(centreLabel))
                AddT(dw, San(centreLabel!), ox + viewW / 2 - 40, oy + cy + 10 - 7, 80, 10, 7, ReportColours.Muted, OfficeTextAlignment.Center);
            DrawLegend(ctx, dw, visible, ox, oy, DonutLegendY, viewW);
        }

        private static void DrawLegend(ReportContext ctx, OfficeDrawing dw,
            List<(string label, double value, string colour)> entries, double ox, double oy, double baseY, double viewW = ChartViewW)
        {
            // Rows are packed to the width (see PackLegend), each centred; a text box is clamped to what
            // is left inside the drawing so a long label never runs past the edge.
            var packed = PackLegend(entries, viewW);
            for (var row = 0; row < packed.Count; row++)
            {
                var rowEntries = packed[row];
                var texts = rowEntries.Select(e => San($"{e.label} ({FmtNum(e.value)})")).ToList();
                var widths = texts.Select(t => LegendSwatch + LegendSwatchGap + t.Length * LegendCharW).ToList();
                var x = Math.Max(6, (viewW - (widths.Sum() + LegendEntryGap * (rowEntries.Count - 1))) / 2);
                var rowY = baseY + row * LegendRowH;
                for (var i = 0; i < rowEntries.Count; i++)
                {
                    var sw = OfficeShape.Rectangle(LegendSwatch, LegendSwatch); sw.FillColor = OC(rowEntries[i].colour); dw.AddShape(sw, ox + x, oy + rowY - 6);
                    var textX = x + LegendSwatch + LegendSwatchGap;
                    var textW = Math.Max(4, Math.Min(texts[i].Length * LegendCharW + 8, viewW - textX - 2));
                    AddT(dw, texts[i], ox + textX, oy + rowY - 6, textW, 10, ChartLabelSize, ctx.Theme.Palette["body"], OfficeTextAlignment.Left);
                    x += widths[i] + LegendEntryGap;
                }
            }
        }

        private static void DrawTrend(ReportContext ctx, OfficeDrawing dw,
            List<(string label, double value, string colour)> entries, double ox, double oy, double? max, double viewW = ChartViewW)
        {
            const double plotLeft = 40, plotTop = 20, plotHeight = 140;
            var plotWidth = viewW - plotLeft - 40; // 320 at the full 400 design width
            const double plotBottom = plotTop + plotHeight;
            var colour = ctx.Theme.Primary;
            var dataMax = Math.Max(entries.Max(e => e.value), 0);
            var scaleMax = max is > 0 ? max!.Value : dataMax > 0 ? dataMax : 1;
            var spacing = plotWidth / Math.Max(entries.Count - 1, 1);
            var pts = entries.Select((e, i) => (
                x: plotLeft + i * spacing,
                y: plotBottom - Math.Min(e.value / scaleMax, 1) * plotHeight)).ToList();

            var rect = OfficeShape.Rectangle(plotWidth, plotHeight);
            rect.FillColor = OC(ReportColours.Panel); rect.StrokeColor = OC(ReportColours.Line); rect.StrokeWidth = 1;
            dw.AddShape(rect, ox + plotLeft, oy + plotTop);
            for (var g = 0; g <= 4; g++)
            {
                var gy = plotTop + g * (plotHeight / 4);
                var gl = OfficeShape.Line(0, 0, plotWidth, 0);
                gl.StrokeColor = OC(ReportColours.Line); gl.StrokeWidth = 0.5; dw.AddShape(gl, ox + plotLeft, oy + gy);
            }
            if (pts.Count > 1)
            {
                // Local coords in a 400x200 box placed at the chart offset (see donut note).
                var area = new List<OfficePathCommand> { OfficePathCommand.MoveTo(pts[0].x, pts[0].y) };
                for (var i = 1; i < pts.Count; i++) area.Add(OfficePathCommand.LineTo(pts[i].x, pts[i].y));
                area.Add(OfficePathCommand.LineTo(pts[^1].x, plotBottom));
                area.Add(OfficePathCommand.LineTo(pts[0].x, plotBottom));
                area.Add(OfficePathCommand.Close());
                var areaShape = OfficeShape.Path(viewW, ChartViewH, area); areaShape.FillColor = OC(colour); areaShape.FillOpacity = 0.3; dw.AddShape(areaShape, ox, oy);

                var line = new List<OfficePathCommand> { OfficePathCommand.MoveTo(pts[0].x, pts[0].y) };
                for (var i = 1; i < pts.Count; i++) line.Add(OfficePathCommand.LineTo(pts[i].x, pts[i].y));
                var lineShape = OfficeShape.Path(viewW, ChartViewH, line); lineShape.StrokeColor = OC(colour); lineShape.StrokeWidth = 2; dw.AddShape(lineShape, ox, oy);
            }
            foreach (var p in pts)
            {
                var dot = OfficeShape.Ellipse(6, 6); dot.FillColor = OC(colour); dw.AddShape(dot, ox + p.x - 3, oy + p.y - 3);
            }
            var stride = (int)Math.Ceiling(entries.Count / 7.0);
            for (var i = 0; i < entries.Count; i++)
                if (i % stride == 0)
                    AddT(dw, San(entries[i].label), ox + pts[i].x - 20, oy + plotBottom + 8, 40, 9, ChartLabelSize, ReportColours.Muted, OfficeTextAlignment.Center);
            foreach (var frac in new[] { 0, 0.25, 0.5, 0.75, 1.0 })
                AddT(dw, FmtNum(Math.Round(scaleMax * frac)), ox, oy + plotBottom - frac * plotHeight - 4, plotLeft - 5, 9, ChartLabelSize, ReportColours.Muted, OfficeTextAlignment.Right);
        }

        // -- sankey (the dashboard CippSankey / nivo flow diagram) --
        // A sankey is a layered DAG: nodes fall into columns by the longest path from a source (a node is
        // one column right of everything that flows into it), a node's height is proportional to the flow
        // through it, and links are ribbons whose thickness carries the value. Same OfficeDrawing canvas as
        // the other charts (top-left origin, y down) so the geometry mirrors d3-sankey directly.
        private sealed class SankeyNode
        {
            public string Id = string.Empty;
            public string Label = string.Empty;
            public string Colour = string.Empty;
            public double Value;      // max(in, out)
            public int Depth;
            public double X, Y, H;    // laid-out position/size in plot coords
            public readonly List<SankeyLink> Out = new();
            public readonly List<SankeyLink> In = new();
        }

        private sealed class SankeyLink
        {
            public SankeyNode Src = null!;
            public SankeyNode Tgt = null!;
            public double Value, Width, Sy, Ty; // Sy/Ty = top edge of the ribbon at the source/target node
        }

        private const double SankeyNodeThickness = 12, SankeyNodeSpacing = 12, SankeyLabelGutter = 88;

        public static void Sankey(ReportContext ctx, PdfContentBuilder item, List<object?> nodes, List<object?> links,
            string? title = null, string? caption = null, double? height = null)
        {
            var w = ctx.ContentWidth - 2; // a drawing exactly the content width is rejected as too wide
            const double pad = 16, titleH = 14, titleGap = 12, captionGap = 8, captionH = 10;
            var hasTitle = !string.IsNullOrEmpty(title);
            var hasCaption = !string.IsNullOrEmpty(caption);
            var plotTop = pad + (hasTitle ? titleH + titleGap : 0);
            var plotH = height is > 0 ? height!.Value : 240;
            var totalH = plotTop + plotH + pad + (hasCaption ? captionGap + captionH : 0);

            var dw = new OfficeDrawing(w, totalH);
            var frame = OfficeShape.RoundedRectangle(w, totalH, 6);
            frame.FillColor = OC(ReportColours.White); frame.StrokeColor = OC(ReportColours.Line); frame.StrokeWidth = 1;
            dw.AddShape(frame, 0, 0);
            if (hasTitle)
                AddT(dw, San(title!), 0, pad, w, titleH, ChartTitleSize, ctx.Theme.Palette["body"], OfficeTextAlignment.Center, true);

            var model = BuildSankey(ctx, nodes, links, w - 2 * SankeyLabelGutter, plotH);
            if (model.Count == 0)
                AddT(dw, "No data available for this chart.", 0, plotTop + plotH / 2 - 6, w, 12, ReportStyles.Body, ReportColours.Faint, OfficeTextAlignment.Center);
            else
                DrawSankey(dw, model, SankeyLabelGutter, plotTop, w - 2 * SankeyLabelGutter, w, totalH);

            if (hasCaption)
                AddT(dw, San(caption!), 0, plotTop + plotH + captionGap, w, captionH, ChartLabelSize, ctx.Theme.Palette["chart"], OfficeTextAlignment.Center);

            item.Drawing(dw, PdfAlign.Left);
            item.Spacer(12);
        }

        // Read the nodes/links payload, assign columns, scale node heights to the plot, and relax the vertical
        // positions so linked nodes line up (fewer ribbon crossings). Returns the laid-out nodes, or empty when
        // there is nothing to draw.
        private static List<SankeyNode> BuildSankey(ReportContext ctx, List<object?> nodes, List<object?> links,
            double plotW, double plotH)
        {
            var byId = new Dictionary<string, SankeyNode>(StringComparer.Ordinal);
            SankeyNode NodeFor(string id) => byId.TryGetValue(id, out var n) ? n
                : byId[id] = new SankeyNode { Id = id, Label = id, Colour = ctx.Theme.Palette["chart"] };

            var order = 0;
            var sequence = new Dictionary<string, int>(StringComparer.Ordinal);
            foreach (var raw in nodes)
            {
                var id = ReportNode.RowStr(raw, "id");
                if (string.IsNullOrEmpty(id)) continue;
                var n = NodeFor(id!);
                n.Label = ReportNode.RowStr(raw, "label") ?? id!;
                var colour = ReportNode.RowStr(raw, "nodeColor") ?? ReportNode.RowStr(raw, "colour");
                if (!string.IsNullOrEmpty(colour)) n.Colour = colour!;
                if (!sequence.ContainsKey(id!)) sequence[id!] = order++;
            }
            foreach (var raw in links)
            {
                var s = ReportNode.RowStr(raw, "source"); var t = ReportNode.RowStr(raw, "target");
                var v = ReportNode.RowNum(raw, "value");
                if (string.IsNullOrEmpty(s) || string.IsNullOrEmpty(t) || v <= 0) continue;
                var src = NodeFor(s!); var tgt = NodeFor(t!);
                if (!sequence.ContainsKey(s!)) sequence[s!] = order++;
                if (!sequence.ContainsKey(t!)) sequence[t!] = order++;
                var link = new SankeyLink { Src = src, Tgt = tgt, Value = v };
                src.Out.Add(link); tgt.In.Add(link);
            }

            var all = byId.Values.Where(n => n.Out.Count > 0 || n.In.Count > 0).ToList();
            if (all.Count == 0) return all;
            foreach (var n in all) n.Value = Math.Max(n.Out.Sum(l => l.Value), n.In.Sum(l => l.Value));

            // Column (depth): longest path from a source, then leaf nodes (no outgoing link) are pushed to
            // the LAST column - this is nivo align="justify", which the dashboard uses. Terminal buckets
            // such as the auth-methods "Single factor" therefore land in the output column exactly as on
            // the dashboard; input-order stacking (below, nivo sort="input") keeps them at the top so their
            // ribbons run cleanly across rather than cutting through the middle stage.
            for (var i = 0; i < all.Count; i++)
                foreach (var n in all)
                    foreach (var l in n.Out)
                        if (l.Tgt.Depth < n.Depth + 1) l.Tgt.Depth = n.Depth + 1;
            var columnCount = all.Max(n => n.Depth) + 1;
            foreach (var n in all) if (n.Out.Count == 0) n.Depth = columnCount - 1;

            var columns = Enumerable.Range(0, columnCount)
                .Select(d => all.Where(n => n.Depth == d).OrderBy(n => sequence[n.Id]).ToList())
                .ToList();

            // One vertical scale across every column - the tightest column (most flow / most nodes) sets it, so
            // nothing overflows the plot. ky converts a value to points of height.
            var ky = double.PositiveInfinity;
            foreach (var col in columns)
            {
                var sum = col.Sum(n => n.Value);
                if (sum <= 0) continue;
                var available = plotH - (col.Count - 1) * SankeyNodeSpacing;
                ky = Math.Min(ky, Math.Max(available, 1) / sum);
            }
            if (double.IsInfinity(ky) || ky <= 0) ky = 1;

            foreach (var n in all)
            {
                n.H = Math.Max(n.Value * ky, 2);
                n.X = columnCount == 1 ? 0 : (double)n.Depth / (columnCount - 1) * Math.Max(plotW - SankeyNodeThickness, 1);
            }
            // Initial y: stack each column and centre the stack in the plot.
            foreach (var col in columns)
            {
                var stack = col.Sum(n => n.H) + (col.Count - 1) * SankeyNodeSpacing;
                var y = Math.Max(0, (plotH - stack) / 2);
                foreach (var n in col) { n.Y = y; y += n.H + SankeyNodeSpacing; }
            }
            // A few relaxation passes align a node with the weighted centre of what flows into/out of it, the
            // way d3-sankey does; collisions are then resolved IN THE FIXED INPUT ORDER (never re-sorted by
            // Y), so the vertical order stays the data order - matching nivo sort="input" on the dashboard.
            for (var iter = 0; iter < 6; iter++)
            {
                var alpha = 0.9 * Math.Pow(0.99, iter);
                foreach (var col in columns)
                    foreach (var n in col)
                    {
                        var linked = n.In.Concat(n.Out).ToList();
                        var weight = linked.Sum(l => l.Value);
                        if (weight <= 0) continue;
                        var target = linked.Sum(l => ((l.Src == n ? l.Tgt : l.Src).Y + (l.Src == n ? l.Tgt : l.Src).H / 2) * l.Value) / weight;
                        n.Y += (target - (n.Y + n.H / 2)) * alpha;
                    }
                foreach (var col in columns) ResolveSankeyCollisions(col, plotH);
            }

            // Stack the ribbon endpoints on each node face, ordered by the counterpart's position so ribbons
            // fan out without crossing at the node.
            foreach (var n in all)
            {
                var oy = n.Y;
                foreach (var l in n.Out.OrderBy(l => l.Tgt.Y)) { l.Width = l.Value * ky; l.Sy = oy; oy += l.Width; }
                var iy = n.Y;
                foreach (var l in n.In.OrderBy(l => l.Src.Y)) { l.Ty = iy; iy += l.Width; }
            }
            return all;
        }

        private static void ResolveSankeyCollisions(List<SankeyNode> col, double plotH)
        {
            if (col.Count == 0) return;
            // Resolve overlaps in the column's GIVEN order (input/sequence order), not by Y - re-sorting by
            // Y would scramble the nivo sort="input" ordering the dashboard uses. Push down, then if the
            // stack overruns the plot, push back up from the bottom.
            var y = 0.0;
            foreach (var n in col) { if (n.Y < y) n.Y = y; y = n.Y + n.H + SankeyNodeSpacing; }
            var overflow = y - SankeyNodeSpacing - plotH;
            if (overflow > 0)
            {
                y = plotH;
                for (var i = col.Count - 1; i >= 0; i--)
                {
                    var n = col[i];
                    if (n.Y + n.H > y) n.Y = y - n.H;
                    y = n.Y - SankeyNodeSpacing;
                }
            }
            foreach (var n in col) n.Y = Math.Max(0, Math.Min(n.Y, plotH - n.H));
        }

        private static void DrawSankey(OfficeDrawing dw, List<SankeyNode> nodes, double ox, double oy, double plotW,
            double boxW, double boxH)
        {
            // Ribbons first (under the node bars): a horizontal cubic band from the source's right face to the
            // target's left face, tinted the source colour so a node's outflow reads as one family.
            foreach (var n in nodes)
                foreach (var l in n.Out)
                {
                    double x0 = ox + l.Src.X + SankeyNodeThickness, x1 = ox + l.Tgt.X, xm = (x0 + x1) / 2;
                    double t0 = oy + l.Sy, t1 = oy + l.Ty, b0 = t0 + l.Width, b1 = t1 + l.Width;
                    var cmds = new List<OfficePathCommand>
                    {
                        OfficePathCommand.MoveTo(x0, t0),
                        OfficePathCommand.CubicBezierTo(xm, t0, xm, t1, x1, t1),
                        OfficePathCommand.LineTo(x1, b1),
                        OfficePathCommand.CubicBezierTo(xm, b1, xm, b0, x0, b0),
                        OfficePathCommand.Close(),
                    };
                    var ribbon = OfficeShape.Path(boxW, boxH, cmds);
                    ribbon.FillColor = OC(l.Src.Colour); ribbon.FillOpacity = 0.45;
                    dw.AddShape(ribbon, 0, 0);
                }
            // Node bars + labels: end columns label outward into the gutter, inner columns label to the right.
            foreach (var n in nodes)
            {
                // A thin node (tiny flow) is shorter than twice the corner radius, which RoundedRectangle
                // rejects - clamp the radius to what fits.
                var radius = Math.Min(3, Math.Min(SankeyNodeThickness, n.H) / 2);
                var bar = OfficeShape.RoundedRectangle(SankeyNodeThickness, n.H, radius);
                bar.FillColor = OC(n.Colour); dw.AddShape(bar, ox + n.X, oy + n.Y);

                var label = n.Label.Length > 22 ? n.Label.Substring(0, 21) + "…" : n.Label;
                var midY = oy + n.Y + n.H / 2 - 4;
                if (n.X <= 0.01)
                    AddT(dw, San(label), ox - SankeyLabelGutter, midY, SankeyLabelGutter - 5, 12, ChartLabelSize, ReportColours.Body, OfficeTextAlignment.Right);
                else if (n.X >= plotW - SankeyNodeThickness - 0.01)
                    AddT(dw, San(label), ox + n.X + SankeyNodeThickness + 5, midY, SankeyLabelGutter - 5, 12, ChartLabelSize, ReportColours.Body, OfficeTextAlignment.Left);
                else
                    AddT(dw, San(label), ox + n.X + SankeyNodeThickness + 4, midY, 100, 12, ChartLabelSize, ReportColours.Muted, OfficeTextAlignment.Left);
            }
        }

        private static string RunsToPlain(IReadOnlyList<TextRun> runs)
        {
            var sb = new System.Text.StringBuilder();
            foreach (var r in runs) sb.Append(r.Text);
            return sb.ToString();
        }

        // -- dispatch --
        /// <summary>Render a list of component/primitive nodes into the current item flow. An optional text
        /// style flows into paragraph nodes so a callout renders its body at the callout size, not body copy.</summary>
        public static void RenderNodes(ReportContext ctx, PdfContentBuilder item, IEnumerable<ReportNode> nodes, TextStyle? textStyle = null)
        {
            foreach (var node in nodes) RenderNode(ctx, item, node, textStyle);
        }

        private static void RenderNode(ReportContext ctx, PdfContentBuilder item, ReportNode node, TextStyle? textStyle = null)
        {
            switch (node.Type)
            {
                case "heading":
                    Heading(ctx, item, (int)(node.Num("level") ?? 2), node.Get<List<TextRun>>("runs") ?? new List<TextRun>());
                    break;
                case "paragraph":
                    Paragraph(ctx, item, node.Get<List<TextRun>>("runs") ?? new List<TextRun>(), textStyle);
                    break;
                case "bullets":
                    // Inside a callout (textStyle set) OfficeIMO panels ignore a per-call list style, so
                    // the list is drawn as one styled paragraph with a marker per line - matching the
                    // client, which renders callout bullets as a single text block. Elsewhere the real
                    // list renderer is used.
                    if (textStyle is { } bts) BulletLines(ctx, item, StringItems(node), bts, _ => "•  ");
                    else Bullets(ctx, item, StringItems(node));
                    break;
                case "numbered":
                    if (textStyle is { } nts)
                    {
                        var start = (int)(node.Num("start") ?? 1);
                        BulletLines(ctx, item, StringItems(node), nts, i => $"{start + i}.  ");
                    }
                    else Numbered(ctx, item, StringItems(node), (int)(node.Num("start") ?? 1));
                    break;
                case "table":
                    RenderTableNode(ctx, item, node);
                    break;
                case "code":
                    Code(ctx, item, node.Str("text") ?? node.Str("content") ?? string.Empty);
                    break;
                case "hr":
                    Hr(ctx, item);
                    break;
                default:
                    // Unknown primitive: fall back to its text content as a paragraph.
                    var text = node.Str("content") ?? node.Str("text");
                    if (!string.IsNullOrEmpty(text)) Paragraph(ctx, item, ReportMarkdown.MarkdownRuns(text));
                    break;
            }
        }

        private static void RenderTableNode(ReportContext ctx, PdfContentBuilder item, ReportNode node)
        {
            var rows = node.Get<List<string[]>>("rows");
            if (rows is { Count: > 0 }) Table(ctx, item, rows);
        }

        private static List<string> StringItems(ReportNode node)
        {
            var result = new List<string>();
            if (node.Get<List<string>>("items") is { } typed) return typed;
            // Items may be plain strings (markdown) or objects with a text/label/content field (the report
            // builder's row editor saves objects), so read the field when an item is a dictionary.
            if (node.ListOf("items") is { } raw)
                foreach (var o in raw)
                    result.Add(o is Dictionary<string, object?>
                        ? (ReportNode.RowStr(o, "text") ?? ReportNode.RowStr(o, "label") ?? ReportNode.RowStr(o, "content") ?? string.Empty)
                        : o?.ToString() ?? string.Empty);
            return result;
        }

        /// <summary>
        /// Block -> component adapter for the Report Builder. Each top-level block renders its title as a
        /// section heading, then its body composed from the component kit. Hero/pagebreak are handled by
        /// the document scaffold, not here.
        /// </summary>
        private static double? ParseNumber(string? text)
            => double.TryParse(text, NumberStyles.Any, CultureInfo.InvariantCulture, out var value) ? value : null;

        public static void RenderBlock(ReportContext ctx, PdfContentBuilder item, ReportNode block, bool firstOnPage = false)
        {
            var content = block.Str("content") ?? string.Empty;

            // Callouts carry their own title inside the box, so they are handled before the generic
            // section-title emit below - the title must not also appear as a heading above the panel.
            switch (block.Type)
            {
                case "infobox":
                    InfoBox(ctx, item, block.Str("title"), block.Str("tone"), block.Str("colour"), block.Bool("tintTitle"), content, block.Bool("lines"));
                    return;
                case "infoboxcolumns":
                    InfoBoxColumns(ctx, item, block.ListOf("items") ?? new List<object?>(), (int)(block.Num("columns") ?? 2));
                    return;
                case "alertbox":
                    AlertBox(ctx, item, block.Str("title"), block.Str("colour"), content, block.Bool("lines"));
                    return;
                case "clearbox":
                    ClearBox(ctx, item, block.Str("title"), content, block.Bool("lines"));
                    return;
                case "paragraphindent":
                    IndentedParagraph(ctx, item, content);
                    return;
                case "note":
                    Note(ctx, item, content);
                    return;
                case "chart":
                    // The fixed reports name these caption/max/centreLabel; the report builder saves them
                    // with a chart prefix. Both reach the page. A half-width chart with no adjacent partner
                    // renders at half width on its own line (the pair renderer handles two together).
                    ChartFromBlock(ctx, item, block, IsHalfWidthChart(block) ? (ctx.ContentWidth - 16) / 2 : (double?)null);
                    return;
                case "sankey":
                    Sankey(ctx, item, block.ListOf("nodes") ?? new List<object?>(), block.ListOf("links") ?? new List<object?>(),
                        block.Str("title"), block.Str("caption") ?? block.Str("chartCaption"),
                        block.Num("height") ?? ParseNumber(block.Str("height")));
                    return;
            }

            // A titled block opens a new section (client <Section>). Every section but the first on a page
            // carries the client's section marginBottom 12 above its heading, on top of the previous
            // block's own trailing space - so sections sit apart the way they do in the react-pdf reports.
            var title = block.Str("title");
            if (!string.IsNullOrEmpty(title))
            {
                if (!firstOnPage) item.Spacer(SectionGap);
                SectionTitle(ctx, item, title);
            }

            // Test-block status line (Passed/Failed/Investigate/Skipped).
            if (block.Type == "test" && !string.IsNullOrEmpty(block.Str("status")))
                Note(ctx, item, "Status: " + block.Str("status"));

            switch (block.Type)
            {
                case "scorecard":
                    StatRow(ctx, item, block.ListOf("stats") ?? new List<object?>());
                    break;
                case "richtable":
                    // The client DataTable always has an empty state: its emptyText, else 'Nothing to report.'.
                    RichTable(ctx, item, block.ListOf("columns") ?? new List<object?>(), block.ListOf("rows") ?? new List<object?>(), (int)(block.Num("limit") ?? ParseNumber(block.Str("limit")) ?? 0), block.Str("emptyText") ?? "Nothing to report.");
                    break;
                case "richbullets":
                    RichBullets(ctx, item, block.ListOf("items") ?? new List<object?>());
                    break;
                case "progress":
                    Progress(ctx, item, block.ListOf("items") ?? new List<object?>());
                    break;
                case "database":
                    var format = block.Str("format");
                    if (!string.IsNullOrEmpty(format) && format != "text") Code(ctx, item, content);
                    else RenderNodes(ctx, item, ReportMarkdown.MarkdownToNodes(content));
                    break;
                case "blank":
                    RenderNodes(ctx, item, ReportMarkdown.HtmlToNodes(content));
                    break;
                case "test":
                    RenderNodes(ctx, item, block.Bool("static")
                        ? ReportMarkdown.HtmlToNodes(content)
                        : ReportMarkdown.MarkdownToNodes(content));
                    break;
                default:
                    // A raw primitive node passed straight through (e.g. from a fixed report composing the kit).
                    RenderNode(ctx, item, block);
                    break;
            }
        }
    }
}
