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

        # Match the list phase's per-scope naming (see New-CIPPStandardsRun): once concurrent
        # single-tenant list runs no longer collide, their apply phases must not collide either. The
        # scope comes from the aggregated standards, which already carry Tenant and TemplateId: a single
        # tenant and/or a single template contributes that part of the suffix, so two manual runs for the
        # same tenant but different templates get distinct apply runs. The all-tenants sweep aggregates
        # many tenants (and templates), so both parts drop and it keeps the bare name.
        $ApplyTenants = @($AllStandards.Tenant | Where-Object { $_ } | Sort-Object -Unique)
        $ApplyTemplates = @($AllStandards.TemplateId | Where-Object { $_ } | Sort-Object -Unique)
        $ApplyScope = @(
            if ($ApplyTenants.Count -eq 1) { $ApplyTenants[0] }
            if ($ApplyTemplates.Count -eq 1) { $ApplyTemplates[0] }
        ) -join '-'
        $OrchestratorName = if ($ApplyScope) { "StandardsApply-$ApplyScope" } else { 'StandardsApply' }

        # Start orchestrator to apply standards
        $InputObject = [PSCustomObject]@{
            OrchestratorName = $OrchestratorName
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
