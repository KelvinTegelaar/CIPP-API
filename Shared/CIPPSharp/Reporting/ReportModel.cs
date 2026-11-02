using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json;

namespace CIPP.Reporting
{
    /// <summary>An inline run of text with its marks - the shared node the markdown and HTML parsers both emit.</summary>
    public sealed class TextRun
    {
        public string Text { get; set; } = string.Empty;
        public bool Bold { get; set; }
        public bool Italic { get; set; }
        public bool Code { get; set; }
        public bool Strike { get; set; }
        public bool Underline { get; set; }

        public TextRun Clone() => new()
        {
            Text = Text, Bold = Bold, Italic = Italic, Code = Code, Strike = Strike, Underline = Underline,
        };
    }

    /// <summary>
    /// One component in a report. The declarative unit every report composes and never bypasses:
    /// a type, its props, and optional children. Built either from the JSON component tree (Report
    /// Builder blocks / fixed-report output) or synthesised by the markdown/HTML parsers.
    /// </summary>
    public sealed class ReportNode
    {
        public string Type { get; set; } = string.Empty;
        public Dictionary<string, object?> Props { get; } = new(StringComparer.OrdinalIgnoreCase);
        public List<ReportNode> Children { get; } = new();

        public ReportNode() { }
        public ReportNode(string type) { Type = type; }

        public ReportNode Set(string key, object? value) { Props[key] = value; return this; }

        public string? Str(string key) => Props.TryGetValue(key, out var v) ? v as string : null;

        public bool Bool(string key, bool @default = false)
            => Props.TryGetValue(key, out var v) && v is bool b ? b : @default;

        public double? Num(string key)
            => Props.TryGetValue(key, out var v) && v is double d ? d : (double?)null;

        public T? Get<T>(string key) where T : class
            => Props.TryGetValue(key, out var v) ? v as T : null;

        public List<object?>? ListOf(string key)
            => Props.TryGetValue(key, out var v) ? v as List<object?> : null;

        // -- JSON parsing --
        public static List<ReportNode> ParseTree(string? json)
        {
            var result = new List<ReportNode>();
            if (string.IsNullOrWhiteSpace(json)) return result;
            JsonDocument doc;
            try { doc = JsonDocument.Parse(json); }
            catch { return result; }
            // Disposed once the tree is copied out, so its pooled buffers go back to the pool.
            using var _ = doc;
            var root = doc.RootElement;
            if (root.ValueKind == JsonValueKind.Array)
            {
                foreach (var el in root.EnumerateArray())
                    if (el.ValueKind == JsonValueKind.Object) result.Add(FromElement(el));
            }
            else if (root.ValueKind == JsonValueKind.Object)
            {
                result.Add(FromElement(root));
            }
            return result;
        }

        private static ReportNode FromElement(JsonElement el)
        {
            var node = new ReportNode
            {
                Type = el.TryGetProperty("type", out var t) && t.ValueKind == JsonValueKind.String
                    ? t.GetString()!.ToLowerInvariant()
                    : string.Empty,
            };
            foreach (var prop in el.EnumerateObject())
            {
                if (prop.NameEquals("type")) continue;
                if (prop.NameEquals("children") && prop.Value.ValueKind == JsonValueKind.Array)
                {
                    foreach (var child in prop.Value.EnumerateArray())
                        if (child.ValueKind == JsonValueKind.Object) node.Children.Add(FromElement(child));
                    continue;
                }
                node.Props[prop.Name] = Convert(prop.Value);
            }
            return node;
        }

        private static object? Convert(JsonElement el) => el.ValueKind switch
        {
            JsonValueKind.String => el.GetString(),
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.Number => el.TryGetDouble(out var d) ? d : 0d,
            JsonValueKind.Array => ConvertArray(el),
            JsonValueKind.Object => ConvertObject(el),
            _ => null,
        };

        private static List<object?> ConvertArray(JsonElement el)
        {
            var list = new List<object?>();
            foreach (var item in el.EnumerateArray()) list.Add(Convert(item));
            return list;
        }

        private static Dictionary<string, object?> ConvertObject(JsonElement el)
        {
            var dict = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            foreach (var p in el.EnumerateObject()) dict[p.Name] = Convert(p.Value);
            return dict;
        }

        /// <summary>Read a nested object's string field (for stats/chart/progress data rows).</summary>
        public static string? RowStr(object? row, string key)
            => row is Dictionary<string, object?> d && d.TryGetValue(key, out var v) ? v?.ToString() : null;

        public static double RowNum(object? row, string key)
        {
            if (row is Dictionary<string, object?> d && d.TryGetValue(key, out var v))
            {
                if (v is double dd) return dd;
                if (v is string s && double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var p)) return p;
            }
            return 0;
        }
    }
}
