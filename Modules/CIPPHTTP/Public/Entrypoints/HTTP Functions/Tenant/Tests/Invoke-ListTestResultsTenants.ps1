function Invoke-ListTestResultsTenants {
    <#
    .SYNOPSIS
        Lists CIPP test results for a given test across one, many, or all tenants.

    .DESCRIPTION
        Cross-tenant overview of stored test results. Backed by Get-CIPPTestResultsTenants, which
        queries the shared CippTestResults table server-side and enriches Custom rows with their
        definition. Results are filtered to the tenants the calling user is permitted to see via
        Test-CIPPAccess, so an all-tenants read still respects per-user tenant scoping.

    .FUNCTIONALITY
        Entrypoint,AnyTenant

    .ROLE
        Tenant.Reports.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    try {
        $TenantFilterRaw = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        $TestIdRaw = $Request.Query.testId ?? $Request.Body.testId
        $StatusRaw = $Request.Query.status ?? $Request.Body.status
        $TestType = $Request.Query.testType ?? $Request.Body.testType
        $Risk = $Request.Query.risk ?? $Request.Body.risk
        $Category = $Request.Query.category ?? $Request.Body.category
        $SummaryOnly = $Request.Query.summaryOnly ?? $Request.Body.summaryOnly
        $RowStatusRaw = $Request.Query.rowStatus ?? $Request.Body.rowStatus
        $IncludeCounts = $Request.Query.includeCounts ?? $Request.Body.includeCounts
        $CountsOnly = $Request.Query.countsOnly ?? $Request.Body.countsOnly

        # Normalise inputs that may arrive as a single string, a comma-delimited string, or an
        # array of strings / {value,label} objects (the frontend autocomplete posts the latter).
        $ToArray = {
            param($Value)
            if ($null -eq $Value) { return @() }
            if ($Value -is [string]) {
                return @($Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            return @($Value | ForEach-Object { $_.value ?? $_ } | Where-Object { $_ })
        }

        $TenantFilterList = & $ToArray $TenantFilterRaw
        $TestIdList = & $ToArray $TestIdRaw
        $StatusList = & $ToArray $StatusRaw
        $RowStatusList = & $ToArray $RowStatusRaw

        $Params = @{}
        if ($TenantFilterList.Count -gt 0) { $Params.TenantFilter = $TenantFilterList }
        if ($TestIdList.Count -gt 0) { $Params.TestId = $TestIdList }
        if ($StatusList.Count -gt 0) { $Params.Status = $StatusList }
        if ($RowStatusList.Count -gt 0) { $Params.RowStatus = $RowStatusList }
        if ($TestType) { $Params.TestType = $TestType }
        if ($Risk) { $Params.Risk = $Risk }
        if ($Category) { $Params.Category = $Category }
        if ([string]$SummaryOnly -eq 'true') { $Params.SummaryOnly = $true }
        if ([string]$IncludeCounts -eq 'true') { $Params.IncludeCounts = $true }
        # countsOnly returns the aggregates with no rows, for callers that only render totals.
        if ([string]$CountsOnly -eq 'true') { $Params.CountsOnly = $true }

        # Restrict to tenants the caller is allowed to see. Test-CIPPAccess returns the list of
        # permitted customerIds, or 'AllTenants' for unrestricted users. Passed into the query so
        # disallowed tenants are dropped before any counting or row building — a post-hoc filter
        # would leak estate size through the counts and burn time filtering rows at scale.
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
            $Params.AllowedTenantIds = @($AllowedTenants | Where-Object { $_ })
        }

        $Response = Get-CIPPTestResultsTenants @Params

        $StatusCode = [HttpStatusCode]::OK
        if ($Params.IncludeCounts -or $Params.CountsOnly) {
            $Body = @{ Results = @($Response.Results); Counts = $Response.Counts }
        } else {
            $Body = @{ Results = @($Response) }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -message "Error retrieving cross-tenant test results: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
