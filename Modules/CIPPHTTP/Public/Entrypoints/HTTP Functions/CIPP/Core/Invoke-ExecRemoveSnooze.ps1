function Invoke-ExecRemoveSnooze {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $PartitionKey = $Request.Body.PartitionKey ?? $Request.Query.PartitionKey
        $RowKey = $Request.Body.RowKey ?? $Request.Query.RowKey

        if ([string]::IsNullOrWhiteSpace($PartitionKey) -or [string]::IsNullOrWhiteSpace($RowKey)) {
            return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'PartitionKey and RowKey are required.' }
            })
        }

        $SnoozeTable = Get-CIPPTable -tablename 'AlertSnooze'
        Remove-AzDataTableEntity @SnoozeTable -Entity @{
            PartitionKey = $PartitionKey
            RowKey       = $RowKey
            ETag         = '*'
        } | Out-Null

        $Result = "Successfully removed snooze for $PartitionKey / $RowKey"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'

        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Result }
        })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to remove snooze: $($ErrorMessage.NormalizedError)" -Sev 'Error'
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed to remove snooze: $($ErrorMessage.NormalizedError)" }
        })
    }
}
