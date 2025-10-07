Function Invoke-RemoveStandard {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $ID = $Request.Query.ID
    try {
        $Table = Get-CippTable -tablename 'standards'
        $Filter = "PartitionKey eq 'standards' and RowKey eq '$ID'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity -Force @Table -Entity $ClearRow
        Write-LogMessage -Headers $Headers -API $APIName -message "Removed standards for $ID." -Sev 'Info'
        $body = [pscustomobject]@{'Results' = 'Successfully removed standards deployment' }
        $StatusCode = [HttpStatusCode]::OK


    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APIName -message "Failed to remove standard for $ID. $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $body = [pscustomobject]@{'Results' = 'Failed to remove standard' }
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })


}
