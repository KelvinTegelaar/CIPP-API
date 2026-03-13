function Push-CIPPTestsList {
    <#
    .SYNOPSIS
        Build the list of test activities for a single tenant (Phase 1)

    .DESCRIPTION
        Checks whether the tenant has cached data and discovers all Invoke-CippTest* functions.
        Returns the task array so the PostExecution aggregator can flatten all tenants into one
        flat Phase 2 orchestrator.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $TenantFilter = $Item.TenantFilter

    try {
        Write-Information "Building test list for tenant: $TenantFilter"

        # Get all test functions
        $AllTests = Get-Command -Name 'Invoke-CippTest*' -Module CIPPCore | Select-Object -ExpandProperty Name | ForEach-Object {
            $_ -replace '^Invoke-CippTest', ''
        }

        if ($AllTests.Count -eq 0) {
            Write-Information 'No test functions found'
            return @()
        }

        # Check if tenant has data
        $DbCounts = Get-CIPPDbItem -TenantFilter $TenantFilter -CountsOnly
        if (($DbCounts | Measure-Object -Property DataCount -Sum).Sum -eq 0) {
            Write-Information "Tenant $TenantFilter has no data in database. Skipping tests."
            return @()
        }

        # Build test task list for this tenant — returned for PostExecution aggregation
        $Tasks = foreach ($Test in $AllTests) {
            [PSCustomObject]@{
                FunctionName = 'CIPPTest'
                TenantFilter = $TenantFilter
                TestId       = $Test
            }
        }

        Write-Information "Built $($Tasks.Count) test tasks for tenant $TenantFilter"
        return @($Tasks)

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Failed to build test list: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return @()
    }
}
