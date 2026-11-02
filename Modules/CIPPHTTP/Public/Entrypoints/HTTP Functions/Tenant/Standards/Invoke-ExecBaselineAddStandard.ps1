function Invoke-ExecBaselineAddStandard {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.ReadWrite
    .DESCRIPTION
        Adds one standard, with its configured settings, to a stage of an existing baseline. The baseline
        is read with Get-CIPPBaseline, the standard is appended to the stage (replacing an existing
        single-instance copy) and the whole baseline is saved again through New-CIPPBaseline, the same
        write path the baseline editor uses. Body: baselineId, stage (1-based, default 1), standard,
        variables, remediateEnabled (default false), alertEnabled (default true).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $Unwrap = {
            param($Value)
            if ($Value -is [array]) {
                return @($Value | ForEach-Object {
                        if ($_ -is [PSCustomObject] -and $null -ne $_.PSObject.Properties['value']) { [PSCustomObject]@{ label = "$($_.label ?? $_.value)"; value = $_.value } } else { $_ }
                    })
            }
            if ($Value -is [PSCustomObject] -and $null -ne $Value.PSObject.Properties['value']) { return $Value.value }
            $Value
        }

        $BaselineId = "$(& $Unwrap $Request.Body.baselineId)"
        $Standard = "$(& $Unwrap $Request.Body.standard)"
        $StageNumber = [int]($(& $Unwrap $Request.Body.stage) ?? 1)
        if (-not $BaselineId -or -not $Standard) { throw 'Provide baselineId and standard.' }
        if ($StageNumber -lt 1) { $StageNumber = 1 }

        $Definition = Get-CIPPBaselineDefinition -Name $Standard | Select-Object -First 1
        if (-not $Definition) { throw "Unknown standard '$Standard'." }
        $Baseline = Get-CIPPBaseline -ID $BaselineId | Select-Object -First 1
        if (-not $Baseline) { throw "Baseline '$BaselineId' was not found." }
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

        $Variables = [PSCustomObject]@{}
        foreach ($Property in @(($Request.Body.variables ?? [PSCustomObject]@{}).PSObject.Properties)) {
            $Variables | Add-Member -NotePropertyName $Property.Name -NotePropertyValue (& $Unwrap $Property.Value)
        }

        $Stages = [System.Collections.Generic.List[object]]::new()
        foreach ($Stage in @($Baseline.stages)) {
            $Stages.Add([PSCustomObject]@{
                    name       = $Stage.name
                    logic      = $Stage.logic
                    conditions = @($Stage.conditions)
                    standards  = [System.Collections.Generic.List[object]]@($Stage.standardsConfig | Where-Object { $_ })
                })
        }
        if ($Stages.Count -eq 0) { throw 'The baseline has no stages.' }
        if ($StageNumber -gt $Stages.Count) { $StageNumber = $Stages.Count }
        $Target = $Stages[$StageNumber - 1]

        $Multiple = $Definition.multiple -eq $true
        $Existing = @($Target.standards | Where-Object { (("$($_.instance)") -split '#')[0] -eq $Standard })
        $InstanceKey = $Standard
        if ($Multiple -and $Existing.Count -gt 0) {
            $Suffix = 2
            while (@($Existing | Where-Object { "$($_.instance)" -eq "$Standard#$Suffix" }).Count -gt 0) { $Suffix++ }
            $InstanceKey = "$Standard#$Suffix"
        }
        $Kept = [System.Collections.Generic.List[object]]::new()
        foreach ($Config in $Target.standards) {
            if (-not $Multiple -and (("$($Config.instance)") -split '#')[0] -eq $Standard) { continue }
            $Kept.Add($Config)
        }
        $Kept.Add([PSCustomObject]@{
                standard         = $Standard
                instance         = $InstanceKey
                variables        = $Variables
                remediateEnabled = [bool]($Request.Body.remediateEnabled -eq $true)
                alertEnabled     = [bool]($Request.Body.alertEnabled ?? $true)
                alertOnRemediate = $false
            })
        $Target.standards = @($Kept)

        $Payload = [PSCustomObject]@{
            GUID                 = $Baseline.GUID
            templateName         = $Baseline.templateName
            description          = $Baseline.description
            assignedTenants      = @($Baseline.assignments)
            excludedTenants      = @($Baseline.exclusions)
            alertEmails          = $Baseline.alertEmails
            alertWebhookUrl      = $Baseline.alertWebhookUrl
            disableAlerts        = [bool]$Baseline.disableAlerts
            disableScheduledRuns = [bool]$Baseline.disableScheduledRuns
            stages               = @($Stages)
        }
        $Saved = New-CIPPBaseline -Baseline $Payload -User $User

        $Message = "Added $($Definition.label ?? $Standard) to stage $StageNumber of baseline '$($Baseline.templateName)'."
        Write-LogMessage -headers $Request.Headers -API $APIName -message "$Message ($($Saved.DeltaCount) delta rows written.)" -Sev 'Info'
        $Results = [pscustomobject]@{ Results = $Message; Metadata = @{ id = $Saved.GUID; instance = $InstanceKey } }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to add the standard to the baseline: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Failed to add the standard to the baseline: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
