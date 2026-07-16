function Invoke-ExecResolveAlert {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Alert.ReadWrite
    .DESCRIPTION
        Marks a fired alert item as resolved by removing it from the stored AlertLastRun
        state, so it disappears from the dashboard immediately. Unlike a snooze this does
        not suppress the alert: if the underlying condition still exists, the item fires
        again on the alert's next scheduled run.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $CmdletName = $Request.Body.CmdletName
        $TenantFilter = $Request.Body.TenantFilter
        $AlertItem = $Request.Body.AlertItem

        if ([string]::IsNullOrWhiteSpace($CmdletName) -or [string]::IsNullOrWhiteSpace($TenantFilter) -or $null -eq $AlertItem) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'CmdletName, TenantFilter, and AlertItem are required.' }
                })
        }

        $HashResult = Get-AlertContentHash -AlertItem $AlertItem

        $Table = Get-CIPPTable -tablename 'AlertLastRun'
        # Remove the item from every partition for this alert, not just the latest:
        # if the latest row is deleted, ListAlertResults falls back to an older-dated
        # row, which would resurface the item. TenantFilter/CmdletName are caller
        # input - escape them so a quote cannot widen the filter to foreign rows.
        $SafeRowKey = ConvertTo-CIPPODataFilterValue -Value "$($TenantFilter)-$($CmdletName)" -Type String
        $Rows = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$SafeRowKey'"

        $Removed = 0
        foreach ($Row in @($Rows)) {
            if ([string]::IsNullOrWhiteSpace($Row.LogData)) { continue }
            try {
                $Items = @($Row.LogData | ConvertFrom-Json -ErrorAction Stop)
            } catch {
                continue
            }

            $Keep = @($Items | Where-Object { (Get-AlertContentHash -AlertItem $_).ContentHash -ne $HashResult.ContentHash })
            if ($Keep.Count -eq $Items.Count) { continue }
            $Removed += $Items.Count - $Keep.Count

            if ($Keep.Count -eq 0) {
                Remove-AzDataTableEntity -Force @Table -Entity $Row | Out-Null
            } else {
                $LogData = ConvertTo-Json -InputObject $Keep -Compress -Depth 10 | Out-String
                $Entity = @{
                    'PartitionKey' = $Row.PartitionKey
                    'RowKey'       = $Row.RowKey
                    'CmdletName'   = "$($Row.CmdletName)"
                    'Tenant'       = "$($Row.Tenant)"
                    'LogData'      = [string]$LogData
                    'AlertComment' = [string]$Row.AlertComment
                }
                # Carry the LastSeen stamp over - dropping it would make the scheduler's
                # post-run check read the surviving items as stale and clear them.
                if ($Row.LastSeen) { $Entity.LastSeen = [string]$Row.LastSeen }
                $Table.Entity = $Entity
                Add-CIPPAzDataTableEntity @Table -Force | Out-Null
            }
        }

        $Result = if ($Removed -gt 0) {
            "Resolved alert: $($HashResult.ContentPreview)"
        } else {
            "Alert was already resolved: $($HashResult.ContentPreview)"
        }
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Result }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to resolve alert: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Failed to resolve alert: $($ErrorMessage.NormalizedError)" }
            })
    }
}
