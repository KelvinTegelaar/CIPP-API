function Push-CIPPStandardsApplyBatch {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    param($Item)

    try {
        # Aggregate all standards from all tenants
        $AllStandards = @($Item.Results | Where-Object { $_ -and $_.FunctionName -eq 'CIPPStandard' })

        if ($AllStandards.Count -eq 0) {
            Write-Information 'No standards to apply across all tenants'
            return
        }

        Write-Information "Aggregated $($AllStandards.Count) standards from all tenants"

        # Start orchestrator to apply standards
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'StandardsApply'
            Batch            = @($AllStandards)
            SkipLog          = $true
        }

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        Write-Information "Started standards apply orchestrator with ID = '$InstanceId'"

    } catch {
        Write-Warning "Error in standards apply batch aggregation: $($_.Exception.Message)"
    }
    return @{
        Success = $true
    }
}
