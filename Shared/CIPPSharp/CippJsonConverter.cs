using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Text.Json;
using Newtonsoft.Json;

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

        /// <summary>
        /// One string field of each record (array root) or of the record (object root), without building
        /// the records: what `@((ConvertFromJson $json).field)` gives when every value is a plain string.
        /// A missing or null value is null. Returns null when that is not exact (a value that is not a string,
        /// a string ConvertFrom-Json reads as a date, a non-object record or a repeated field), so the caller
        /// can fall back to ConvertFromJson.
        /// </summary>
        public static string?[]? ReadStringField(string json, string field)
        {
            if (string.IsNullOrEmpty(json)) return null;
            using var doc = JsonDocument.Parse(json, Opts);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Array)
                return TryReadStringField(root, field, out var one) ? new[] { one } : null;

            var values = new string?[root.GetArrayLength()];
            int i = 0;
            foreach (var item in root.EnumerateArray())
                if (!TryReadStringField(item, field, out values[i++])) return null;
            return values;
        }

        private static bool TryReadStringField(JsonElement record, string field, out string? value)
        {
            value = null;
            if (record.ValueKind != JsonValueKind.Object) return false;
            bool found = false;
            foreach (var p in record.EnumerateObject())
            {
                if (!string.Equals(p.Name, field, StringComparison.OrdinalIgnoreCase)) continue;
                if (found) return false;
                found = true;
                if (p.Value.ValueKind == JsonValueKind.Null) continue;
                if (p.Value.ValueKind != JsonValueKind.String || ReadString(p.Value) is not string s) return false;
                value = s;
            }
            return true;
        }

        /// <summary>
        /// A JSON string as ConvertFrom-Json reads it: ISO-8601 and "/Date(ms)/" values become DateTime. Newtonsoft
        /// only tries strings of 19-40 chars with a 'T' at index 10, so date-only and minute-precision values stay strings.
        /// </summary>
        private static object ReadString(JsonElement el)
        {
            var s = el.GetString()!;
            if (s.Length >= 19 && s.Length <= 40 && char.IsDigit(s[0]) && s[10] == 'T' && el.TryGetDateTime(out var dt)) return dt;
            return TryParseMicrosoftDate(s, out var msDate) ? msDate : s;
        }

        /// <summary>Newtonsoft's "/Date(ms[+-hhmm])/": UTC, or local time when an offset is present.</summary>
        private static bool TryParseMicrosoftDate(string s, out DateTime value)
        {
            value = default;
            if (s.Length < 9 || !s.StartsWith("/Date(", StringComparison.Ordinal) || !s.EndsWith(")/", StringComparison.Ordinal)) return false;
            var inner = s.AsSpan(6, s.Length - 8);
            int sign = inner.Length > 1 ? inner.Slice(1).IndexOfAny('+', '-') : -1;
            var ms = sign >= 0 ? inner.Slice(0, sign + 1) : inner;
            if (!long.TryParse(ms, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out long millis)) return false;
            if (sign >= 0)
            {
                var offset = inner.Slice(sign + 1);
                if (offset.Length != 5 || !int.TryParse(offset.Slice(1), NumberStyles.None, CultureInfo.InvariantCulture, out _)) return false;
            }
            DateTime utc;
            try { utc = DateTime.UnixEpoch.AddMilliseconds(millis); } catch (ArgumentOutOfRangeException) { return false; }
            value = sign >= 0 ? utc.ToLocalTime() : utc;
            return true;
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
                    return ReadString(el);

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

        /// <summary>
        /// Serializes like `ConvertTo-Json -InputObject $value -Depth $depth -Compress`, for the values
        /// ConvertFrom-Json and PowerShell-built rows hold: PSCustomObject, IDictionary, IList, string,
        /// bool, numbers, DateTime, Guid, enums and null. Returns null for anything else, or anything
        /// nested deeper than depth, so the caller can fall back to ConvertTo-Json.
        /// </summary>
        public static string? ToJson(object? value, int depth = 100)
        {
            var sw = new StringWriter(CultureInfo.InvariantCulture);
            using (var w = new JsonTextWriter(sw) { Formatting = Formatting.None })
            {
                if (!TryWrite(w, value, depth)) return null;
            }
            return sw.ToString();
        }

        private static bool TryWrite(JsonTextWriter w, object? v, int depth)
        {
            // An empty pipeline assigned to a variable holds AutomationNull, which ConvertTo-Json writes as null
            if (ReferenceEquals(v, System.Management.Automation.Internal.AutomationNull.Value)) { w.WriteNull(); return true; }
            if (v is PSObject pso)
            {
                if (pso.BaseObject is PSCustomObject)
                {
                    if (depth < 0) return false;
                    w.WriteStartObject();
                    foreach (var p in pso.Properties)
                    {
                        object? pv;
                        try { pv = p.Value; } catch { return false; }
                        w.WritePropertyName(p.Name);
                        if (!TryWrite(w, pv, depth - 1)) return false;
                    }
                    w.WriteEndObject();
                    return true;
                }
                // ConvertTo-Json ignores note properties on strings and dates only; anything else with
                // them is written as {"value":...}. Members is not enumerated: that builds every adapted member.
                var baseObject = pso.BaseObject;
                if (!(baseObject is string || baseObject is DateTime)
                    && pso.Properties.Match("*", PSMemberTypes.NoteProperty).Count > 0) return false;
                v = baseObject;
            }

            switch (v)
            {
                case null: w.WriteNull(); return true;
                case string s: w.WriteValue(s); return true;
                case bool b: w.WriteValue(b); return true;
                case long l: w.WriteValue(l); return true;
                case int i: w.WriteValue(i); return true;
                case double d: w.WriteValue(d); return true;
                case decimal m: w.WriteValue(m); return true;
                case DateTime dt: w.WriteValue(dt); return true;
                case Guid g: w.WriteValue(g.ToString()); return true;
                case Enum e: w.WriteValue(Convert.ToInt64(e, CultureInfo.InvariantCulture)); return true;
                case IDictionary dict:
                    if (depth < 0) return false;
                    w.WriteStartObject();
                    foreach (DictionaryEntry e in dict)
                    {
                        w.WritePropertyName(e.Key.ToString() ?? string.Empty);
                        if (!TryWrite(w, e.Value, depth - 1)) return false;
                    }
                    w.WriteEndObject();
                    return true;
                case IList list:
                    if (depth < 0) return false;
                    w.WriteStartArray();
                    foreach (var x in list)
                        if (!TryWrite(w, x, depth - 1)) return false;
                    w.WriteEndArray();
                    return true;
                default:
                    return false;
            }
        }
    }
}
