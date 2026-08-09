function Invoke-ExecBaselineStage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    .DESCRIPTION
        Advances a tenant to the next stage of a baseline (manual stage approval). The tenant
        receives all standards from the new stage on the next engine run.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $TenantFilter = $Request.Body.tenantFilter
        $TemplateId = $Request.Body.templateId
        if (-not ($TenantFilter -and $TemplateId)) {
            throw 'Provide tenantFilter and templateId.'
        }

        $Baseline = Get-CIPPBaseline -ID $TemplateId
        if (-not $Baseline) { throw "No baseline found with ID $TemplateId." }
        $TotalStages = @($Baseline.stages).Count

        $StateTable = Get-CippTable -tablename 'BaselineRolloutState'
        $SafeTemplate = ConvertTo-CIPPODataFilterValue -Value $TemplateId
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $State = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTemplate' and RowKey eq '$SafeTenant'"
        $CurrentStage = if ($State) { [int]$State.currentStage } else { 1 }
        if ($CurrentStage -ge $TotalStages) {
            throw "$TenantFilter is already in the final stage of $($Baseline.templateName)."
        }

        $NewStage = $CurrentStage + 1
        $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
        $StateTable.Force = $true
        Add-CIPPAzDataTableEntity @StateTable -Entity @{
            PartitionKey    = "$TemplateId"
            RowKey          = "$TenantFilter"
            currentStage    = $NewStage
            enteredStageAt  = $Now
            firstDeployedAt = $State.firstDeployedAt ?? $State.enteredStageAt ?? $Now
        }

        $StageName = $Baseline.stages[$NewStage - 1].name
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        $null = Add-CIPPBaselineHistoryEvent -TenantFilter $TenantFilter -Standard $Baseline.templateName -Mode 'stage' -TriggeredBy $User -Outcome 'Stage Advanced' -Detail "Moved to stage $NewStage ($StageName) - the stage's standards apply on the next run"
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Moved $TenantFilter to stage $NewStage ($StageName) of baseline $($Baseline.templateName)." -Sev 'Info'
        $Results = [pscustomobject]@{ Results = "Moved $TenantFilter to stage $NewStage ($StageName) of $($Baseline.templateName). The stage's standards apply on the next run." }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to advance stage: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Failed to advance stage: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
