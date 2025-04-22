function New-CIPPDeviceAction {
    [CmdletBinding()]
    param(
        $Action,
        $ActionBody = '{}',
        $DeviceFilter,
        $TenantFilter,
        $Headers,
        $APINAME
    )
    try {
        if ($action -eq 'delete') {
            $null = New-Graphpostrequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$DeviceFilter" -type DELETE -tenantid $TenantFilter
            Write-LogMessage -headers $Headers -API $APINAME -tenant $TenantFilter -message "Queued $Action on $DeviceFilter" -Sev 'Info'
            return "Queued $Action on $DeviceFilter"
        }
        $null = New-Graphpostrequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceFilter')/$($Action)" -type POST -tenantid $TenantFilter -body $ActionBody
        Write-LogMessage -headers $Headers -API $APINAME -tenant $TenantFilter -message "Queued $Action on $DeviceFilter" -Sev 'Info'
        return "Queued $Action on $DeviceFilter"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APINAME -tenant $TenantFilter -message "Failed to queue action $Action on $DeviceFilter : $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return    "Failed to queue action $Action on $DeviceFilter $($ErrorMessage.NormalizedError)"
    }
}
