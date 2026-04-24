using System;
using System.Collections.Concurrent;
using System.Threading;

namespace CIPP
{
    /// <summary>
    /// Process-scoped, thread-safe cache for test data lookups.
    /// Backed by a static ConcurrentDictionary so it is shared across
    /// all PowerShell runspaces within the Azure Functions worker.
    /// Expired entries are swept every 500 access calls to prevent unbounded growth.
    /// TTL is 30 minutes as a safety net.
    /// </summary>
    public static class TestDataCache
    {
        private static readonly ConcurrentDictionary<string, CacheEntry> _cache = new();
        private static readonly TimeSpan _ttl = TimeSpan.FromMinutes(30);
        private static int _accessCount;
        private const int SweepInterval = 500;

        private sealed class CacheEntry
        {
            public object? Value { get; }
            public DateTime ExpiresUtc { get; }

            public CacheEntry(object? value, DateTime expiresUtc)
            {
                Value = value;
                ExpiresUtc = expiresUtc;
            }

            public bool IsExpired => DateTime.UtcNow >= ExpiresUtc;
        }

        private static void SweepIfDue()
        {
            var count = Interlocked.Increment(ref _accessCount);
            if (count % SweepInterval == 0)
            {
                foreach (var kvp in _cache)
                {
                    if (kvp.Value.IsExpired)
                    {
                        _cache.TryRemove(kvp.Key, out _);
                    }
                }
            }
        }

        public static bool TryGet(string key, out object? value)
        {
            SweepIfDue();

            if (_cache.TryGetValue(key, out var entry) && !entry.IsExpired)
            {
                value = entry.Value;
                return true;
            }

            // Remove expired entry if present
            if (entry != null)
            {
                _cache.TryRemove(key, out _);
            }

            value = null;
            return false;
        }

        public static void Set(string key, object? value)
        {
            SweepIfDue();
            _cache[key] = new CacheEntry(value, DateTime.UtcNow + _ttl);
        }

        public static void Clear()
        {
            _cache.Clear();
            Interlocked.Exchange(ref _accessCount, 0);
        }

        public static int Count => _cache.Count;
    }
}
