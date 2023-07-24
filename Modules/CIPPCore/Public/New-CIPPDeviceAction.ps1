function New-CIPPDeviceAction {
    [CmdletBinding()]
    param(
        $Action,
        $ActionBody = '{}',
        $DeviceFilter,
        $TenantFilter,
        $ExecutingUser,
        $APINAME
    )
    try {     
        $GraphRequest = New-Graphpostrequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceFilter')/$($Action)" -type POST -tenantid $TenantFilter -body $ActionBody
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $TenantFilter -message "Queued $Action on $DeviceFilter" -Sev "Info"
        return "Queued $Action on $DeviceFilter"
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $TenantFilter -message "Failed to queue action $Action on $DeviceFilter : $($_.Exception.Message)" -Sev "Error"
        return    "Failed to queue action $Action on $DeviceFilter $($_.Exception.Message)"
    }
}
