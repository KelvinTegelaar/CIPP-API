function Push-CIPPTestsList {
    <#
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

        # Build test batch for this tenant
        $TestBatch = foreach ($Test in $AllTests) {
            [PSCustomObject]@{
                FunctionName = 'CIPPTest'
                TenantFilter = $TenantFilter
                TestId       = $Test
            }
        }

        Write-Information "Built $($TestBatch.Count) test activities for tenant $TenantFilter"

        # Start orchestrator for this tenant's tests
        $InputObject = [PSCustomObject]@{
            OrchestratorName = "TestsRun_$TenantFilter"
            Batch            = @($TestBatch)
            SkipLog          = $true
        }

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        Write-Information "Started tests orchestrator for tenant $TenantFilter with ID = '$InstanceId'"

        return @{
            Success    = $true
            Tenant     = $TenantFilter
            InstanceId = $InstanceId
            TestCount  = $TestBatch.Count
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Failed to start tests for tenant: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return @{
            Success = $false
            Tenant  = $TenantFilter
            Error   = $ErrorMessage.NormalizedError
        }
    }
}
