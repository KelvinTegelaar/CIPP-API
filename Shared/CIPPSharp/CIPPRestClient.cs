#nullable enable
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace CIPP
{
    // =====================================================================
    // HttpResult
    // =====================================================================
    // Sealed result type returned to the PowerShell wrapper for every HTTP
    // call. Using init-only properties keeps this effectively immutable once
    // constructed by SendAsync — no caller can mutate the result after the
    // fact, which is important when results flow across runspace boundaries.
    // =====================================================================
    public sealed class HttpResult
    {
        public int                          StatusCode      { get; init; }
        public bool                         IsSuccess       { get; init; }
        public string                       Content         { get; init; } = string.Empty;
        public bool                         IsJson          { get; init; }

        /// <summary>
        /// Flat header dictionary keyed by header name (case-insensitive).
        /// Multi-value headers are preserved as string arrays, matching the
        /// shape that Invoke-RestMethod surfaces via -ResponseHeadersVariable.
        /// </summary>
        public Dictionary<string, string[]> ResponseHeaders { get; init; } = new();
    }

    // =====================================================================
    // CIPPRestClient
    // =====================================================================
    // Thread-safe, process-scoped HTTP client manager.
    //
    // DESIGN GOALS
    // ------------
    // 1. Eliminate SNAT port exhaustion caused by Invoke-RestMethod creating
    //    a new HttpClient (and therefore new TCP connections) on every call.
    // 2. Enforce per-hostname connection caps to stay within the Azure
    //    Function App SNAT port budget of 125 ports per instance.
    // 3. Tune connection pool parameters independently per destination so
    //    high-volume endpoints (Graph) don't starve low-volume ones (Login).
    //
    // PORT BUDGET (125 total, targeting ~75 allocated, ~50 buffer)
    // -------------------------------------------------------------
    //   Graph          30   microsoft.com graph endpoints
    //   EXO            20   Exchange Online / Outlook endpoints
    //   Login           5   login.microsoftonline.com (token acquisition)
    //   AdminPlane      5   admin.microsoft.com, reports, Defender, etc.
    //   Compliance      5   compliance redirect discovery (no-redirect)
    //   PartnerCenter   5   api.partnercenter.microsoft.com
    //   Default         5   catch-all + absorbs legacy Invoke-RestMethod calls
    //   ─────────────
    //   Total          75   leaves a 50-port buffer for the Functions host,
    //                       Durable extension, AppInsights, Azure SDK clients,
    //                       and any stragglers that bypass the pool.
    //
    // CONCURRENCY ASSUMPTIONS
    // -----------------------
    // PSWorkerInProcConcurrencyUpperBound = 10  (set as an App Setting; this
    //   is the target steady-state value — the caps above are sized for this.)
    // FUNCTIONS_WORKER_PROCESS_COUNT      = 1
    // Traffic split: ~2/3 Graph, ~1/3 EXO
    //
    // At peak (10 concurrent invocations):
    //   ~7 Graph calls in flight   → 30-cap absorbs pagination bursts
    //                                 and fan-out activity workers
    //   ~3 EXO calls in flight     → 20-cap absorbs bulk EXO batches
    //   Login bursts on cold start → 5-cap, backed by aggressive token
    //                                 caching so steady-state is 1-2 conns
    //
    // Graph and EXO caps are larger than the concurrency bound because a
    // single runspace can legitimately have multiple requests in flight
    // (pagination, $batch sub-requests, token + data pre-fetch, parallel
    // retries). The smaller pools (Login/AdminPlane/Compliance/PartnerCenter/
    // Default) are low-volume and can safely queue briefly if saturated.
    //
    // HTTP/2 NOTE
    // -----------
    // Graph and EXO both support HTTP/2. With EnableMultipleHttp2Connections,
    // the handler opens additional H2 connections when the existing ones are
    // saturated, but multiple streams share each TCP connection. In practice
    // real port consumption will be significantly below the configured caps
    // for these endpoints.
    //
    // SINGLETON INITIALISATION
    // ------------------------
    // All singleton HttpClient instances are lazily initialised on first use via
    // a SemaphoreSlim-guarded double-checked lock. Once created they live for
    // the lifetime of the worker process — this is intentional. Disposing and
    // recreating clients would defeat connection pooling entirely.
    // =====================================================================
    public static class CIPPRestClient
    {
        // -----------------------------------------------------------------
        // Singleton HttpClient instances — one per destination group.
        // Each is backed by its own SocketsHttpHandler so connection pool
        // limits are enforced independently per group.
        // -----------------------------------------------------------------
        private static HttpClient? _graphClient;
        private static HttpClient? _exoClient;
        private static HttpClient? _loginClient;
        private static HttpClient? _complianceClient;
        private static HttpClient? _partnerCenterClient;
        private static HttpClient? _adminPlaneClient;
        private static HttpClient? _defaultClient;

        /// <summary>
        /// Guards lazy initialisation. Max count of 1 makes this a binary
        /// semaphore (mutex equivalent) without the thread-affinity of Monitor.
        /// </summary>
        private static readonly SemaphoreSlim _initLock = new(1, 1);

        // -----------------------------------------------------------------
        // Lightweight usage telemetry for diagnostics.
        // -----------------------------------------------------------------
        private static readonly ConcurrentDictionary<string, long> _poolSelections =
            new(StringComparer.OrdinalIgnoreCase);
        private static readonly ConcurrentDictionary<string, long> _poolSuccesses =
            new(StringComparer.OrdinalIgnoreCase);
        private static readonly ConcurrentDictionary<string, long> _poolFailures =
            new(StringComparer.OrdinalIgnoreCase);
        private static readonly ConcurrentDictionary<string, long> _poolTransportErrors =
            new(StringComparer.OrdinalIgnoreCase);
        private static readonly ConcurrentDictionary<string, long> _hostSelections =
            new(StringComparer.OrdinalIgnoreCase);
        private static readonly ConcurrentDictionary<int, long> _statusCodes = new();

        // -----------------------------------------------------------------
        // Client factory helpers
        // -----------------------------------------------------------------
        // Each method builds a SocketsHttpHandler tuned for its destination:
        //
        //   PooledConnectionLifetime  30 min  — upper bound recommended by the
        //     Azure App Service / SocketsHttpHandler guidance. Connections are
        //     recycled after this age to respect DNS TTL changes (e.g. Azure
        //     Traffic Manager failovers). Raising from 15 min halves the
        //     graceful-recycle churn and cuts the TIME_WAIT tail under steady
        //     load — a small but measurable port saving.
        //
        //   PooledConnectionIdleTimeout  2 min — idle connections that have
        //     not been used for 2 minutes are closed and removed from the
        //     pool. Keeps the pool lean during quiet periods.
        //
        //   MaxConnectionsPerServer — hard cap on simultaneous TCP connections
        //     to a single host:port pair. Requests beyond this limit queue
        //     inside the handler rather than opening a new connection, which
        //     is exactly the SNAT-friendly behaviour we want.
        //
        //   HttpClient.Timeout = InfiniteTimeSpan — per-request timeouts are
        //     applied via CancellationToken in SendAsync instead. A shared
        //     HttpClient timeout would race against every in-flight request
        //     and is not safe to use with a singleton client.
        // -----------------------------------------------------------------

        /// <summary>
        /// Graph client — highest throughput, HTTP/2 enabled.
        /// Covers graph.microsoft.com and any *.microsoft.com graph surface.
        /// Cap: 30 connections.
        /// </summary>
        private static HttpClient BuildGraphClient() => new HttpClient(new SocketsHttpHandler
        {
            AutomaticDecompression         = DecompressionMethods.All,
            PooledConnectionLifetime       = TimeSpan.FromMinutes(30),
            PooledConnectionIdleTimeout    = TimeSpan.FromMinutes(2),
            EnableMultipleHttp2Connections = true,   // Graph supports HTTP/2; streams share connections
            AllowAutoRedirect              = true,
            MaxAutomaticRedirections       = 10,
            MaxConnectionsPerServer        = 30,
        }) { Timeout = Timeout.InfiniteTimeSpan };

        /// <summary>
        /// EXO client — Exchange Online and Outlook endpoints.
        /// Covers outlook.office365.com, outlook.office.com, outlook.com,
        /// and *.protection.outlook.com (mail protection / transport).
        /// Cap: 20 connections.
        /// HTTP/2 enabled — EXO REST APIs support it.
        /// </summary>
        private static HttpClient BuildExoClient() => new HttpClient(new SocketsHttpHandler
        {
            AutomaticDecompression         = DecompressionMethods.All,
            PooledConnectionLifetime       = TimeSpan.FromMinutes(30),
            PooledConnectionIdleTimeout    = TimeSpan.FromMinutes(2),
            EnableMultipleHttp2Connections = true,
            AllowAutoRedirect              = true,
            MaxAutomaticRedirections       = 10,
            MaxConnectionsPerServer        = 20,
        }) { Timeout = Timeout.InfiniteTimeSpan };

        /// <summary>
        /// Login client — token acquisition against login.microsoftonline.com.
        /// Cap: 5 connections. HTTP/2 disabled — login.microsoftonline.com
        /// does not benefit from H2 multiplexing for short-lived token
        /// requests, and tokens are cached aggressively so the steady-state
        /// rate of requests is low.
        /// </summary>
        private static HttpClient BuildLoginClient() => new HttpClient(new SocketsHttpHandler
        {
            AutomaticDecompression         = DecompressionMethods.All,
            PooledConnectionLifetime       = TimeSpan.FromMinutes(30),
            PooledConnectionIdleTimeout    = TimeSpan.FromMinutes(2),
            EnableMultipleHttp2Connections = false,
            AllowAutoRedirect              = true,
            MaxAutomaticRedirections       = 5,
            MaxConnectionsPerServer        = 5,
        }) { Timeout = Timeout.InfiniteTimeSpan };

        /// <summary>
        /// Compliance client — used exclusively for EXO compliance URL
        /// discovery (New-ExoRequest with MaximumRedirection = 0).
        /// AllowAutoRedirect is false because the 3xx redirect response IS
        /// the expected result — the Location header contains the real EXO
        /// endpoint for the tenant.
        /// Cap: 5 connections.
        /// HTTP/2 disabled — compliance endpoints are HTTP/1.1 only.
        /// </summary>
        private static HttpClient BuildComplianceClient() => new HttpClient(new SocketsHttpHandler
        {
            AutomaticDecompression         = DecompressionMethods.All,
            PooledConnectionLifetime       = TimeSpan.FromMinutes(30),
            PooledConnectionIdleTimeout    = TimeSpan.FromMinutes(2),
            EnableMultipleHttp2Connections = false,
            AllowAutoRedirect              = false,  // 3xx IS the expected response here
            MaxConnectionsPerServer        = 5,
        }) { Timeout = Timeout.InfiniteTimeSpan };

        /// <summary>
        /// Partner Center client — dedicated lane for high-frequency partner
        /// APIs so they do not compete with default traffic.
        /// Covers api.partnercenter.microsoft.com and related subdomains.
        /// Cap: 5 connections.
        /// </summary>
        private static HttpClient BuildPartnerCenterClient() => new HttpClient(new SocketsHttpHandler
        {
            AutomaticDecompression         = DecompressionMethods.All,
            PooledConnectionLifetime       = TimeSpan.FromMinutes(30),
            PooledConnectionIdleTimeout    = TimeSpan.FromMinutes(2),
            EnableMultipleHttp2Connections = true,
            AllowAutoRedirect              = true,
            MaxAutomaticRedirections       = 10,
            MaxConnectionsPerServer        = 5,
        }) { Timeout = Timeout.InfiniteTimeSpan };

        /// <summary>
        /// Admin plane client — dedicated lane for Microsoft admin/reporting
        /// surfaces (Admin Center, Office reports, Defender APIs, etc.).
        /// Cap: 5 connections.
        /// </summary>
        private static HttpClient BuildAdminPlaneClient() => new HttpClient(new SocketsHttpHandler
        {
            AutomaticDecompression         = DecompressionMethods.All,
            PooledConnectionLifetime       = TimeSpan.FromMinutes(30),
            PooledConnectionIdleTimeout    = TimeSpan.FromMinutes(2),
            EnableMultipleHttp2Connections = true,
            AllowAutoRedirect              = true,
            MaxAutomaticRedirections       = 10,
            MaxConnectionsPerServer        = 5,
        }) { Timeout = Timeout.InfiniteTimeSpan };

        /// <summary>
        /// Default catch-all client — handles any hostname not matched by the
        /// routing switch, including unknown Microsoft endpoints and any
        /// third-party APIs called via this wrapper.
        /// Cap: 5 connections. This also absorbs the small number of legacy
        /// Invoke-RestMethod calls that bypass the pool entirely, which consume
        /// ports outside our accounting.
        /// </summary>
        private static HttpClient BuildDefaultClient() => new HttpClient(new SocketsHttpHandler
        {
            AutomaticDecompression         = DecompressionMethods.All,
            PooledConnectionLifetime       = TimeSpan.FromMinutes(30),
            PooledConnectionIdleTimeout    = TimeSpan.FromMinutes(2),
            EnableMultipleHttp2Connections = true,
            AllowAutoRedirect              = true,
            MaxAutomaticRedirections       = 10,
            MaxConnectionsPerServer        = 5,
        }) { Timeout = Timeout.InfiniteTimeSpan };

        // -----------------------------------------------------------------
        // Lazy initialisation — double-checked locking via SemaphoreSlim
        // -----------------------------------------------------------------
        // All five clients are initialised together in a single lock pass to
        // avoid partial initialisation states where some clients are ready and
        // others are not. The null check outside the semaphore is the "fast
        // path" — once all clients exist no locking overhead is incurred.
        // -----------------------------------------------------------------
        private static async Task EnsureClientsAsync()
        {
            // Fast path — all clients already initialised
            if (_graphClient      is not null &&
                _exoClient        is not null &&
                _loginClient      is not null &&
                _complianceClient is not null &&
                _partnerCenterClient is not null &&
                _adminPlaneClient is not null &&
                _defaultClient    is not null)
                return;

            await _initLock.WaitAsync().ConfigureAwait(false);
            try
            {
                // Re-check inside the lock (double-checked locking pattern)
                if (_graphClient is null)
                {
                    _graphClient      = BuildGraphClient();
                    _exoClient        = BuildExoClient();
                    _loginClient      = BuildLoginClient();
                    _complianceClient = BuildComplianceClient();
                    _partnerCenterClient = BuildPartnerCenterClient();
                    _adminPlaneClient = BuildAdminPlaneClient();
                    _defaultClient    = BuildDefaultClient();
                }
            }
            finally
            {
                _initLock.Release();
            }
        }

        // -----------------------------------------------------------------
        // Client routing
        // -----------------------------------------------------------------
        // Selects the appropriate singleton client based on the request URI
        // and the MaximumRedirection flag.
        //
        // ROUTING RULES (evaluated in order):
        //   1. noRedirect flag OR *.compliance.microsoft.com
        //      → complianceClient (AllowAutoRedirect = false)
        //   2. *.graph.microsoft.com
        //      → graphClient
        //   3. login.microsoftonline.com
        //      → loginClient
        //   4. outlook.office365.com / outlook.office.com / outlook.com /
        //      *.protection.outlook.com
        //      → exoClient
        //   5. Everything else
        //      → defaultClient
        //
        // NOTE: The compliance check is first because a compliance URL may
        // technically match other patterns (e.g. *.microsoft.com) but must
        // always use the no-redirect client regardless.
        // -----------------------------------------------------------------
        private static (HttpClient Client, string Pool, string Host) SelectClient(string uri, bool noRedirect)
        {
            var requestUri = new Uri(uri);
            var host = requestUri.Host;

            // Rule 1 — compliance / no-redirect always wins
            if (noRedirect || host.EndsWith(".compliance.microsoft.com",
                StringComparison.OrdinalIgnoreCase))
                return (_complianceClient!, "Compliance", host);

            // Rule 1b — compliance InvokeCommand (needs redirects, but NOT HTTP/2)
            // These are the regional compliance endpoints like nam10b.ps.compliance.protection.outlook.com
            // They must be checked BEFORE the EXO *.protection.outlook.com rule.
            if (host.EndsWith(".compliance.protection.outlook.com", StringComparison.OrdinalIgnoreCase)
                || host.Equals("ps.compliance.protection.outlook.com", StringComparison.OrdinalIgnoreCase))
                return (_loginClient!, "Compliance", host);

            return host switch
            {
                // Rule 2 — Graph
                var h when h.Equals("graph.microsoft.com",
                    StringComparison.OrdinalIgnoreCase)                    => (_graphClient!, "Graph", host),
                var h when h.EndsWith(".graph.microsoft.com",
                    StringComparison.OrdinalIgnoreCase)                    => (_graphClient!, "Graph", host),

                // Rule 3 — Login / token acquisition
                var h when h.Equals("login.microsoftonline.com",
                    StringComparison.OrdinalIgnoreCase)                    => (_loginClient!, "Login", host),
                var h when h.Equals("login.microsoftonline.us",
                    StringComparison.OrdinalIgnoreCase)                    => (_loginClient!, "Login", host),
                var h when h.Equals("login.windows.net",
                    StringComparison.OrdinalIgnoreCase)                    => (_loginClient!, "Login", host),

                // Rule 4 — EXO / Outlook endpoints
                var h when h.Equals("outlook.office365.com",
                    StringComparison.OrdinalIgnoreCase)                    => (_exoClient!, "Exo", host),
                var h when h.Equals("outlook.office.com",
                    StringComparison.OrdinalIgnoreCase)                    => (_exoClient!, "Exo", host),
                var h when h.EndsWith(".outlook.com",
                    StringComparison.OrdinalIgnoreCase)                    => (_exoClient!, "Exo", host),
                var h when h.EndsWith(".protection.outlook.com",
                    StringComparison.OrdinalIgnoreCase)                    => (_exoClient!, "Exo", host),

                // Rule 5 — Partner Center dedicated lane
                var h when h.Equals("api.partnercenter.microsoft.com",
                    StringComparison.OrdinalIgnoreCase)                    => (_partnerCenterClient!, "PartnerCenter", host),
                var h when h.EndsWith(".partnercenter.microsoft.com",
                    StringComparison.OrdinalIgnoreCase)                    => (_partnerCenterClient!, "PartnerCenter", host),

                // Rule 6 — Microsoft admin/reporting/security lanes
                var h when IsAdminPlaneHost(h)                             => (_adminPlaneClient!, "AdminPlane", host),

                // Rule 7 — catch-all
                _                                                           => (_defaultClient!, "Default", host),
            };
        }

        private static bool IsAdminPlaneHost(string host) => host switch
        {
            var h when h.Equals("admin.microsoft.com", StringComparison.OrdinalIgnoreCase) => true,
            var h when h.Equals("manage.office.com", StringComparison.OrdinalIgnoreCase) => true,
            var h when h.Equals("reports.office.com", StringComparison.OrdinalIgnoreCase) => true,
            var h when h.Equals("api.securitycenter.microsoft.com", StringComparison.OrdinalIgnoreCase) => true,
            var h when h.Equals("licensing.m365.microsoft.com", StringComparison.OrdinalIgnoreCase) => true,
            var h when h.Equals("substrate.office.com", StringComparison.OrdinalIgnoreCase) => true,
            _ => false,
        };

        private static void TrackPoolSelection(string pool, string host)
        {
            _poolSelections.AddOrUpdate(pool, 1, static (_, current) => current + 1);
            _hostSelections.AddOrUpdate(host, 1, static (_, current) => current + 1);
        }

        private static void TrackPoolResult(string pool, bool success, int statusCode)
        {
            if (success)
                _poolSuccesses.AddOrUpdate(pool, 1, static (_, current) => current + 1);
            else
                _poolFailures.AddOrUpdate(pool, 1, static (_, current) => current + 1);

            _statusCodes.AddOrUpdate(statusCode, 1, static (_, current) => current + 1);
        }

        private static void TrackTransportError(string pool)
        {
            _poolTransportErrors.AddOrUpdate(pool, 1, static (_, current) => current + 1);
        }

        // -----------------------------------------------------------------
        // Public entry point — synchronous wrapper for PowerShell
        // -----------------------------------------------------------------
        // PowerShell cannot natively await Tasks, so this synchronous shim
        // calls SendAsync via GetAwaiter().GetResult(). This is safe here
        // because Azure Functions PowerShell workers do not have a
        // SynchronizationContext that could deadlock on .Result/.GetResult().
        // -----------------------------------------------------------------
        public static HttpResult Send(
            string                      uri,
            string                      method             = "GET",
            string?                     body               = null,
            Dictionary<string, string>? headers            = null,
            string?                     contentType        = null,
            bool                        skipErrorCheck     = false,
            int                         timeoutSec         = 100,
            int                         maximumRedirection = -1)
        {
            return SendAsync(uri, method, body, headers, contentType,
                             skipErrorCheck, timeoutSec, maximumRedirection)
                   .GetAwaiter().GetResult();
        }

        // -----------------------------------------------------------------
        // Core async implementation
        // -----------------------------------------------------------------
        public static async Task<HttpResult> SendAsync(
            string                      uri,
            string                      method             = "GET",
            string?                     body               = null,
            Dictionary<string, string>? headers            = null,
            string?                     contentType        = null,
            bool                        skipErrorCheck     = false,
            int                         timeoutSec         = 100,
            int                         maximumRedirection = -1)
        {
            await EnsureClientsAsync().ConfigureAwait(false);

            // Select the correct pooled client for this URI
            bool noRedirect = maximumRedirection == 0;
            var selection = SelectClient(uri, noRedirect);
            var client = selection.Client;
            TrackPoolSelection(selection.Pool, selection.Host);

            using var request = new HttpRequestMessage(new HttpMethod(method), new Uri(uri));

            // ----------------------------------------------------------
            // Headers
            // ----------------------------------------------------------
            // HttpRequestMessage.Headers only accepts request headers
            // (e.g. Authorization, Accept). Content headers (e.g. Content-Type,
            // Content-Encoding) must be set on the HttpContent object.
            // Headers that are rejected by TryAddWithoutValidation are deferred
            // and applied to the content once it is created below.
            // ----------------------------------------------------------
            var deferredContentHeaders = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (headers is not null)
            {
                foreach (var (key, value) in headers)
                {
                    if (!request.Headers.TryAddWithoutValidation(key, value))
                        deferredContentHeaders[key] = value;
                }
            }

            // ----------------------------------------------------------
            // Body serialisation
            // ----------------------------------------------------------
            // The body arrives from PowerShell as a pre-serialised string
            // (the PS wrapper handles Hashtable → form-encode and
            // PSObject → JSON conversion). We only need to wrap it in
            // StringContent with the correct encoding and media type.
            //
            // Content-Type parsing splits on ';' to separate the media type
            // from any charset parameter, then re-applies the full value so
            // that 'application/json; charset=utf-8' round-trips correctly.
            // ----------------------------------------------------------
            if (body is not null)
            {
                var effectiveCt   = string.IsNullOrWhiteSpace(contentType)
                    ? "application/json; charset=utf-8"
                    : contentType;

                var ctParts       = effectiveCt.Split(';', StringSplitOptions.TrimEntries);
                var mediaTypePart = ctParts[0];

                var encoding = Encoding.UTF8;
                foreach (var part in ctParts.Skip(1))
                {
                    if (part.StartsWith("charset=", StringComparison.OrdinalIgnoreCase))
                    {
                        var charsetName = part["charset=".Length..].Trim('"', '\'', ' ');
                        try { encoding = Encoding.GetEncoding(charsetName); } catch { /* keep UTF-8 */ }
                        break;
                    }
                }

                request.Content = new StringContent(body, encoding, mediaTypePart);

                // Re-apply the full Content-Type (including charset) because
                // StringContent's constructor strips parameters on some runtimes
                if (ctParts.Length > 1)
                {
                    request.Content.Headers.Remove("Content-Type");
                    request.Content.Headers.TryAddWithoutValidation("Content-Type", effectiveCt);
                }
            }

            // Apply any deferred content headers (e.g. Content-Encoding)
            foreach (var (key, value) in deferredContentHeaders)
            {
                request.Content ??= new StringContent(string.Empty, Encoding.UTF8);
                request.Content.Headers.Remove(key);
                request.Content.Headers.TryAddWithoutValidation(key, value);
            }

            // ----------------------------------------------------------
            // Per-request timeout via CancellationToken
            // ----------------------------------------------------------
            // HttpClient.Timeout is set to InfiniteTimeSpan on all singleton
            // clients so a shared timeout cannot fire across unrelated requests.
            // Instead we create a CancellationTokenSource per request with the
            // caller-specified timeout. timeoutSec = 0 means no timeout.
            // ----------------------------------------------------------
            using var cts = timeoutSec > 0
                ? new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSec))
                : null;
            var token = cts?.Token ?? CancellationToken.None;

            // ----------------------------------------------------------
            // Send
            // ----------------------------------------------------------
            HttpResponseMessage response;
            try
            {
                response = await client.SendAsync(request, token).ConfigureAwait(false);
            }
            catch
            {
                TrackTransportError(selection.Pool);
                throw;
            }

            using (response)
            {
                var statusCode = (int)response.StatusCode;
                var content    = response.Content is not null
                    ? await response.Content.ReadAsStringAsync(token).ConfigureAwait(false)
                    : string.Empty;

            // ----------------------------------------------------------
            // Response headers
            // ----------------------------------------------------------
            // Combine response headers and content headers into one dictionary
            // so the PowerShell wrapper can surface them via -ResponseHeadersVariable
            // with the same shape as Invoke-RestMethod.
            // ----------------------------------------------------------
                var allHeaders = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
                foreach (var h in response.Headers)
                    allHeaders[h.Key] = h.Value.ToArray();
                if (response.Content is not null)
                    foreach (var h in response.Content.Headers)
                        allHeaders[h.Key] = h.Value.ToArray();

            // ----------------------------------------------------------
            // Error handling
            // ----------------------------------------------------------
            // When MaximumRedirection == 0 we always skip the error check
            // because the compliance client expects a 3xx response — the
            // redirect Location header IS the result we want.
            // ----------------------------------------------------------
                bool effectiveSkipCheck = skipErrorCheck || noRedirect;
                TrackPoolResult(selection.Pool, response.IsSuccessStatusCode, statusCode);
                if (!effectiveSkipCheck && !response.IsSuccessStatusCode)
                    throw new HttpRequestException(
                        $"Response status code does not indicate success: {statusCode}",
                        inner: null,
                        statusCode: response.StatusCode);

            // ----------------------------------------------------------
            // JSON detection
            // ----------------------------------------------------------
            // Check Content-Type first, then fall back to sniffing the first
            // character of the body. This handles APIs that return JSON with
            // a non-standard or missing Content-Type header.
            // ----------------------------------------------------------
                var mediaType = response.Content?.Headers.ContentType?.MediaType ?? string.Empty;
                var trimmed   = content.TrimStart();
                var isJson    = mediaType.Contains("application/json", StringComparison.OrdinalIgnoreCase)
                             || trimmed.StartsWith('{')
                             || trimmed.StartsWith('[');

                return new HttpResult
                {
                    StatusCode      = statusCode,
                    IsSuccess       = response.IsSuccessStatusCode,
                    Content         = content,
                    IsJson          = isJson,
                    ResponseHeaders = allHeaders,
                };
            }
        }

        // =================================================================
        // Diagnostics
        // =================================================================
        // Returns a JSON string describing the current pool configuration.
        // Call this from profile.ps1 on startup to verify the configuration
        // is live and to establish a baseline in your function app logs.
        //
        // HOW TO MONITOR POOL HEALTH
        // --------------------------
        // 1. STARTUP BASELINE (profile.ps1)
        //    Add-Type -Path "$PSScriptRoot/CIPP.dll"
        //    $diag = [CIPP.CIPPRestClient]::GetDiagnostics()
        //    Write-Host "CIPPRestClient config: $diag"
        //
        // 2. AZURE MONITOR / APP INSIGHTS
        //    The most useful metric for SNAT health is:
        //      Metric: "SNAT Connection Count" (under Networking in the portal)
        //      Alert:  > 100 connections sustained for > 5 minutes
        //    Also watch:
        //      "Connection Errors" for failed port allocations
        //      "Http 5xx" spike often correlates with SNAT exhaustion
        //
        // 3. KUSTO QUERY (App Insights / Log Analytics)
        //    Use this to correlate SNAT port usage with function invocations:
        //
        //    AzureMetrics
        //    | where MetricName == "SnatConnectionCount"
        //    | summarize avg(Average), max(Maximum) by bin(TimeGenerated, 1m)
        //    | render timechart
        //
        // 4. WHAT HEALTHY LOOKS LIKE
        //    - SNAT count rises quickly during ramp-up then plateaus
        //    - Plateau value is well below 110 (your allocated budget)
        //    - No "connection refused" or socket exhaustion errors in logs
        //    - Port count does NOT grow linearly with request volume
        //
        // 5. WHAT UNHEALTHY LOOKS LIKE
        //    - SNAT count continuously climbing with no plateau
        //    - Errors containing "An attempt was made to access a socket in
        //      a way forbidden by its access permissions"
        //    - HTTP 500s or timeouts correlating with high concurrency periods
        //
        // 6. POOL SATURATION (requests queuing inside the handler)
        //    There is no built-in .NET metric for "requests waiting for a
        //    pooled connection". If you suspect queuing is adding latency,
        //    instrument SendAsync with a Stopwatch before and after
        //    client.SendAsync and log the delta. Long pre-send waits with no
        //    network activity indicate pool saturation — raise the cap for
        //    that client group or reduce concurrency.
        // =================================================================
        public static string GetDiagnostics()
        {
            return JsonSerializer.Serialize(new
            {
                Initialized = _graphClient is not null,
                PoolUsage = new
                {
                    Selections = _poolSelections.OrderBy(kvp => kvp.Key)
                        .ToDictionary(kvp => kvp.Key, kvp => kvp.Value),
                    Successes = _poolSuccesses.OrderBy(kvp => kvp.Key)
                        .ToDictionary(kvp => kvp.Key, kvp => kvp.Value),
                    Failures = _poolFailures.OrderBy(kvp => kvp.Key)
                        .ToDictionary(kvp => kvp.Key, kvp => kvp.Value),
                    TransportErrors = _poolTransportErrors.OrderBy(kvp => kvp.Key)
                        .ToDictionary(kvp => kvp.Key, kvp => kvp.Value),
                    TopHosts = _hostSelections
                        .OrderByDescending(kvp => kvp.Value)
                        .ThenBy(kvp => kvp.Key, StringComparer.OrdinalIgnoreCase)
                        .Take(25)
                        .Select(kvp => new { Host = kvp.Key, Requests = kvp.Value })
                        .ToArray(),
                    StatusCodes = _statusCodes
                        .OrderBy(kvp => kvp.Key)
                        .ToDictionary(kvp => kvp.Key.ToString(), kvp => kvp.Value),
                },
            }, new JsonSerializerOptions { WriteIndented = true });
        }

        /// <summary>
        /// Resets the runtime pool telemetry counters. Intended for the
        /// diagnostics profile endpoint so operators can clear the counts
        /// between observation windows without restarting the worker.
        /// </summary>
        public static void ResetDiagnostics()
        {
            _poolSelections.Clear();
            _poolSuccesses.Clear();
            _poolFailures.Clear();
            _poolTransportErrors.Clear();
            _hostSelections.Clear();
            _statusCodes.Clear();
        }
    }

    public sealed class TokenCacheLookupResult
    {
        public bool   Found            { get; init; }
        public string TokenPayloadJson { get; init; } = string.Empty;
        public long   ExpiresOnUnix    { get; init; }
    }

    // =====================================================================
    // CIPPTokenCache
    // =====================================================================
    // Process-wide token cache shared by all runspaces in the worker process.
    // The cache is intentionally generic: PowerShell constructs the key and
    // controls token acquisition semantics. C# only handles storage, expiry,
    // and lightweight diagnostics.
    // =====================================================================
    public static class CIPPTokenCache
    {
        private sealed class TokenCacheEntry
        {
            public string TokenPayloadJson { get; init; } = string.Empty;
            public long   ExpiresOnUnix    { get; init; }
            public long   CachedAtUnix     { get; init; }
        }

        private static readonly ConcurrentDictionary<string, TokenCacheEntry> _entries =
            new(StringComparer.OrdinalIgnoreCase);

        // Per-key semaphores to prevent thundering herd / cache stampede.
        // When multiple runspaces miss the cache for the same key simultaneously,
        // only one acquires a token while the others wait and reuse the result.
        private static readonly ConcurrentDictionary<string, SemaphoreSlim> _keyLocks =
            new(StringComparer.OrdinalIgnoreCase);

        private static long _hits;
        private static long _misses;
        private static long _sets;
        private static long _invalidations;
        private static long _expiredRemovals;
        private static long _lockWaits;

        public static string BuildKey(
            string tenantId,
            string scope,
            bool asApp,
            string? clientId,
            string? grantType)
        {
            return string.Join("|",
                (tenantId ?? string.Empty).Trim().ToLowerInvariant(),
                (scope ?? string.Empty).Trim().ToLowerInvariant(),
                asApp ? "app" : "delegated",
                (clientId ?? string.Empty).Trim().ToLowerInvariant(),
                (grantType ?? string.Empty).Trim().ToLowerInvariant());
        }

        public static TokenCacheLookupResult Lookup(string key, int refreshSkewSeconds = 120)
        {
            if (string.IsNullOrWhiteSpace(key))
            {
                Interlocked.Increment(ref _misses);
                return new TokenCacheLookupResult { Found = false };
            }

            if (!_entries.TryGetValue(key, out var entry))
            {
                Interlocked.Increment(ref _misses);
                return new TokenCacheLookupResult { Found = false };
            }

            var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            var refreshBoundary = entry.ExpiresOnUnix - Math.Max(0, refreshSkewSeconds);
            if (now >= refreshBoundary)
            {
                _entries.TryRemove(key, out _);
                Interlocked.Increment(ref _expiredRemovals);
                Interlocked.Increment(ref _misses);
                return new TokenCacheLookupResult { Found = false };
            }

            Interlocked.Increment(ref _hits);
            return new TokenCacheLookupResult
            {
                Found            = true,
                TokenPayloadJson = entry.TokenPayloadJson,
                ExpiresOnUnix    = entry.ExpiresOnUnix,
            };
        }

        public static void Store(string key, string tokenPayloadJson, long expiresOnUnix)
        {
            if (string.IsNullOrWhiteSpace(key) ||
                string.IsNullOrWhiteSpace(tokenPayloadJson) ||
                expiresOnUnix <= 0)
                return;

            _entries[key] = new TokenCacheEntry
            {
                TokenPayloadJson = tokenPayloadJson,
                ExpiresOnUnix    = expiresOnUnix,
                CachedAtUnix     = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            };

            Interlocked.Increment(ref _sets);
        }

        public static void Remove(string key)
        {
            if (string.IsNullOrWhiteSpace(key))
                return;

            if (_entries.TryRemove(key, out _))
                Interlocked.Increment(ref _invalidations);
        }

        public static int CompactExpired(int refreshSkewSeconds = 0, int maxRemovals = 1000)
        {
            var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            var removed = 0;
            var skew = Math.Max(0, refreshSkewSeconds);

            foreach (var kvp in _entries)
            {
                if (removed >= maxRemovals)
                    break;

                if (now >= (kvp.Value.ExpiresOnUnix - skew) && _entries.TryRemove(kvp.Key, out _))
                {
                    removed++;
                    Interlocked.Increment(ref _expiredRemovals);
                }
            }

            return removed;
        }

        /// <summary>
        /// Acquire a per-key lock to prevent thundering herd on cache miss.
        /// Returns true if the lock was acquired within the timeout.
        /// After acquiring, the caller should Lookup() again (double-check),
        /// then acquire the token and Store() it, then ReleaseLock().
        /// </summary>
        public static bool AcquireLock(string key, int timeoutMs = 30000)
        {
            if (string.IsNullOrWhiteSpace(key))
                return false;

            var sem = _keyLocks.GetOrAdd(key, _ => new SemaphoreSlim(1, 1));
            Interlocked.Increment(ref _lockWaits);
            return sem.Wait(timeoutMs);
        }

        /// <summary>
        /// Release the per-key lock after token acquisition and Store().
        /// Safe to call even if AcquireLock returned false (no-ops gracefully).
        /// </summary>
        public static void ReleaseLock(string key)
        {
            if (string.IsNullOrWhiteSpace(key))
                return;

            if (_keyLocks.TryGetValue(key, out var sem))
            {
                try { sem.Release(); } catch (SemaphoreFullException) { /* already released */ }
            }
        }

        public static string GetDiagnostics()
        {
            return JsonSerializer.Serialize(new
            {
                Entries = _entries.Count,
                Hits = Interlocked.Read(ref _hits),
                Misses = Interlocked.Read(ref _misses),
                Sets = Interlocked.Read(ref _sets),
                Invalidations = Interlocked.Read(ref _invalidations),
                ExpiredRemovals = Interlocked.Read(ref _expiredRemovals),
                LockWaits = Interlocked.Read(ref _lockWaits),
                ActiveLocks = _keyLocks.Count,
            }, new JsonSerializerOptions { WriteIndented = true });
        }

        public static void ResetDiagnostics()
        {
            Interlocked.Exchange(ref _hits, 0);
            Interlocked.Exchange(ref _misses, 0);
            Interlocked.Exchange(ref _sets, 0);
            Interlocked.Exchange(ref _invalidations, 0);
            Interlocked.Exchange(ref _expiredRemovals, 0);
            Interlocked.Exchange(ref _lockWaits, 0);
        }
    }
}
