using namespace System.Net

Function Invoke-RemoveBPATemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $ID = $request.query.TemplateName
    try {
        $Table = Get-CippTable -tablename 'templates'

        $Filter = "PartitionKey eq 'BPATemplate' and RowKey eq '$id'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity @Table -Entity $clearRow
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Removed BPA Template with ID $ID." -Sev 'Info'
        $body = [pscustomobject]@{'Results' = 'Successfully removed BPA Template' }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to remove BPA template $ID. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed to remove template: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })


}
