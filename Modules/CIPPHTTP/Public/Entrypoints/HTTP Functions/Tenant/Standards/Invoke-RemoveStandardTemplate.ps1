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
    if (-not $ID) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ID is required' } })
    }
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
        # The request names no tenant, so check the tenants the template targets; the import placeholder targets nothing.
        $Targets = @(foreach ($Row in $ClearRow) { if ($Row.JSON) { (ConvertFrom-Json -InputObject $Row.JSON -ErrorAction SilentlyContinue).tenantFilter } }) | Where-Object { "$($_.value ?? $_)" -ne 'Template Tenant' }
        if ($Targets) { Assert-CippTenantAccess -Request $Request -TenantFilter @($Targets) }
        $Entities = Get-AzDataTableEntity @Table -Filter $Filter
        if (-not $Entities) { throw [System.Management.Automation.ItemNotFoundException]::new("No standards template with id $ID was found.") }
        Remove-CIPPAzDataTableEntity -Force @Table -Entity $Entities

        # Remove any drift remediation scheduled tasks associated with this template
        $ScheduledTasksTable = Get-CIPPTable -TableName 'ScheduledTasks'
        $SafeTag = ConvertTo-CIPPODataFilterValue -Value "DriftRemediation_$SafeID"
        $DriftTasks = Get-CIPPAzDataTableEntity @ScheduledTasksTable -Filter "PartitionKey eq 'ScheduledTask' and Tag eq '$SafeTag'"
        foreach ($DriftTask in $DriftTasks) {
            Remove-CIPPAzDataTableEntity -Force @ScheduledTasksTable -Entity $DriftTask
            Write-LogMessage -Headers $Headers -API $APIName -message "Removed drift remediation scheduled task: $($DriftTask.Name)" -Sev Info
        }
        $StandardsReportsTable = Get-CIPPTable -TableName 'CippStandardsReports'
        $RemovedTemplateIds = @(@($Entities.RowKey) + $ID | Where-Object { $_ } | Select-Object -Unique)
        $OrphanedReports = [System.Collections.Generic.List[object]]::new()
        foreach ($RemovedTemplateId in $RemovedTemplateIds) {
            $SafeTemplateId = ConvertTo-CIPPODataFilterValue -Value $RemovedTemplateId -Type Guid
            $Rows = Get-CIPPAzDataTableEntity @StandardsReportsTable -Filter "TemplateId eq '$SafeTemplateId'"
            foreach ($Row in $Rows) { $OrphanedReports.Add($Row) }
        }
        if ($OrphanedReports.Count -gt 0) {
            Remove-CIPPAzDataTableEntity -Force @StandardsReportsTable -Entity @($OrphanedReports)
            Write-LogMessage -Headers $Headers -API $APIName -message "Removed $($OrphanedReports.Count) orphaned standards comparison row(s) for template id: $($ID)" -Sev Info
        }

        $Result = "Removed Standards Template named: '$($TemplateName)' with id: $($ID)"
        if ($DriftTasks) {
            $Result += ". Also removed $(@($DriftTasks).Count) associated drift remediation scheduled task(s)."
        }
        if ($OrphanedReports.Count -gt 0) {
            $Result += " Cleaned up $($OrphanedReports.Count) orphaned standards comparison row(s)."
        }
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Standards template: $TemplateName with id: $ID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
