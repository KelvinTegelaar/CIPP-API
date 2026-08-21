function Export-CIPPBaselineTemplate {
    <#
    .SYNOPSIS
        Assembles a baseline's portable export: the baseline file + every referenced template.
    .DESCRIPTION
        Produces the artifact set the community-repo upload pushes:
        - ONE baseline file (TemplateType 'BaselineTemplate'): an AddBaseline-compatible
          payload with tenant assignments replaced by the 'Exported Template' placeholder,
          instance-specific alert destinations blanked, and a referencedTemplates manifest
          (partition + guid + displayName + the repo path each template is pushed to).
        - One templates-table ENTITY per referenced CA/Intune template, serialized exactly
          like the existing UploadTemplate action (whole entity minus ETag/Timestamp) so
          they round-trip through the untouched Import-CommunityTemplate path.
        Package standards are expanded AT EXPORT TIME into their concrete member
        instances (a snapshot of the tag's membership at this moment) - repo files carry
        no package registry, so a portable baseline must reference templates directly.
        The Package column still rides along on each template entity, so tags
        reconstitute on the importing instance as a bonus.
        Related templates are separate files, not embedded - a baseline referencing
        dozens of policies would otherwise produce one enormous blob.
    .OUTPUTS
        $null when the baseline does not exist, else
        @{ Baseline = <baseline file object>; Templates = @(<templates-table entities>) }
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($GUID)

    $Baseline = Get-CIPPBaseline -ID $GUID | Select-Object -First 1
    if (-not $Baseline) { return $null }

    $Definitions = @(Get-CIPPBaselineDefinition)
    $DefinitionsByName = @{}
    foreach ($Definition in $Definitions) { if ($Definition.name) { $DefinitionsByName[$Definition.name] = $Definition } }
    $TemplatesTable = Get-CippTable -tablename 'templates'
    $PartitionRows = @{}
    $GetPartitionRows = {
        param($Partition)
        if (-not $PartitionRows.ContainsKey($Partition)) {
            $SafePartition = ConvertTo-CIPPODataFilterValue -Value $Partition
            $PartitionRows[$Partition] = @(Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq '$SafePartition'")
        }
        $PartitionRows[$Partition]
    }
    $Unwrap = { param($Value) if ($Value -is [System.Management.Automation.PSCustomObject] -and $null -ne $Value.value) { $Value.value } else { $Value } }

    # Referenced templates dedupe on (partition, RowKey); manifest + entity collected once.
    $SeenTemplates = @{}
    $TemplateEntities = [System.Collections.Generic.List[object]]::new()
    $Manifest = [System.Collections.Generic.List[object]]::new()
    $CollectTemplate = {
        param($Partition, $TemplateRef)
        $Row = & $GetPartitionRows $Partition | Where-Object { $_.RowKey -like "$TemplateRef*" -or $_.GUID -eq $TemplateRef } | Select-Object -First 1
        if (-not $Row) { return $false }
        $SeenKey = '{0}|{1}' -f $Partition, $Row.RowKey
        if ($SeenTemplates.ContainsKey($SeenKey)) { return $true }
        $SeenTemplates[$SeenKey] = $true
        $TemplateJson = $(try { $Row.JSON | ConvertFrom-Json -Depth 100 } catch { $null })
        $DisplayName = "$($TemplateJson.Displayname ?? $TemplateJson.displayName ?? $TemplateJson.name ?? $Row.RowKey)"
        $Basename = $DisplayName -replace '\s', '_' -replace '[^\w\d_]', ''
        $TemplateEntities.Add(($Row | Select-Object -ExcludeProperty ETag, Timestamp))
        $Manifest.Add([PSCustomObject]@{
                partition   = "$Partition"
                guid        = "$(if ("$($Row.GUID)") { $Row.GUID } else { $Row.RowKey })"
                displayName = $DisplayName
                path        = ('{0}/{1}.json' -f $Partition, $Basename)
            })
        $true
    }

    $ExportStages = foreach ($Stage in $Baseline.stages) {
        $ExportStandards = [System.Collections.Generic.List[object]]::new()
        foreach ($Config in @($Stage.standardsConfig)) {
            if (-not $Config) { continue }
            $BaseName = ("$($Config.instance ?? $Config.standard)" -split '#')[0]
            $Definition = $DefinitionsByName[$BaseName]
            if ($Definition.package) {
                # Snapshot the tag's membership NOW: the exported baseline carries the
                # concrete member instances, exactly what the resolver would produce.
                $Partition = "$($Definition.package.templatePartition)"
                foreach ($Member in @(Expand-CIPPBaselineTemplatePackage -Definition $Definition -Config $Config -TemplateRows (& $GetPartitionRows $Partition))) {
                    if (-not (& $CollectTemplate $Partition "$($Member.variables.$($Definition.package.memberVariable))")) { continue }
                    $ExportStandards.Add([PSCustomObject]@{
                            standard         = $Member.standard
                            instance         = $Member.instance
                            variables        = $Member.variables
                            remediateEnabled = [bool]$Member.remediateEnabled
                            alertEnabled     = [bool]$Member.alertEnabled
                            alertOnRemediate = [bool]$Member.alertOnRemediate
                        })
                }
                continue
            }
            # Bundle the referenced template body when the instance identity IS a
            # templates-table reference: declared via the identity block, or the
            # CA/Intune convention (partition = executor). Identity-carrying standards
            # whose identity is a plain name (no identity block) have nothing to bundle.
            $IdentityPartition = if ($Definition.identity.partition) {
                "$($Definition.identity.partition)"
            } elseif ("$($Definition.remediate.executor)" -in @('IntuneTemplate', 'CATemplate')) {
                "$($Definition.remediate.executor)"
            }
            if ($Definition.instanceIdentity -and $IdentityPartition) {
                $TemplateRef = "$(& $Unwrap $Config.variables.$($Definition.instanceIdentity))"
                if (-not $TemplateRef -or -not (& $CollectTemplate $IdentityPartition $TemplateRef)) {
                    Write-Information "Export-CIPPBaselineTemplate: $($Config.instance) references template '$TemplateRef' which no longer exists - skipped from the export."
                    continue
                }
            }
            $ExportStandards.Add([PSCustomObject]@{
                    standard         = "$($Config.standard)"
                    instance         = "$($Config.instance)"
                    variables        = ($Config.variables ?? [PSCustomObject]@{})
                    remediateEnabled = [bool]$Config.remediateEnabled
                    alertEnabled     = [bool]$Config.alertEnabled
                    alertOnRemediate = [bool]$Config.alertOnRemediate
                })
        }
        [PSCustomObject]@{
            name       = $Stage.name
            logic      = $Stage.logic ?? 'and'
            conditions = @($Stage.conditions)
            standards  = @($ExportStandards)
        }
    }

    $BaselineFile = [PSCustomObject]@{
        TemplateType        = 'BaselineTemplate'
        templateName        = "$($Baseline.templateName)"
        description         = "$($Baseline.description)"
        # Tenant assignments never travel: the placeholder is visibly wrong on import,
        # which is the point - the operator must consciously assign real tenants.
        assignedTenants     = @([PSCustomObject]@{ label = 'Exported Template'; value = 'Exported Template'; type = 'Tenant' })
        excludedTenants     = @()
        alertEmails         = ''
        alertWebhookUrl     = ''
        stages              = @($ExportStages)
        referencedTemplates = @($Manifest)
    }

    @{ Baseline = $BaselineFile; Templates = @($TemplateEntities) }
}
