using namespace System.Net

Function Invoke-RemoveIntuneTemplate {
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
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $ID = $request.Query.ID ?? $Request.Body.ID
    try {
        $Table = Get-CippTable -tablename 'templates'
        Write-Host $ID

        $Filter = "PartitionKey eq 'IntuneTemplate' and RowKey eq '$ID'"
        Write-Host $Filter
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity -Force @Table -Entity $clearRow
        $Result = "Removed Intune Template with ID $ID"
        Write-LogMessage -Headers $Headers -API $APINAME -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Intune template $($ID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APINAME -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })


}
