Function Invoke-RemoveSensitivityLabelTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitivityLabel.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $ID = $Request.Body.ID ?? $Request.Query.ID
    try {
        $Table = Get-CippTable -tablename 'templates'
        $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type Guid
        $Filter = "PartitionKey eq 'SensitivityLabelTemplate' and RowKey eq '$SafeID'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity -Force @Table -Entity $ClearRow
        $Result = "Removed Sensitivity Label template with ID $ID"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Sensitivity Label template $ID. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
