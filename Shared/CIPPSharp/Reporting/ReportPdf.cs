using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.Json;
using OfficeIMO;
using OfficeIMO.Pdf;

namespace CIPP.Reporting
{
    /// <summary>
    /// Entry point for server-side report rendering. Called from PowerShell as
    /// <c>[CIPP.Reporting.ReportPdf]::Render(...)</c> (wrapped by ConvertTo-CippReportPdf.ps1).
    /// Takes the declarative component tree + branding + variables and returns the finished PDF bytes,
    /// composing the OfficeIMO document from the shared component kit - cover page, then content
    /// sections carrying header / footer / page numbers / watermark, with hero pages and page breaks
    /// splitting the flow (buildPageGroups equivalent).
    /// </summary>
    public static class ReportPdf
    {
        public static byte[] Render(
            string blocksJson,
            string brandingJson,
            string variablesJson,
            string tenantName,
            string reportName,
            string generatedOn,
            string pageSize = "A4",
            bool landscape = false,
            bool chrome = true)
        {
            var blocks = ReportNode.ParseTree(blocksJson);
            var branding = BrandingInput.FromJson(brandingJson);
            var theme = ReportTheme.Create(branding);

            var variables = ParseVariables(variablesJson);
            variables["tenantname"] = tenantName ?? "Organization";
            variables["reportname"] = reportName ?? "Report";
            variables["reportdate"] = generatedOn ?? string.Empty;

            // A report builder cover block: its fields become the cover variables a fixed report's tree
            // builder supplies, and the block itself draws nothing.
            var cover = blocks.Find(b => b.Type == "cover");
            if (cover != null)
            {
                foreach (var (variable, field) in new[] { ("covertitle", "title"), ("coveraccent", "coverAccent"), ("coversubtitle", "subtitle"), ("coverlabel", "coverLabel") })
                {
                    var value = cover.Str(field);
                    if (!string.IsNullOrWhiteSpace(value)) variables[variable] = value;
                }
                blocks.RemoveAll(b => b.Type == "cover");
            }

            var logo = ReportComponents.DecodeImage(branding.Logo);
            // The cover photo, resolved the way the client's resolveCoverImage did: an uploaded cover wins,
            // then the stock photo the branding picked ("none" means no cover at all), then the report's
            // own %coverfallbackimage% (e.g. "/reportImages/soc.jpg"), so a report without configured
            // branding still gets a cover.
            var coverImage = ReportComponents.DecodeImage(branding.CoverImage)
                ?? (branding.CoverStock == "none" ? null
                    : ReportComponents.DecodeImage(branding.CoverStock)
                        ?? (variables.TryGetValue("coverfallbackimage", out var coverFallback) ? ReportComponents.DecodeImage(coverFallback) : null));
            ReportContext Context(byte[]? logoBytes) => new()
            {
                Theme = theme,
                Variables = variables,
                PageSize = string.IsNullOrWhiteSpace(pageSize) ? "A4" : pageSize,
                Landscape = landscape,
                TenantName = tenantName ?? "Organization",
                ReportName = reportName ?? "Report",
                GeneratedOn = generatedOn ?? string.Empty,
                Logo = logoBytes,
                CoverImage = coverImage,
            };

            var groups = BuildPageGroups(blocks);
            // A branding logo the engine cannot embed (a PNG with a bad chunk CRC, an unsupported format)
            // only surfaces when the document is serialised, not where the logo is placed, so it must not
            // sink the report: render once more without it. Any other failure still propagates.
            var watermark = theme.WatermarkEnabled ? DrawableMark(ReportTheme.ApplyWatermark(theme.WatermarkText, variables)) : string.Empty;
            // The client's mark is a centred text box as wide as the page, so a mark wider than that (its 4pt
            // letter spacing counted) breaks into lines. OfficeIMO draws one line: it is handed the lines joined,
            // with room behind them for the line moves LiftWatermark writes in their place.
            var markLines = ReportComponents.WrapLines(watermark, ReportStyles.ContentWidth(pageSize, landscape) + 2 * ReportStyles.PagePadding, WatermarkSize, bold: true, tracking: 4);
            if (markLines.Count > 1) watermark = string.Join(" ", markLines) + new string(' ', MarkLineRoom * (markLines.Count - 1));
            byte[] Finish(PdfDocument doc) => chrome ? LiftWatermark(doc.ToBytes(), watermark, markLines) : doc.ToBytes();
            try { return Finish(Compose(Context(logo), groups, chrome, watermark)); }
            catch when (logo is not null) { return Finish(Compose(Context(null), groups, chrome, watermark)); }
        }

        private static PdfDocument Compose(ReportContext ctx, List<PageGroup> groups, bool chrome, string watermark)
        {
            var theme = ctx.Theme;
            var variables = ctx.Variables;
            // Branding's configured footer wins; a report's own %footerlabel% is the fallback (client
            // PageFooter's `label`), so a fixed report still identifies itself when no branding footer is set.
            var footerText = theme.FooterEnabled
                ? ReportTheme.ApplyFooter(theme.FooterTemplate, variables)
                : (variables.TryGetValue("footerlabel", out var fl) ? ReportTheme.ApplyFooter(fl, variables) : string.Empty);

            return PdfDocument.Create(compose =>
            {
                // OfficeIMO 3.4 dropped the document-wide Defaults() hook, so the page size, margin and
                // orientation are applied to every page/section here instead.
                void ApplyPageDefaults(PdfPageBuilder p)
                {
                    p.Size(ResolveSize(ctx.PageSize));
                    if (ctx.Landscape) p.Landscape();
                    p.Margin(ReportStyles.PagePadding);
                }

                // Cover - its own page, no header/footer/watermark. Skipped in chrome-less mode (used by
                // the component A/B harness and any embedded/preview render that wants only the content).
                // A cover photo (branding) fills the page behind the drawn cover content.
                if (chrome)
                    compose.Page(p =>
                    {
                        ApplyPageDefaults(p);
                        p.Background(ReportComponents.Pdf(ReportColours.White));
                        if (ctx.CoverImage is { Length: > 0 })
                        {
                            try { p.BackgroundImage(ctx.CoverImage, OfficeIMO.Drawing.OfficeImageFit.Cover, 0.5); }
                            catch { /* an unusable cover photo leaves the plain white cover */ }
                        }
                        p.Content(cc => cc.Item(i => ReportComponents.RenderCoverDrawing(ctx, i)));
                    });

                foreach (var group in groups)
                {
                    if (group.Kind == "hero")
                    {
                        // Full-bleed divider: a dark page with an optional cover photo behind the big figure,
                        // no header/footer chrome. The photo is a page background image (edge to edge); the
                        // text is drawn over it, vertically centred, with the footer note bottom-right.
                        var heroImage = ReportComponents.DecodeImage(group.Block!.Str("heroImage") ?? group.Block!.Str("backgroundImage"));
                        compose.Section(p =>
                        {
                            ApplyPageDefaults(p);
                            p.Background(ReportComponents.Pdf(ctx.Theme.Palette["infographicBackground"]));
                            if (heroImage is { Length: > 0 })
                            {
                                try { p.BackgroundImage(heroImage, OfficeIMO.Drawing.OfficeImageFit.Cover, 0.28); }
                                catch { /* an unusable cover photo leaves the plain dark page */ }
                            }
                            // The client's watermarkTextOnDark: the same mark in the divider's text colour and a
                            // little stronger, since an 8% brand-colour mark disappears on a dark page.
                            if (!string.IsNullOrEmpty(watermark))
                                p.Watermark(watermark.ToUpperInvariant(), fontSize: WatermarkSize, color: ReportComponents.Pdf(ctx.Theme.OnInfographic), opacity: 0.12, rotationAngle: DividerWatermarkAngle, bold: true);
                            p.Content(cc => cc.Item(i => ReportComponents.RenderHeroDrawing(ctx, i, group.Block!)));
                        });
                        continue;
                    }
                    compose.Section(p =>
                    {
                        ApplyPageDefaults(p);
                        if (chrome) ApplyContentChrome(p, ctx, footerText, watermark);
                        p.Content(cc => cc.Item(i =>
                        {
                            // A titled group (a fixed report's ContentPage) heads with its own title and
                            // subtitle; the Report Builder path has neither, so it falls back to the report
                            // name and the generated-on date.
                            if (chrome) RenderPageHeader(ctx, i, group.Title ?? ctx.ReportName, group.Subtitle ?? ctx.GeneratedOn);
                            var firstBlock = true;
                            // Two adjacent half-width charts render side by side in one row; anything else
                            // (including a lone half-width chart) renders on its own line.
                            for (var bi = 0; bi < group.Blocks.Count; bi++)
                            {
                                var block = group.Blocks[bi];
                                if (ReportComponents.IsHalfWidthChart(block) && bi + 1 < group.Blocks.Count && ReportComponents.IsHalfWidthChart(group.Blocks[bi + 1]))
                                {
                                    ReportComponents.RenderChartPair(ctx, i, block, group.Blocks[bi + 1], firstBlock);
                                    bi++;
                                }
                                else
                                {
                                    ReportComponents.RenderBlock(ctx, i, block, firstBlock);
                                }
                                firstBlock = false;
                            }
                        }));
                    });
                }
            }, BuildOptions());
        }

        // PDF options carrying the emoji fallback font: the standard fonts have no glyph for any emoji, so a
        // bundled monochrome symbol/emoji font is registered as a Unicode fallback and OfficeIMO routes each
        // emoji code point through it (per character - the surrounding text stays in the standard font), in
        // table cells and paragraphs alike. The report's three status emoji are tinted per run downstream;
        // everything else renders in the surrounding text colour.
        private static PdfOptions BuildOptions()
        {
            var options = new PdfOptions();
            if (EmojiFallbacks.Value is { } fallbacks)
            {
                options.CompressEmbeddedFonts = true;
                options.EmbeddedFontFallbacks = fallbacks;
            }
            return options;
        }

        // Built once per process: a candidate copies the ~800 KB font, and OfficeIMO keeps the parsed font per
        // candidate, so a candidate made per render copied and re-parsed the whole font on every render.
        // OfficeIMO embeds only the glyphs a given report actually uses, compressed, so a report
        // gains a few KB, not the whole ~800 KB font. The fallback is scoped to exactly the code
        // points the font carries above U+00FF (the Latin-1 glyphs it also holds exist only so
        // OfficeIMO's greedy neighbour-of-an-emoji fallback never lands on an uncovered character),
        // so ordinary text always stays in the standard font.
        private static readonly Lazy<PdfEmbeddedFontFallbackSet?> EmojiFallbacks = new(() =>
        {
            var font = ReportMarkdown.EmojiFontBytes.Value;
            var coverage = ReportMarkdown.EmojiCoverage;
            if (font is not { Length: > 0 } || coverage.Count == 0) return null;
            var ranges = new OfficeIMO.Drawing.OfficeFontUnicodeRangeSet(CoverageRanges(coverage));
            return new PdfEmbeddedFontFallbackSet(new[] { new PdfEmbeddedFontFallbackCandidate("CippReportEmoji", font, ranges) });
        });

        // The coverage set compressed into [start,end] ranges for the fallback scope. The emoji blocks are
        // scattered, so this coalesces across the smallest gaps until within OfficeIMO's 1..128-range limit.
        // Widening a range is safe: it only ever includes unassigned/uncovered code points, which Sanitize
        // (gated on the exact coverage set) never keeps, so no uncovered character is routed to the fallback.
        private const int MaxFallbackRanges = 128;
        private static OfficeIMO.Drawing.OfficeFontUnicodeRange[] CoverageRanges(HashSet<int> coverage)
        {
            var sorted = new List<int>(coverage);
            sorted.Sort();
            var ranges = new List<(int start, int end)>();
            var start = sorted[0];
            var prev = sorted[0];
            for (var k = 1; k < sorted.Count; k++)
            {
                if (sorted[k] == prev + 1) { prev = sorted[k]; continue; }
                ranges.Add((start, prev));
                start = prev = sorted[k];
            }
            ranges.Add((start, prev));

            while (ranges.Count > MaxFallbackRanges)
            {
                var mergeAt = 0;
                var smallestGap = int.MaxValue;
                for (var k = 0; k < ranges.Count - 1; k++)
                {
                    var gap = ranges[k + 1].start - ranges[k].end;
                    if (gap < smallestGap) { smallestGap = gap; mergeAt = k; }
                }
                ranges[mergeAt] = (ranges[mergeAt].start, ranges[mergeAt + 1].end);
                ranges.RemoveAt(mergeAt + 1);
            }
            return ranges.ConvertAll(r => new OfficeIMO.Drawing.OfficeFontUnicodeRange(r.start, r.end)).ToArray();
        }

        // The styled page header (big title + subtitle + brand rule) that opens each content group,
        // matching the client's ContentPage header. Rendered as content rather than a running header so
        // it can carry the brand-coloured rule the running-header API can't draw.
        private static void RenderPageHeader(ReportContext ctx, PdfContentBuilder item, string? title, string? subtitle)
        {
            // Client pageHeader, from the 28pt page top: the 20pt title and 11pt subtitle each on the page's
            // 14pt line (baseline 0.9x the size under the line top), 8pt between them, then 8pt of padding,
            // the 1pt brand rule and 14pt under it. OfficeIMO seats every paragraph's first baseline
            // FlowBaseline under its top, so the space above the title and the title line itself carry the
            // difference in seats, and the rule's spacing puts it and the content under it where the
            // client's are.
            var titleColour = ctx.Theme.Palette["title"];
            var subtitleColour = ctx.Theme.Palette["subtitle"];
            var titleText = title ?? ctx.ReportName;
            Action<PdfParagraphBuilder> titleRun = b => { b.FontSize(ReportStyles.PageTitle); ReportComponents.EmitInline(b, titleText, titleColour, ReportStyles.PageTitle, bold: true); };
            Action<PdfParagraphBuilder>? subtitleRun = string.IsNullOrEmpty(subtitle) ? null
                : b => { b.FontSize(ReportStyles.PageSubtitle); ReportComponents.EmitInline(b, subtitle!, subtitleColour, ReportStyles.PageSubtitle); };
            var subtitleStyle = new PdfParagraphStyle { LineHeight = 14 / ReportStyles.PageSubtitle, SpacingAfter = 0 };
            var titleSeat = 0.9 * ReportStyles.PageTitle - ReportComponents.FlowBaseline;

            // Client pageHeader: the title block takes the width (flex 1) and the branding logo sits at the
            // right edge, 30pt tall and top-aligned with the title's line, with no gap between them. Without
            // a logo the paragraphs flow directly. The title's seat goes in the text column, so the logo
            // stays at the page top.
            var logoType = ctx.Logo is { Length: > 0 } ? ReportComponents.ImageContentType(ctx.Logo) : null;
            var box = logoType is null ? (w: 0.0, h: 0.0) : ReportComponents.LogoBox(ctx.Logo!, 30, 120);
            // A one-line title sits on the client's 14pt line, which also carries the 8pt down to the
            // subtitle. The client keeps that 14pt pitch when the title wraps, so its 20pt lines run into
            // each other; a title too long for one line takes a 1.15 leading here instead.
            var titleLines = ReportComponents.WrappedLines(ReportMarkdown.Sanitize(titleText), ctx.ContentWidth - box.w, ReportStyles.PageTitle, bold: true);
            var titleStyle = new PdfParagraphStyle
            {
                LineHeight = titleLines > 1 ? 1.15 : (14 + 8 - 0.9 * (ReportStyles.PageTitle - ReportStyles.PageSubtitle)) / ReportStyles.PageTitle,
                SpacingAfter = 0,
            };
            if (logoType is null)
            {
                item.Spacer(titleSeat);
                item.Paragraph(titleRun, PdfAlign.Left, null, titleStyle);
                if (subtitleRun is not null) item.Paragraph(subtitleRun, PdfAlign.Left, null, subtitleStyle);
            }
            else
            {
                item.Row(r =>
                {
                    r.Gap(0);
                    r.RelativeColumn(c =>
                    {
                        c.Spacer(titleSeat);
                        c.Paragraph(titleRun, PdfAlign.Left, null, titleStyle);
                        if (subtitleRun is not null) c.Paragraph(subtitleRun, PdfAlign.Left, null, subtitleStyle);
                    });
                    r.FixedColumn(box.w, c => c.Image(ctx.Logo!, box.w, box.h, PdfAlign.Right));
                });
            }
            // Full-width brand rule under the header (HR auto-fits the content width; a fixed-width
            // rectangle risks exceeding it).
            item.HR(1, ReportComponents.Pdf(ctx.Theme.Palette["heading"]), spacingBefore: 6.2, spacingAfter: 14);
        }

        // Client PageFooter: a 20pt box 14pt above the paper edge with a 1pt rule along its top, 5pt of padding
        // under the rule, the label on the left and a bold "Page N of M" on the right. The page's bottom
        // padding reserves the box plus 6pt, so the body stops 40pt above the paper edge.
        private const double FooterInset = 14, FooterHeight = 20, FooterReserve = FooterInset + FooterHeight + 6, PagePaddingTop = 28;

        // `text` cut to fit `width` points at `size` (Helvetica), ending in an ellipsis (1em) when cut.
        internal static string FitLine(string text, double width, double size)
        {
            if (ReportComponents.TextEm(text, bold: false) * size <= width) return text;
            var n = text.Length;
            while (n > 0 && (ReportComponents.TextEm(text[..n], bold: false) + 1) * size > width) n--;
            if (n > 0 && char.IsHighSurrogate(text[n - 1])) n--; // never split an emoji's surrogate pair
            return text[..n].TrimEnd() + "…";
        }

        private static void ApplyContentChrome(PdfPageBuilder p, ReportContext ctx, string footerText, string watermark)
        {
            // Client content page padding: 28 above (the header, or a continued table), 40 below (the footer).
            p.Margin(ReportStyles.PagePadding, PagePaddingTop, ReportStyles.PagePadding, FooterReserve);
            var showText = ctx.Theme.FooterShow && !string.IsNullOrEmpty(footerText);
            if (showText || ctx.Theme.ShowPageNumbers)
            {
                // The label's baseline above the paper edge: under the rule and the padding, 0.9x its size into
                // the page's 14pt line. OfficeIMO sets every footer zone on one baseline, so the page number
                // shares it (the client centres its shorter natural line, 3pt lower).
                var baseline = FooterInset + FooterHeight - 1 - 5 - 0.9 * ReportStyles.FooterText;
                var w = ctx.ContentWidth;
                // The rule: a 1pt band at the top of a shape whose foot sits on the footer baseline.
                var rule = OfficeIMO.Drawing.OfficeShape.Path(w, FooterInset + FooterHeight - baseline,
                    OfficeIMO.Drawing.OfficePathCommand.MoveTo(0, 0), OfficeIMO.Drawing.OfficePathCommand.LineTo(w, 0),
                    OfficeIMO.Drawing.OfficePathCommand.LineTo(w, 1), OfficeIMO.Drawing.OfficePathCommand.LineTo(0, 1),
                    OfficeIMO.Drawing.OfficePathCommand.Close());
                rule.FillColor = ReportComponents.OC(ReportColours.Line);
                // The client's page number starts at the left of its 80pt box at the right edge. A zone can only
                // right-align, so an empty shape after the text fills the rest of the box (sized for one-digit
                // numbers; OfficeIMO leaves 4pt between the text and the shape).
                var numberPad = OfficeIMO.Drawing.OfficeShape.Rectangle(80 - 4 - ReportComponents.TextEm("Page 8 of 8", bold: true) * ReportStyles.FooterText, 1);
                p.Footer(f =>
                {
                    f.FontSize(ReportStyles.FooterText).Offset(FooterReserve - baseline);
                    f.Shape(rule, PdfAlign.Center);
                    if (ctx.Theme.ShowPageNumbers) f.Shape(numberPad, PdfAlign.Right);
                    // The client's label wraps beside the page number's 80pt box; a zone would run under it, so a
                    // label too long for the room left of the box is cut with an ellipsis. The 16pt spare covers
                    // the number growing left past its box with two- and three-digit page counts.
                    var text = ReportMarkdown.Sanitize(footerText);
                    if (ctx.Theme.ShowPageNumbers) text = FitLine(text, w - 80 - 16, ReportStyles.FooterText);
                    var label = new PdfTextRun(text, color: ReportComponents.Pdf(ctx.Theme.Palette["footer"]), fontSize: ReportStyles.FooterText);
                    var number = new PdfTextRun(" ", bold: true, color: ReportComponents.Pdf(ReportColours.Faint), fontSize: ReportStyles.FooterText);
                    PdfTextRun Number(string s) => new(s, bold: true, color: number.Color, fontSize: ReportStyles.FooterText);
                    f.StyledZones(
                        showText ? z => z.Run(label) : null,
                        null,
                        ctx.Theme.ShowPageNumbers ? z => z.Run(Number("Page ")).CurrentPage(number).Run(Number(" of ")).TotalPages(number) : null);
                });
            }
            // Named on purpose: OfficeIMO's positional order is (text, fontSize, colour, opacity, angle), so
            // Watermark(text, 0.08, colour) asks for a 0.08pt watermark - drawn, but invisible. The values
            // mirror the client's watermarkText style: 72pt bold, uppercase, 8% opacity.
            if (!string.IsNullOrEmpty(watermark))
                p.Watermark(watermark.ToUpperInvariant(), fontSize: WatermarkSize, color: ReportComponents.Pdf(ctx.Theme.Palette["watermark"]), opacity: 0.08, rotationAngle: WatermarkAngle, bold: true);
        }

        // The client's mark is rotated -45deg in CSS, rising from bottom left to top right; OfficeIMO turns a
        // positive angle counter-clockwise, so the same mark is +45 here. The divider's is asked for at 45.05
        // (the same to the eye) only so LiftWatermark can tell it from a content page's - the client sets the
        // two on different lines - and is written back at exactly 45.
        private const double WatermarkSize = 72, WatermarkAngle = 45, DividerWatermarkAngle = 45.05;
        // Spaces added to a multi-line mark per extra line: 32 bytes of hex, where a line move ("-123.45 -79.2 Td"
        // and the line's own "<...> Tj" framing, less the space it replaces) needs about 22.
        private const int MarkLineRoom = 16;
        private static readonly byte[] WatermarkRotation = Encoding.ASCII.GetBytes("0.707 0.707 -0.707 0.707");
        private static readonly byte[] DividerWatermarkRotation = Encoding.ASCII.GetBytes("0.706 0.708 -0.708 0.706");

        /// <summary>
        /// OfficeIMO paints a page watermark before anything else on the page, so every card, panel and
        /// image covers it, where the client reports drew it over the content. The PDF it writes is
        /// classic - no object or cross-reference streams - with uncompressed content streams, so the
        /// watermark's operator block (a self-contained q ... Q group, recognised by its text and its
        /// 45 degree text matrix) is moved to the end of each page's content stream in place: the same
        /// bytes in a different order, so no length or offset in the file changes. On the way its text
        /// matrix is rewritten, space-padded to the same length, to put the mark where the client's is
        /// (<see cref="PlaceWatermark"/>). A stream the block cannot be found in is left as written.
        /// </summary>
        internal static byte[] LiftWatermark(byte[] pdf, string watermark, IReadOnlyList<string> lines)
        {
            if (string.IsNullOrEmpty(watermark)) return pdf;
            var marker = Encoding.ASCII.GetBytes(Hex(watermark) + " Tj");
            var streamTag = Encoding.ASCII.GetBytes("stream\n");
            var lengthTag = Encoding.ASCII.GetBytes("/Length ");
            var open = Encoding.ASCII.GetBytes("q\n");
            var close = Encoding.ASCII.GetBytes("\nQ\n");

            var at = 0;
            while ((at = IndexOf(pdf, marker, at, pdf.Length)) >= 0)
            {
                var streamAt = LastIndexOf(pdf, streamTag, at);
                var lengthAt = streamAt < 0 ? -1 : LastIndexOf(pdf, lengthTag, streamAt);
                if (streamAt < 0 || lengthAt < 0 || streamAt - lengthAt > 64) { at += marker.Length; continue; }
                var dataStart = streamAt + streamTag.Length;
                var length = 0;
                for (var d = lengthAt + lengthTag.Length; d < pdf.Length && pdf[d] >= '0' && pdf[d] <= '9'; d++) length = length * 10 + (pdf[d] - '0');
                var dataEnd = Math.Min(dataStart + length, pdf.Length);

                // Back to the "q" that opens the watermark's group (at a line start), forward to its "Q".
                var blockStart = LastIndexOf(pdf, open, at);
                while (blockStart > dataStart && pdf[blockStart - 1] != '\n') blockStart = LastIndexOf(pdf, open, blockStart);
                var closeAt = IndexOf(pdf, close, at, dataEnd);
                if (blockStart < dataStart || closeAt < 0) { at = dataEnd; continue; }
                var blockEnd = closeAt + close.Length;
                var rotationAt = IndexOf(pdf, WatermarkRotation, blockStart, blockEnd);
                var divider = rotationAt < 0;
                if (divider) rotationAt = IndexOf(pdf, DividerWatermarkRotation, blockStart, blockEnd);
                if (rotationAt < 0) { at = dataEnd; continue; }
                PlaceWatermark(pdf, rotationAt, blockEnd, divider, watermark, lines, at, marker.Length);

                var block = pdf[blockStart..blockEnd];
                // Same length: the block's trailing newline becomes the separator in front of it. The tail
                // slides down in place (an overlapping span copy is a memmove).
                pdf.AsSpan(blockEnd, dataEnd - blockEnd).CopyTo(pdf.AsSpan(blockStart));
                var moved = blockStart + dataEnd - blockEnd;
                pdf[moved] = (byte)'\n';
                Buffer.BlockCopy(block, 0, pdf, moved + 1, block.Length - 1);
                at = dataEnd;
            }
            return pdf;
        }

        /// <summary>
        /// Moves the mark whose "a b c d e f Tm" operands start at <paramref name="at"/> to the client's place.
        /// The client centres the text's box on the page and seats the baseline 0.9x the size under its line
        /// box top; a line box is a content page's inherited 14pt line, or a divider's natural 1.1x line.
        /// OfficeIMO seats the baseline half the size under the page centre, so the mark moves the difference
        /// across the text, and 2pt back along it: the client's 4pt letter spacing also trails the last
        /// letter, which the centring counts. A mark of several lines has its text (at <paramref name="textAt"/>)
        /// rewritten as one line per <paramref name="lines"/> entry, each centred along the text on its own and
        /// a Td move of a full 1.1x line down from the last, in the room its padding left. (The client stacks
        /// a content page's lines on its 14pt line, so 72pt letters overprint; here they read as lines.) The
        /// stack is centred where the one-line mark sits. Left as written when the operands or the lines will
        /// not fit.
        /// </summary>
        private static void PlaceWatermark(byte[] pdf, int at, int end, bool divider, string watermark, IReadOnlyList<string> lines, int textAt, int textLength)
        {
            var tm = IndexOf(pdf, Encoding.ASCII.GetBytes(" Tm"), at, end);
            var operands = tm < 0 ? Array.Empty<string>() : Encoding.ASCII.GetString(pdf, at, tm - at).Split(' ');
            if (operands.Length != 6
                || !double.TryParse(operands[4], NumberStyles.Float, CultureInfo.InvariantCulture, out var e)
                || !double.TryParse(operands[5], NumberStyles.Float, CultureInfo.InvariantCulture, out var f)) return;
            var lineBox = divider ? 1.1 * WatermarkSize : 14;
            var pitch = 1.1 * WatermarkSize;
            double Width(string s) => ReportComponents.TextEm(s, bold: true) * WatermarkSize;
            string Num(double v) => v.ToString("0.##", CultureInfo.InvariantCulture);

            byte[]? text = null;
            if (lines.Count > 1)
            {
                var sb = new StringBuilder(Hex(lines[0]) + " Tj");
                for (var i = 1; i < lines.Count; i++)
                    sb.Append('\n').Append(Num((Width(lines[i - 1]) - Width(lines[i])) / 2)).Append(' ').Append(Num(-pitch)).Append(" Td ").Append(Hex(lines[i])).Append(" Tj");
                text = Encoding.ASCII.GetBytes(sb.ToString());
                if (text.Length > textLength) return;
            }

            // From OfficeIMO's origin to the first line's, along the text and up across it.
            var along = (Width(watermark) - Width(lines[0])) / 2 - 2;
            var up = WatermarkSize / 2 + lineBox / 2 - 0.9 * WatermarkSize + (lines.Count - 1) * pitch / 2;
            // At 45 degrees the text runs along (k, k) and across it, upwards, is (-k, k) in PDF space.
            var k = Math.Sqrt(0.5);
            e += k * (along - up);
            f += k * (along + up);
            foreach (var format in new[] { "0.##", "0" })
            {
                var matrix = Encoding.ASCII.GetBytes(Encoding.ASCII.GetString(WatermarkRotation) + " "
                    + e.ToString(format, CultureInfo.InvariantCulture) + " " + f.ToString(format, CultureInfo.InvariantCulture));
                if (matrix.Length > tm - at) continue;
                Buffer.BlockCopy(matrix, 0, pdf, at, matrix.Length);
                Array.Fill(pdf, (byte)' ', at + matrix.Length, tm - at - matrix.Length);
                if (text is not null)
                {
                    Buffer.BlockCopy(text, 0, pdf, textAt, text.Length);
                    Array.Fill(pdf, (byte)' ', textAt + text.Length, textLength - text.Length);
                }
                return;
            }
        }

        // A PDF hex string of `s` as OfficeIMO writes the standard fonts' text: one WinAnsi byte a character, so
        // a curly quote, dash or euro sign (0x80..0x9F) matches the bytes on the page.
        private static string Hex(string s)
        {
            var bytes = new byte[s.Length];
            for (var i = 0; i < s.Length; i++) bytes[i] = (byte)Math.Max(0, ReportComponents.WinAnsiCode(s[i]));
            return "<" + Convert.ToHexString(bytes) + ">";
        }

        // The mark, upper-cased, in the standard Helvetica-Bold it is drawn in. A character with no WinAnsi code
        // (from %tenantname%, or made by upper-casing, like the Greek capital mu of 'µ') fails the engine's
        // encoding check and with it the whole report, so it prints as '?', the way the body text prints one.
        private static string DrawableMark(string text)
        {
            var upper = ReportMarkdown.Sanitize(text).ToUpperInvariant();
            var sb = new StringBuilder(upper.Length);
            foreach (var ch in upper) sb.Append(ReportComponents.WinAnsiCode(ch) >= 0 ? ch : '?');
            return sb.ToString();
        }

        // The first `needle` wholly inside [from, to), or -1.
        private static int IndexOf(byte[] hay, byte[] needle, int from, int to)
        {
            from = Math.Max(0, from);
            if (to - from < needle.Length) return -1;
            var i = hay.AsSpan(from, to - from).IndexOf(needle);
            return i < 0 ? -1 : from + i;
        }

        // The last `needle` wholly before `before`, or -1.
        private static int LastIndexOf(byte[] hay, byte[] needle, int before)
            => before < 0 ? -1 : hay.AsSpan(0, Math.Min(before, hay.Length)).LastIndexOf(needle);

        private sealed class PageGroup
        {
            public string Kind = "content"; // content|hero
            public List<ReportNode> Blocks = new();
            public ReportNode? Block;
            public string? Title;    // a fixed report's ContentPage title (null -> report name)
            public string? Subtitle; // its descriptive subtitle (null -> generated-on date)
        }

        private static List<PageGroup> BuildPageGroups(List<ReportNode> blocks)
        {
            var groups = new List<PageGroup>();
            var current = new PageGroup();
            void Flush() { if (current.Blocks.Count > 0) { groups.Add(current); current = new PageGroup { Title = null, Subtitle = null }; } }
            foreach (var block in blocks)
            {
                if (block.Type == "pagebreak") { Flush(); continue; }
                if (block.Type == "hero") { Flush(); groups.Add(new PageGroup { Kind = "hero", Block = block }); current = new PageGroup(); continue; }
                // A 'page' block opens a new titled content page (a fixed report's ContentPage).
                if (block.Type == "page") { Flush(); current.Title = block.Str("title"); current.Subtitle = block.Str("subtitle"); continue; }
                current.Blocks.Add(block);
            }
            Flush();
            if (groups.Count == 0) groups.Add(new PageGroup());
            return groups;
        }

        private static PageSize ResolveSize(string size) => (size ?? "A4").ToUpperInvariant() switch
        {
            "LETTER" => PageSizes.Letter,
            "LEGAL" => PageSizes.Legal,
            "A3" => PageSizes.A3,
            "A5" => PageSizes.A5,
            _ => PageSizes.A4,
        };

        private static Dictionary<string, string> ParseVariables(string? json)
        {
            var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (string.IsNullOrWhiteSpace(json)) return dict;
            try
            {
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;
                if (root.ValueKind == JsonValueKind.Object)
                    foreach (var p in root.EnumerateObject())
                        if (p.Value.ValueKind == JsonValueKind.String) dict[p.Name] = p.Value.GetString()!;
                        else if (p.Value.ValueKind is JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False) dict[p.Name] = p.Value.ToString();
            }
            catch { /* leave empty */ }
            return dict;
        }
    }
}
