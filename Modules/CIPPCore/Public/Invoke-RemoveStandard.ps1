using namespace System.Net

Function Invoke-RemoveStandard {
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

    $ID = $request.query.id
    try {
        $Table = Get-CippTable -tablename 'standards'
        $Filter = "PartitionKey eq 'standards' and RowKey eq '$id'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity -Force @Table -Entity $clearRow
        Write-LogMessage -Headers $User -API $APINAME -message "Removed standards for $ID." -Sev 'Info'
        $body = [pscustomobject]@{'Results' = 'Successfully removed standards deployment' }


    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $User -API $APINAME -message "Failed to remove standard for $ID. $($ErrorMessage.NormalizedError)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = 'Failed to remove standard)' }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })


}
