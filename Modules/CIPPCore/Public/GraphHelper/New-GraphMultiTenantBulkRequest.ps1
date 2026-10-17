function New-GraphMultiTenantBulkRequest {
    <#
    .SYNOPSIS
        Sends one Graph $batch per tenant, concurrently across tenants, in a single call.
    .DESCRIPTION
        Each item is @{ TenantFilter; Requests = @(@{ id; method; url; body; headers }) }. A tenant with more than
        20 requests is split into several batches. Returns one [pscustomobject]@{ TenantFilter; Responses; Error }
        per item, in input order. Error is set when the tenant's token or batch POST failed.

        The batch POST is retried on 429/5xx. Sub-request statuses are left to the caller, with no per-item retry
        or paging, because some callers must not retry a sub-request 429 (an audit search 429 is a full search cap).
        Callers pass tenants already scoped by Get-Tenants; there is no per-tenant authorisation check.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$TenantRequests,
        [bool]$AsApp = $true,
        $Scope,
        [ValidateSet('v1.0', 'beta')][string]$Version = 'beta',
        [int]$MaxConcurrency = 16,
        [int]$MaxRetries = 2
    )

    $Url = "https://graph.microsoft.com/$Version/`$batch"
    $UserAgent = Get-CippUserAgent
    $Results = [System.Collections.Generic.List[object]]::new()
    $Requests = [System.Collections.Generic.List[CIPP.CIPPConcurrentRequest]]::new()
    $Owners = [System.Collections.Generic.List[object]]::new()

    foreach ($Item in $TenantRequests) {
        $Result = [pscustomobject]@{ TenantFilter = $Item.TenantFilter; Responses = [System.Collections.Generic.List[object]]::new(); Error = $null }
        $Results.Add($Result)
        $SubRequests = @($Item.Requests)
        if ($SubRequests.Count -eq 0) { continue }
        try {
            $Authorization = (Get-GraphToken -tenantid $Item.TenantFilter -scope $Scope -AsApp $AsApp).Authorization
        } catch {
            $Result.Error = $_.Exception.Message
            continue
        }
        for ($i = 0; $i -lt $SubRequests.Count; $i += 20) {
            $Body = @{ requests = @($SubRequests[$i..([Math]::Min($i + 19, $SubRequests.Count - 1))]) }
            $Request = [CIPP.CIPPConcurrentRequest]::new()
            $Request.Uri = $Url
            $Request.Method = 'POST'
            $Request.Body = [CIPP.CippJson]::ToJson($Body, 100) ?? (ConvertTo-Json -InputObject $Body -Compress -Depth 100)
            $Request.ContentType = 'application/json; charset=utf-8'
            $Headers = [System.Collections.Generic.Dictionary[string, string]]::new()
            $Headers['Authorization'] = $Authorization
            $Headers['User-Agent'] = $UserAgent
            if ($script:XMsThrottlePriority) { $Headers['x-ms-throttle-priority'] = $script:XMsThrottlePriority }
            $Request.Headers = $Headers
            $Requests.Add($Request)
            $Owners.Add($Result)
        }
    }

    if ($Requests.Count -gt 0) {
        foreach ($Sent in [CIPP.CIPPRestClient]::SendConcurrent($Requests, $MaxConcurrency, $MaxRetries)) {
            $Owner = $Owners[$Sent.Index]
            if ($Sent.Error) {
                $Owner.Error = $Sent.Error
                continue
            }
            if (-not $Sent.IsSuccess) {
                $Owner.Error = 'HTTP {0}: {1}' -f $Sent.StatusCode, $(if ($Sent.Result.HasContent) { $Sent.Result.Content })
                continue
            }
            try {
                foreach ($Response in ([CIPP.CippJson]::ConvertFromResponse($Sent.Result)).responses) { $Owner.Responses.Add($Response) }
            } catch {
                $Owner.Error = "Could not parse the batch response: $($_.Exception.Message)"
            }
        }
    }
    return $Results.ToArray()
}
