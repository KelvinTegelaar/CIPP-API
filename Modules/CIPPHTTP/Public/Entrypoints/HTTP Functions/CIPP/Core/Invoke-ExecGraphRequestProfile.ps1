function Invoke-ExecGraphRequestProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Mode = $Request.Query.Mode

    # ── Diagnostics-only mode ───────────────────────────────────────────
    # Returns a point-in-time snapshot of the CIPPHttp DLL runtime state —
    # pool usage counters, top hosts, status code distribution, and the
    # CIPPTokenCache entry count. No Graph/EXO calls, no tenant required.
    if ($Mode -eq 'Diagnostics') {
        $Reset = [System.Convert]::ToBoolean($Request.Query.Reset ?? $false)

        $RestDiag  = [CIPP.CIPPRestClient]::GetDiagnostics() | ConvertFrom-Json
        $CacheDiag = [CIPP.CIPPTokenCache]::GetDiagnostics()  | ConvertFrom-Json

        if ($Reset) {
            [CIPP.CIPPRestClient]::ResetDiagnostics()
        }

        return [HttpResponseContext]@{
            StatusCode = 200
            Body       = [PSCustomObject]@{
                Mode              = 'Diagnostics'
                CapturedAt        = (Get-Date).ToUniversalTime().ToString('o')
                CountersReset     = $Reset
                RestClient        = $RestDiag
                TokenCache        = $CacheDiag
            }
        }
    }

    $TenantFilter = $Request.Query.tenantFilter
    $Endpoint = $Request.Query.Endpoint
    if (!$TenantFilter -or !$Endpoint) {
        return [HttpResponseContext]@{
            StatusCode = 400
            Body       = @{ error = 'tenantFilter and Endpoint are required' } | ConvertTo-Json
        }
    }

    $Timings = [System.Collections.Generic.List[object]]::new()
    $OverallSw = [System.Diagnostics.Stopwatch]::StartNew()

    function Add-Timing($Step, $Detail, $ElapsedMs) {
        $Timings.Add([PSCustomObject]@{
                Step      = $Step
                Detail    = $Detail
                Ms        = [math]::Round($ElapsedMs, 1)
                WallClock = [math]::Round($OverallSw.Elapsed.TotalMilliseconds, 1)
            })
    }

    # ── 1. Parameter setup ──────────────────────────────────────────────
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $Parameters = @{}
    foreach ($key in @('$filter', 'graphFilter', '$select', '$expand', 'expand', '$top', '$count', '$orderby', '$search', '$format')) {
        if ($Request.Query.$key) {
            if ($key -eq 'graphFilter') { $Parameters.'$filter' = $Request.Query.$key }
            elseif ($key -eq '$count') { $Parameters.$key = ([string]([System.Boolean]$Request.Query.$key)).ToLower() }
            else { $Parameters.$key = $Request.Query.$key }
        }
    }
    $sw.Stop()
    Add-Timing 'ParameterSetup' 'Extracted query params' $sw.Elapsed.TotalMilliseconds

    # ── 2. Graph URL build ──────────────────────────────────────────────
    $sw.Restart()
    $Version = if ($Request.Query.Version) { $Request.Query.Version } else { 'beta' }
    $Endpoint = $Endpoint -replace '^/', ''
    $GraphQuery = [System.UriBuilder]('https://graph.microsoft.com/{0}/{1}' -f $Version, $Endpoint)
    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($Item in ($Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        $val = $Item.Value
        if ($val -is [System.Boolean]) { $val = $val.ToString().ToLower() }
        if ($val) { $ParamCollection.Add($Item.Key, $val) }
    }
    $GraphQuery.Query = $ParamCollection.ToString()
    $GraphUrl = $GraphQuery.ToString()
    $sw.Stop()
    Add-Timing 'UrlBuild' $GraphUrl $sw.Elapsed.TotalMilliseconds

    # ── 3. Get-CIPPAuthentication (env check) ───────────────────────────
    $sw.Restart()
    $envPresent = [bool]$env:ApplicationID -and [bool]$env:ApplicationSecret -and [bool]$env:RefreshToken
    if (!$env:SetFromProfile) {
        Get-CIPPAuthentication | Out-Null
    }
    $sw.Stop()
    Add-Timing 'GetCIPPAuthentication' "EnvPresent=$envPresent SetFromProfile=$($env:SetFromProfile)" $sw.Elapsed.TotalMilliseconds

    # ── 4. CIPPTokenCache state ──────────────────────────────────────────
    $sw.Restart()
    $scope = 'https://graph.microsoft.com/.default'
    $CacheClientId = [string]$env:ApplicationID
    $CacheKeyRefresh = [CIPP.CIPPTokenCache]::BuildKey([string]$TenantFilter, [string]$scope, $false, $CacheClientId, 'refresh_token')
    $CacheKeyClient = [CIPP.CIPPTokenCache]::BuildKey([string]$TenantFilter, [string]$scope, $true, $CacheClientId, 'client_credentials')
    $LookupRefresh = [CIPP.CIPPTokenCache]::Lookup($CacheKeyRefresh, 120)
    $LookupClient  = [CIPP.CIPPTokenCache]::Lookup($CacheKeyClient, 120)
    $CacheDiag     = [CIPP.CIPPTokenCache]::GetDiagnostics() | ConvertFrom-Json
    $coreState = @{
        TokenCachedRefresh = $LookupRefresh.Found
        TokenCachedClient  = $LookupClient.Found
        CacheCount         = $CacheDiag.Entries
        CacheType          = 'CIPPTokenCache'
        CacheDiagnostics   = $CacheDiag
    }
    $sw.Stop()
    Add-Timing 'CIPPTokenCacheState' "CacheCount=$($coreState.CacheCount) RefreshCached=$($coreState.TokenCachedRefresh) ClientCached=$($coreState.TokenCachedClient)" $sw.Elapsed.TotalMilliseconds

    # ── 5. Get-AuthorisedRequest ────────────────────────────────────────
    $sw.Restart()
    $isAuth = Get-AuthorisedRequest -Uri $GraphUrl -TenantID $TenantFilter
    $sw.Stop()
    Add-Timing 'GetAuthorisedRequest' "Authorised=$isAuth" $sw.Elapsed.TotalMilliseconds

    # ── 6. Get-GraphToken ───────────────────────────────────────────────
    $sw.Restart()
    $headers = Get-GraphToken -tenantid $TenantFilter -scope $scope
    $sw.Stop()
    Add-Timing 'GetGraphToken' "HasAuth=$([bool]$headers.Authorization)" $sw.Elapsed.TotalMilliseconds

    # ── 7. Raw Invoke-RestMethod (baseline — no wrapper overhead) ──────
    $sw.Restart()
    $directRequest = @{
        Uri         = $GraphUrl
        Method      = 'GET'
        Headers     = $headers
        ContentType = 'application/json; charset=utf-8'
    }
    $directResult = Invoke-RestMethod @directRequest
    $directCount = if ($directResult.value) { $directResult.value.Count } else { 1 }
    $sw.Stop()
    Add-Timing 'DirectInvokeRestMethod' "ResultCount=$directCount" $sw.Elapsed.TotalMilliseconds

    # ── 8. Invoke-CIPPRestMethod (pooled C# client — no wrapper) ───────
    $sw.Restart()
    $pooledRequest = @{
        Uri         = $GraphUrl
        Method      = 'GET'
        Headers     = $headers
        ContentType = 'application/json; charset=utf-8'
    }
    $pooledResult = Invoke-CIPPRestMethod @pooledRequest
    $pooledCount = if ($pooledResult.value) { $pooledResult.value.Count } else { 1 }
    $sw.Stop()
    Add-Timing 'PooledCIPPRestMethod' "ResultCount=$pooledCount" $sw.Elapsed.TotalMilliseconds

    # ── 9. Get-GraphRequestList (full wrapper) ──────────────────────────
    $sw.Restart()
    $ManualPagination = [System.Boolean]$Request.Query.manualPagination
    $listParams = @{
        TenantFilter     = $TenantFilter
        Endpoint         = $Request.Query.Endpoint
        Parameters       = ($Parameters.Clone())
        ManualPagination = $ManualPagination
        SkipCache        = $true
    }
    $listParams.Parameters.Remove('$count')
    $listResult = Get-GraphRequestList @listParams
    $listCount = if ($listResult -is [array]) { $listResult.Count } else { 1 }
    $sw.Stop()
    Add-Timing 'GetGraphRequestList' "ResultCount=$listCount" $sw.Elapsed.TotalMilliseconds

    # ── 10. CIPPTokenCache state after calls ─────────────────────────────
    $sw.Restart()
    $LookupRefreshAfter = [CIPP.CIPPTokenCache]::Lookup($CacheKeyRefresh, 120)
    $LookupClientAfter  = [CIPP.CIPPTokenCache]::Lookup($CacheKeyClient, 120)
    $CacheDiagAfter     = [CIPP.CIPPTokenCache]::GetDiagnostics() | ConvertFrom-Json
    $coreStateAfter = @{
        TokenCachedRefresh = $LookupRefreshAfter.Found
        TokenCachedClient  = $LookupClientAfter.Found
        CacheCount         = $CacheDiagAfter.Entries
        CacheDiagnostics   = $CacheDiagAfter
    }
    $sw.Stop()
    Add-Timing 'CIPPTokenCacheStateAfter' "CacheCount=$($coreStateAfter.CacheCount) RefreshCached=$($coreStateAfter.TokenCachedRefresh) ClientCached=$($coreStateAfter.TokenCachedClient)" $sw.Elapsed.TotalMilliseconds

    $OverallSw.Stop()
    Add-Timing 'Total' 'End-to-end' $OverallSw.Elapsed.TotalMilliseconds

    $ProfileData = [PSCustomObject]@{
        Tenant          = $TenantFilter
        Endpoint        = $Request.Query.Endpoint
        GraphUrl        = $GraphUrl
        CoreStateBefore = $coreState
        CoreStateAfter  = $coreStateAfter
        Timings         = @($Timings)
    }

    return [HttpResponseContext]@{
        StatusCode = 200
        Body       = $ProfileData
    }
}
