using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace CIPP
{
    /// <summary>
    /// Records a collection's field names and kinds, one nested level deep, for the '&lt;Type&gt;-Count' row Shape
    /// that Add-CIPPDbItem writes. Same rules as the PowerShell it replaces, without a script block call per field.
    /// </summary>
    public static class CippDbShape
    {
        private static readonly Regex IsoDate = new(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public static void Note(IDictionary fields, object? item, int maxFields)
        {
            foreach (var (name, value) in PropertiesOf(item))
            {
                var kind = NoteField(fields, name, value, maxFields);
                object? inner = null;
                if (kind == "object") inner = value;
                else if (kind == "array" && Unwrap(value) is IEnumerable items)
                    foreach (var first in items) { inner = first; break; }
                if (inner != null && KindOf(inner) == "object")
                    foreach (var (childName, childValue) in PropertiesOf(inner))
                        NoteField(fields, name + "." + childName, childValue, maxFields);
            }
        }

        // null when the field cap is reached for a new name: the caller then skips its children
        private static string? NoteField(IDictionary fields, string name, object? value, int maxFields)
        {
            if (fields.Count >= maxFields && !fields.Contains(name)) return null;
            var kind = KindOf(value);
            if (!fields.Contains(name) || string.Equals(fields[name]?.ToString(), "null", StringComparison.OrdinalIgnoreCase)) fields[name] = kind;
            return kind;
        }

        public static string KindOf(object? value)
        {
            if (value is PSObject pso && pso.BaseObject is PSCustomObject) return "object";
            value = Unwrap(value);
            switch (value)
            {
                case null: return "null";
                case bool: return "boolean";
                case DateTime: case DateTimeOffset: return "date";
                case string s: return IsoDate.IsMatch(s) ? "date" : "string";
                case decimal: return "number";
                case PSCustomObject: return "object";
            }
            if (value.GetType().IsPrimitive) return "number";
            if (value is IDictionary) return "object";
            if (value is IEnumerable) return "array";
            return "string";
        }

        private static object? Unwrap(object? value) => value is PSObject pso && pso.BaseObject is not PSCustomObject ? pso.BaseObject : value;

        private static IEnumerable<(string Name, object? Value)> PropertiesOf(object? value)
        {
            if (Unwrap(value) is IDictionary dict)
            {
                foreach (DictionaryEntry e in dict)
                    yield return (LanguagePrimitives.ConvertTo<string>(e.Key) ?? string.Empty, e.Value);
                yield break;
            }
            if (value is not PSObject pso || pso.BaseObject is not PSCustomObject) yield break;
            foreach (var p in PSMembers.Available ? PSMembers.InstanceProperties(pso) : pso.Properties)
            {
                object? v;
                try { v = p.Value; } catch { continue; }
                yield return (p.Name, v);
            }
        }
    }
}
