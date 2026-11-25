function Merge-CIPPManagedBaseline {
    <#
    .SYNOPSIS
        Works out what Align or Merge writes for a managed baseline, without touching a table.
    .DESCRIPTION
        Align makes the standards and the stage layout identical to CyberDrain's. Merge
        overwrites the standards both sides have, keeps the partner's own, and adds only the
        CyberDrain-only standards named in -Add. Name, description, tenants, exclusions and
        alerting always stay the partner's.
        Two standards are the same when the engine would treat them as one thing: the instance
        key, or the selected template for standards that carry one. A standard that sits in
        more than one stage is paired in stage order.
    .OUTPUTS
        @{ Payload = <New-CIPPBaseline payload>; Changes = <what the preview lists>; TemplateIds = <templates the write touches> }
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Local,
        [Parameter(Mandatory = $true)]$Remote,
        [Parameter(Mandatory = $true)][ValidateSet('align', 'merge')][string]$Mode,
        [string[]]$Add = @(),
        $Definitions = @()
    )

    $DefinitionsByName = @{}
    foreach ($Definition in @($Definitions)) {
        if ($Definition.name) { $DefinitionsByName["$($Definition.name)"] = $Definition }
    }

    # Pickers save option wrappers ({label, value}); the value is what counts.
    $Unwrap = {
        param($Value)
        if ($Value -is [array]) { return , @($Value | ForEach-Object { $_.value ?? $_ }) }
        $Value.value ?? $Value
    }
    $BaseNameOf = {
        param($Config)
        ("$($Config.instance ?? $Config.standard)" -split '#')[0]
    }
    $IdentityOf = {
        param($Config)
        $InstanceKey = "$($Config.instance ?? $Config.standard)"
        $BaseName = ($InstanceKey -split '#')[0]
        $IdentityVariable = $DefinitionsByName[$BaseName].instanceIdentity
        if ($IdentityVariable) {
            $IdentityValue = & $Unwrap $Config.variables.$IdentityVariable
            if ("$IdentityValue") { return '{0}#{1}' -f $BaseName, $IdentityValue }
        }
        $InstanceKey
    }
    # A blank setting means its declared default, exactly as the engine reads it at run time, so
    # a baseline that was only opened and saved in the editor does not read as changed.
    $SettingsOf = {
        param($Config)
        $Variables = $Config.variables ?? [PSCustomObject]@{}
        if ($Variables -is [System.Collections.IDictionary]) { $Variables = [PSCustomObject]$Variables }
        $Declared = $DefinitionsByName[(& $BaseNameOf $Config)].variables ?? [PSCustomObject]@{}
        $Names = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Property in $Declared.PSObject.Properties) { $null = $Names.Add($Property.Name) }
        foreach ($Property in $Variables.PSObject.Properties) { $null = $Names.Add($Property.Name) }
        $Pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($Name in $Names) {
            $Value = & $Unwrap $Variables.$Name
            if ([string]::IsNullOrEmpty("$Value")) {
                $Value = & $Unwrap ($Declared.$Name.default ?? $Declared.$Name.recommended)
            }
            if ($Value -is [string] -and "$($Declared.$Name.type)" -eq 'number' -and $Value -match '^-?\d+(\.\d+)?$') {
                $Value = [double]$Value
            } elseif ($Value -is [int] -or $Value -is [long]) {
                $Value = [double]$Value
            }
            $Pairs.Add(('{0}={1}' -f $Name, (ConvertTo-Json -Compress -Depth 20 -InputObject $Value)))
        }
        $Pairs -join ';'
    }
    $DifferencesOf = {
        param($Was, $Becomes)
        $Differences = [System.Collections.Generic.List[string]]::new()
        if ((& $SettingsOf $Was) -cne (& $SettingsOf $Becomes)) { $Differences.Add('Settings') }
        foreach ($Flag in @(
                @{ Name = 'remediateEnabled'; Label = 'Automatic remediation' }
                @{ Name = 'alertEnabled'; Label = 'Alerts' }
                @{ Name = 'alertOnRemediate'; Label = 'Alert on remediation' }
            )) {
            $Old = [bool]$Was.($Flag.Name)
            $New = [bool]$Becomes.($Flag.Name)
            if ($Old -ne $New) {
                $Differences.Add(('{0}: {1} to {2}' -f $Flag.Label, ($Old ? 'on' : 'off'), ($New ? 'on' : 'off')))
            }
        }
        , @($Differences)
    }
    # One entry per standard per stage; the key numbers a standard's occurrences in stage order.
    $ItemsOf = {
        param($Stages, $ConfigProperty)
        $Seen = @{}
        $StageIndex = 0
        foreach ($Stage in @($Stages)) {
            $StageIndex++
            foreach ($Config in @($Stage.$ConfigProperty)) {
                if (-not $Config) { continue }
                if ($Config -is [string]) {
                    $Config = [PSCustomObject]@{ standard = ($Config -split '#')[0]; instance = $Config; variables = [PSCustomObject]@{}; remediateEnabled = $false; alertEnabled = $true; alertOnRemediate = $false }
                }
                $Identity = & $IdentityOf $Config
                $Seen[$Identity] = [int]$Seen[$Identity] + 1
                [PSCustomObject]@{
                    Key        = '{0}|{1}' -f $Identity, $Seen[$Identity]
                    Config     = $Config
                    StageIndex = $StageIndex
                    StageName  = "$($Stage.name)"
                }
            }
        }
    }
    $EntryOf = {
        param($Item, $Changes, $StageName)
        $BaseName = & $BaseNameOf $Item.Config
        [PSCustomObject]@{
            key      = $Item.Key
            standard = $BaseName
            label    = "$($DefinitionsByName[$BaseName].label ?? $BaseName)"
            stage    = "$($StageName ?? $Item.StageName)"
            changes  = @($Changes | Where-Object { $_ })
        }
    }
    $ConfigFrom = {
        param($Source, $Instance)
        [PSCustomObject]@{
            standard         = "$($Instance.standard ?? (& $BaseNameOf $Instance))"
            instance         = "$($Instance.instance ?? $Instance.standard)"
            variables        = $Source.variables ?? [PSCustomObject]@{}
            remediateEnabled = [bool]$Source.remediateEnabled
            alertEnabled     = [bool]$Source.alertEnabled
            alertOnRemediate = [bool]$Source.alertOnRemediate
        }
    }

    $TemplateIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $AddTemplate = {
        param($Config)
        $IdentityVariable = $DefinitionsByName[(& $BaseNameOf $Config)].instanceIdentity
        if ($IdentityVariable) {
            $TemplateId = "$(& $Unwrap $Config.variables.$IdentityVariable)"
            if ($TemplateId) { $null = $TemplateIds.Add($TemplateId) }
        }
    }

    $LocalItems = @(& $ItemsOf $Local.stages 'standardsConfig')
    $RemoteItems = @(& $ItemsOf $Remote.stages 'standards')
    $LocalByKey = @{}
    foreach ($Item in $LocalItems) { $LocalByKey[$Item.Key] = $Item }
    $RemoteByKey = @{}
    foreach ($Item in $RemoteItems) { $RemoteByKey[$Item.Key] = $Item }
    $LocalStageNames = @(foreach ($Stage in @($Local.stages)) { "$($Stage.name)" })

    $Overwritten = [System.Collections.Generic.List[object]]::new()
    $Removed = [System.Collections.Generic.List[object]]::new()
    $Kept = [System.Collections.Generic.List[object]]::new()
    $Added = [System.Collections.Generic.List[object]]::new()
    $Available = [System.Collections.Generic.List[object]]::new()
    $Unchanged = 0
    $StageChange = $null
    $PayloadStages = [System.Collections.Generic.List[object]]::new()

    if ($Mode -eq 'merge') {
        $StageConfigs = @{}
        for ($Number = 1; $Number -le $LocalStageNames.Count; $Number++) {
            $StageConfigs[$Number] = [System.Collections.Generic.List[object]]::new()
        }
        foreach ($Item in $LocalItems) {
            $Match = $RemoteByKey[$Item.Key]
            if (-not $Match) {
                $Kept.Add((& $EntryOf $Item))
                $StageConfigs[$Item.StageIndex].Add($Item.Config)
                continue
            }
            # The template a shared standard points at follows CyberDrain even when its settings did not move.
            & $AddTemplate $Match.Config
            $Differences = & $DifferencesOf $Item.Config $Match.Config
            if ($Differences.Count -eq 0) {
                $Unchanged++
                $StageConfigs[$Item.StageIndex].Add($Item.Config)
            } else {
                $Overwritten.Add((& $EntryOf $Item $Differences))
                $StageConfigs[$Item.StageIndex].Add((& $ConfigFrom $Match.Config $Item.Config))
            }
        }
        foreach ($Item in $RemoteItems) {
            if ($LocalByKey.ContainsKey($Item.Key)) { continue }
            if ($Add -notcontains $Item.Key) {
                $Available.Add((& $EntryOf $Item))
                continue
            }
            # Same stage name first, else the same position, never past the last local stage.
            $Target = 0
            for ($Index = 0; $Index -lt $LocalStageNames.Count; $Index++) {
                if ($LocalStageNames[$Index] -eq $Item.StageName) { $Target = $Index + 1; break }
            }
            if ($Target -eq 0) { $Target = [Math]::Min($Item.StageIndex, $LocalStageNames.Count) }
            & $AddTemplate $Item.Config
            $Added.Add((& $EntryOf $Item $null $LocalStageNames[$Target - 1]))
            $StageConfigs[$Target].Add((& $ConfigFrom $Item.Config $Item.Config))
        }
        $Number = 0
        foreach ($Stage in @($Local.stages)) {
            $Number++
            $PayloadStages.Add([PSCustomObject]@{
                    name            = $Stage.name
                    sourceStage     = $Number
                    logic           = $Stage.logic ?? 'and'
                    conditions      = @($Stage.conditions | Where-Object { $_ })
                    conditionGroups = @($Stage.conditionGroups | Where-Object { $_ })
                    standards       = @($StageConfigs[$Number])
                })
        }
    } else {
        # CyberDrain cannot know the partner's tenant groups or custom variables.
        $AllowedConditions = @('time', 'success', 'manual')
        $Number = 0
        foreach ($Stage in @($Remote.stages)) {
            $Number++
            # Tenants keep their progress where a stage keeps its name, else its position.
            $SourceStage = $null
            for ($Index = 0; $Index -lt $LocalStageNames.Count; $Index++) {
                if ($LocalStageNames[$Index] -eq "$($Stage.name)") { $SourceStage = $Index + 1; break }
            }
            if (-not $SourceStage -and $Number -le $LocalStageNames.Count) { $SourceStage = $Number }
            $PayloadStages.Add([PSCustomObject]@{
                    name            = $Stage.name
                    sourceStage     = $SourceStage
                    logic           = $Stage.logic ?? 'and'
                    conditions      = @(@($Stage.conditions).Where({ $_.type -in $AllowedConditions }))
                    conditionGroups = @(foreach ($Group in @($Stage.conditionGroups)) {
                            $GroupConditions = @(@($Group.conditions).Where({ $_.type -in $AllowedConditions }))
                            if ($GroupConditions.Count -gt 0) { [PSCustomObject]@{ logic = $Group.logic ?? 'and'; conditions = $GroupConditions } }
                        })
                    standards       = @(foreach ($Item in $RemoteItems) {
                            if ($Item.StageIndex -eq $Number) { & $ConfigFrom $Item.Config $Item.Config }
                        })
                })
        }
        foreach ($Item in $RemoteItems) {
            & $AddTemplate $Item.Config
            $Match = $LocalByKey[$Item.Key]
            if (-not $Match) {
                $Added.Add((& $EntryOf $Item))
                continue
            }
            $Differences = & $DifferencesOf $Match.Config $Item.Config
            if ($Differences.Count -eq 0) { $Unchanged++ } else { $Overwritten.Add((& $EntryOf $Item $Differences)) }
        }
        foreach ($Item in $LocalItems) {
            if (-not $RemoteByKey.ContainsKey($Item.Key)) { $Removed.Add((& $EntryOf $Item)) }
        }
        $RemoteStageNames = @(foreach ($Stage in @($Remote.stages)) { "$($Stage.name)" })
        if (($LocalStageNames -join "`n") -ne ($RemoteStageNames -join "`n")) {
            $StageChange = [PSCustomObject]@{ from = $LocalStageNames; to = $RemoteStageNames }
        }
    }

    # A baseline with no tenant at all would lose its standards: they are stored per assignment.
    $Assigned = @($Local.assignments | Where-Object { $_ })
    if ($Assigned.Count -eq 0) {
        $Assigned = @([PSCustomObject]@{ label = 'Exported Template'; value = 'Exported Template'; type = 'Tenant' })
    }

    @{
        Payload     = [PSCustomObject]@{
            GUID                 = $Local.GUID
            templateName         = $Local.templateName
            description          = $Local.description
            assignedTenants      = $Assigned
            excludedTenants      = @($Local.exclusions | Where-Object { $_ })
            alertEmails          = "$($Local.alertEmails)"
            alertWebhookUrl      = "$($Local.alertWebhookUrl)"
            disableAlerts        = [bool]$Local.disableAlerts
            disableScheduledRuns = [bool]$Local.disableScheduledRuns
            stages               = @($PayloadStages)
        }
        Changes     = [PSCustomObject]@{
            overwritten = @($Overwritten)
            unchanged   = $Unchanged
            removed     = @($Removed)
            kept        = @($Kept)
            added       = @($Added)
            available   = @($Available)
            stages      = $StageChange
        }
        TemplateIds = [string[]]@($TemplateIds)
    }
}
