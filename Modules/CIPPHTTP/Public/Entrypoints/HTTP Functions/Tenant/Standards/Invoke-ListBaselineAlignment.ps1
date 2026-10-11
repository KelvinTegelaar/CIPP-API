function Invoke-ListBaselineAlignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.Read
    .DESCRIPTION
        Baseline alignment data. With ?tenantFilter= returns the tenant payload (summary,
        resolved rows with history, stage states, deviation feed); with
        ?tenantFilter=&history=true returns the flattened run-event history; with
        ?byStandard=true returns the aggregate payload (fleet score, per-standard rollups,
        tenant summaries, trend, and the accepted/denied deviation list). byStandard also
        takes &baselineId=<GUID> to limit it to one baseline and &stage=<1-based stage number>
        to limit that further to one stage; filtered payloads carry a 'filter' object and a
        trend of today's live point only.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $Results = if ($Request.Query.byStandard -eq $true) {
            $FilterParams = @{}
            if ($Request.Query.baselineId) { $FilterParams.BaselineId = $Request.Query.baselineId }
            if ($Request.Query.stage) { $FilterParams.Stage = [int]$Request.Query.stage }
            Get-CIPPBaselineAlignment -ByStandard @FilterParams
        } elseif ($Request.Query.tenantFilter -and $Request.Query.history -eq $true) {
            Get-CIPPBaselineAlignment -TenantFilter $Request.Query.tenantFilter -History
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
