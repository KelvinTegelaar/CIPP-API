Function Invoke-RemoveTenantAllowBlockListTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $ID = $Request.query.ID ?? $Request.body.ID
    try {
        $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type Guid
    } catch {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Failed to remove Tenant Allow/Block List template: '$ID' is not a valid template ID." }
            })
    }

    try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'TenantAllowBlockListTemplate' and RowKey eq '$SafeID'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        if (-not $ClearRow) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = "Tenant Allow/Block List template with ID $ID not found." }
                })
        }
        Remove-CIPPAzDataTableEntity -Force @Table -Entity $ClearRow
        $Result = "Removed Tenant Allow/Block List Template with ID $ID."
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Tenant Allow/Block List Template with ID $ID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
