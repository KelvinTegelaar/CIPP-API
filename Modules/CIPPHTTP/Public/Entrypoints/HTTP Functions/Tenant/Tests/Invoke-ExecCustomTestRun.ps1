function Invoke-ExecCustomTestRun {
    <#
    .SYNOPSIS
        Triggers a Custom test-suite run for one or all tenants.

    .DESCRIPTION
        Re-runs the enabled Custom tests against the most recent cached data for the requested
        tenant(s) by starting the standard tests orchestration with a Custom-only suite filter.
        Used by the cross-tenant Custom Test Report to refresh results on demand.

    .FUNCTIONALITY
        Entrypoint,AnyTenant

    .ROLE
        Tenant.Tests.ReadWrite
    #>
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = 'allTenants'
    try {
        $TenantFilterRaw = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        # Accept a plain string, a {value} object, or a single-element array of either.
        if ($TenantFilterRaw -is [array]) { $TenantFilterRaw = $TenantFilterRaw | Select-Object -First 1 }
        if ($TenantFilterRaw -is [pscustomobject]) { $TenantFilterRaw = $TenantFilterRaw.value }
        if (-not [string]::IsNullOrWhiteSpace($TenantFilterRaw)) { $TenantFilter = [string]$TenantFilterRaw }
        if ($TenantFilter -eq 'AllTenants') { $TenantFilter = 'allTenants' }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Starting Custom test run for: $TenantFilter" -sev Info
        $null = Start-CIPPDBTestsRun -TenantFilter $TenantFilter -Suites 'Custom' -Force

        $Scope = if ($TenantFilter -eq 'allTenants') { 'all tenants' } else { $TenantFilter }
        $StatusCode = [HttpStatusCode]::OK
        $Body = [PSCustomObject]@{ Results = "Successfully started a custom test run for $Scope. Results will populate here as each tenant completes." }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to start custom test run: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = [PSCustomObject]@{ Results = "Failed to start custom test run: $($ErrorMessage.NormalizedError)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
