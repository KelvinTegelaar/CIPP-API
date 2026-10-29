function Invoke-ExecBaselineStage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.ReadWrite
    .DESCRIPTION
        Advances a tenant to the next stage of a baseline (manual stage approval), with action
        'previous' moves it back one stage, or with action 'evaluate' re-checks the next stage's
        conditions now instead of waiting for the scheduled run. The tenant receives the standards
        of every stage up to its new one on the next engine run.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $TenantFilter = $Request.Body.tenantFilter
        $TemplateId = $Request.Body.templateId
        if (-not ($TenantFilter -and $TemplateId)) {
            throw [System.ArgumentException]::new('Provide tenantFilter and templateId.')
        }

        $Baseline = Get-CIPPBaseline -ID $TemplateId
        if (-not $Baseline) { throw [System.Management.Automation.ItemNotFoundException]::new("No baseline found with ID $TemplateId.") }
        $TotalStages = @($Baseline.stages).Count

        $StateTable = Get-CippTable -tablename 'BaselineRolloutState'
        $SafeTemplate = ConvertTo-CIPPODataFilterValue -Value $TemplateId
        $Tenant = @(Get-Tenants -TenantFilter $TenantFilter -IncludeErrors)[0]
        $TenantId = $Tenant.customerId ?? $TenantFilter
        # Rows saved before customerId keys carry one of the tenant's domains instead.
        $TenantKeys = @($TenantId, $Tenant.defaultDomainName, $Tenant.initialDomainName, $TenantFilter) | Where-Object { $_ }
        $State = @(Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTemplate'" | Where-Object { $_.RowKey -in $TenantKeys } | Sort-Object -Property { $_.RowKey -ne $TenantId })[0]
        $CurrentStage = if ($State) { [int]$State.currentStage } else { 1 }
        $MovingBack = $Request.Body.action -eq 'previous'
        if ($MovingBack -and $CurrentStage -le 1) {
            throw [System.ArgumentException]::new("$TenantFilter is already in the first stage of $($Baseline.templateName).")
        }
        if (-not $MovingBack -and $CurrentStage -ge $TotalStages) {
            throw [System.ArgumentException]::new("$TenantFilter is already in the final stage of $($Baseline.templateName).")
        }

        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

        # evaluate: re-check the next stage's conditions now; anything else is a manual advance
        if ($Request.Body.action -eq 'evaluate') {
            $Evaluation = @(Invoke-CIPPBaselineGraduation -TenantFilter $TenantFilter -TemplateId $TemplateId -TriggeredBy $User) | Select-Object -First 1
            $Message = if (-not $Evaluation) {
                "Stage $($CurrentStage + 1) of $($Baseline.templateName) has no automatic conditions for $TenantFilter to meet."
            } elseif ($Evaluation.Advanced) {
                "Moved $TenantFilter to stage $($Evaluation.Stage) ($($Evaluation.StageName)) of $($Baseline.templateName). The stage's standards apply on the next run."
            } else {
                "$TenantFilter stays in stage $CurrentStage of $($Baseline.templateName). Conditions not met: $($Evaluation.Unmet -join ', ')."
            }
            Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = [pscustomobject]@{ Results = $Message }
                })
        }

        # A stage number past the end (left by an older stage removal) steps back to the final stage.
        $NewStage = if ($MovingBack) { [Math]::Min($CurrentStage - 1, $TotalStages) } else { $CurrentStage + 1 }
        $Moved = if ($MovingBack) { 'Moved back' } else { 'Moved' }
        $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
        $StateTable.Force = $true
        Add-CIPPAzDataTableEntity @StateTable -Entity @{
            PartitionKey    = "$TemplateId"
            RowKey          = "$TenantId"
            currentStage    = $NewStage
            enteredStageAt  = $Now
            firstDeployedAt = $State.firstDeployedAt ?? $State.enteredStageAt ?? $Now
        }

        $StageName = $Baseline.stages[$NewStage - 1].name
        $null = Add-CIPPBaselineHistoryEvent -TenantFilter $TenantFilter -Standard $Baseline.templateName -Mode 'stage' -TriggeredBy $User -Outcome $(if ($MovingBack) { 'Stage Moved Back' } else { 'Stage Advanced' }) -Detail "$Moved to stage $NewStage ($StageName) - the stage's standards apply on the next run"
        Write-LogMessage -headers $Request.Headers -API $APIName -message "$Moved $TenantFilter to stage $NewStage ($StageName) of baseline $($Baseline.templateName)." -Sev 'Info'
        $Results = [pscustomobject]@{ Results = "$Moved $TenantFilter to stage $NewStage ($StageName) of $($Baseline.templateName). The stage's standards apply on the next run." }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to change stage: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Failed to change stage: $($_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
