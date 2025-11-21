function Invoke-RemoveIntuneTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $ID = $request.Query.ID ?? $Request.Body.ID
    try {
        $Table = Get-CippTable -tablename 'templates'

        $Filter = "PartitionKey eq 'IntuneTemplate' and RowKey eq '$ID'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        if ($ClearRow) {
            Remove-AzDataTableEntity @Table -Entity $clearRow -Force
            $Result = "Removed Intune Template with ID $ID."
        } else {
            $Result = "The template with ID $ID has already been deleted."
        }
        Write-LogMessage -Headers $Headers -API $APINAME -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Intune template $($ID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APINAME -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })


}
