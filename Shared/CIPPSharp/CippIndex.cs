using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace CIPP
{
    /// <summary>
    /// Key -> items lookups for PowerShell callers. The keys of each item are computed in PowerShell;
    /// inserting them here avoids an interpreted loop per key (44k group memberships: 3.4s and 233 MB in
    /// PowerShell, 26 ms and 3 MB here). Find/Has/AddItem avoid PowerShell's slow TryGetValue([ref]).
    /// </summary>
    public sealed class CippIndex : Dictionary<string, List<object?>>
    {
        private readonly string _nullKey;

        private CippIndex(string nullKey) : base(StringComparer.OrdinalIgnoreCase) { _nullKey = nullKey; }

        /// <summary>
        /// Index <paramref name="items"/> by <paramref name="keySets"/> (one entry per item: a key, a collection
        /// of keys, or null). Matches the PowerShell builder it replaces: items and key collections are
        /// enumerated the way foreach does, keys convert to string as [string] does, keys compare
        /// case-insensitively, a null key is stored under <paramref name="nullKey"/>, and an item is listed once
        /// per key, in input order.
        /// </summary>
        public static CippIndex Build(object? items, object?[] keySets, string nullKey = "\0")
        {
            var list = new List<object?>();
            if (items is not null)
            {
                var sequence = LanguagePrimitives.GetEnumerable(items);
                if (sequence is null) list.Add(items);
                else foreach (var item in sequence) list.Add(item);
            }
            if (list.Count != keySets.Length)
                throw new ArgumentException("items and keySets must have the same length");

            var index = new CippIndex(nullKey);
            for (var i = 0; i < list.Count; i++)
            {
                var keys = keySets[i];
                foreach (var key in LanguagePrimitives.GetEnumerable(keys) ?? new[] { keys })
                    index.AddItem(key, list[i]);
            }
            return index;
        }

        private string Name(object? key) => key is null ? _nullKey : LanguagePrimitives.ConvertTo<string>(key);

        /// <summary>Add <paramref name="item"/> under <paramref name="key"/> unless it is already the last item there.</summary>
        public void AddItem(object? key, object? item)
        {
            var name = Name(key);
            if (!TryGetValue(name, out var list))
            {
                list = new List<object?>();
                this[name] = list;
            }
            if (list.Count == 0 || !ReferenceEquals(list[list.Count - 1], item))
                list.Add(item);
        }

        /// <summary>The items under <paramref name="key"/> as PowerShell output would unroll them: nothing, the one item, or an array.</summary>
        public object? Find(object? key)
        {
            if (!TryGetValue(Name(key), out var list) || list.Count == 0) return System.Management.Automation.Internal.AutomationNull.Value;
            return list.Count == 1 ? list[0] : list.ToArray();
        }

        public bool Has(object? key) => ContainsKey(Name(key));
    }
}
