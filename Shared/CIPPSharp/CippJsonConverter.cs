using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.Json;

namespace CIPP
{
    /// <summary>
    /// Fast JSON -> PowerShell converter for the CippReportingDB read path, replacing
    /// `ConvertFrom-Json` in New-CIPPDbRequest.
    ///
    /// COMPATIBILITY: reproduces ConvertFrom-Json's observable semantics, because every caller
    /// depends on them and any divergence fails *silently*:
    ///   - PSCustomObject records, so `$x[0]`, `$x.Count` and `$x.PSObject.Properties` all keep
    ///     the scalar semantics callers rely on. Hashtable output is cheaper but changes those,
    ///     and only when a pipeline yields exactly one record — do not switch.
    ///   - ISO-8601-looking strings become [DateTime] (tests compare these against [datetime]).
    ///   - Every integer becomes Int64 regardless of magnitude (never Int32).
    /// Matching these costs nothing measurable, so there is no reason to ship divergence.
    ///
    /// PERFORMANCE: without a field list this is modestly faster and allocates less than
    /// ConvertFrom-Json, but retains the SAME live bytes — the parser was never the memory cost.
    /// The memory win comes from <paramref name="fields"/>: not materializing unread fields.
    /// </summary>
    public static class CippJson
    {
        private static readonly JsonDocumentOptions Opts = new JsonDocumentOptions { MaxDepth = 1024 };

        /// <summary>Convert a JSON document, materializing every field.</summary>
        public static object? ConvertFromJson(string json) => ConvertFromJson(json, null);

        /// <summary>
        /// Convert a JSON document, keeping only <paramref name="fields"/> on each RECORD.
        ///
        /// Projection applies at the record level only: for an object root, the root's own fields;
        /// for an array root, each element's own fields. A field that is kept keeps its ENTIRE
        /// subtree — projection never reaches inside a retained value. Null/empty keeps everything.
        ///
        /// The saving therefore scales with how much of the record is dropped: large for
        /// scalar-only field sets, small when a kept subtree is most of the payload.
        /// </summary>
        public static object? ConvertFromJson(string json, string[]? fields)
        {
            if (string.IsNullOrEmpty(json)) return null;

            HashSet<string>? keep = (fields != null && fields.Length > 0)
                ? new HashSet<string>(fields, StringComparer.OrdinalIgnoreCase)
                : null;

            using var doc = JsonDocument.Parse(json, Opts);
            var root = doc.RootElement;

            // Records live at the root, or one level down if the root is an array.
            if (root.ValueKind == JsonValueKind.Array)
            {
                var rows = new List<object?>();
                foreach (var item in root.EnumerateArray()) rows.Add(ReadRecord(item, keep));
                return rows.ToArray();
            }

            return ReadRecord(root, keep);
        }

        /// <summary>A record: the one level at which projection applies.</summary>
        private static object? ReadRecord(JsonElement el, HashSet<string>? keep)
        {
            if (el.ValueKind != JsonValueKind.Object) return ReadValue(el);

            var pso = new PSObject();
            foreach (var p in el.EnumerateObject())
            {
                // Skipped fields are never materialized — this is the whole point of projection.
                if (keep != null && !keep.Contains(p.Name)) continue;
                pso.Properties.Add(new PSNoteProperty(p.Name, ReadValue(p.Value)));  // kept => whole subtree
            }
            return pso;
        }

        /// <summary>Everything below the record level: materialized in full.</summary>
        private static object? ReadValue(JsonElement el)
        {
            switch (el.ValueKind)
            {
                case JsonValueKind.Object:
                    var pso = new PSObject();
                    foreach (var p in el.EnumerateObject())
                        pso.Properties.Add(new PSNoteProperty(p.Name, ReadValue(p.Value)));
                    return pso;

                case JsonValueKind.Array:
                    var list = new List<object?>();
                    foreach (var item in el.EnumerateArray()) list.Add(ReadValue(item));
                    return list.ToArray();

                case JsonValueKind.String:
                    // ConvertFrom-Json coerces ISO-8601 strings to DateTime; matching that keeps
                    // date comparisons in tests behaving as they do today.
                    return el.TryGetDateTime(out var dt) ? dt : (object?)el.GetString();

                case JsonValueKind.True:  return true;
                case JsonValueKind.False: return false;
                case JsonValueKind.Null:  return null;

                case JsonValueKind.Number:
                    // ConvertFrom-Json yields Int64 for all integers — never narrow to Int32.
                    if (el.TryGetInt64(out long l)) return l;
                    return el.GetDouble();

                default: return null;
            }
        }
    }
}
