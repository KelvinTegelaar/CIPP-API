function Invoke-ExecTimeSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Timezone = $Request.Body.Timezone.value ?? $Request.Body.Timezone

        if (-not $Timezone) {
            throw 'Timezone is required'
        }

        # Validate the IANA timezone ID is recognised by .NET
        try {
            $null = [TimeZoneInfo]::FindSystemTimeZoneById($Timezone)
        } catch {
            throw "Invalid timezone: '$Timezone' is not a recognised IANA timezone ID"
        }

        $Config = @{
            PartitionKey   = 'TimeSettings'
            RowKey         = 'TimeSettings'
            Timezone       = $Timezone
            # An explicit choice outranks the region-derived default Initialize-CIPPTimezone
            # writes, and stops it being reconsidered on later warmups.
            TimezoneSource = 'User'
        }

        $ConfigTable = Get-CIPPTable -tablename Config
        # UpsertMerge, not -Force: -Force is a replace and would drop DetectedRegion.
        Add-CIPPAzDataTableEntity @ConfigTable -Entity $Config -OperationType UpsertMerge | Out-Null
        $env:CIPP_TIMEZONE = $Timezone
        try { [Craft.Services.SchedulerBridge]::SetTimezone($Timezone) } catch { $null }
        try { [Craft.Services.PowerShellRunnerService]::SetProcessEnvVar('CIPP_TIMEZONE', $Timezone) } catch { $null }
        # The scheduler resolves CraftTZ at startup; without this it keeps the old value until
        # the node restarts.
        try { [Craft.Services.PowerShellRunnerService]::SetProcessEnvVar('CraftTZ', $Timezone) } catch { $null }
        Write-LogMessage -API 'ExecTimeSettings' -headers $Request.Headers -message "Updated time settings: Timezone=$Timezone" -Sev 'Info'

        return ([HttpResponseContext]@{
                StatusCode = [httpstatusCode]::OK
                Body       = @{
                    Results  = 'Time settings updated successfully.'
                    Timezone = $Timezone
                }
            })

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'ExecTimeSettings' -headers $Request.Headers -message "Failed to update time settings: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage

        return ([HttpResponseContext]@{
                StatusCode = [httpstatusCode]::BadRequest
                Body       = @{
                    Results = "Failed to update time settings: $($ErrorMessage.NormalizedError)"
                }
            })
    }
}
