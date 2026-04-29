function Invoke-RemoveStandardTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $ID = $Request.Body.ID ?? $Request.Query.ID
    try {
        $Table = Get-CippTable -tablename 'templates'
        $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type Guid
        $Filter = "PartitionKey eq 'StandardsTemplateV2' and (RowKey eq '$SafeID' or OriginalEntityId eq '$SafeID' or OriginalEntityId eq guid'$SafeID')"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        if ($ClearRow.JSON) {
            $TemplateName = (ConvertFrom-Json -InputObject $ClearRow.JSON -ErrorAction SilentlyContinue).templateName
        } else {
            $TemplateName = ''
        }
        $Entities = Get-AzDataTableEntity @Table -Filter $Filter
        Remove-AzDataTableEntity -Force @Table -Entity $Entities

        # Remove any drift remediation scheduled tasks associated with this template
        $ScheduledTasksTable = Get-CIPPTable -TableName 'ScheduledTasks'
        $SafeTag = ConvertTo-CIPPODataFilterValue -Value "DriftRemediation_$SafeID"
        $DriftTasks = Get-CIPPAzDataTableEntity @ScheduledTasksTable -Filter "PartitionKey eq 'ScheduledTask' and Tag eq '$SafeTag'"
        foreach ($DriftTask in $DriftTasks) {
            Remove-AzDataTableEntity -Force @ScheduledTasksTable -Entity $DriftTask
            Write-LogMessage -Headers $Headers -API $APIName -message "Removed drift remediation scheduled task: $($DriftTask.Name)" -Sev Info
        }

        $Result = "Removed Standards Template named: '$($TemplateName)' with id: $($ID)"
        if ($DriftTasks) {
            $Result += ". Also removed $(@($DriftTasks).Count) associated drift remediation scheduled task(s)."
        }
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Standards template: $TemplateName with id: $ID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
