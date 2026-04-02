function Invoke-ListSnoozedAlerts {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Alert.Read
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



        $CurrentUnixTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds

        $Results = @($SnoozeRecords | ForEach-Object {
                $SnoozeUntil = [int64]$_.SnoozeUntil
                $IsForever = $SnoozeUntil -eq -1
                $IsExpired = (-not $IsForever) -and ($SnoozeUntil -lt $CurrentUnixTime)
                $RemainingSeconds = if ($IsForever) { -1 } elseif ($IsExpired) { 0 } else { $SnoozeUntil - $CurrentUnixTime }
                $RemainingDays = if ($IsForever) { -1 } elseif ($IsExpired) { 0 } else { [math]::Ceiling($RemainingSeconds / 86400) }

                [PSCustomObject]@{
                    PartitionKey   = $_.PartitionKey
                    RowKey         = $_.RowKey
                    CmdletName     = $_.PartitionKey
                    Tenant         = $_.Tenant
                    ContentPreview = $_.ContentPreview
                    SnoozedBy      = $_.SnoozedBy
                    SnoozedAt      = $_.SnoozedAt
                    SnoozeUntil    = $_.SnoozeUntil
                    IsForever      = $IsForever
                    IsExpired      = $IsExpired
                    RemainingDays  = $RemainingDays
                    Status         = if ($IsForever) { 'Forever' } elseif ($IsExpired) { 'Expired' } else { 'Active' }
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
