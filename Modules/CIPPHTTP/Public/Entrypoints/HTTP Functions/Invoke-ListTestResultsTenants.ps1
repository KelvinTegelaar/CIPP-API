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

        $Params = @{}
        if ($TenantFilterList.Count -gt 0) { $Params.TenantFilter = $TenantFilterList }
        if ($TestIdList.Count -gt 0) { $Params.TestId = $TestIdList }
        if ($StatusList.Count -gt 0) { $Params.Status = $StatusList }
        if ($TestType) { $Params.TestType = $TestType }
        if ($Risk) { $Params.Risk = $Risk }
        if ($Category) { $Params.Category = $Category }

        $Results = @(Get-CIPPTestResultsTenants @Params)

        # Restrict to tenants the caller is allowed to see. Test-CIPPAccess returns the list of
        # permitted customerIds, or 'AllTenants' for unrestricted users.
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
            $AllowedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Allowed in $AllowedTenants) {
                if ($Allowed) { [void]$AllowedSet.Add([string]$Allowed) }
            }
            $Results = @($Results | Where-Object { $_.TenantId -and $AllowedSet.Contains([string]$_.TenantId) })
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = @{ Results = @($Results) }
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
