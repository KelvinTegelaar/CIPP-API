function Invoke-ListAlertResults {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Alert.Read
    .DESCRIPTION
        Lists the tracked alert items for a tenant from the AlertLifecycle table, which
        Write-AlertTrace maintains: one row per alert item with its Status (Open,
        Acknowledged, Snoozed or Resolved), when it was first and last seen, when it was
        last checked, how often it reopened and who acknowledged it. Pass tenantFilter
        (or AllTenants for every tenant the caller may see). Open, Acknowledged and
        Snoozed items are always returned; Resolved items are included when
        IncludeResolved=true, limited to those resolved within the last Days days
        (default 2, at most 366). Each item carries the raw alert item and the keys
        needed to snooze, unsnooze or acknowledge it.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'tenantFilter is required.' }
                })
        }

        $IncludeResolved = [System.Convert]::ToBoolean(($Request.Query.IncludeResolved ?? $Request.Body.IncludeResolved ?? $false))
        $Days = ($Request.Query.Days ?? $Request.Body.Days) -as [int]
        if (-not $Days -or $Days -lt 1) { $Days = 2 }
        if ($Days -gt 366) { $Days = 366 }
        $ResolvedCutoff = [datetime]::UtcNow.AddDays(-$Days)

        $Table = Get-CIPPTable -tablename 'AlertLifecycle'
        # AnyTenant skips the framework's per-tenant check, so narrow on the row's own Tenant
        # column: restricted callers keep only rows for tenants in scope.
        $Rows = if ($TenantFilter -eq 'AllTenants') {
            Get-CIPPAzDataTableEntity @Table | Select-CippAllowedTenantData -TenantProperty 'Tenant'
        } else {
            $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
            Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant'" | Select-CippAllowedTenantData -TenantProperty 'Tenant'
        }

        $Results = [System.Collections.Generic.List[object]]::new()
        foreach ($Row in @($Rows)) {
            if ($null -eq $Row) { continue }
            $Status = [string]$Row.Status
            if ($Status -eq 'Resolved') {
                if (-not $IncludeResolved) { continue }
                [datetime]$ResolvedAt = [datetime]::MinValue
                if (-not [datetime]::TryParse([string]$Row.ResolvedAt, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$ResolvedAt)) { continue }
                if ($ResolvedAt -lt $ResolvedCutoff) { continue }
            }

            $AlertItem = $null
            if (-not [string]::IsNullOrWhiteSpace($Row.AlertItem)) {
                try { $AlertItem = $Row.AlertItem | ConvertFrom-Json -ErrorAction Stop } catch { $AlertItem = $null }
            }
            $Keys = Get-CIPPAlertLifecycleKey -CmdletName ([string]$Row.CmdletName) -TenantFilter ([string]$Row.Tenant) -ContentHash ([string]$Row.ContentHash)

            $Results.Add([PSCustomObject]@{
                    PartitionKey       = $Row.PartitionKey
                    RowKey             = $Row.RowKey
                    CmdletName         = $Row.CmdletName
                    AlertComment       = $Row.AlertComment
                    Tenant             = $Row.Tenant
                    ContentHash        = $Row.ContentHash
                    ContentPreview     = $Row.ContentPreview
                    AlertItem          = $AlertItem
                    Status             = $Status
                    FirstSeen          = $Row.FirstSeen
                    LastSeen           = $Row.LastSeen
                    LastChecked        = $Row.LastChecked
                    ResolvedAt         = $Row.ResolvedAt
                    ReopenCount        = [int]($Row.ReopenCount ?? 0)
                    AcknowledgedBy     = $Row.AcknowledgedBy
                    AcknowledgedAt     = $Row.AcknowledgedAt
                    AcknowledgeNote    = $Row.AcknowledgeNote
                    SnoozeUntil        = $Row.SnoozeUntil
                    SnoozedBy          = $Row.SnoozedBy
                    SnoozePartitionKey = $Keys.SnoozePartitionKey
                    SnoozeRowKey       = if ([string]::IsNullOrWhiteSpace($Row.SnoozeRowKey)) { $Keys.SnoozeRowKey } else { $Row.SnoozeRowKey }
                })
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($Results | Sort-Object -Property @{ Expression = { $_.Status -eq 'Resolved' } }, @{ Expression = 'LastSeen'; Descending = $true })
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to list alert results: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Failed to list alert results: $($ErrorMessage.NormalizedError)" }
            })
    }
}
