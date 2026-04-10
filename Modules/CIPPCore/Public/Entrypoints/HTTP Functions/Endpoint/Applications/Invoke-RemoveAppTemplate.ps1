function Invoke-RemoveAppTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $ID = $Request.Body.ID ?? $Request.Query.ID
        if (!$ID) { throw 'No template ID provided' }

        $Table = Get-CippTable -tablename 'templates'
        $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type Guid
        $Filter = "PartitionKey eq 'AppTemplate' and RowKey eq '$SafeID'"
        $Entity = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        if ($Entity) {
            Remove-AzDataTableEntity @Table -Entity $Entity
            $Result = 'Successfully removed app template'
            Write-LogMessage -headers $Headers -API $APIName -message "Removed app template $ID" -Sev 'Info'
        } else {
            $Result = 'Template not found'
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove app template: $($ErrorMessage.NormalizedMessage)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    })
}
