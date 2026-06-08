function Set-CIPPDBCacheSettings {
    <#
    .SYNOPSIS
        Caches directory settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache settings for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching directory settings' -sev Debug

        $BulkRequests = @(
            [PSCustomObject]@{
                id     = 'settings'
                method = 'GET'
                url    = '/settings?$top=999'
            }
            [PSCustomObject]@{
                id     = 'appsAndServices'
                method = 'GET'
                url    = '/admin/appsAndServices'
            }
            [PSCustomObject]@{
                id     = 'formsSettings'
                method = 'GET'
                url    = '/admin/forms/settings'
            }
        )

        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

        $SettingsResponse = $BulkResults | Where-Object { $_.id -eq 'settings' } | Select-Object -First 1
        $Settings = @()
        if ($SettingsResponse -and $SettingsResponse.status -eq 200) {
            $Settings = @($SettingsResponse.body.value)
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Settings request failed in bulk response (status: $($SettingsResponse.status))" -sev Warning
        }
        if (!$Settings) { $Settings = @() }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Settings' -Data $Settings -AddCount
        $Settings = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching apps and services settings' -sev Debug
        $AppsAndServicesResponse = $BulkResults | Where-Object { $_.id -eq 'appsAndServices' } | Select-Object -First 1
        $AppsAndServices = @()
        if ($AppsAndServicesResponse -and $AppsAndServicesResponse.status -eq 200) {
            $AppsAndServices = $AppsAndServicesResponse.body
            if ($AppsAndServices -and $AppsAndServices.PSObject.Properties.Name -contains 'settings') {
                $AppsAndServices = $AppsAndServices.settings
            }
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "AppsAndServices request failed in bulk response (status: $($AppsAndServicesResponse.status))" -sev Warning
        }
        if (!$AppsAndServices) { $AppsAndServices = @() }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppsAndServices' -Data $AppsAndServices -AddCount
        $AppsAndServices = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Forms settings' -sev Debug
        $FormsSettingsResponse = $BulkResults | Where-Object { $_.id -eq 'formsSettings' } | Select-Object -First 1
        $FormsSettings = @()
        if ($FormsSettingsResponse -and $FormsSettingsResponse.status -eq 200) {
            $FormsSettings = $FormsSettingsResponse.body
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "FormsSettings request failed in bulk response (status: $($FormsSettingsResponse.status))" -sev Warning
        }
        if (!$FormsSettings) { $FormsSettings = @() }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'FormsSettings' -Data $FormsSettings -AddCount
        $FormsSettings = $null

        $BulkResults = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached directory settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache directory settings: $($_.Exception.Message)" -sev Error
    }
}
