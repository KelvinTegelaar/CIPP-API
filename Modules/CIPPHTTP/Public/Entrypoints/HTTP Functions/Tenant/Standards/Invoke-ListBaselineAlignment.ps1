function Invoke-ListBaselineAlignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.Read
    .DESCRIPTION
        Baseline alignment data. With ?tenantFilter= returns the tenant payload (summary,
        resolved rows, stage states, deviation feed); with ?tenantFilter=&history=true
        returns run events newest-first, filtered server-side by since, standard, outcome and
        mode; with &pageSize=<n> it returns one page plus Metadata.nextLink, which is passed back as
        &nextLink= for the next, older page; with
        ?byStandard=true returns the aggregate payload (fleet score, per-standard rollups,
        tenant summaries, trend, and the accepted/denied deviation list). byStandard also
        takes &baselineId=<GUID> to limit it to one baseline and &stage=<1-based stage number>
        to limit that further to one stage; filtered payloads carry a 'filter' object and a
        trend of today's live point only.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    # Paging cursor from the previous page's Metadata.nextLink
    $NextLink = $Request.Query.nextLink
    if ($NextLink -and $NextLink -notmatch '^\d{19}-[0-9A-Za-z-]+$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'nextLink is not a valid history cursor.' } })
    }
    try {
        $Results = if ($Request.Query.byStandard -eq $true) {
            $FilterParams = @{}
            if ($Request.Query.baselineId) { $FilterParams.BaselineId = $Request.Query.baselineId }
            if ($Request.Query.stage) { $FilterParams.Stage = [int]$Request.Query.stage }
            Get-CIPPBaselineAlignment -ByStandard @FilterParams
        } elseif ($Request.Query.tenantFilter -and $Request.Query.history -eq $true) {
            $HistoryParams = @{
                # Comma-separated standard names, instance keys included (ConditionalAccessTemplate#<id>)
                Standard = @("$($Request.Query.standard)" -split ',' | Where-Object { $_ })
                # Comma-separated outcomes (Compliant, Drift, Remediated, ...)
                Outcome  = @("$($Request.Query.outcome)" -split ',' | Where-Object { $_ })
                # Comma-separated event types (run, compare, oneoff, triage, ...)
                Mode     = @("$($Request.Query.mode)" -split ',' | Where-Object { $_ })
                # Only events at or after this time, in unix seconds
                Since    = $Request.Query.since -as [long]
                # Page size; the response then carries Metadata.nextLink for the next, older page
                PageSize = $Request.Query.pageSize -as [int]
                After    = $NextLink
            }
            Get-CIPPBaselineAlignment -TenantFilter $Request.Query.tenantFilter -History @HistoryParams
        } elseif ($Request.Query.tenantFilter) {
            Get-CIPPBaselineAlignment -TenantFilter $Request.Query.tenantFilter
        } else {
            throw 'Provide tenantFilter or byStandard=true.'
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to list baseline alignment: $($_.Exception.Message)" -Sev 'Error'
        $Results = @{ Results = "Failed to list baseline alignment: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
