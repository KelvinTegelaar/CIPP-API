using namespace System.Net

Function Invoke-RemoveStandardTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $User = $Request.Headers
    Write-LogMessage -Headers $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $ID = $Request.Body.ID ?? $Request.Query.ID
    try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'StandardsTemplateV2' and RowKey eq '$id'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity -Force @Table -Entity $clearRow
        Write-LogMessage -Headers $User -API $APINAME -message "Removed Standards Template named $($ClearRow.name) and id $($id)" -Sev 'Info'
        $body = [pscustomobject]@{'Results' = 'Successfully removed Template' }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $User -API $APINAME -message "Failed to remove Standards template $ID. $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = "Failed to remove template: $($ErrorMessage.NormalizedError)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })


}
