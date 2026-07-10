using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;

namespace CIPP
{
    /// <summary>
    /// Host-scoped, thread-safe LRU cache for test data lookups. The DLL is
    /// loaded once per Azure Functions host, so every PowerShell worker
    /// process on that host shares this exact instance. Bounded by both a
    /// byte-size cap (default 300 MB) and a short TTL (default 5 minutes)
    /// so that test suites running against a single tenant get fast cache
    /// hits without accumulating stale Gen2 roots that cause GC thrashing.
    /// </summary>
    public static class TestDataCache
    {
        // ── Configuration ──
        // Defaults are 300 MB / 5 min. Both are overridable per deployment via
        // Azure Functions app settings (environment variables) resolved once at
        // load, or programmatically via Configure() for tests. The cap now maps to
        // real managed-heap bytes (see EstimateValueSize), so 300 MB means ~300 MB.
        private static long _maxBytes = 300L * 1024 * 1024;  // 300 MB default
        private static TimeSpan _ttl = TimeSpan.FromMinutes(5);

        static TestDataCache()
        {
            try
            {
                if (long.TryParse(Environment.GetEnvironmentVariable("CIPPTestCacheMaxMB"), out var maxMB) && maxMB > 0)
                    _maxBytes = maxMB * 1024L * 1024L;
                if (int.TryParse(Environment.GetEnvironmentVariable("CIPPTestCacheTtlSeconds"), out var ttlSec) && ttlSec > 0)
                    _ttl = TimeSpan.FromSeconds(ttlSec);
            }
            catch { /* keep defaults if app settings are unreadable */ }
        }

        // ── State ──
        private static readonly ConcurrentDictionary<string, CacheEntry> _cache = new();
        private static readonly LinkedList<string> _lruOrder = new();          // head = oldest
        private static readonly Dictionary<string, LinkedListNode<string>> _lruIndex = new(); // key → node
        private static readonly object _lruLock = new();
        private static long _currentBytes;
        private static long _accessCount;
        private static long _hits;
        private static long _misses;
        private static long _evictions;
        private static long _oversized;
        private static int _sweepInFlight; // 0 = idle, 1 = a background ClearExpired is running

        private sealed class CacheEntry
        {
            public object? Value { get; }
            public long SizeBytes { get; }
            public DateTime ExpiresUtc { get; }
            public DateTime CreatedUtc { get; }

            public CacheEntry(object? value, long sizeBytes, DateTime expiresUtc)
            {
                Value = value;
                SizeBytes = sizeBytes;
                ExpiresUtc = expiresUtc;
                CreatedUtc = DateTime.UtcNow;
            }

            public bool IsExpired => DateTime.UtcNow >= ExpiresUtc;
        }

        /// <summary>Configure the cache limits. Call before first use or between test runs.</summary>
        public static void Configure(long maxBytes = 300L * 1024 * 1024, int ttlSeconds = 300)
        {
            _maxBytes = maxBytes;
            _ttl = TimeSpan.FromSeconds(ttlSeconds);
        }

        public static bool TryGet(string key, out object? value)
        {
            var count = Interlocked.Increment(ref _accessCount);
            // Every ~1000 accesses, kick off a background sweep so TTL-expired
            // entries that nobody re-reads still get evicted. CAS-guarded so
            // overlapping triggers collapse to a single sweep.
            if ((count % 1000) == 0) TryFireBackgroundSweep();

            if (_cache.TryGetValue(key, out var entry) && !entry.IsExpired)
            {
                // Promote to most-recently-used
                lock (_lruLock)
                {
                    if (_lruIndex.TryGetValue(key, out var node))
                    {
                        _lruOrder.Remove(node);
                        _lruOrder.AddLast(node);
                    }
                }
                Interlocked.Increment(ref _hits);
                value = entry.Value;
                return true;
            }

            // Remove expired entry if present
            if (entry != null)
                RemoveEntry(key);

            Interlocked.Increment(ref _misses);
            value = null;
            return false;
        }

        public static void Set(string key, object? value)
        {
            Interlocked.Increment(ref _accessCount);

            // Estimate size before taking lock
            int itemCount = value is ICollection col ? col.Count : 0;
            long sizeBytes = EstimateValueSize(value, itemCount);

            // If a single entry exceeds the cap, don't cache it at all — bump
            // _oversized so GetDiagnostics surfaces these silent drops instead
            // of leaving callers to chase phantom misses.
            if (sizeBytes > _maxBytes)
            {
                Interlocked.Increment(ref _oversized);
                return;
            }

            // Remove existing entry for this key first
            if (_cache.ContainsKey(key))
                RemoveEntry(key);

            // Take the LRU lock once for both eviction and insertion. The previous
            // implementation took _lruLock per eviction iteration plus another time
            // for the AddLast, which under write contention turned every Set() into
            // a stream of short critical sections instead of one bounded one.
            var entry = new CacheEntry(value, sizeBytes, DateTime.UtcNow + _ttl);
            lock (_lruLock)
            {
                while (_currentBytes + sizeBytes > _maxBytes)
                {
                    if (_lruOrder.First == null) break;
                    var victimKey = _lruOrder.First.Value;
                    if (_cache.TryRemove(victimKey, out var victim))
                    {
                        Interlocked.Add(ref _currentBytes, -victim.SizeBytes);
                        if (_lruIndex.TryGetValue(victimKey, out var vnode))
                        {
                            _lruOrder.Remove(vnode);
                            _lruIndex.Remove(victimKey);
                        }
                        Interlocked.Increment(ref _evictions);
                    }
                    else
                    {
                        // Defensive: dictionary already pruned, drop the LRU node anyway.
                        _lruOrder.RemoveFirst();
                        _lruIndex.Remove(victimKey);
                    }
                }

                if (_cache.TryAdd(key, entry))
                {
                    Interlocked.Add(ref _currentBytes, sizeBytes);
                    var node = _lruOrder.AddLast(key);
                    _lruIndex[key] = node;
                }
            }
        }

        private static void RemoveEntry(string key)
        {
            if (_cache.TryRemove(key, out var removed))
            {
                Interlocked.Add(ref _currentBytes, -removed.SizeBytes);
                lock (_lruLock)
                {
                    if (_lruIndex.TryGetValue(key, out var node))
                    {
                        _lruOrder.Remove(node);
                        _lruIndex.Remove(key);
                    }
                }
            }
        }

        public static void Clear()
        {
            lock (_lruLock)
            {
                _cache.Clear();
                _lruOrder.Clear();
                _lruIndex.Clear();
            }
            Interlocked.Exchange(ref _currentBytes, 0);
            Interlocked.Exchange(ref _accessCount, 0);
            Interlocked.Exchange(ref _hits, 0);
            Interlocked.Exchange(ref _misses, 0);
            Interlocked.Exchange(ref _evictions, 0);
            Interlocked.Exchange(ref _oversized, 0);
        }

        /// <summary>
        /// Remove all entries belonging to a single tenant. Cache keys are formatted
        /// as "tenantFilter|type", so we match by the "tenantFilter|" prefix.
        /// </summary>
        public static int ClearTenant(string tenantFilter)
        {
            if (string.IsNullOrWhiteSpace(tenantFilter)) return 0;
            var prefix = tenantFilter + "|";
            int removed = 0;
            // Snapshot keys to avoid mutating while iterating the concurrent dictionary
            var matchingKeys = _cache.Keys.Where(k => k.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)).ToList();
            foreach (var key in matchingKeys)
            {
                RemoveEntry(key);
                removed++;
            }
            return removed;
        }

        /// <summary>
        /// Remove every entry whose TTL has elapsed. Pair to the lazy per-key
        /// eviction in TryGet — handles keys that nobody reads again. Safe to
        /// call from anywhere; the background sweep triggered by TryGet uses
        /// this method.
        /// </summary>
        public static int ClearExpired()
        {
            // Snapshot first; RemoveEntry mutates _cache and _lruIndex under _lruLock.
            var expiredKeys = new List<string>();
            foreach (var kvp in _cache)
            {
                if (kvp.Value.IsExpired) expiredKeys.Add(kvp.Key);
            }
            foreach (var key in expiredKeys) RemoveEntry(key);
            return expiredKeys.Count;
        }

        /// <summary>
        /// Fire-and-forget a single background ClearExpired sweep. The CAS guard
        /// collapses overlapping triggers so we never have more than one sweep
        /// running at a time, regardless of read pressure.
        /// </summary>
        private static void TryFireBackgroundSweep()
        {
            if (Interlocked.CompareExchange(ref _sweepInFlight, 1, 0) != 0) return;
            Task.Run(() =>
            {
                try { ClearExpired(); }
                catch { /* swallow — sweep is best-effort */ }
                finally { Interlocked.Exchange(ref _sweepInFlight, 0); }
            });
        }

        public static int Count => _cache.Count;
        public static long CurrentBytes => Interlocked.Read(ref _currentBytes);
        public static double CurrentMB => Math.Round(Interlocked.Read(ref _currentBytes) / (1024.0 * 1024.0), 2);
        public static long MaxBytes => _maxBytes;
        public static int TtlSeconds => (int)_ttl.TotalSeconds;
        public static long Hits => Interlocked.Read(ref _hits);
        public static long Misses => Interlocked.Read(ref _misses);
        public static long Evictions => Interlocked.Read(ref _evictions);
        public static long Oversized => Interlocked.Read(ref _oversized);
        public static double HitRate => (_hits + _misses) > 0
            ? Math.Round(_hits * 100.0 / (_hits + _misses), 1) : 0;

        // ── PSObject reflection (cached, resolved once at first use) ──
        private static readonly object s_reflectLock = new();
        private static bool s_psResolved;
        private static Type? s_psObjectType;
        private static PropertyInfo? s_psPropsProp;   // PSObject.Properties
        private static PropertyInfo? s_psPropName;     // PSPropertyInfo.Name
        private static PropertyInfo? s_psPropValue;    // PSPropertyInfo.Value
        // ── Managed-heap size model (x64 CoreCLR) ──
        // The cache stores *parsed PSObject graphs*, whose live heap footprint is
        // many times their JSON text size (measured ≈8× on real Graph data). Sizing
        // by JSON serialization therefore under-counts by ~8× and lets the byte cap
        // balloon far past its nominal limit. Instead we walk the object graph and
        // sum approximate per-object heap costs. Constants below are calibrated
        // against real GC heap growth (see tools/measure-testcache.ps1).
        private const int ObjectHeader = 16;            // sync block + method table ptr
        private const int RefSlot = 8;                  // one reference (array/field slot)
        private const int StringBaseOverhead = 22;      // header(16)+length(4)+terminator(2)
        private const int BoxedPrimitive = 24;          // header(16)+<=8 payload, aligned
        private const int BoxedLarge = 32;              // header(16)+16 payload (decimal/Guid)
        private const int PSObjectBase = 192;           // PSObject wrapper + base + member collections
        private const int PSNotePropertyOverhead = 132; // PSNoteProperty + name-lookup entry (excl. name string + value)
        private const int DictBase = 80;                // buckets + entries baseline
        private const int DictEntryOverhead = 48;       // per-entry slot incl. capacity slack (excl. key + value)
        private const int CollectionBase = 56;          // list/array object + backing array baseline

        // Bound the walk on pathological payloads: full-walk small collections for
        // accuracy, but stride-sample very large ones so a 100k-item array can't
        // turn a single Set() into a multi-second reflection storm.
        private const int LargeCollectionThreshold = 512;
        private const int LargeCollectionSamples = 256;
        private const int MaxDepth = 32;
        private const long NodeBudget = 2_000_000;      // hard ceiling on nodes visited per Set()

        private static void EnsurePSResolved()
        {
            if (s_psResolved) return;
            lock (s_reflectLock)
            {
                if (s_psResolved) return;
                try
                {
                    foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
                    {
                        var t = asm.GetType("System.Management.Automation.PSObject");
                        if (t == null) continue;
                        s_psObjectType = t;
                        s_psPropsProp = t.GetProperty("Properties");
                        var piType = asm.GetType("System.Management.Automation.PSPropertyInfo");
                        if (piType != null)
                        {
                            s_psPropName = piType.GetProperty("Name");
                            s_psPropValue = piType.GetProperty("Value");
                        }
                        break;
                    }
                }
                catch { /* SMA not loaded */ }
                s_psResolved = true;
            }
        }

        private static long Align8(long bytes) => (bytes + 7) & ~7L;

        /// <summary>
        /// Estimate the live managed-heap footprint of a cached value by walking the
        /// object graph and summing approximate per-object costs. This tracks real
        /// memory (parsed PSObjects, boxed primitives, strings, dictionaries and
        /// collections) rather than JSON text size, so the byte cap corresponds to
        /// actual process memory. <paramref name="itemCount"/> is accepted for call
        /// compatibility but the walk recomputes counts itself.
        /// </summary>
        private static long EstimateValueSize(object? value, int itemCount)
        {
            if (value == null) return 0;
            EnsurePSResolved();
            try
            {
                long budget = NodeBudget;
                return SizeOf(value, 0, ref budget);
            }
            catch { return 0; }
        }

        /// <summary>
        /// Recursively sum the approximate managed-heap bytes of <paramref name="value"/>
        /// and everything it owns. Returns the object's own heap size; the reference
        /// slot that points at it is accounted for by the owning object/collection.
        /// </summary>
        private static long SizeOf(object? value, int depth, ref long budget)
        {
            if (value == null) return 0;
            if (--budget <= 0 || depth > MaxDepth) return 0;

            switch (value)
            {
                case string s:
                    return Align8(StringBaseOverhead + 2L * s.Length);
                case bool: case byte: case sbyte: case char:
                case short: case ushort: case int: case uint:
                case long: case ulong: case float: case double:
                case DateTime: case DateTimeOffset: case TimeSpan: case Enum:
                    return BoxedPrimitive;
                case decimal: case Guid:
                    return BoxedLarge;
                case byte[] bytes:
                    return Align8(ObjectHeader + RefSlot + bytes.LongLength);
            }

            // PSObject → wrapper cost + each NoteProperty (name string + value + overhead)
            if (s_psObjectType != null && s_psObjectType.IsInstanceOfType(value))
                return SizeOfPSObject(value, depth, ref budget);

            // Dictionary / Hashtable → base + per-entry overhead + keys + values
            if (value is IDictionary dict)
            {
                long total = ObjectHeader + DictBase;
                foreach (DictionaryEntry de in dict)
                {
                    total += DictEntryOverhead;
                    total += SizeOf(de.Key, depth + 1, ref budget);
                    total += SizeOf(de.Value, depth + 1, ref budget);
                    if (budget <= 0) break;
                }
                return total;
            }

            // Other collections (object[], List<object>, …). Stride-sample very large
            // ones to bound the walk; full-walk the rest for accuracy.
            if (value is IEnumerable enumerable && value is not string)
            {
                int count = value is ICollection col ? col.Count : -1;

                if (count > LargeCollectionThreshold && value is IList list)
                {
                    long step = count / (long)LargeCollectionSamples;
                    if (step < 1) step = 1;
                    long sampled = 0, sampledBytes = 0;
                    for (long i = 0; i < count && sampled < LargeCollectionSamples; i += step)
                    {
                        sampledBytes += SizeOf(list[(int)i], depth + 1, ref budget);
                        sampled++;
                        if (budget <= 0) break;
                    }
                    long avgItem = sampled > 0 ? sampledBytes / sampled : 0;
                    // backing array slots + extrapolated element payloads
                    return ObjectHeader + CollectionBase + count * (RefSlot + avgItem);
                }

                long total = ObjectHeader + CollectionBase;
                foreach (var item in enumerable)
                {
                    total += RefSlot;
                    total += SizeOf(item, depth + 1, ref budget);
                    if (budget <= 0) break;
                }
                return total;
            }

            // Unknown reference type: header plus a small nominal for its fields.
            return ObjectHeader + 32;
        }

        private static long SizeOfPSObject(object psObj, int depth, ref long budget)
        {
            long total = PSObjectBase;
            if (s_psPropsProp == null || s_psPropName == null || s_psPropValue == null)
                return total;
            if (s_psPropsProp.GetValue(psObj) is not IEnumerable props) return total;

            foreach (var prop in props)
            {
                if (--budget <= 0) break;
                total += PSNotePropertyOverhead;
                try
                {
                    if (s_psPropName.GetValue(prop) is string name)
                        total += Align8(StringBaseOverhead + 2L * name.Length);
                    total += SizeOf(s_psPropValue.GetValue(prop), depth + 1, ref budget);
                }
                catch { /* skip properties that throw on access */ }
            }
            return total;
        }

        /// <summary>
        /// Returns a diagnostic snapshot of the cache: entry count, keys grouped
        /// by data type, estimated serialized size, and expiry details.
        /// Designed for the worker-health dashboard — call from PS via
        /// [CIPP.TestDataCache]::GetDiagnostics() or from CRAFT metrics bridge.
        /// </summary>
        public static CacheDiagnostics GetDiagnostics()
        {
            var entries = _cache.ToArray(); // snapshot

            long totalBytes = 0;
            var byType = new Dictionary<string, TypeBucket>();
            int active = 0, expired = 0;
            DateTime? earliestExpiry = null, latestExpiry = null;

            // Single pass — use the SizeBytes stored at insert instead of
            // re-running EstimateValueSize (which would JSON-serialize every
            // PSObject tree on every diagnostic poll and thrash the LOH).
            foreach (var kvp in entries)
            {
                var parts = kvp.Key.Split('|', 2);
                var dataType = parts.Length > 1 ? parts[1] : "?";

                int itemCount = 0;
                if (kvp.Value.Value is ICollection col)
                    itemCount = col.Count;

                long entryBytes = kvp.Value.SizeBytes;
                totalBytes += entryBytes;

                if (!byType.TryGetValue(dataType, out var bucket))
                {
                    bucket = new TypeBucket { Type = dataType };
                    byType[dataType] = bucket;
                }
                bucket.EntryCount++;
                bucket.TotalBytes += entryBytes;
                bucket.TotalItems += itemCount;

                if (kvp.Value.IsExpired) { expired++; } else { active++; }
                var exp = kvp.Value.ExpiresUtc;
                if (earliestExpiry == null || exp < earliestExpiry) earliestExpiry = exp;
                if (latestExpiry == null || exp > latestExpiry) latestExpiry = exp;
            }

            return new CacheDiagnostics
            {
                TotalEntries = entries.Length,
                ActiveEntries = active,
                ExpiredEntries = expired,
                EstimatedTotalMB = Math.Round(totalBytes / (1024.0 * 1024.0), 2),
                TrackedTotalMB = CurrentMB,
                MaxMB = Math.Round(_maxBytes / (1024.0 * 1024.0), 2),
                TtlSeconds = (int)_ttl.TotalSeconds,
                Hits = Interlocked.Read(ref _hits),
                Misses = Interlocked.Read(ref _misses),
                HitRate = HitRate,
                Evictions = Interlocked.Read(ref _evictions),
                Oversized = Interlocked.Read(ref _oversized),
                EarliestExpiryUtc = earliestExpiry,
                LatestExpiryUtc = latestExpiry,
                AccessCount = Interlocked.Read(ref _accessCount),
                TypeBreakdown = byType.Values
                    .OrderByDescending(b => b.TotalBytes)
                    .ToList(),
            };
        }
    }

    /// <summary>Diagnostic snapshot returned by TestDataCache.GetDiagnostics().</summary>
    public class CacheDiagnostics
    {
        public int TotalEntries { get; set; }
        public int ActiveEntries { get; set; }
        public int ExpiredEntries { get; set; }
        public double EstimatedTotalMB { get; set; }
        public double TrackedTotalMB { get; set; }
        public double MaxMB { get; set; }
        public int TtlSeconds { get; set; }
        public long Hits { get; set; }
        public long Misses { get; set; }
        public double HitRate { get; set; }
        public long Evictions { get; set; }
        public long Oversized { get; set; }
        public DateTime? EarliestExpiryUtc { get; set; }
        public DateTime? LatestExpiryUtc { get; set; }
        public long AccessCount { get; set; }
        public List<TypeBucket> TypeBreakdown { get; set; } = new();
    }

    /// <summary>Per-data-type cache usage bucket.</summary>
    public class TypeBucket
    {
        public string Type { get; set; } = "";
        public int EntryCount { get; set; }
        public long TotalBytes { get; set; }
        public int TotalItems { get; set; }
        public double TotalMB => Math.Round(TotalBytes / (1024.0 * 1024.0), 2);
    }
}
