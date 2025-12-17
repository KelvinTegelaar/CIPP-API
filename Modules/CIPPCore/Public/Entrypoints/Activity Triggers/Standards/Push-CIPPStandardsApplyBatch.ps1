function Push-CIPPStandardsApplyBatch {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    param($Item)

    try {
        # Aggregate all standards from all tenants
        $AllStandards = $Item.Results | ForEach-Object {
            foreach ($Standard in $_) {
                if ($Standard -and $Standard.FunctionName -eq 'CIPPStandard') {
                    $Standard
                }
            }
        }

        if ($AllStandards.Count -eq 0) {
            Write-Information 'No standards to apply across all tenants'
            return
        }

        Write-Information "Aggregated $($AllStandards.Count) standards from all tenants: $($AllStandards | ConvertTo-Json -Depth 5 -Compress)"

        # Start orchestrator to apply standards
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'StandardsApply'
            Batch            = @($AllStandards)
            SkipLog          = $true
        } | ConvertTo-Json -Depth 25 -Compress
        Write-Host "Standards InputObject: $InputObject"
        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject $InputObject
        Write-Information "Started standards apply orchestrator with ID = '$InstanceId'"

    } catch {
        Write-Warning "Error in standards apply batch aggregation: $($_.Exception.Message)"
    }
    return @{
        Success = $true
    }
}
