function Invoke-ExecGraphRequestProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

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

    # ── 4. CIPPCore module state ────────────────────────────────────────
    $sw.Restart()
    $scope = 'https://graph.microsoft.com/.default'
    # Match Get-GraphToken's key format: $asApp is $null when not passed, so key ends with empty string
    $TokenKeyNull = '{0}-{1}-{2}' -f $TenantFilter, $scope, $null
    $TokenKeyFalse = '{0}-{1}-{2}' -f $TenantFilter, $scope, $false
    $coreState = & (Get-Module CIPPCore) {
        $keyNull = $args[0]
        $keyFalse = $args[1]
        $cachedNull = $script:AccessTokens.$keyNull
        $cachedFalse = $script:AccessTokens.$keyFalse
        $now = [int](Get-Date -UFormat %s -Millisecond 0)
        @{
            TokenCachedNull  = [bool]($cachedNull -and $now -lt $cachedNull.expires_on)
            TokenCachedFalse = [bool]($cachedFalse -and $now -lt $cachedFalse.expires_on)
            CacheKeys        = if ($script:AccessTokens) { @($script:AccessTokens.Keys) } else { @() }
            CacheType        = if ($script:AccessTokens) { $script:AccessTokens.GetType().Name } else { 'null' }
            CacheCount       = if ($script:AccessTokens) { $script:AccessTokens.Count } else { 0 }
            LoginSession     = [bool]$script:LoginWebSession
            GraphSession     = [bool]$script:GraphWebSession
        }
    } $TokenKeyNull $TokenKeyFalse
    $sw.Stop()
    Add-Timing 'CoreModuleState' "CacheCount=$($coreState.CacheCount) Keys=$($coreState.CacheKeys -join ';') LoginSession=$($coreState.LoginSession) GraphSession=$($coreState.GraphSession)" $sw.Elapsed.TotalMilliseconds

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
    if ($coreState.GraphSession) {
        $graphSess = & (Get-Module CIPPCore) { $script:GraphWebSession }
        if ($graphSess) { $directRequest.WebSession = $graphSess }
    }
    $directResult = Invoke-RestMethod @directRequest
    $directCount = if ($directResult.value) { $directResult.value.Count } else { 1 }
    $sw.Stop()
    Add-Timing 'DirectInvokeRestMethod' "ResultCount=$directCount" $sw.Elapsed.TotalMilliseconds

    # ── 8. Get-GraphRequestList (full wrapper) ──────────────────────────
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

    # ── 9. CIPPCore state after calls ───────────────────────────────────
    $sw.Restart()
    $coreStateAfter = & (Get-Module CIPPCore) {
        $keyNull = $args[0]
        $now = [int](Get-Date -UFormat %s -Millisecond 0)
        $cached = $script:AccessTokens.$keyNull
        @{
            TokenCached  = [bool]($cached -and $now -lt $cached.expires_on)
            CacheCount   = if ($script:AccessTokens) { $script:AccessTokens.Count } else { 0 }
            CacheKeys    = if ($script:AccessTokens) { @($script:AccessTokens.Keys) } else { @() }
            LoginSession = [bool]$script:LoginWebSession
            GraphSession = [bool]$script:GraphWebSession
        }
    } $TokenKeyNull
    $sw.Stop()
    Add-Timing 'CoreStateAfter' "TokenCached=$($coreStateAfter.TokenCached) CacheCount=$($coreStateAfter.CacheCount) LoginSession=$($coreStateAfter.LoginSession) GraphSession=$($coreStateAfter.GraphSession)" $sw.Elapsed.TotalMilliseconds

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
