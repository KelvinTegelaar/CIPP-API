function Push-CIPPTestsList {
    <#
    .SYNOPSIS
        Build the list of test suite activities for a single tenant (Phase 1)

    .DESCRIPTION
        Checks whether the tenant has cached data and returns one task per test suite.
        Suite tasks are executed by Push-CIPPTestCollection, which discovers individual
        test functions at runtime via Get-Command — no filesystem paths are used, so this
        works correctly with ModuleBuilder compiled modules.

        Reduces activity count from ~262 per tenant (one per test) to 6 per tenant
        (one per suite), dramatically cutting orchestrator replay overhead.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $TenantFilter = $Item.TenantFilter

    try {
        Write-Information "Building test suite list for tenant: $TenantFilter"

        # Check if tenant has data before emitting any work
        $DbCounts = Get-CIPPDbItem -TenantFilter $TenantFilter -CountsOnly
        if (($DbCounts | Measure-Object -Property DataCount -Sum).Sum -eq 0) {
            Write-Information "Tenant $TenantFilter has no data in database. Skipping tests."
            return @()
        }

        # Emit one task per suite — suite names must match the ValidateSet in Invoke-CIPPTestCollection.
        # Function discovery happens inside Invoke-CIPPTestCollection via Get-Command (path-independent).
        $Suites = @('ZTNA', 'ORCA', 'EIDSCA', 'CISA', 'CIS', 'SMB1001', 'CopilotReadiness', 'GenericTests', 'Custom')

        $Tasks = foreach ($Suite in $Suites) {
            [PSCustomObject]@{
                FunctionName = 'CIPPTestCollection'
                TenantFilter = $TenantFilter
                SuiteName    = $Suite
            }
        }

        Write-Information "Built $($Tasks.Count) suite tasks for tenant $TenantFilter"
        return @($Tasks)

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Failed to build test suite list: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return @()
    }
}
