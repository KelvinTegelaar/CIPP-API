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

        # Custom scripts are scheduled individually using ScriptGuid identifiers
        $AllTests = @($AllTests | Where-Object { $_ -ne 'CustomScripts' })

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
        $Tasks = [System.Collections.Generic.List[object]]::new()
        foreach ($Test in $AllTests) {
            $Tasks.Add([PSCustomObject]@{
                FunctionName = 'CIPPTest'
                TenantFilter = $TenantFilter
                TestId       = $Test
            })
        }

        # Add custom scripts as individual tests (CustomScript-<Guid>) using latest enabled versions
        $CustomTestsTable = Get-CippTable -tablename 'CustomPowershellScripts'
        $CustomScripts = @(Get-CIPPAzDataTableEntity @CustomTestsTable -Filter "PartitionKey eq 'CustomScript'")
        if ($CustomScripts.Count -gt 0) {
            $LatestCustomScripts = $CustomScripts |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_.ScriptGuid) } |
                Group-Object -Property ScriptGuid |
                ForEach-Object {
                    $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
                }

            foreach ($Script in @($LatestCustomScripts)) {
                # We can't prefilter this on table lookup as each script version has its own Enabled property, so we need to check here if the latest version is enabled
                $IsEnabled = if ($Script.PSObject.Properties['Enabled']) { [bool]$Script.Enabled } else { $true }
                if (-not $IsEnabled) {
                    continue
                }

                $Tasks.Add([PSCustomObject]@{
                        FunctionName = 'CIPPTest'
                        TenantFilter = $TenantFilter
                        TestId       = "CustomScript-$($Script.ScriptGuid)"
                    })
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
