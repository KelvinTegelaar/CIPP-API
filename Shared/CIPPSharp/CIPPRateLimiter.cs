#nullable enable
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CIPP
{
    // Process-wide pacing per tenant + service, shared by every HTTP and background runspace. A 429's
    // Retry-After blocks its tenant + endpoint for all workers, not just the caller that hit it.
    public static class CIPPRateLimiter
    {
        internal sealed record Rule(string Name, Regex Match, double PerSecond, int Burst);

        // Token buckets measured live (CA What If: ~10-14 burst refilling ~1/s; EXO: 3000 per fixed minute).
        private static readonly Rule[] _rules =
        {
            new("ca-service",   Pattern(@"^graph\.microsoft\.com/(v1\.0|beta)/(identity/conditionalAccess/|identityProtection/|riskyUsers|riskDetections)"), 0.9, 10),
            new("auth-methods", Pattern(@"^graph\.microsoft\.com/(v1\.0|beta)/users/[^/]+/authentication/"), 20, 20),
            new("exo-adminapi", Pattern(@"^outlook\.office365\.com/adminapi/"), 45, 300),
        };

        private sealed class Bucket
        {
            public long Tat;
            public long BlockedUntil;
            public long Claims;
            public long Waits;
            public long WaitedMs;
            public long Throttled;
        }

        public sealed class Claim
        {
            internal readonly List<(string Key, string? SubId)> Keys = new();
            internal readonly Dictionary<string, (Rule? Rule, int Cost)> Costs = new(StringComparer.OrdinalIgnoreCase);
            public TimeSpan Wait { get; internal set; }
        }

        private static readonly bool _disabled =
            string.Equals(Environment.GetEnvironmentVariable("CIPP_RATELIMIT_DISABLED"), "true", StringComparison.OrdinalIgnoreCase);
        public static readonly TimeSpan MaxWait = TimeSpan.FromSeconds(120);
        private const int DefaultRetryAfterSeconds = 5;
        private const int MaxRetryAfterSeconds = 300;

        private static readonly ConcurrentDictionary<string, Bucket> _buckets = new(StringComparer.OrdinalIgnoreCase);
        private static readonly ConcurrentDictionary<string, string> _tenantByToken = new(StringComparer.Ordinal);

        private static Regex Pattern(string p) => new(p, RegexOptions.IgnoreCase | RegexOptions.Compiled | RegexOptions.CultureInvariant);

        /// <summary>Reserves capacity for a request and returns how long to wait before sending it, or null when the request is not tracked.</summary>
        public static Claim? Acquire(string uri, string method, string? body, IEnumerable<KeyValuePair<string, string>>? headers)
        {
            if (_disabled) return null;
            var tenant = TenantFromHeaders(headers);
            if (tenant is null || !Uri.TryCreate(uri, UriKind.Absolute, out var parsed)) return null;

            var target = parsed.Host + parsed.AbsolutePath;
            var claim = new Claim();
            var costs = claim.Costs;

            void Add(string t, string? subId)
            {
                var rule = _rules.FirstOrDefault(r => r.Match.IsMatch(t));
                var key = tenant + "|" + (rule?.Name ?? Template(t));
                claim.Keys.Add((key, subId));
                costs[key] = (rule, costs.TryGetValue(key, out var c) ? c.Cost + 1 : 1);
            }

            if (body is not null && target.EndsWith("/$batch", StringComparison.OrdinalIgnoreCase))
            {
                var basePath = target[..^"$batch".Length];
                foreach (var (id, url) in BatchRequests(body))
                {
                    var sub = url.StartsWith("http", StringComparison.OrdinalIgnoreCase) && Uri.TryCreate(url, UriKind.Absolute, out var abs)
                        ? abs.Host + abs.AbsolutePath
                        : basePath + url.Split('?')[0].TrimStart('/');
                    Add(sub, id);
                }
                if (claim.Keys.Count == 0) Add(target, null);
            }
            else
            {
                Add(target, null);
            }

            claim.Wait = Reserve(claim);
            if (_buckets.Count > 20000) Prune(DateTime.UtcNow.Ticks);
            return claim;
        }

        /// <summary>Call after waiting: if a key was blocked meanwhile, reserves a new slot after the block instead of sending into it.</summary>
        public static TimeSpan Recheck(Claim? claim)
        {
            if (claim is null) return TimeSpan.Zero;
            var now = DateTime.UtcNow.Ticks;
            foreach (var key in claim.Costs.Keys)
                if (_buckets.TryGetValue(key, out var b) && b.BlockedUntil > now) return Reserve(claim);
            return TimeSpan.Zero;
        }

        private static TimeSpan Reserve(Claim claim)
        {
            var now = DateTime.UtcNow.Ticks;
            long wait = 0;
            foreach (var (key, (rule, cost)) in claim.Costs)
            {
                Bucket? bucket;
                if (rule is null && !_buckets.TryGetValue(key, out bucket)) continue;
                bucket = _buckets.GetOrAdd(key, _ => new Bucket());
                long start;
                lock (bucket)
                {
                    start = now;
                    if (bucket.BlockedUntil > start)
                        start = bucket.BlockedUntil + TimeSpan.FromMilliseconds(Random.Shared.Next(0, 1000)).Ticks;
                    if (rule is not null)
                    {
                        // GCRA token bucket: Burst tokens, refilled at PerSecond; a burst drains it and later claims wait for the refill.
                        var interval = (long)(TimeSpan.TicksPerSecond / rule.PerSecond);
                        var tat = Math.Max(bucket.Tat, start);
                        bucket.Tat = tat + cost * interval;
                        start = Math.Max(start, bucket.Tat - rule.Burst * interval);
                    }
                    bucket.Claims += cost;
                    if (start > now)
                    {
                        bucket.Waits++;
                        bucket.WaitedMs += (start - now) / TimeSpan.TicksPerMillisecond;
                    }
                }
                wait = Math.Max(wait, start - now);
            }

            return TimeSpan.FromTicks(Math.Min(wait, MaxWait.Ticks));
        }

        /// <summary>Feeds a response back: a throttled request (or throttled $batch sub-request) blocks its key for every worker.</summary>
        public static void Observe(Claim? claim, int statusCode, IReadOnlyDictionary<string, string[]>? headers, string? content)
        {
            if (claim is null || claim.Keys.Count == 0) return;

            if (statusCode == 429 || (statusCode == 503 && RetryAfter(headers) is not null))
            {
                var seconds = RetryAfter(headers) ?? DefaultRetryAfterSeconds;
                foreach (var key in claim.Keys.Select(k => k.Key).Distinct(StringComparer.OrdinalIgnoreCase))
                    Block(key, seconds);
                return;
            }

            if (content is null || claim.Keys[0].SubId is null) return;
            if (!content.Contains("\"status\":429") && !content.Contains("\"status\": 429")) return;
            try
            {
                using var doc = JsonDocument.Parse(content);
                if (!doc.RootElement.TryGetProperty("responses", out var responses) || responses.ValueKind != JsonValueKind.Array) return;
                foreach (var response in responses.EnumerateArray())
                {
                    if (!response.TryGetProperty("status", out var status) || !status.TryGetInt32(out var code) || code != 429) continue;
                    var id = response.TryGetProperty("id", out var idEl) ? idEl.ToString() : null;
                    int? seconds = null;
                    if (response.TryGetProperty("headers", out var subHeaders) && subHeaders.ValueKind == JsonValueKind.Object)
                        foreach (var h in subHeaders.EnumerateObject())
                            if (h.Name.Equals("Retry-After", StringComparison.OrdinalIgnoreCase))
                                seconds = ParseRetryAfter(h.Value.ToString());
                    foreach (var (key, subId) in claim.Keys)
                        if (subId == id) Block(key, seconds ?? DefaultRetryAfterSeconds);
                }
            }
            catch (JsonException) { }
        }

        public static object GetDiagnostics()
        {
            var now = DateTime.UtcNow.Ticks;
            var rows = _buckets.ToArray();
            return new
            {
                Disabled = _disabled,
                Keys = rows.Length,
                BlockedNow = rows.Count(r => r.Value.BlockedUntil > now),
                Buckets = rows
                    .OrderByDescending(r => r.Value.Throttled).ThenByDescending(r => r.Value.WaitedMs)
                    .Take(50)
                    .Select(r => new
                    {
                        Key = r.Key,
                        r.Value.Claims,
                        r.Value.Waits,
                        r.Value.WaitedMs,
                        r.Value.Throttled,
                        BlockedForMs = Math.Max(0, (r.Value.BlockedUntil - now) / TimeSpan.TicksPerMillisecond),
                    })
                    .ToArray(),
            };
        }

        public static void Reset()
        {
            _buckets.Clear();
            _tenantByToken.Clear();
        }

        private static void Block(string key, int seconds)
        {
            var bucket = _buckets.GetOrAdd(key, _ => new Bucket());
            var until = DateTime.UtcNow.AddSeconds(Math.Clamp(seconds, 1, MaxRetryAfterSeconds)).Ticks;
            lock (bucket)
            {
                bucket.BlockedUntil = Math.Max(bucket.BlockedUntil, until);
                bucket.Throttled++;
            }
        }

        private static void Prune(long now)
        {
            foreach (var (key, bucket) in _buckets)
                if (bucket.Tat < now && bucket.BlockedUntil < now) _buckets.TryRemove(key, out _);
        }

        private static int? RetryAfter(IReadOnlyDictionary<string, string[]>? headers) =>
            headers is not null && headers.TryGetValue("Retry-After", out var values) && values.Length > 0
                ? ParseRetryAfter(values[0])
                : null;

        private static int? ParseRetryAfter(string? value)
        {
            if (string.IsNullOrWhiteSpace(value)) return null;
            if (int.TryParse(value, out var seconds)) return seconds;
            if (DateTimeOffset.TryParse(value, out var at)) return (int)Math.Ceiling((at - DateTimeOffset.UtcNow).TotalSeconds);
            return null;
        }

        // users/{id}/authentication/methods, reports/getMailboxUsageDetail() - throttles are per service, not per object.
        private static string Template(string target)
        {
            var segments = target.Split('/', StringSplitOptions.RemoveEmptyEntries);
            for (var i = 1; i < segments.Length; i++)
            {
                var s = segments[i];
                var paren = s.IndexOf('(');
                if (paren > 0) s = s[..paren] + "()";
                if (paren == 0 || s.Contains('@') || s.Contains('\'') || Guid.TryParse(s, out _) || s.All(char.IsDigit) ||
                    (s.Length >= 16 && s.Any(char.IsDigit)))
                    s = "{id}";
                segments[i] = s.ToLowerInvariant();
            }
            segments[0] = segments[0].ToLowerInvariant();
            return string.Join('/', segments);
        }

        private static IEnumerable<(string? Id, string Url)> BatchRequests(string body)
        {
            var found = new List<(string?, string)>();
            try
            {
                using var doc = JsonDocument.Parse(body);
                if (doc.RootElement.ValueKind == JsonValueKind.Object &&
                    doc.RootElement.TryGetProperty("requests", out var requests) && requests.ValueKind == JsonValueKind.Array)
                    foreach (var r in requests.EnumerateArray())
                        if (r.TryGetProperty("url", out var url) && url.ValueKind == JsonValueKind.String)
                            found.Add((r.TryGetProperty("id", out var id) ? id.ToString() : null, url.GetString()!));
            }
            catch (JsonException) { }
            return found;
        }

        private static string? TenantFromHeaders(IEnumerable<KeyValuePair<string, string>>? headers)
        {
            if (headers is null) return null;
            string? auth = null;
            foreach (var (k, v) in headers)
                if (k.Equals("Authorization", StringComparison.OrdinalIgnoreCase)) { auth = v; break; }
            if (auth is null || !auth.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) return null;
            var token = auth[7..].Trim();
            if (_tenantByToken.TryGetValue(token, out var cached)) return cached;

            var parts = token.Split('.');
            if (parts.Length < 2) return null;
            try
            {
                var payload = parts[1].Replace('-', '+').Replace('_', '/');
                payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
                using var doc = JsonDocument.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(payload)));
                if (!doc.RootElement.TryGetProperty("tid", out var tid) || tid.ValueKind != JsonValueKind.String) return null;
                if (_tenantByToken.Count > 5000) _tenantByToken.Clear();
                return _tenantByToken[token] = tid.GetString()!;
            }
            catch (Exception ex) when (ex is FormatException || ex is JsonException) { return null; }
        }
    }
}
