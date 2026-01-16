function Invoke-CIPPTestsRun {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Tests.Read
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants'
    )

    Write-Information "Starting tests run for tenant: $TenantFilter"

    try {
        $AllTests = Get-Command -Name 'Invoke-CippTest*' -Module CIPPCore | Select-Object -ExpandProperty Name | ForEach-Object {
            $_ -replace '^Invoke-CippTest', ''
        }

        if ($AllTests.Count -eq 0) {
            Write-LogMessage -API 'Tests' -message 'No test functions found.' -sev Error
            return
        }

        Write-Information "Found $($AllTests.Count) test functions to run"
        $AllTenantsList = if ($TenantFilter -eq 'allTenants') {
            $DbCounts = Get-CIPPDbItem -CountsOnly -TenantFilter 'allTenants'
            $TenantsWithData = $DbCounts | Where-Object { $_.Count -gt 0 } | Select-Object -ExpandProperty PartitionKey -Unique
            Write-Information "Found $($TenantsWithData.Count) tenants with data in database"
            $TenantsWithData
        } else {
            $DbCounts = Get-CIPPDbItem -TenantFilter $TenantFilter -CountsOnly
            if (($DbCounts | Measure-Object -Property Count -Sum).Sum -gt 0) {
                @($TenantFilter)
            } else {
                Write-LogMessage -API 'Tests' -tenant $TenantFilter -message 'Tenant has no data in database. Skipping tests.' -sev Info
                @()
            }
        }

        if ($AllTenantsList.Count -eq 0) {
            Write-LogMessage -API 'Tests' -message 'No tenants with data found. Exiting.' -sev Info
            return
        }

        # Build batch: all tests for all tenants
        $Batch = foreach ($Tenant in $AllTenantsList) {
            foreach ($Test in $AllTests) {
                @{
                    FunctionName = 'CIPPTest'
                    TenantFilter = $Tenant
                    TestId       = $Test
                }
            }
        }

        Write-Information "Built batch of $($Batch.Count) test activities ($($AllTests.Count) tests × $($AllTenantsList.Count) tenants)"

        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'TestsRun'
            Batch            = @($Batch)
            SkipLog          = $true
        }

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        Write-Information "Started tests orchestration with ID = '$InstanceId'"

        return @{
            InstanceId = $InstanceId
            Message    = "Tests orchestration started: $($AllTests.Count) tests for $($AllTenantsList.Count) tenants"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -message "Failed to start tests orchestration: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw $ErrorMessage
    }
}
