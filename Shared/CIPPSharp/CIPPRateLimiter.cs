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
        internal sealed record Rule(string Name, Regex Match, double PerSecond, int Burst, int Reserve = 0,
            Func<string, string?, int>? Cost = null, double MaxPerSecond = 0);

        // Token buckets measured live (CA What If: ~10-14 burst refilling ~1/s). EXO: 3000 per fixed minute and 900
        // concurrent requests per tenant, so a large burst is safe: 45/s sustained, and the Rate-Limit headers pace the
        // rest of the window (Reserve = requests assumed already in flight when the server counted).
        private static readonly Rule[] _rules =
        {
            new("ca-service",   Pattern(@"^graph\.microsoft\.com/(v1\.0|beta)/(identity/conditionalAccess/|identityProtection/|riskyUsers|riskDetections)"), 0.9, 10),
            new("auth-methods", Pattern(@"^graph\.microsoft\.com/(v1\.0|beta)/users/[^/]+/authentication/"), 20, 20),
            // Identity and access reports (sign-ins, directory audits, provisioning, authentication-method and credential
            // reports): 5 requests per 10 seconds per app and tenant, as documented; measured, a fresh bucket takes 12-20 and
            // every $batch sub-request counts.
            new("entra-reports", Pattern(@"^graph\.microsoft\.com/(v1\.0|beta)/(auditLogs(/|$)|reports/(authenticationMethods|credentialUser|getCredentialUser|credentialUsage|getCredentialUsage|userCredentialUsage|azureADUserFeatureUsage|getAzureADUserFeatureUsage|applicationSignIn|getApplicationSignIn|relyingParty|getRelyingParty))"), 0.5, 10),
            new("exo-adminapi", Pattern(@"^outlook\.office365\.com/adminapi/"), 45, 2700, 300),
            // SharePoint charges CSOM, SOAP, _api and Graph's SharePoint endpoints to one per-app quota per tenant, in
            // resource units. The lowest licence band allows ~1,250 a minute: 18/s plus a 150 burst stays under it. Larger
            // tenants get more, so the rate climbs while callers wait and drops on a 429, up to the top band's ~104/s.
            new("sharepoint", Pattern(@"^([^/]+\.sharepoint(-[a-z]+)?\.[a-z.]+/|((dod-)?graph\.microsoft\.(com|us|de)|microsoftgraph\.chinacloudapi\.cn)/(v1\.0|beta)/((sites|drives|shares|drive)(/|$)|(users|groups|me)/([^/]+/)?(drives?|sites|followedSites)(/|$)))"),
                18, 150, Cost: SharePointCost, MaxPerSecond: 104),
        };

        private sealed class Bucket
        {
            public long Tat;
            public long BlockedUntil;
            public long Claims;
            public long Waits;
            public long WaitedMs;
            public long Throttled;
            public long BudgetHolds;
            public long PacedUntil;
            public double PacedPerSecond;
            public int PacedBurst;
            public double LearnedPerSecond;
            public long LastThrottle;
            public long LastRaise;
        }

        public sealed class Claim
        {
            internal readonly List<(string Key, string? SubId)> Keys = new();
            internal readonly Dictionary<string, (Rule? Rule, int Cost)> Costs = new(StringComparer.OrdinalIgnoreCase);
            public TimeSpan Wait { get; internal set; }
        }

        private static readonly bool _disabled =
            string.Equals(Environment.GetEnvironmentVariable("CIPP_RATELIMIT_DISABLED"), "true", StringComparison.OrdinalIgnoreCase);
        private const int DefaultRetryAfterSeconds = 5;
        private const int MaxRetryAfterSeconds = 300;
        // SharePoint blocks for up to ~280 s; a caller must outwait a full block (plus its release jitter) instead of sending into it.
        public static readonly TimeSpan MaxWait = TimeSpan.FromSeconds(MaxRetryAfterSeconds + 5);

        private static readonly ConcurrentDictionary<string, Bucket> _buckets = new(StringComparer.OrdinalIgnoreCase);
        private static readonly ConcurrentDictionary<string, string> _tenantByToken = new(StringComparer.Ordinal);

        private static Regex Pattern(string p) => new(p, RegexOptions.IgnoreCase | RegexOptions.Compiled | RegexOptions.CultureInvariant);

        /// <summary>The measured budget a Graph $batch sub-request falls under.</summary>
        public sealed record BatchBudget(string Name, int Burst);

        /// <summary>
        /// A $batch lands all its sub-requests at once, so the limiter can only space whole batches: a caller keeps the
        /// sub-requests of one budget in a batch within its burst. Null when the URL has no measured budget.
        /// </summary>
        public static BatchBudget? BatchBudgetFor(string relativeUrl, string version = "beta")
        {
            if (_disabled || string.IsNullOrEmpty(relativeUrl)) return null;
            var target = $"graph.microsoft.com/{version}/{relativeUrl.Split('?')[0].TrimStart('/')}";
            var rule = _rules.FirstOrDefault(r => r.Match.IsMatch(target));
            return rule is null ? null : new BatchBudget(rule.Name, rule.Burst);
        }

        /// <summary>Reserves capacity for a request and returns how long to wait before sending it, or null when the request is not tracked.</summary>
        public static Claim? Acquire(string uri, string method, string? body, IEnumerable<KeyValuePair<string, string>>? headers)
        {
            if (_disabled) return null;
            var tenant = TenantFromHeaders(headers);
            if (tenant is null || !Uri.TryCreate(uri, UriKind.Absolute, out var parsed)) return null;

            var target = parsed.Host + parsed.AbsolutePath;
            var claim = new Claim();
            var costs = claim.Costs;

            void Add(string t, string? subId, string? requestBody)
            {
                var rule = _rules.FirstOrDefault(r => r.Match.IsMatch(t));
                var key = tenant + "|" + (rule?.Name ?? Template(t));
                var cost = rule?.Cost?.Invoke(t, requestBody) ?? 1;
                claim.Keys.Add((key, subId));
                costs[key] = (rule, costs.TryGetValue(key, out var c) ? c.Cost + cost : cost);
            }

            if (body is not null && target.EndsWith("/$batch", StringComparison.OrdinalIgnoreCase))
            {
                var basePath = target[..^"$batch".Length];
                foreach (var (id, url) in BatchRequests(body))
                {
                    var sub = url.StartsWith("http", StringComparison.OrdinalIgnoreCase) && Uri.TryCreate(url, UriKind.Absolute, out var abs)
                        ? abs.Host + abs.AbsolutePath
                        : basePath + url.Split('?')[0].TrimStart('/');
                    Add(sub, id, null);
                }
                if (claim.Keys.Count == 0) Add(target, null, null);
            }
            else
            {
                Add(target, null, body);
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
                    if (rule is not null && rule.PerSecond > 0)
                    {
                        // GCRA token bucket: Burst tokens, refilled at PerSecond; a burst drains it and later claims wait for the refill.
                        // A server-reported budget (ObserveBudget) slows both until its window resets.
                        var paced = bucket.PacedUntil > now;
                        var adaptive = rule.MaxPerSecond > rule.PerSecond;
                        var basePerSecond = adaptive && bucket.LearnedPerSecond > 0 ? bucket.LearnedPerSecond : rule.PerSecond;
                        var perSecond = paced ? Math.Min(basePerSecond, bucket.PacedPerSecond) : basePerSecond;
                        var burst = paced ? Math.Min(rule.Burst, bucket.PacedBurst) : rule.Burst;
                        var interval = (long)(TimeSpan.TicksPerSecond / perSecond);
                        var tat = Math.Max(bucket.Tat, start);
                        bucket.Tat = tat + cost * interval;
                        start = Math.Max(start, bucket.Tat - burst * interval);
                        // Demand is above the current rate and nothing was throttled for 5 minutes: probe 10% higher,
                        // at most every 30 s and never on a tenant's first burst.
                        if (adaptive && bucket.LastRaise == 0) bucket.LastRaise = now;
                        if (adaptive && start > now && now - bucket.LastThrottle > 5 * TimeSpan.TicksPerMinute && now - bucket.LastRaise > 30 * TimeSpan.TicksPerSecond)
                        {
                            bucket.LearnedPerSecond = Math.Min(rule.MaxPerSecond, basePerSecond * 1.1);
                            bucket.LastRaise = now;
                        }
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
            ObserveBudget(claim, headers);

            if (statusCode == 429 || (statusCode == 503 && RetryAfter(headers) is not null))
            {
                var seconds = RetryAfter(headers) ?? DefaultRetryAfterSeconds;
                foreach (var key in claim.Keys.Select(k => k.Key).Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    Block(key, seconds);
                    if (statusCode == 429) SlowDown(key, claim.Costs[key].Rule);
                }
                return;
            }

            if (content is null || claim.Keys[0].SubId is null) return;
            if (!content.Contains("\"status\":429") && !content.Contains("\"status\": 429")) return;
            try
            {
                using var doc = JsonDocument.Parse(content);
                ObserveBatch(claim, doc);
            }
            catch (JsonException) { }
        }

        /// <summary>Observe for a body kept as UTF-8 bytes.</summary>
        public static void Observe(Claim? claim, int statusCode, IReadOnlyDictionary<string, string[]>? headers, byte[] body)
        {
            if (claim is null || claim.Keys.Count == 0) return;
            if (statusCode == 429 || (statusCode == 503 && RetryAfter(headers) is not null) || claim.Keys[0].SubId is null)
            {
                Observe(claim, statusCode, headers, (string?)null);
                return;
            }
            var json = HttpBody.Utf8(body);
            if (json is null) { Observe(claim, statusCode, headers, HttpBody.Decode(body)); return; }
            ObserveBudget(claim, headers);
            var span = json.Value.Span;
            if (span.IndexOf("\"status\":429"u8) < 0 && span.IndexOf("\"status\": 429"u8) < 0) return;
            try
            {
                using var doc = JsonDocument.Parse(json.Value);
                ObserveBatch(claim, doc);
            }
            catch (JsonException) { }
        }

        // EXO reports its per-tenant minute budget on every response. What is left after the in-flight reserve is
        // spread over the time left in the window, so calls slow down before the cap instead of running into 429s;
        // only an already-spent reserve holds until the reset.
        private static void ObserveBudget(Claim claim, IReadOnlyDictionary<string, string[]>? headers)
        {
            if (headers is null || !headers.TryGetValue("Rate-Limit-Remaining", out var remainingValues) ||
                remainingValues.Length == 0 || !int.TryParse(remainingValues[0], out var remaining)) return;
            var seconds = headers.TryGetValue("Rate-Limit-Reset", out var reset) && reset.Length > 0 ? ParseRetryAfter(reset[0]) ?? 0 : 0;
            if (seconds <= 0) return;
            foreach (var (key, (rule, _)) in claim.Costs)
            {
                if (rule is null || rule.PerSecond <= 0) continue;
                var usable = remaining - rule.Reserve;
                if (usable <= 0) { Hold(key, seconds); continue; }
                Pace(key, (double)usable / seconds, Math.Min(rule.Burst, usable), seconds);
            }
        }

        private static void ObserveBatch(Claim claim, JsonDocument doc)
        {
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
                    if (subId == id)
                    {
                        Block(key, seconds ?? DefaultRetryAfterSeconds);
                        SlowDown(key, claim.Costs[key].Rule);
                    }
            }
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
                        r.Value.BudgetHolds,
                        PacedPerSecond = r.Value.PacedUntil > now ? Math.Round(r.Value.PacedPerSecond, 1) : (double?)null,
                        LearnedPerSecond = r.Value.LearnedPerSecond > 0 ? Math.Round(r.Value.LearnedPerSecond, 1) : (double?)null,
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

        private static void SlowDown(string key, Rule? rule)
        {
            if (rule is null || rule.MaxPerSecond <= rule.PerSecond) return;
            var bucket = _buckets.GetOrAdd(key, _ => new Bucket());
            lock (bucket)
            {
                var current = bucket.LearnedPerSecond > 0 ? bucket.LearnedPerSecond : rule.PerSecond;
                bucket.LearnedPerSecond = Math.Max(rule.PerSecond, current * 0.7);
                bucket.LastThrottle = DateTime.UtcNow.Ticks;
            }
        }

        // Resource units measured on a lowest-band tenant: Graph and _api reads 1 (lists too), the CSOM site-list page ~2.4,
        // and a GetSitePropertiesByUrl request ~5.5 however many sites it reads. Permissions are charged the documented 5: at 3
        // a sharing-links scan was throttled ~530 times at the 18/s floor. CSOM writes were not burned; a write sweep
        // throttled at ~1/s, so they are charged ~20.
        private static int SharePointCost(string target, string? body)
        {
            if (body is not null && target.EndsWith("/client.svc/ProcessQuery", StringComparison.OrdinalIgnoreCase))
            {
                if (body.Contains("<SetProperty", StringComparison.Ordinal) || body.Contains(" Name=\"Update\"", StringComparison.Ordinal) ||
                    body.Contains(" Name=\"Set", StringComparison.Ordinal)) return 20;
                if (body.Contains("GetSitePropertiesByUrl", StringComparison.Ordinal)) return 6;
                if (body.Contains("GetSitePropertiesFromSharePoint", StringComparison.Ordinal)) return 3;
                return 1;
            }
            return target.EndsWith("/permissions", StringComparison.OrdinalIgnoreCase) ||
                   target.Contains("/permissions/", StringComparison.OrdinalIgnoreCase) ? 5 : 1;
        }

        private static void Hold(string key, int seconds)
        {
            var bucket = _buckets.GetOrAdd(key, _ => new Bucket());
            var until = DateTime.UtcNow.AddSeconds(Math.Clamp(seconds, 1, MaxRetryAfterSeconds)).Ticks;
            lock (bucket)
            {
                if (until <= bucket.BlockedUntil) return;
                bucket.BlockedUntil = until;
                bucket.BudgetHolds++;
            }
        }

        private static void Pace(string key, double perSecond, int burst, int seconds)
        {
            var bucket = _buckets.GetOrAdd(key, _ => new Bucket());
            lock (bucket)
            {
                bucket.PacedPerSecond = Math.Max(perSecond, 0.1);
                bucket.PacedBurst = Math.Max(burst, 1);
                bucket.PacedUntil = DateTime.UtcNow.AddSeconds(Math.Clamp(seconds, 1, MaxRetryAfterSeconds)).Ticks;
            }
        }

        private static void Prune(long now)
        {
            foreach (var (key, bucket) in _buckets)
                if (bucket.Tat < now && bucket.BlockedUntil < now && bucket.PacedUntil < now) _buckets.TryRemove(key, out _);
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
