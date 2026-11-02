function Invoke-ListSnoozedAlerts {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AlertSnooze.Read
    .DESCRIPTION
        Lists alerts that have been snoozed (temporarily suppressed), filterable by cmdlet name. Returns the snooze duration, whether it runs until the item resolves, whether the item stays visible on the dashboard, and who set it.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $CmdletName = $Request.Query.CmdletName
        $SnoozeTable = Get-CIPPTable -tablename 'AlertSnooze'

        # Build filter based on provided parameters
        if (-not [string]::IsNullOrWhiteSpace($CmdletName)) {
            $Filter = "PartitionKey eq '$($CmdletName)'"
            $SnoozeRecords = Get-CIPPAzDataTableEntity @SnoozeTable -Filter $Filter
        } else {
            $SnoozeRecords = Get-CIPPAzDataTableEntity @SnoozeTable
        }

        # AnyTenant skips the framework's per-tenant check, and snooze rows carry alert content
        # previews. Narrow to the caller's allowed tenants (dropping estate-wide rows for
        # restricted callers); unrestricted callers pass through untouched.
        $SnoozeRecords = $SnoozeRecords | Select-CippAllowedTenantData -TenantProperty 'Tenant'

        $CurrentUnixTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds

        $Results = @($SnoozeRecords | ForEach-Object {
                $UntilResolved = [string]$_.UntilResolved -eq 'True'
                $KeepVisible = [string]$_.KeepVisible -eq 'True'
                $SnoozeUntil = ([string]$_.SnoozeUntil) -as [int64]
                if ($null -eq $SnoozeUntil) { $SnoozeUntil = 0 }
                $IsExpired = (-not $UntilResolved) -and ($SnoozeUntil -lt $CurrentUnixTime)
                $RemainingSeconds = if ($UntilResolved -or $IsExpired) { 0 } else { $SnoozeUntil - $CurrentUnixTime }
                $RemainingDays = if ($UntilResolved -or $IsExpired) { 0 } else { [math]::Ceiling($RemainingSeconds / 86400) }

                [PSCustomObject]@{
                    PartitionKey   = $_.PartitionKey
                    RowKey         = $_.RowKey
                    CmdletName     = $_.PartitionKey
                    Tenant         = $_.Tenant
                    ContentHash    = $_.ContentHash
                    ContentPreview = $_.ContentPreview
                    SnoozeReason   = $_.SnoozeReason
                    SnoozedBy      = $_.SnoozedBy
                    SnoozedAt      = $_.SnoozedAt
                    SnoozeUntil    = $_.SnoozeUntil
                    UntilResolved  = $UntilResolved
                    KeepVisible    = $KeepVisible
                    IsExpired      = $IsExpired
                    RemainingDays  = $RemainingDays
                    Status         = if ($UntilResolved) { 'Until Resolved' } elseif ($IsExpired) { 'Expired' } else { 'Active' }
                }
            })

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($Results)
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to list snoozed alerts: $($ErrorMessage.NormalizedError)" -Sev 'Error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Failed to list snoozed alerts: $($ErrorMessage.NormalizedError)" }
            })
    }
}
