function Invoke-ExecRemoveSnooze {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AlertSnooze.ReadWrite
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

        # AnyTenant: restricted callers may only remove snoozes for tenants in scope
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
            $SafePartitionKey = ConvertTo-CIPPODataFilterValue -Value $PartitionKey -Type String
            $SafeRowKey = ConvertTo-CIPPODataFilterValue -Value $RowKey -Type String
            $Existing = Get-CIPPAzDataTableEntity @SnoozeTable -Filter "PartitionKey eq '$SafePartitionKey' and RowKey eq '$SafeRowKey'"
            if (-not $Existing.Tenant -or -not (Get-Tenants -TenantFilter $Existing.Tenant)) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body       = @{ Results = 'Access to this snooze is not allowed' }
                    })
            }
        }

        Remove-CIPPAzDataTableEntity @SnoozeTable -Entity @{
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
