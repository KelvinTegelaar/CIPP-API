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

        # FUTURE USE - ZAC
        # Group all ConditionalAccessTemplate standards per tenant into a single batch item so
        # they deploy sequentially (one activity per tenant) instead of fanning out one activity
        # per template. This removes the 429 storm against the ~1 req/s CA write endpoint and the
        # duplicate named location / c1-c99 / 1040 races. Non-CA standards pass through unchanged.
        # $CAStandards = @($AllStandards | Where-Object { $_.Standard -eq 'ConditionalAccessTemplate' })
        # if ($CAStandards.Count -gt 0) {
        #     $OtherStandards = @($AllStandards | Where-Object { $_.Standard -ne 'ConditionalAccessTemplate' })
        #     $GroupedCA = foreach ($TenantGroup in ($CAStandards | Group-Object -Property Tenant)) {
        #         [pscustomobject]@{
        #             Tenant         = $TenantGroup.Name
        #             Standard       = 'ConditionalAccessTemplate'
        #             FunctionName   = 'CIPPStandard'
        #             QueuedTime     = ($TenantGroup.Group | Select-Object -First 1).QueuedTime
        #             BatchTemplates = @($TenantGroup.Group | ForEach-Object {
        #                     [pscustomobject]@{
        #                         Settings   = $_.Settings
        #                         TemplateId = $_.TemplateId
        #                     }
        #                 })
        #         }
        #     }
        #     $AllStandards = @($OtherStandards) + @($GroupedCA)
        #     Write-Information "Grouped $($CAStandards.Count) Conditional Access template standards into $(@($GroupedCA).Count) per-tenant batch item(s)."
        # }

        Write-Information "Aggregated $($AllStandards.Count) standards from all tenants: $($AllStandards | ConvertTo-Json -Depth 5 -Compress)"

        # Start orchestrator to apply standards
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'StandardsApply'
            Batch            = @($AllStandards)
            SkipLog          = $true
        }
        Write-Host "Standards InputObject: $($InputObject | ConvertTo-Json -Depth 25 -Compress)"
        $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
        Write-Information "Started standards apply orchestrator with ID = '$InstanceId'"
    } catch {
        Write-Warning "Error in standards apply batch aggregation: $($_.Exception.Message)"
    }
    return @{
        Success = $true
    }
}
