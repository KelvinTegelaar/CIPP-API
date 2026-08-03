function Invoke-RemoveBaseline {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    .DESCRIPTION
        Deletes a baseline and its rollout state. Resolved rows are left for the
        engine to clean up on the next run, when the baseline stops resolving.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $ID = $Request.Body.ID ?? $Request.Query.ID
    try {
        if (-not $ID) { throw 'Provide the ID of the baseline to remove.' }
        $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID

        $Table = Get-CippTable -tablename 'BaselineRollouts'
        $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'rollout' and RowKey eq '$SafeID'"
        if (-not $Entity) { throw "No baseline found with ID $ID." }
        $BaselineName = $Entity.templateName ?? $ID
        Remove-CIPPAzDataTableEntity -Force @Table -Entity $Entity

        # The exploded delta rows and rollout state for this baseline go with it.
        $DeltaTable = Get-CippTable -tablename 'Baselines'
        $DeltaRows = Get-CIPPAzDataTableEntity @DeltaTable -Filter "PartitionKey eq 'standardItem' and templateId eq '$SafeID'"
        if ($DeltaRows) {
            Remove-CIPPAzDataTableEntity -Force @DeltaTable -Entity $DeltaRows
        }
        $StateTable = Get-CippTable -tablename 'BaselineRolloutState'
        $StateRows = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeID'"
        if ($StateRows) {
            Remove-CIPPAzDataTableEntity -Force @StateTable -Entity $StateRows
        }

        Write-LogMessage -headers $Request.Headers -API $APIName -message "Removed baseline $BaselineName ($ID)." -Sev 'Info'
        $Results = [pscustomobject]@{ Results = "Successfully removed baseline $BaselineName" }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to remove baseline: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Failed to remove baseline: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
