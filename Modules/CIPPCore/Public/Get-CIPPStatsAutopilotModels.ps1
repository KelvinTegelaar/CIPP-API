function Get-CIPPStatsAutopilotModels {
    <#
    .SYNOPSIS
    Unique Autopilot manufacturer/model pairs seen on this instance, for the anonymous stats payload

    .DESCRIPTION
    Reads the AutopilotDeviceModels table written by Set-CIPPDBCacheAutopilotDeviceModels. The table is
    already deduped and holds no tenant or device data; only the exact manufacturer and model strings
    are returned.
    #>
    [CmdletBinding()]
    param()

    try {
        $Table = Get-CIPPTable -tablename 'AutopilotDeviceModels'
        return @(Get-CIPPAzDataTableEntity @Table -Property Manufacturer, Model | Select-Object -Property Manufacturer, Model)
    } catch {
        Write-LogMessage -API 'CIPPStatsTimer' -tenant $env:TenantID -message "Failed to read Autopilot model stats: $($_.Exception.Message)" -sev Warning
        return @()
    }
}
