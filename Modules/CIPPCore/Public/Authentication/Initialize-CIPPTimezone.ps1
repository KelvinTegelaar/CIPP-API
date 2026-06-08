function Initialize-CIPPTimezone {
    <#
    .SYNOPSIS
    Loads the configured timezone from storage, sets $env:CIPP_TIMEZONE,
    and updates the scheduler timezone.

    .DESCRIPTION
    Reads the TimeSettings row from the Config table. Sets the CIPP_TIMEZONE
    environment variable to the configured timezone, or defaults to 'UTC' if not set or on error.
    #>
    [CmdletBinding()]
    param()

    try {
        $ConfigTable = Get-CIPPTable -tablename Config
        $TimeSettings = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'TimeSettings' and RowKey eq 'TimeSettings'" -Property @('PartitionKey', 'RowKey', 'Timezone') -First 1
        if ($TimeSettings.Timezone) {
            $null = [TimeZoneInfo]::FindSystemTimeZoneById($TimeSettings.Timezone)
            [Craft.Services.PowerShellRunnerService]::SetProcessEnvVar('CIPP_TIMEZONE', $TimeSettings.Timezone)
            [Craft.Services.PowerShellRunnerService]::SetProcessEnvVar('CraftTZ', $TimeSettings.Timezone)
            Write-Information "[Timezone-Init] Timezone set to $($TimeSettings.Timezone)"
        } else {
            [Craft.Services.PowerShellRunnerService]::SetProcessEnvVar('CIPP_TIMEZONE', 'UTC')
            Write-Information '[Timezone-Init] No timezone configured, defaulting to UTC'
        }
    } catch {
        [Craft.Services.PowerShellRunnerService]::SetProcessEnvVar('CIPP_TIMEZONE', 'UTC')
        Write-Warning "[Timezone-Init] Failed to load timezone, defaulting to UTC: $_"
    }
}
