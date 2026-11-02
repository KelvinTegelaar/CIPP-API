using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace CIPP.Reporting
{
    /// <summary>
    /// Faithful C# port of the frontend fidelity contract:
    ///   markdown-inline.js, html-inline.js, markdown-table.js and the markdown/HTML block converters
    ///   in ReportBuilderPDF.jsx.
    /// Inline parsing yields a shared nested tree that flattens into <see cref="TextRun"/>s; block
    /// parsing yields <see cref="ReportNode"/>s the component kit renders. Both markdown and HTML feed
    /// the same run emitter - ported once, exactly as the JS does.
    /// </summary>
    public static class ReportMarkdown
    {
        private sealed class InlineNode
        {
            public string Type = "text";           // text|strong|em|strongEm|code|strike|underline
            public string Value = string.Empty;    // for text
            public List<InlineNode> Children = new();
        }

        // -- Inline markdown --
        private static readonly (string marker, string type)[] EmphasisMarkers =
        {
            ("***", "strongEm"), ("___", "strongEm"), ("**", "strong"), ("__", "strong"),
            ("~~", "strike"), ("*", "em"), ("_", "em"),
        };
        private const string Escapable = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";

        private static bool IsBoundary(char? c)
            => c is null || char.IsWhiteSpace(c.Value) || char.IsPunctuation(c.Value) || char.IsSymbol(c.Value);

        private static List<InlineNode> ParseInlineMarkdown(string? text)
        {
            var source = text ?? string.Empty;
            var nodes = new List<InlineNode>();
            var buffer = new StringBuilder();
            var i = 0;

            void Flush()
            {
                if (buffer.Length > 0) { nodes.Add(new InlineNode { Type = "text", Value = buffer.ToString() }); buffer.Clear(); }
            }

            while (i < source.Length)
            {
                var ch = source[i];

                if (ch == '\\' && i + 1 < source.Length && Escapable.IndexOf(source[i + 1]) >= 0)
                {
                    buffer.Append(source[i + 1]); i += 2; continue;
                }
                if (ch == '`')
                {
                    var end = source.IndexOf('`', i + 1);
                    if (end > i + 1)
                    {
                        Flush();
                        nodes.Add(new InlineNode { Type = "code", Children = { new InlineNode { Type = "text", Value = source.Substring(i + 1, end - i - 1) } } });
                        i = end + 1; continue;
                    }
                }
                if (ch == '[')
                {
                    var link = Regex.Match(source.Substring(i), "^\\[([^\\]]*)\\]\\([^)\\s]*(?:\\s+\"[^\"]*\")?\\)");
                    if (link.Success)
                    {
                        Flush();
                        nodes.AddRange(ParseInlineMarkdown(link.Groups[1].Value));
                        i += link.Value.Length; continue;
                    }
                }
                if (ch == '*' || ch == '_' || ch == '~')
                {
                    var span = MatchEmphasis(source, i);
                    if (span is not null)
                    {
                        Flush();
                        nodes.Add(new InlineNode { Type = span.Value.type, Children = ParseInlineMarkdown(span.Value.content) });
                        i = span.Value.end; continue;
                    }
                }
                buffer.Append(ch); i += 1;
            }
            Flush();
            return nodes;
        }

        private static (string type, string content, int end)? MatchEmphasis(string source, int start)
        {
            foreach (var (marker, type) in EmphasisMarkers)
            {
                if (string.CompareOrdinal(source, start, marker, 0, marker.Length) != 0) continue;
                if (marker[0] == '_' && !IsBoundary(start - 1 >= 0 ? source[start - 1] : (char?)null)) continue;

                var contentStart = start + marker.Length;
                if (contentStart >= source.Length || char.IsWhiteSpace(source[contentStart])) continue;

                var search = contentStart;
                while (search < source.Length)
                {
                    var close = source.IndexOf(marker, search, StringComparison.Ordinal);
                    if (close == -1) break;
                    var before = source[close - 1];
                    var after = close + marker.Length < source.Length ? source[close + marker.Length] : (char?)null;
                    var closes = !char.IsWhiteSpace(before)
                        && (marker[0] != '_' || IsBoundary(after))
                        && close > contentStart;
                    if (closes)
                        return (type, source.Substring(contentStart, close - contentStart), close + marker.Length);
                    search = close + 1;
                }
            }
            return null;
        }

        // -- Inline HTML --
        private static readonly Dictionary<string, string> MarkTags = new(StringComparer.OrdinalIgnoreCase)
        {
            ["strong"] = "strong", ["b"] = "strong", ["em"] = "em", ["i"] = "em",
            ["s"] = "strike", ["del"] = "strike", ["strike"] = "strike", ["u"] = "underline", ["code"] = "code",
        };
        private static readonly HashSet<string> VoidContentTags = new(StringComparer.OrdinalIgnoreCase) { "script", "style" };
        private static readonly Dictionary<string, string> NamedEntities = new(StringComparer.OrdinalIgnoreCase)
        {
            ["amp"] = "&", ["lt"] = "<", ["gt"] = ">", ["quot"] = "\"", ["apos"] = "'", ["nbsp"] = " ",
            ["ndash"] = "–", ["mdash"] = "—", ["hellip"] = "…",
            ["lsquo"] = "‘", ["rsquo"] = "’", ["ldquo"] = "“", ["rdquo"] = "”",
        };

        public static string DecodeHtmlEntities(string? text) => Regex.Replace(text ?? string.Empty,
            "&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);", m =>
            {
                var entity = m.Groups[1].Value;
                if (entity[0] == '#')
                {
                    var isHex = entity.Length > 1 && (entity[1] == 'x' || entity[1] == 'X');
                    var ok = int.TryParse(isHex ? entity.Substring(2) : entity.Substring(1),
                        isHex ? NumberStyles.HexNumber : NumberStyles.Integer, CultureInfo.InvariantCulture, out var cp);
                    return ok && cp > 0 ? char.ConvertFromUtf32(cp) : m.Value;
                }
                return NamedEntities.TryGetValue(entity, out var named) ? named : m.Value;
            });

        private static readonly Regex TagPattern = new("<(/?)([a-zA-Z][a-zA-Z0-9]*)\\b[^>]*>");

        private static List<InlineNode> ParseInlineHtml(string? html)
        {
            var source = html ?? string.Empty;
            var root = new InlineNode();
            var stack = new List<InlineNode> { root };
            var buffer = new StringBuilder();
            string? skipUntil = null;

            void Flush()
            {
                if (buffer.Length == 0) return;
                stack[^1].Children.Add(new InlineNode { Type = "text", Value = DecodeHtmlEntities(buffer.ToString()) });
                buffer.Clear();
            }

            var cursor = 0;
            foreach (Match match in TagPattern.Matches(source))
            {
                var isClosing = match.Groups[1].Value == "/";
                var name = match.Groups[2].Value.ToLowerInvariant();
                var tag = match.Value;

                if (skipUntil is not null)
                {
                    cursor = match.Index + match.Length;
                    if (isClosing && name == skipUntil) skipUntil = null;
                    continue;
                }

                buffer.Append(source.Substring(cursor, match.Index - cursor));
                cursor = match.Index + match.Length;

                if (VoidContentTags.Contains(name))
                {
                    if (!isClosing && !tag.EndsWith("/>", StringComparison.Ordinal)) skipUntil = name;
                    continue;
                }
                if (name == "br")
                {
                    Flush();
                    stack[^1].Children.Add(new InlineNode { Type = "text", Value = "\n" });
                    continue;
                }
                if (!MarkTags.TryGetValue(name, out var type)) continue;

                if (isClosing)
                {
                    for (var i = stack.Count - 1; i > 0; i--)
                    {
                        if (stack[i].Type == type) { Flush(); stack.RemoveRange(i, stack.Count - i); break; }
                    }
                    continue;
                }
                if (tag.EndsWith("/>", StringComparison.Ordinal)) continue;

                Flush();
                var node = new InlineNode { Type = type };
                stack[^1].Children.Add(node);
                stack.Add(node);
            }
            if (skipUntil is null) buffer.Append(source.Substring(cursor));
            Flush();
            return root.Children;
        }

        // The light check/cross marks (✓ ✗) have no colour Twemoji asset, so they are mapped to the same
        // [Pass]/[Fail] tokens the fixed reports use, which then promote to a colour glyph. Every other
        // status emoji (✅ ❌ 🔴 🟠 🟡 🟢 ...) has a Twemoji image and is left for Sanitize/the renderer to
        // draw in colour. Also strips the VS16 emoji-style variation selector.
        private static readonly (string from, string to)[] GlyphMap =
        {
            ("✓", "[Pass]"), ("✗", "[Fail]"),
            ("️", ""),
        };

        // The three report emoji: warning ⚠, the green white-heavy-check ✅ (the client's pass indicator),
        // and info ℹ. They render as colour Twemoji images, or fall back to the monochrome font tinted to
        // their brand colour. Kept verbatim rather than mapped to a token, and are the tokens' promotion
        // targets. (The plain heavy check ✔ (U+2714) is Twemoji's dark check, so ✅ is used for "pass".)
        public const char EmojiWarning = '⚠';
        public const char EmojiCheck = '✅';
        public const char EmojiInfo = 'ℹ';
        private static readonly HashSet<char> EmojiKept = new() { EmojiWarning, EmojiCheck, EmojiInfo };

        // The monochrome fallback font ships next to the assembly as emoji-fallback.ttf (like the OfficeIMO
        // DLLs). Loaded once; absence just means emoji degrade to the ASCII tokens rather than throwing.
        internal static readonly Lazy<byte[]?> EmojiFontBytes = new(() =>
        {
            try
            {
                var dir = System.IO.Path.GetDirectoryName(typeof(ReportMarkdown).Assembly.Location);
                if (string.IsNullOrEmpty(dir)) return null;
                var path = System.IO.Path.Combine(dir, "emoji-fallback.ttf");
                return System.IO.File.Exists(path) ? System.IO.File.ReadAllBytes(path) : null;
            }
            catch { return null; }
        });

        // Exactly the code points the bundled font can draw above U+00FF, minus the CP1252 specials the
        // standard fonts render: the single source of truth for what Sanitize keeps (keeping one the font
        // can't draw would make OfficeIMO's encoding preflight throw) and which ranges ReportPdf declares
        // for the fallback. Read once from the font's own cmap so the two never drift; empty without a font.
        private static readonly Lazy<HashSet<int>> EmojiCoverageSet = new(() =>
        {
            var set = new HashSet<int>();
            var font = EmojiFontBytes.Value;
            if (font is not { Length: > 0 }) return set;
            try
            {
                foreach (var cp in FontCmap.ReadCodepoints(font))
                    if (cp > 0xFF && !IsWinAnsiSpecial(cp)) set.Add(cp);
            }
            catch { set.Clear(); }
            return set;
        });
        public static HashSet<int> EmojiCoverage => EmojiCoverageSet.Value;

        // With the fallback font bundled, the reports' portable ASCII status tokens are promoted to the
        // matching glyph (rendered downstream); without it they stay as tokens, so the report degrades.
        public static bool RenderEmojiGlyphs => EmojiFontBytes.Value is { Length: > 0 };

        // True when the bundled Twemoji colour PNG set is present, so an emoji grapheme cluster (including
        // multi-code-point ZWJ sequences, flags and skin tones) is kept whole for the renderer to place as
        // an inline colour image; the monochrome font remains the fallback for anything not bundled.
        public static bool RenderEmojiImages => TwemojiAssets.Enabled;
        private static readonly (string token, string glyph)[] EmojiTokens =
        {
            ("[!]", "⚠"), ("[Pass]", "✅"), ("[Fail]", "❌"), ("[i]", "ℹ"),
        };

        // CP1252 / WinAnsi code points above U+00FF that the PDF standard fonts CAN encode - kept as-is.
        private static readonly HashSet<char> WinAnsiSpecials = new(new[]
        {
            '€','‚','ƒ','„','…','†','‡','ˆ','‰','Š',
            '‹','Œ','Ž','‘','’','“','”','•','–','—',
            '˜','™','š','›','œ','ž','Ÿ',
        });

        // A CP1252 special (rendered by the standard fonts) rather than an emoji - excluded from the
        // fallback coverage so normal punctuation like — or ™ never routes to the emoji font.
        public static bool IsWinAnsiSpecial(int cp) => cp >= 0 && cp <= 0xFFFF && WinAnsiSpecials.Contains((char)cp);

        /// <summary>
        /// Make text safe for the PDF standard fonts (WinAnsi): map the colour-coded status emoji to ASCII
        /// tokens (a monochrome filled circle can't tell red from green), then keep anything the fonts can
        /// draw - at or below U+00FF, the CP1252 punctuation set, or, when a fallback font is bundled, an
        /// emoji that font actually carries (BMP or astral). Any remaining non-encodable character becomes
        /// '?' so OfficeIMO's encoding preflight never throws.
        /// </summary>
        public static string Sanitize(string? s)
        {
            if (string.IsNullOrEmpty(s)) return s ?? string.Empty;
            foreach (var g in GlyphMap) s = s.Replace(g.from, g.to);
            if (RenderEmojiGlyphs) foreach (var e in EmojiTokens) s = s.Replace(e.token, e.glyph);
            var needsFilter = false;
            foreach (var c in s) { if (c > 'ÿ' && !WinAnsiSpecials.Contains(c) && !EmojiKept.Contains(c)) { needsFilter = true; break; } }
            if (!needsFilter) return s;
            var sb = new StringBuilder(s.Length);
            // Walk by grapheme cluster so a multi-code-point emoji (ZWJ sequence, flag, skin-tone) is judged
            // and kept as one unit for the colour-image renderer; plain text falls through to the per-code-
            // point keep rule (WinAnsi, CP1252 specials, or a code point the monochrome fallback font draws).
            var elements = System.Globalization.StringInfo.GetTextElementEnumerator(s);
            while (elements.MoveNext())
            {
                var cluster = (string)elements.Current;
                if (cluster.Length == 1 && cluster[0] <= 'ÿ') { sb.Append(cluster); continue; }
                if (RenderEmojiImages && TwemojiAssets.Has(cluster)) { sb.Append(cluster); continue; }
                for (var i = 0; i < cluster.Length; i++)
                {
                    var c = cluster[i];
                    if (char.IsHighSurrogate(c) && i + 1 < cluster.Length && char.IsLowSurrogate(cluster[i + 1]))
                    {
                        var cp = char.ConvertToUtf32(c, cluster[i + 1]);
                        if (RenderEmojiGlyphs && EmojiCoverage.Contains(cp)) { sb.Append(c); sb.Append(cluster[i + 1]); }
                        i++; // the low surrogate was consumed with its high half
                        continue;
                    }
                    if (c <= 'ÿ' || WinAnsiSpecials.Contains(c) || EmojiKept.Contains(c) || (RenderEmojiGlyphs && EmojiCoverage.Contains(c)))
                        sb.Append(c);
                    else if (!char.IsHighSurrogate(c) && !char.IsLowSurrogate(c))
                        sb.Append('?');
                    // a lone surrogate (no matching half) is dropped
                }
            }
            return sb.ToString();
        }

        // -- Flatten to runs --
        private static List<TextRun> Flatten(List<InlineNode> nodes)
        {
            var runs = new List<TextRun>();
            void Walk(List<InlineNode> ns, TextRun marks)
            {
                foreach (var n in ns)
                {
                    if (n.Type == "text")
                    {
                        if (n.Value.Length == 0) continue;
                        var r = marks.Clone(); r.Text = Sanitize(n.Value); runs.Add(r);
                        continue;
                    }
                    var next = marks.Clone();
                    switch (n.Type)
                    {
                        case "strong": next.Bold = true; break;
                        case "em": next.Italic = true; break;
                        case "strongEm": next.Bold = true; next.Italic = true; break;
                        case "code": next.Code = true; break;
                        case "strike": next.Strike = true; break;
                        case "underline": next.Underline = true; break;
                    }
                    Walk(n.Children, next);
                }
            }
            Walk(nodes, new TextRun());
            return runs;
        }

        private static string PlainText(List<InlineNode> nodes)
        {
            var sb = new StringBuilder();
            void Walk(List<InlineNode> ns) { foreach (var n in ns) { if (n.Type == "text") sb.Append(Sanitize(n.Value)); else Walk(n.Children); } }
            Walk(nodes);
            return sb.ToString();
        }

        public static List<TextRun> MarkdownRuns(string? text) => Flatten(ParseInlineMarkdown(text));
        public static List<TextRun> HtmlRuns(string? html) => Flatten(ParseInlineHtml(html));
        public static string MarkdownPlain(string? text) => PlainText(ParseInlineMarkdown(text));
        public static string HtmlPlain(string? html) => PlainText(ParseInlineHtml(html));

        // -- Table rows (markdown-table.js) --
        private static readonly Regex SeparatorRow = new("^\\|?[\\s:|-]*-[\\s:|-]*\\|?$");

        public static bool IsTableSeparatorRow(string? line)
        {
            var t = (line ?? string.Empty).Trim();
            if (!t.Contains('|') || !t.Contains('-')) return false;
            return SeparatorRow.IsMatch(t);
        }

        public static List<string> ParseTableRow(string? line)
        {
            var raw = (line ?? string.Empty).Trim();
            var cells = new List<string>();
            if (raw.Length == 0) return cells;
            var current = new StringBuilder();
            var leading = false; var trailing = false;
            for (var i = 0; i < raw.Length; i++)
            {
                var ch = raw[i];
                var next = i + 1 < raw.Length ? raw[i + 1] : '\0';
                if (ch == '\\' && (next == '|' || next == '\\')) { current.Append(next); i++; continue; }
                if (ch == '|')
                {
                    if (i == 0) leading = true;
                    if (i == raw.Length - 1) trailing = true;
                    cells.Add(current.ToString()); current.Clear(); continue;
                }
                current.Append(ch);
            }
            cells.Add(current.ToString());
            if (leading && cells.Count > 0) cells.RemoveAt(0);
            if (trailing && cells.Count > 0) cells.RemoveAt(cells.Count - 1);
            for (var i = 0; i < cells.Count; i++) cells[i] = Sanitize(cells[i].Trim());
            return cells;
        }

        public static string[] NormaliseTableRow(List<string> cells, int columnCount)
        {
            if (columnCount <= 0) return Array.Empty<string>();
            if (cells.Count == columnCount) return cells.ToArray();
            if (cells.Count < columnCount)
            {
                var padded = new string[columnCount];
                for (var i = 0; i < columnCount; i++) padded[i] = i < cells.Count ? cells[i] : string.Empty;
                return padded;
            }
            var head = cells.GetRange(0, columnCount - 1);
            head.Add(string.Join(" | ", cells.GetRange(columnCount - 1, cells.Count - (columnCount - 1))));
            return head.ToArray();
        }

        // -- Block markdown -> nodes (markdownToElements) --
        public static List<ReportNode> MarkdownToNodes(string? markdown)
        {
            var elements = new List<ReportNode>();
            if (string.IsNullOrEmpty(markdown)) return elements;
            var lines = markdown.Replace("\r\n", "\n").Split('\n');

            var inCode = false; var code = new StringBuilder();
            var inTable = false; var tableRows = new List<List<string>>();

            void FlushTable()
            {
                if (tableRows.Count > 0)
                {
                    var cols = tableRows[0].Count;
                    var rows = new List<string[]>();
                    foreach (var r in tableRows) rows.Add(NormaliseTableRow(r, cols));
                    var node = new ReportNode("table"); node.Set("rows", rows); node.Set("hasHeader", true);
                    elements.Add(node);
                }
                inTable = false; tableRows = new List<List<string>>();
            }

            // Consecutive list items are grouped into one bullets/numbered node.
            List<string>? listItems = null; var listOrdered = false; var listStart = 1;
            void FlushList()
            {
                if (listItems is { Count: > 0 })
                {
                    var node = new ReportNode(listOrdered ? "numbered" : "bullets");
                    node.Set("items", new List<string>(listItems));
                    if (listOrdered) node.Set("start", (double)listStart);
                    elements.Add(node);
                }
                listItems = null;
            }

            foreach (var raw in lines)
            {
                var line = raw;
                var trimmed = line.Trim();

                if (trimmed.StartsWith("```", StringComparison.Ordinal))
                {
                    if (inCode)
                    {
                        FlushList();
                        elements.Add(new ReportNode("code").Set("text", code.ToString().TrimEnd()));
                        code.Clear(); inCode = false;
                    }
                    else { FlushList(); inCode = true; }
                    continue;
                }
                if (inCode) { code.Append(line).Append('\n'); continue; }

                if (trimmed.StartsWith("|", StringComparison.Ordinal))
                {
                    FlushList();
                    if (!inTable) { inTable = true; tableRows = new List<List<string>>(); }
                    if (IsTableSeparatorRow(line)) continue;
                    tableRows.Add(ParseTableRow(line));
                    continue;
                }
                if (inTable) FlushTable();

                if (trimmed.Length == 0) { FlushList(); continue; }

                if (line.StartsWith("### ", StringComparison.Ordinal)) { FlushList(); elements.Add(Heading(3, line.Substring(4), false)); }
                else if (line.StartsWith("## ", StringComparison.Ordinal)) { FlushList(); elements.Add(Heading(2, line.Substring(3), false)); }
                else if (line.StartsWith("# ", StringComparison.Ordinal)) { FlushList(); elements.Add(Heading(1, line.Substring(2), false)); }
                else if (Regex.IsMatch(trimmed, "^[-*_]{3,}$")) { FlushList(); elements.Add(new ReportNode("hr")); }
                else if (Regex.IsMatch(trimmed, "^[-*+]\\s"))
                {
                    if (listItems is null || listOrdered) { FlushList(); listItems = new List<string>(); listOrdered = false; }
                    listItems.Add(MarkdownPlain(Regex.Replace(trimmed, "^[-*+]\\s", string.Empty)));
                }
                else if (Regex.IsMatch(trimmed, "^\\d+\\.\\s"))
                {
                    var num = int.Parse(Regex.Match(trimmed, "^(\\d+)\\.").Groups[1].Value, CultureInfo.InvariantCulture);
                    if (listItems is null || !listOrdered) { FlushList(); listItems = new List<string>(); listOrdered = true; listStart = num; }
                    listItems.Add(MarkdownPlain(Regex.Replace(trimmed, "^\\d+\\.\\s", string.Empty)));
                }
                else { FlushList(); elements.Add(Paragraph(MarkdownRuns(line))); }
            }
            if (inCode && code.Length > 0) elements.Add(new ReportNode("code").Set("text", code.ToString().TrimEnd()));
            if (inTable) FlushTable();
            FlushList();
            return elements;
        }

        // -- Block HTML -> nodes (htmlToElements) --
        public static List<ReportNode> HtmlToNodes(string? html)
        {
            var elements = new List<ReportNode>();
            if (string.IsNullOrEmpty(html)) return elements;

            // Extract tables first, replacing each with a placeholder paragraph.
            var tables = new List<string>();
            var remaining = Regex.Replace(html, "<table[^>]*>([\\s\\S]*?)</table>", m =>
            {
                var placeholder = $"__TABLE_{tables.Count}__"; tables.Add(m.Value); return $"<p>{placeholder}</p>";
            }, RegexOptions.IgnoreCase);

            var blocks = Regex.Split(remaining, "</p>|</h[1-6]>|</li>|</pre>|</blockquote>|<br\\s*/?>");
            var inOrdered = false; var orderedIndex = 0;

            // Group consecutive <li> into one list node.
            List<string>? listItems = null; var listOrdered = false; var listStart = 1;
            void FlushList()
            {
                if (listItems is { Count: > 0 })
                {
                    var node = new ReportNode(listOrdered ? "numbered" : "bullets");
                    node.Set("items", new List<string>(listItems));
                    if (listOrdered) node.Set("start", (double)listStart);
                    elements.Add(node);
                }
                listItems = null;
            }

            foreach (var block in blocks)
            {
                var cleaned = block.Trim();
                if (cleaned.Length == 0) continue;

                if (Regex.IsMatch(cleaned, "<ol[\\s>]", RegexOptions.IgnoreCase)) { inOrdered = true; orderedIndex = 0; }
                else if (Regex.IsMatch(cleaned, "<ul[\\s>]", RegexOptions.IgnoreCase)) inOrdered = false;

                var tableMatch = Regex.Match(cleaned, "__TABLE_(\\d+)__");
                if (tableMatch.Success)
                {
                    FlushList();
                    var idx = int.Parse(tableMatch.Groups[1].Value, CultureInfo.InvariantCulture);
                    if (idx < tables.Count) elements.Add(HtmlTable(tables[idx]));
                    continue;
                }

                if (Regex.IsMatch(cleaned, "<h1[^>]*>", RegexOptions.IgnoreCase)) { FlushList(); elements.Add(Heading(1, Regex.Replace(cleaned, "<h1[^>]*>", string.Empty, RegexOptions.IgnoreCase), true)); }
                else if (Regex.IsMatch(cleaned, "<h2[^>]*>", RegexOptions.IgnoreCase)) { FlushList(); elements.Add(Heading(2, Regex.Replace(cleaned, "<h2[^>]*>", string.Empty, RegexOptions.IgnoreCase), true)); }
                else if (Regex.IsMatch(cleaned, "<h3[^>]*>", RegexOptions.IgnoreCase)) { FlushList(); elements.Add(Heading(3, Regex.Replace(cleaned, "<h3[^>]*>", string.Empty, RegexOptions.IgnoreCase), true)); }
                else if (Regex.IsMatch(cleaned, "<li[^>]*>", RegexOptions.IgnoreCase))
                {
                    if (inOrdered) orderedIndex++;
                    if (listItems is null || listOrdered != inOrdered) { FlushList(); listItems = new List<string>(); listOrdered = inOrdered; listStart = inOrdered ? orderedIndex : 1; }
                    listItems.Add(HtmlPlain(Regex.Replace(cleaned, "<li[^>]*>", string.Empty, RegexOptions.IgnoreCase)));
                }
                else if (Regex.IsMatch(cleaned, "<pre[^>]*>", RegexOptions.IgnoreCase))
                {
                    FlushList();
                    var inner = Regex.Replace(Regex.Replace(cleaned, "<pre[^>]*>", string.Empty, RegexOptions.IgnoreCase), "<code[^>]*>", string.Empty, RegexOptions.IgnoreCase);
                    elements.Add(new ReportNode("code").Set("text", HtmlPlain(inner)));
                }
                else
                {
                    var inner = Regex.Replace(cleaned, "<p[^>]*>", string.Empty, RegexOptions.IgnoreCase);
                    if (HtmlPlain(inner).Trim().Length > 0) { FlushList(); elements.Add(Paragraph(HtmlRuns(inner))); }
                }

                if (Regex.IsMatch(cleaned, "</(ol|ul)>", RegexOptions.IgnoreCase)) { FlushList(); inOrdered = false; }
            }
            FlushList();
            return elements;
        }

        private static ReportNode HtmlTable(string tableHtml)
        {
            var rows = new List<string[]>();
            var rowHeaderFlags = new List<bool>();
            foreach (Match rowMatch in Regex.Matches(tableHtml, "<tr[^>]*>([\\s\\S]*?)</tr>", RegexOptions.IgnoreCase))
            {
                var cells = new List<string>();
                var allHeader = true;
                foreach (Match cellMatch in Regex.Matches(rowMatch.Groups[1].Value, "<(td|th)[^>]*>([\\s\\S]*?)</(?:td|th)>", RegexOptions.IgnoreCase))
                {
                    if (!cellMatch.Groups[1].Value.Equals("th", StringComparison.OrdinalIgnoreCase)) allHeader = false;
                    cells.Add(HtmlPlain(cellMatch.Groups[2].Value.Trim()));
                }
                if (cells.Count > 0) { rows.Add(cells.ToArray()); rowHeaderFlags.Add(allHeader); }
            }
            var hasHeader = Regex.IsMatch(tableHtml, "<thead", RegexOptions.IgnoreCase) || (rowHeaderFlags.Count > 0 && rowHeaderFlags[0]);
            var cols = rows.Count > 0 ? rows[0].Length : 0;
            var normalised = new List<string[]>();
            foreach (var r in rows) normalised.Add(NormaliseTableRow(new List<string>(r), cols));
            var node = new ReportNode("table"); node.Set("rows", normalised); node.Set("hasHeader", hasHeader);
            return node;
        }

        private static ReportNode Heading(int level, string text, bool html)
            => new ReportNode("heading").Set("level", (double)level)
                .Set("runs", html ? HtmlRuns(text) : MarkdownRuns(text));

        private static ReportNode Paragraph(List<TextRun> runs) => new ReportNode("paragraph").Set("runs", runs);
    }
}
