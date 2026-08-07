function Invoke-AddBaseline {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    .DESCRIPTION
        Creates or updates a baseline. There is no baseline blob: the Baselines
        delta rows (design doc §4.1) are the editable source of truth for every standard's
        configuration, and the BaselineRollouts row (§12.2) holds the baseline-level data -
        name, description, exclusions, alert destinations, and the ordered stage definitions.
        Baselines are reconstructed from those rows on read.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        if (-not $Request.Body.templateName) {
            throw 'A baseline requires a name.'
        }
        if (-not $Request.Body.stages -or @($Request.Body.stages).Count -lt 1) {
            throw 'A baseline requires at least one stage.'
        }

        $GUID = $Request.Body.GUID ? $Request.Body.GUID : (New-Guid).GUID
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())

        # Baseline-level record: metadata + ordered stage definitions (standards live on the deltas).
        $StageDefinitions = @($Request.Body.stages | ForEach-Object {
                [PSCustomObject]@{
                    name       = $_.name
                    logic      = $_.logic ?? 'and'
                    conditions = @($_.conditions)
                }
            })
        $RolloutTable = Get-CippTable -tablename 'BaselineRollouts'
        $RolloutTable.Force = $true
        # The editor round-trips the tenant selector's own option objects ({label, value,
        # type}) verbatim via assignedTo/excludedTo; the flat excludedTenants values keep
        # the exclusion logic simple. Raw string values are accepted everywhere too.
        $ExcludedValues = @($Request.Body.excludedTenants | ForEach-Object {
                if ($null -eq $_) { } elseif ($_ -is [string]) { $_ } else { "$($_.value)" }
            } | Where-Object { $_ })
        Add-CIPPAzDataTableEntity @RolloutTable -Entity @{
            PartitionKey    = 'rollout'
            RowKey          = "$GUID"
            templateName    = "$($Request.Body.templateName)"
            description     = "$($Request.Body.description)"
            assignedTo      = (ConvertTo-Json -Compress -Depth 10 -InputObject @($Request.Body.assignedTenants))
            excludedTo      = (ConvertTo-Json -Compress -Depth 10 -InputObject @($Request.Body.excludedTenants))
            excludedTenants = (ConvertTo-Json -Compress -Depth 10 -InputObject $ExcludedValues)
            alertEmails     = "$($Request.Body.alertEmails)"
            alertWebhookUrl = "$($Request.Body.alertWebhookUrl)"
            Stages          = (ConvertTo-Json -Compress -Depth 100 -InputObject $StageDefinitions)
            updatedBy       = "$User"
            updatedAt       = $Now
        }

        # Explode into delta rows: RK <scopeSegment>-<standardName>-s<stage>-<templateId>.
        # The stage is part of the key so the same standard can exist in two stages (the
        # report-only -> enforce pattern). IDs in keys, never names: group scopes key on the
        # group ID; scopeName carries the display name. '#' (multi-instance marker) is not
        # legal in Azure Table keys; standardName column keeps the real key.
        $DeltaTable = Get-CippTable -tablename 'Baselines'
        $SafeGuid = ConvertTo-CIPPODataFilterValue -Value $GUID
        $OldDeltas = Get-CIPPAzDataTableEntity @DeltaTable -Filter "PartitionKey eq 'standardItem' and templateId eq '$SafeGuid'"
        if ($OldDeltas) {
            Remove-CIPPAzDataTableEntity -Force @DeltaTable -Entity $OldDeltas
        }

        $Groups = @()
        try { $Groups = @(Get-TenantGroups) } catch { Write-Information "AddBaseline: tenant group lookup failed: $($_.Exception.Message)" }
        $Scopes = foreach ($Assignment in @($Request.Body.assignedTenants)) {
            if ($null -eq $Assignment) { continue }
            # Selector option objects carry the key in .value; raw strings are the key itself.
            $Value = if ($Assignment -is [string]) { $Assignment } else { "$($Assignment.value)" }
            if (-not $Value) { continue }
            if ($Value -eq 'AllTenants') {
                @{ scope = 'allTenants'; scopeId = 'AllTenants'; scopeName = 'AllTenants'; segment = 'allTenants' }
            } else {
                # Group selections send the group ID; older saves round-tripped names. Accept both.
                $Group = $Groups | Where-Object { $_.Id -eq $Value -or $_.Name -eq $Value } | Select-Object -First 1
                if ($Group) {
                    @{ scope = 'group'; scopeId = "$($Group.Id)"; scopeName = "$($Group.Name)"; segment = "group_$($Group.Id)" }
                } else {
                    @{ scope = 'tenant'; scopeId = $Value; scopeName = $Value; segment = "tenant_$Value" }
                }
            }
        }

        $RolloutId = if (@($Request.Body.stages).Count -gt 1) { $GUID } else { '' }
        $DeltaTable.Force = $true
        $StageNumber = 0
        $DeltaCount = 0
        foreach ($Stage in $Request.Body.stages) {
            $StageNumber++
            foreach ($Config in @($Stage.standards)) {
                if (-not $Config) { continue }
                $InstanceKey = if ($Config -is [string]) { $Config } else { $Config.instance ?? $Config.standard }
                $Variables = if ($Config -is [string]) { [PSCustomObject]@{} } else { $Config.variables ?? [PSCustomObject]@{} }
                $SafeInstance = $InstanceKey -replace '#', '~'
                foreach ($Scope in $Scopes) {
                    Add-CIPPAzDataTableEntity @DeltaTable -Entity @{
                        PartitionKey     = 'standardItem'
                        RowKey           = ('{0}-{1}-s{2}-{3}' -f $Scope.segment, $SafeInstance, $StageNumber, $GUID)
                        standardName     = "$InstanceKey"
                        templateId       = "$GUID"
                        scope            = "$($Scope.scope)"
                        scopeId          = "$($Scope.scopeId)"
                        scopeName        = "$($Scope.scopeName)"
                        stage            = $StageNumber
                        expectedValue    = (ConvertTo-Json -Compress -Depth 100 -InputObject $Variables)
                        remediateEnabled = [bool]$(if ($Config -is [string]) { $true } else { $Config.remediateEnabled ?? $true })
                        alertEnabled     = [bool]$(if ($Config -is [string]) { $true } else { $Config.alertEnabled ?? $true })
                        alertOnRemediate = [bool]$(if ($Config -is [string]) { $false } else { $Config.alertOnRemediate ?? $false })
                        rolloutId        = "$RolloutId"
                        updatedBy        = "$User"
                        updatedAt        = $Now
                    }
                    $DeltaCount++
                }
            }
        }

        # Resolved rows for standards no longer in this baseline would linger forever -
        # clear them now so the alignment view reflects the edit immediately.
        $Instances = [System.Collections.Generic.List[string]]::new()
        foreach ($Stage in $Request.Body.stages) {
            foreach ($Config in @($Stage.standards)) {
                if (-not $Config) { continue }
                $Instances.Add($(if ($Config -is [string]) { $Config } else { $Config.instance ?? $Config.standard }))
            }
        }
        $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
        $Orphans = @(Get-CIPPAzDataTableEntity @ResolvedTable -Filter "TemplateId eq '$SafeGuid'" | Where-Object { $Instances -notcontains $_.StandardName })
        if ($Orphans) {
            Remove-CIPPAzDataTableEntity -Force @ResolvedTable -Entity $Orphans
        }

        Write-LogMessage -headers $Request.Headers -API $APIName -message "Baseline $($Request.Body.templateName) ($GUID) saved; $DeltaCount delta rows written." -Sev 'Info'
        $Results = [pscustomobject]@{ Results = 'Successfully saved the baseline'; Metadata = @{ id = $GUID; deltas = $DeltaCount } }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to save baseline: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Failed to save baseline: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
