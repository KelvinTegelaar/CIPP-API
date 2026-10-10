function Invoke-ExecSnoozeAlert {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AlertSnooze.ReadWrite
    .DESCRIPTION
        Snoozes one alert item so it stops notifying. Body: CmdletName, TenantFilter, AlertItem,
        and either Duration (7, 14, 30 or 90 days) or UntilResolved=true, which keeps the snooze
        until the alert stops reporting the item and is then removed automatically. KeepVisible=true
        leaves the item on the dashboard, marked as snoozed, rather than hiding it. Reason is an
        optional note. There is no indefinite snooze.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $CmdletName = $Request.Body.CmdletName
        $TenantFilter = $Request.Body.TenantFilter
        $AlertItem = $Request.Body.AlertItem
        $Duration = ($Request.Body.Duration) -as [int]
        $UntilResolved = [System.Convert]::ToBoolean(($Request.Body.UntilResolved ?? $false))
        $KeepVisible = [System.Convert]::ToBoolean(($Request.Body.KeepVisible ?? $false))
        $Reason = [string]$Request.Body.Reason
        $SnoozedBy = try {
            ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        } catch { 'Unknown' }

        if ([string]::IsNullOrWhiteSpace($CmdletName) -or [string]::IsNullOrWhiteSpace($TenantFilter) -or $null -eq $AlertItem) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'CmdletName, TenantFilter, and AlertItem are required.' }
                })
        }

        if (-not $UntilResolved -and $Duration -notin @(7, 14, 30, 90)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'Duration must be 7, 14, 30, or 90 days, or set UntilResolved to true.' }
                })
        }

        # AnyTenant: enforce tenant scope here; Get-Tenants is narrowed to the caller's allowed tenants
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants' -and -not (Get-Tenants -TenantFilter $TenantFilter)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{ Results = 'Access to this tenant is not allowed' }
                })
        }

        # Compute content hash for this alert item
        $HashResult = Get-AlertContentHash -AlertItem $AlertItem

        $CurrentUnixTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        $SnoozeUntil = if ($UntilResolved) { [int64]0 } else { $CurrentUnixTime + ($Duration * 86400) }

        $SnoozeTable = Get-CIPPTable -tablename 'AlertSnooze'
        $Keys = Get-CIPPAlertLifecycleKey -CmdletName $CmdletName -TenantFilter $TenantFilter -ContentHash $HashResult.ContentHash
        $SnoozeEntity = @{
            PartitionKey   = $Keys.SnoozePartitionKey
            RowKey         = $Keys.SnoozeRowKey
            ContentHash    = [string]$HashResult.ContentHash
            Tenant         = [string]$TenantFilter
            SnoozeUntil    = [string]$SnoozeUntil
            UntilResolved  = [string]$UntilResolved
            KeepVisible    = [string]$KeepVisible
            SnoozedBy      = [string]$SnoozedBy
            SnoozedAt      = [string]$CurrentUnixTime
            ContentPreview = [string]$HashResult.ContentPreview
            SnoozeKey      = [string]$HashResult.RawKey
            SnoozeReason   = [string]$Reason
        }

        Add-CIPPAzDataTableEntity @SnoozeTable -Entity $SnoozeEntity -Force | Out-Null

        # Reflect the snooze on the tracked item straight away, so the dashboard does not have
        # to wait for the alert's next run to move it out of the active list.
        try {
            $LifecycleTable = Get-CIPPTable -tablename 'AlertLifecycle'
            $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $Keys.PartitionKey -Type String
            $SafeRowKey = ConvertTo-CIPPODataFilterValue -Value $Keys.RowKey -Type String
            $Tracked = Get-CIPPAzDataTableEntity @LifecycleTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$SafeRowKey'" | Select-Object -First 1
            if ($Tracked -and [string]$Tracked.Status -ne 'Resolved') {
                $Update = @{}
                foreach ($Prop in $Tracked.PSObject.Properties) {
                    if ($Prop.Name -in @('ETag', 'Timestamp')) { continue }
                    $Update[$Prop.Name] = $Prop.Value
                }
                $Update.Status = 'Snoozed'
                $Update.SnoozeUntil = [string]$SnoozeUntil
                $Update.SnoozedBy = [string]$SnoozedBy
                $Update.SnoozeRowKey = $Keys.SnoozeRowKey
                $Update.SnoozeReason = [string]$Reason
                $Update.SnoozeVisible = [string]$KeepVisible
                $Update.SnoozeUntilResolved = [string]$UntilResolved
                Add-CIPPAzDataTableEntity @LifecycleTable -Entity $Update -Force | Out-Null
            }
        } catch {
            Write-Information "Snooze stored but the tracked alert item could not be updated: $($_.Exception.Message)"
        }

        $DurationLabel = if ($UntilResolved) { 'until it resolves' } else { "for $Duration days" }
        $ContentPreview = $HashResult.ContentPreview
        $Result = "Successfully snoozed alert ${DurationLabel}: ${ContentPreview}"
        if ($KeepVisible) { $Result = "$Result (kept visible on the dashboard)" }
        if (-not [string]::IsNullOrWhiteSpace($Reason)) {
            $Result = "$Result - Reason: $Reason"
        }

        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{
                    Results       = $Result
                    ContentHash   = $HashResult.ContentHash
                    SnoozeUntil   = $SnoozeUntil
                    UntilResolved = $UntilResolved
                    KeepVisible   = $KeepVisible
                    SnoozedBy     = $SnoozedBy
                }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to snooze alert: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Failed to snooze alert: $($ErrorMessage.NormalizedError)" }
            })
    }
}
