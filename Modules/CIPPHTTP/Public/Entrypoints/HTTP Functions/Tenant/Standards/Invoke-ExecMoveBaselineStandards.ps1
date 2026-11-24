function Invoke-ExecMoveBaselineStandards {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.ReadWrite
    .SYNOPSIS
        Moves or copies a standard, or a whole stage, from one baseline to another.
    .DESCRIPTION
        Moves or copies one standard (standard + sourceStage) or a whole stage (stage) into another saved baseline.
        A single standard goes into an existing stage (targetStage) or a new stage of its own with no graduation
        conditions (newStage, end only). A whole stage always becomes a new stage (newStage, default 'end') and keeps its name
        and graduation conditions. A standard that allows one instance is never added to a stage that already has
        it; multi-instance standards get a new instance id. The target is saved first, then the source.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # GUID of the baseline the standards come from.
    $SourceId = $Request.Body.sourceId
    # GUID of the baseline the standards go to. Must differ from sourceId.
    $TargetId = $Request.Body.targetId
    # 'move' (default) removes the standards from the source baseline; 'copy' leaves the source unchanged.
    $Mode = $Request.Body.mode ?? 'move'
    # Instance key of one standard to move, as the editor shows it ('Name' or 'Name#id'). Send with sourceStage.
    $StandardKey = $Request.Body.standard
    # 0-based index of the source stage that holds the standard.
    $SourceStageIndex = $Request.Body.sourceStage -as [int]
    # 0-based index of a whole source stage to move. Send instead of standard.
    $WholeStageIndex = $Request.Body.stage -as [int]
    # Single standard only: 0-based index of an existing target stage to add the standard to. Send this or newStage.
    $TargetStageValue = $Request.Body.targetStage
    # Where a new stage goes in the target: 'end' or the 0-based index of the stage it goes straight after.
    # A new stage with no graduation conditions (a single standard, or a conditionless stage) must go at the end.
    # Required for a single standard unless targetStage is sent; a whole stage defaults to 'end'.
    $NewStageValue = $Request.Body.newStage

    if (-not $SourceId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'sourceId is required.' } })
    }
    if (-not $TargetId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'targetId is required.' } })
    }
    if ("$SourceId" -eq "$TargetId") {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Pick a different baseline to move to.' } })
    }
    if ($Mode -notin @('move', 'copy')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "mode must be 'move' or 'copy'." } })
    }
    $IsWholeStage = -not $StandardKey
    if ($IsWholeStage -and $null -eq $WholeStageIndex) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Send either standard with sourceStage, or stage.' } })
    }
    if (-not $IsWholeStage -and $null -eq $SourceStageIndex) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'sourceStage is required when moving a single standard.' } })
    }
    $ToExisting = "$TargetStageValue" -ne ''
    $ToNew = "$NewStageValue" -ne ''
    if ($ToExisting -and $ToNew) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Send either targetStage or newStage, not both.' } })
    }
    if ($ToExisting -and $IsWholeStage) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'A whole stage always becomes a new stage. Send newStage instead of targetStage.' } })
    }
    if (-not $ToExisting -and -not $ToNew -and -not $IsWholeStage) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Send targetStage for an existing stage, or newStage for a new one.' } })
    }
    $TargetStageIndex = $TargetStageValue -as [int]
    if ($ToExisting -and $null -eq $TargetStageIndex) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'targetStage must be a stage index.' } })
    }
    $AtEnd = -not $ToExisting -and "$NewStageValue" -in @('', 'end')
    $AfterIndex = $NewStageValue -as [int]
    if ($ToNew -and -not $AtEnd -and $null -eq $AfterIndex) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "newStage must be 'end' or the index of the stage the new stage goes after." } })
    }
    if ($ToNew -and -not $AtEnd -and $AfterIndex -lt 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'A new stage cannot go before Stage 1. Stage 1 always stays the first stage.' } })
    }

    try {
        $Source = $null
        $Target = $null
        foreach ($Baseline in @(Get-CIPPBaseline -ID $SourceId)) { $Source = $Baseline; break }
        foreach ($Baseline in @(Get-CIPPBaseline -ID $TargetId)) { $Target = $Baseline; break }
        $MultipleStandards = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Labels = @{}
        foreach ($Definition in @(Get-CIPPBaselineDefinition)) {
            if ($Definition.multiple -eq $true) { $null = $MultipleStandards.Add("$($Definition.name)") }
            if ($Definition.label) { $Labels["$($Definition.name)"] = "$($Definition.label)" }
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to load the baselines: $($_.Exception.Message)" -Sev 'Error'
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "Failed to load the baselines: $($_.Exception.Message)" } })
    }

    if (-not $Source -or -not $Target) {
        $Missing = if (-not $Source) { $SourceId } else { $TargetId }
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = "Baseline $Missing was not found. It may have been deleted." } })
    }

    foreach ($Baseline in @($Source, $Target)) {
        $OutOfScope = @(Get-CIPPBaselineOutOfScopeAssignment -Assignments @($Baseline.assignments))
        if ($OutOfScope.Count -gt 0) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = "Your role can't change baseline $($Baseline.templateName), because it is assigned to tenants outside your access: $($OutOfScope -join ', ')." } })
        }
    }

    # Save-shaped copies of both baselines (the shape AddBaseline/New-CIPPBaseline take). sourceStage keeps tenant
    # progress mapped to the right stage when a stage is removed or inserted.
    $Payloads = @{}
    foreach ($Baseline in @($Source, $Target)) {
        $Stages = [System.Collections.Generic.List[object]]::new()
        $Position = 0
        foreach ($Stage in @($Baseline.stages)) {
            $Position++
            $Stages.Add(@{
                    name            = $Stage.name
                    logic           = $Stage.logic
                    conditions      = @($Stage.conditions)
                    conditionGroups = @($Stage.conditionGroups)
                    sourceStage     = $Position
                    standards       = [System.Collections.Generic.List[object]]::new([object[]]@($Stage.standardsConfig).Where({ $_ }))
                })
        }
        $Payloads[$Baseline.GUID] = @{
            GUID                 = $Baseline.GUID
            templateName         = $Baseline.templateName
            description          = $Baseline.description
            assignedTenants      = @($Baseline.assignments)
            excludedTenants      = @($Baseline.exclusions)
            alertEmails          = $Baseline.alertEmails
            alertWebhookUrl      = $Baseline.alertWebhookUrl
            disableAlerts        = [bool]$Baseline.disableAlerts
            disableScheduledRuns = [bool]$Baseline.disableScheduledRuns
            stages               = $Stages
        }
    }
    $SourcePayload = $Payloads[$Source.GUID]
    $TargetPayload = $Payloads[$Target.GUID]

    $FromIndex = if ($IsWholeStage) { $WholeStageIndex } else { $SourceStageIndex }
    if ($FromIndex -lt 0 -or $FromIndex -ge $SourcePayload.stages.Count) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Baseline $($Source.templateName) has no stage $($FromIndex + 1)." } })
    }
    if ($ToExisting -and ($TargetStageIndex -lt 0 -or $TargetStageIndex -ge $TargetPayload.stages.Count)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Baseline $($Target.templateName) has no stage $($TargetStageIndex + 1)." } })
    }
    if ($ToNew -and -not $AtEnd -and $AfterIndex -ge $TargetPayload.stages.Count) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Baseline $($Target.templateName) has no stage $($AfterIndex + 1) to place the new stage after." } })
    }
    if (-not $ToExisting -and $TargetPayload.stages.Count -ge 20) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Baseline $($Target.templateName) already has 20 stages, the most a baseline can have." } })
    }

    $FromStage = $SourcePayload.stages[$FromIndex]
    $Moving = [System.Collections.Generic.List[object]]::new()
    foreach ($Config in $FromStage.standards) {
        if ($IsWholeStage -or "$($Config.instance)" -eq $StandardKey) { $Moving.Add($Config) }
    }
    if (-not $IsWholeStage -and $Moving.Count -eq 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Stage $($FromIndex + 1) of $($Source.templateName) does not contain $StandardKey." } })
    }
    $StandardName = "$($Moving[0].standard)"
    if ($ToExisting -and -not $MultipleStandards.Contains($StandardName)) {
        foreach ($Config in $TargetPayload.stages[$TargetStageIndex].standards) {
            if ("$($Config.standard)" -eq $StandardName) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Stage $($TargetStageIndex + 1) of $($Target.templateName) already has $StandardName, and it can only be added once per stage. Pick another stage or a new stage." } })
            }
        }
    }

    $Copies = [System.Collections.Generic.List[object]]::new()
    foreach ($Config in $Moving) {
        $Instance = "$($Config.instance)"
        if ($MultipleStandards.Contains("$($Config.standard)")) {
            $Instance = '{0}#{1}' -f $Config.standard, ([guid]::NewGuid().ToString('N').Substring(0, 8))
        }
        $Copies.Add([PSCustomObject]@{
                standard         = $Config.standard
                instance         = $Instance
                variables        = $Config.variables
                remediateEnabled = [bool]$Config.remediateEnabled
                alertEnabled     = [bool]$Config.alertEnabled
                alertOnRemediate = [bool]$Config.alertOnRemediate
            })
    }

    $HasConditions = $true
    if ($ToExisting) {
        $TargetPayload.stages[$TargetStageIndex].standards.AddRange($Copies)
        $Where = "stage $($TargetStageIndex + 1) of $($Target.templateName)"
    } else {
        $InsertAt = if ($AtEnd) { $TargetPayload.stages.Count } else { $AfterIndex + 1 }
        $NewStage = if ($IsWholeStage) {
            @{ name = $FromStage.name; logic = $FromStage.logic; conditions = $FromStage.conditions; conditionGroups = $FromStage.conditionGroups }
        } else {
            @{ name = "$($Labels[$StandardName] ?? $StandardName) (from $($Source.templateName))"; logic = 'and'; conditions = @(); conditionGroups = @() }
        }
        $NewStage.standards = $Copies
        # Counts as reached only by tenants already past the stage it is inserted before, so every tenant keeps its stage.
        $NewStage.sourceStage = $InsertAt + 1
        $TargetPayload.stages.Insert($InsertAt, $NewStage)
        $Where = "a new stage $($InsertAt + 1) ($($NewStage.name)) of $($Target.templateName)"
        $HasConditions = $false
        foreach ($Condition in @($NewStage.conditions; $NewStage.conditionGroups.conditions)) {
            if ($Condition.type) { $HasConditions = $true }
        }
        if (-not $HasConditions -and -not $AtEnd) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'A new stage with no graduation conditions can only go at the end, or it stops every tenant from moving past it. Send newStage as end.' } })
        }
    }

    if ($Mode -eq 'move') {
        if (-not $IsWholeStage) {
            $null = $FromStage.standards.Remove($Moving[0])
        } elseif ($FromIndex -eq 0) {
            # Stage 1 is the default stage every assigned tenant sits in, so it is emptied, never deleted.
            $FromStage.standards.Clear()
        } else {
            $SourcePayload.stages.RemoveAt($FromIndex)
        }
    }

    $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    $What = if ($IsWholeStage) { "stage $($FromIndex + 1) ($($FromStage.name)) of $($Source.templateName)" } else { "$StandardKey from $($Source.templateName)" }
    $NoConditions = if ($HasConditions) { '' } else {
        " The new stage has no graduation conditions yet, so no tenant moves into it until you add one. The baseline editor asks for one before $($Target.templateName) can be saved again."
    }

    try {
        # A repo-synced baseline edited here has local changes not yet in its repo.
        if ($Target.source) {
            $null = New-CIPPBaseline -Baseline $TargetPayload -User $User -LocalChanges:$true
        } else {
            $null = New-CIPPBaseline -Baseline $TargetPayload -User $User
        }
        Write-LogMessage -headers $Headers -API $APIName -message "Added $($Copies.Count) standard(s) to $Where ($($Target.GUID)), $($Mode -eq 'move' ? 'moved' : 'copied') from $What." -Sev 'Info'
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to save baseline $($Target.templateName): $($_.Exception.Message)" -Sev 'Error'
        return ([HttpResponseContext]@{ StatusCode = Get-CippErrorStatusCode -ErrorRecord $_; Body = @{ Results = "Failed to save baseline $($Target.templateName). Nothing was changed. $($_.Exception.Message)" } })
    }

    if ($Mode -eq 'copy') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = "Copied $What to $Where.$NoConditions" } })
    }

    try {
        if ($Source.source) {
            $null = New-CIPPBaseline -Baseline $SourcePayload -User $User -LocalChanges:$true
        } else {
            $null = New-CIPPBaseline -Baseline $SourcePayload -User $User
        }
        Write-LogMessage -headers $Headers -API $APIName -message "Removed $($Moving.Count) standard(s) from $What ($($Source.GUID)), moved to $Where." -Sev 'Info'
    } catch {
        $Message = "The standards were copied to $Where, but could not be removed from $($Source.templateName): $($_.Exception.Message). Remove them from $($Source.templateName) by hand."
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error'
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = $Message } })
    }

    return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = "Moved $What to $Where.$NoConditions" } })
}
