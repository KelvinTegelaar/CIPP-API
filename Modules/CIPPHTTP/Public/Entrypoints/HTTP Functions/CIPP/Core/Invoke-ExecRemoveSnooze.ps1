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

        # The row is read back for everyone: restricted callers need its Tenant for the scope
        # check, and the tracked alert item it belongs to is keyed on its Tenant and ContentHash.
        $SafePartitionKey = ConvertTo-CIPPODataFilterValue -Value $PartitionKey -Type String
        $SafeRowKey = ConvertTo-CIPPODataFilterValue -Value $RowKey -Type String
        $Existing = Get-CIPPAzDataTableEntity @SnoozeTable -Filter "PartitionKey eq '$SafePartitionKey' and RowKey eq '$SafeRowKey'" | Select-Object -First 1

        # AnyTenant: restricted callers may only remove snoozes for tenants in scope
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
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

        # Put the tracked item back to Open right away; the alert's next run notifies again if
        # the condition still holds.
        if ($Existing -and $Existing.Tenant -and $Existing.ContentHash) {
            try {
                $Keys = Get-CIPPAlertLifecycleKey -CmdletName $PartitionKey -TenantFilter ([string]$Existing.Tenant) -ContentHash ([string]$Existing.ContentHash)
                $LifecycleTable = Get-CIPPTable -tablename 'AlertLifecycle'
                $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $Keys.PartitionKey -Type String
                $SafeLifecycleKey = ConvertTo-CIPPODataFilterValue -Value $Keys.RowKey -Type String
                $Tracked = Get-CIPPAzDataTableEntity @LifecycleTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$SafeLifecycleKey'" | Select-Object -First 1
                if ($Tracked -and [string]$Tracked.Status -eq 'Snoozed') {
                    $Update = @{}
                    foreach ($Prop in $Tracked.PSObject.Properties) {
                        if ($Prop.Name -in @('ETag', 'Timestamp')) { continue }
                        $Update[$Prop.Name] = $Prop.Value
                    }
                    $Update.Status = 'Open'
                    $Update.SnoozeUntil = ''
                    $Update.SnoozedBy = ''
                    $Update.SnoozeRowKey = ''
                    Add-CIPPAzDataTableEntity @LifecycleTable -Entity $Update -Force | Out-Null
                }
            } catch {
                Write-Information "Snooze removed but the tracked alert item could not be updated: $($_.Exception.Message)"
            }
        }

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
