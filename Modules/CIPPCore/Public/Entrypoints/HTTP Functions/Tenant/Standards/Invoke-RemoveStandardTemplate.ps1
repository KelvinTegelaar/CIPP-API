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
        $Filter = "PartitionKey eq 'StandardsTemplateV2' and GUID eq '$ID'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey, JSON
        if ($ClearRow.JSON) {
            $TemplateName = (ConvertFrom-Json -InputObject $ClearRow.JSON -ErrorAction SilentlyContinue).templateName
        } else {
            $TemplateName = ''
        }
        Remove-AzDataTableEntity -Force @Table -Entity $ClearRow
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
