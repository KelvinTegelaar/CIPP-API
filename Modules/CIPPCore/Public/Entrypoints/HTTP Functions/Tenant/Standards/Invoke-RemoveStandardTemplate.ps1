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
    $TemplateName = ''
    try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'StandardsTemplateV2' and (GUID eq '$ID' or RowKey eq '$ID' or OriginalEntityId eq '$ID')"
        $MergedRows = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        if ($MergedRows.JSON) {
            try {
                $TemplateName = (ConvertFrom-Json -InputObject $MergedRows.JSON -ErrorAction SilentlyContinue).templateName
            } catch {
                $TemplateName = ''
            }
        }
        $RowsToDelete = @(Get-AzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey, ETag)
        foreach ($Row in $RowsToDelete) {
            Remove-AzDataTableEntity -Force @Table -Entity $Row
        }
        $Result = "Removed Standards Template named: '$($TemplateName)' with id: $($ID)"
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
